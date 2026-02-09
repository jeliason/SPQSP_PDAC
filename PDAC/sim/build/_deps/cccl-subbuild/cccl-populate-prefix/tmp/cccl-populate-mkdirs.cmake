# Distributed under the OSI-approved BSD 3-Clause License.  See accompanying
# file Copyright.txt or https://cmake.org/licensing for details.

cmake_minimum_required(VERSION 3.5)

file(MAKE_DIRECTORY
  "/home/chase/SPQSP/SPQSP_PDAC-main/PDAC/sim/build/_deps/cccl-src"
  "/home/chase/SPQSP/SPQSP_PDAC-main/PDAC/sim/build/_deps/cccl-build"
  "/home/chase/SPQSP/SPQSP_PDAC-main/PDAC/sim/build/_deps/cccl-subbuild/cccl-populate-prefix"
  "/home/chase/SPQSP/SPQSP_PDAC-main/PDAC/sim/build/_deps/cccl-subbuild/cccl-populate-prefix/tmp"
  "/home/chase/SPQSP/SPQSP_PDAC-main/PDAC/sim/build/_deps/cccl-subbuild/cccl-populate-prefix/src/cccl-populate-stamp"
  "/home/chase/SPQSP/SPQSP_PDAC-main/PDAC/sim/build/_deps/cccl-subbuild/cccl-populate-prefix/src"
  "/home/chase/SPQSP/SPQSP_PDAC-main/PDAC/sim/build/_deps/cccl-subbuild/cccl-populate-prefix/src/cccl-populate-stamp"
)

set(configSubDirs )
foreach(subDir IN LISTS configSubDirs)
    file(MAKE_DIRECTORY "/home/chase/SPQSP/SPQSP_PDAC-main/PDAC/sim/build/_deps/cccl-subbuild/cccl-populate-prefix/src/cccl-populate-stamp/${subDir}")
endforeach()
if(cfgdir)
  file(MAKE_DIRECTORY "/home/chase/SPQSP/SPQSP_PDAC-main/PDAC/sim/build/_deps/cccl-subbuild/cccl-populate-prefix/src/cccl-populate-stamp${cfgdir}") # cfgdir has leading slash
endif()
