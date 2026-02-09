# Distributed under the OSI-approved BSD 3-Clause License.  See accompanying
# file Copyright.txt or https://cmake.org/licensing for details.

cmake_minimum_required(VERSION 3.5)

file(MAKE_DIRECTORY
  "/home/chase/SPQSP/SPQSP_PDAC-main/PDAC/sim/build/_deps/jitify-src/jitify"
  "/home/chase/SPQSP/SPQSP_PDAC-main/PDAC/sim/build/_deps/jitify-build"
  "/home/chase/SPQSP/SPQSP_PDAC-main/PDAC/sim/build/_deps/jitify-subbuild/jitify-populate-prefix"
  "/home/chase/SPQSP/SPQSP_PDAC-main/PDAC/sim/build/_deps/jitify-subbuild/jitify-populate-prefix/tmp"
  "/home/chase/SPQSP/SPQSP_PDAC-main/PDAC/sim/build/_deps/jitify-subbuild/jitify-populate-prefix/src/jitify-populate-stamp"
  "/home/chase/SPQSP/SPQSP_PDAC-main/PDAC/sim/build/_deps/jitify-subbuild/jitify-populate-prefix/src"
  "/home/chase/SPQSP/SPQSP_PDAC-main/PDAC/sim/build/_deps/jitify-subbuild/jitify-populate-prefix/src/jitify-populate-stamp"
)

set(configSubDirs )
foreach(subDir IN LISTS configSubDirs)
    file(MAKE_DIRECTORY "/home/chase/SPQSP/SPQSP_PDAC-main/PDAC/sim/build/_deps/jitify-subbuild/jitify-populate-prefix/src/jitify-populate-stamp/${subDir}")
endforeach()
if(cfgdir)
  file(MAKE_DIRECTORY "/home/chase/SPQSP/SPQSP_PDAC-main/PDAC/sim/build/_deps/jitify-subbuild/jitify-populate-prefix/src/jitify-populate-stamp${cfgdir}") # cfgdir has leading slash
endif()
