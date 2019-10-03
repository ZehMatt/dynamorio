# Boost Software License - Version 1.0 - August 17th, 2003
#
# Permission is hereby granted, free of charge, to any person or organization
# obtaining a copy of the software and accompanying documentation covered by
# this license (the "Software") to use, reproduce, display, distribute,
# execute, and transmit the Software, and to prepare derivative works of the
# Software, and to permit third-parties to whom the Software is furnished to
# do so, all subject to the following:
#
# The copyright notices in the Software and this entire statement, including
# the above license grant, this restriction and the following disclaimer,
# must be included in all copies of the Software, in whole or in part, and
# all derivative works of the Software, unless such copies or derivative
# works are solely in the form of machine-executable object code generated by
# a source language processor.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE, TITLE AND NON-INFRINGEMENT. IN NO EVENT
# SHALL THE COPYRIGHT HOLDERS OR ANYONE DISTRIBUTING THE SOFTWARE BE LIABLE
# FOR ANY DAMAGES OR OTHER LIABILITY, WHETHER IN CONTRACT, TORT OR OTHERWISE,
# ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
# DEALINGS IN THE SOFTWARE.

# We customize this function from the vera++ package's user_vera++.cmake for
# the following purposes:
# 1) Pass --error instead of --warning.
#    Xref https://bitbucket.org/verateam/vera/issues/91
# 2) Exclude some files from the glob, in particular backup files.

function(add_vera_targets_for_dynamorio)
  # default values
  set(target "style")
  set(target_all "style_reports")
  set(profile "default")
  set(root "${CMAKE_CURRENT_BINARY_DIR}")
  set(exclusions)
  set(recurse OFF)
  set(globs)
  # parse the options
  math(EXPR lastIdx "${ARGC} - 1")
  set(i 0)
  while(i LESS ${ARGC})
    set(arg "${ARGV${i}}")
    if("${arg}" STREQUAL "NAME")
      vera_incr(i)
      set(target "${ARGV${i}}")
    elseif("${arg}" STREQUAL "NAME_ALL")
      vera_incr(i)
      set(target_all "${ARGV${i}}")
    elseif("${arg}" STREQUAL "ROOT")
      vera_incr(i)
      set(root "${ARGV${i}}")
    elseif("${arg}" STREQUAL "PROFILE")
      vera_incr(i)
      set(profile "${ARGV${i}}")
    elseif("${arg}" STREQUAL "EXCLUSION")
      vera_incr(i)
      list(APPEND exclusions --exclusions "${ARGV${i}}")
    elseif("${arg}" STREQUAL "RECURSE")
      set(recurse ON)
    else()
      list(APPEND globs ${arg})
    endif()
    vera_incr(i)
  endwhile()

  if(recurse)
    file(GLOB_RECURSE srcs ${globs})
  else()
    file(GLOB srcs ${globs})
  endif()
  list(SORT srcs)

  if(NOT VERA++_EXECUTABLE AND TARGET vera)
    set(vera_program "$<TARGET_FILE:vera>")
  else()
    set(vera_program "${VERA++_EXECUTABLE}")
  endif()

  # Two custom targets will be created:
  # * style_reports is run as part of the build, and is not rerun unless one of
  # the file checked is modified;
  # * style must be explicitly called (make style) and is rerun even if the files
  # to check have not been modified. To achieve this behavior, the commands used
  # in this target pretend to produce a file without actually producing it.
  # Because the output file is not there after the run, the command will be rerun
  # again at the next target build.
  # The report style is selected based on the build environment, so the style
  # problems are properly reported in the IDEs
  if(MSVC)
    set(style vc)
  else()
    set(style std)
  endif()
  set(xmlreports)
  set(noreports)
  set(reportNb 0)
  set(reportsrcs)
  list(GET srcs 0 first)
  get_filename_component(currentDir ${first} PATH)
  # add a fake src file in a fake dir to trigger the creation of the last
  # custom command
  list(APPEND srcs "#12345678900987654321#/0987654321#1234567890")
  foreach(s ${srcs})
    if (NOT s MATCHES "\\.#" AND # avoid emacs backup files
        # We also exclude files in make/style_checks/exclusions here to speed
        # up the build slightly and to handle vera++ 1.2.1 better (1.2.1 does not
        # support regex exclusions).
        NOT s MATCHES "/suite/tests" AND
        NOT s MATCHES "/libutil/" AND
        NOT s MATCHES "/tools/" AND
        NOT s MATCHES "/third_party/" AND
        # Somehow on Travis vera checks build-dir files.
        NOT s MATCHES "/build_" AND
        NOT s MATCHES "/install/")
      get_filename_component(d ${s} PATH)
      if(NOT "${d}" STREQUAL "${currentDir}")
        # this is a new dir - lets generate everything needed for the previous dir
        string(LENGTH "${CMAKE_SOURCE_DIR}" len)
        string(SUBSTRING "${currentDir}" 0 ${len} pre)
        if("${pre}" STREQUAL "${CMAKE_SOURCE_DIR}")
          string(SUBSTRING "${currentDir}" ${len} -1 currentDir)
          string(REGEX REPLACE "^/" "" currentDir "${currentDir}")
        endif()
        if("${currentDir}" STREQUAL "")
          set(currentDir ".")
        endif()
        set(xmlreport ${CMAKE_CURRENT_BINARY_DIR}/vera_report_${reportNb}.xml)
        if (VERA_ERROR)
          set(error_or_warning --error)
        else ()
          set(error_or_warning --warning)
        endif (VERA_ERROR)
        add_custom_command(
          OUTPUT ${xmlreport}
          COMMAND ${vera_program}
            --root ${root}
            --profile ${profile}
            --${style}-report=-
            --show-rule
            ${error_or_warning}
            --xml-report=${xmlreport}
            ${exclusions}
            ${reportsrcs}
          DEPENDS ${reportsrcs}
          COMMENT "Checking style with vera++ in ${currentDir}"
        )
        set(noreport ${CMAKE_CURRENT_BINARY_DIR}/vera_noreport_${reportNb}.xml)
        add_custom_command(
          OUTPUT ${noreport}
          COMMAND ${vera_program}
            --root ${root}
            --profile ${profile}
            --${style}-report=-
            --show-rule
            ${error_or_warning}
            # --xml-report=${noreport}
            ${exclusions}
            ${reportsrcs}
          DEPENDS ${reportsrcs}
          COMMENT "Checking style with vera++ in ${currentDir}"
        )
        list(APPEND xmlreports ${xmlreport})
        list(APPEND noreports ${noreport})
        vera_incr(reportNb)
        # clear the list for the next dir
        set(reportsrcs)
        set(currentDir ${d})
      endif()
      list(APPEND reportsrcs ${s})
    endif ()
  endforeach()
  # Create the custom targets that will trigger the custom command created
  # previously
  add_custom_target(${target_all} ALL DEPENDS ${xmlreports})
  add_custom_target(${target} DEPENDS ${noreports})
endfunction()
