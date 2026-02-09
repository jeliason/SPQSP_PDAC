# Distributed under the OSI-approved BSD 3-Clause License.  See accompanying
# file Copyright.txt or https://cmake.org/licensing for details.

cmake_minimum_required(VERSION 3.5)

file(MAKE_DIRECTORY
  "/home/chase/SPQSP/SPQSP_PDAC-main/PDAC/sim/build/_deps/tinyxml2-src/tinyxml2"
  "/home/chase/SPQSP/SPQSP_PDAC-main/PDAC/sim/build/_deps/tinyxml2-build"
  "/home/chase/SPQSP/SPQSP_PDAC-main/PDAC/sim/build/_deps/tinyxml2-subbuild/tinyxml2-populate-prefix"
  "/home/chase/SPQSP/SPQSP_PDAC-main/PDAC/sim/build/_deps/tinyxml2-subbuild/tinyxml2-populate-prefix/tmp"
  "/home/chase/SPQSP/SPQSP_PDAC-main/PDAC/sim/build/_deps/tinyxml2-subbuild/tinyxml2-populate-prefix/src/tinyxml2-populate-stamp"
  "/home/chase/SPQSP/SPQSP_PDAC-main/PDAC/sim/build/_deps/tinyxml2-subbuild/tinyxml2-populate-prefix/src"
  "/home/chase/SPQSP/SPQSP_PDAC-main/PDAC/sim/build/_deps/tinyxml2-subbuild/tinyxml2-populate-prefix/src/tinyxml2-populate-stamp"
)

set(configSubDirs )
foreach(subDir IN LISTS configSubDirs)
    file(MAKE_DIRECTORY "/home/chase/SPQSP/SPQSP_PDAC-main/PDAC/sim/build/_deps/tinyxml2-subbuild/tinyxml2-populate-prefix/src/tinyxml2-populate-stamp/${subDir}")
endforeach()
if(cfgdir)
  file(MAKE_DIRECTORY "/home/chase/SPQSP/SPQSP_PDAC-main/PDAC/sim/build/_deps/tinyxml2-subbuild/tinyxml2-populate-prefix/src/tinyxml2-populate-stamp${cfgdir}") # cfgdir has leading slash
endif()
