cmake_minimum_required(VERSION 3.18)

# CUDA language support
project(PDAC CUDA CXX)

# Set C++ and CUDA standards
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CUDA_STANDARD 17)
set(CMAKE_CUDA_STANDARD_REQUIRED ON)

add_compile_options($<$<COMPILE_LANGUAGE:CUDA>:--diag-suppress=1301>)

# Option for FLAMEGPU2 location
set(FLAMEGPU_ROOT "" CACHE PATH "Path to FLAMEGPU2 installation or source")

# Disable Runtime Compilation (RTC) - compile CUDA code ahead-of-time during build
# This increases build time but eliminates JIT compilation delay on first run
set(FLAMEGPU_ENABLE_RTC OFF CACHE BOOL "Disable RTC for ahead-of-time compilation")

# Disable FLAMEGPU seatbelt runtime checks.
# Seatbelts flag mixed read + atomic-write on the same MacroProperty in one layer,
# but our occupancy grid uses CAS (which atomically handles compare-and-swap) — this
# is semantically safe and the conservative seatbelt check produces false positives.
set(FLAMEGPU_SEATBELTS OFF CACHE BOOL "Disable FLAMEGPU2 seatbelt checks" FORCE)

# Set CUDA architecture
# Common architectures:
#   70 = V100
#   75 = RTX 20xx, T4
#   80 = A100
#   86 = RTX 30xx
#   89 = RTX 40xx
if(NOT DEFINED CMAKE_CUDA_ARCHITECTURES)
    set(CMAKE_CUDA_ARCHITECTURES 75 80 86)
endif()

# Find SUNDIALS (CVODE) - optional for QSP coupling
# Searches SUNDIALS_DIR, then common HPC module paths
set(SUNDIALS_DIR "$ENV{HOME}/lib/sundials-4.0.1" CACHE PATH "SUNDIALS installation directory")
set(SUNDIALS_FOUND FALSE)
# Try lib/ then lib64/ for the library directory
foreach(_sundials_libdir "lib" "lib64")
    if(EXISTS "${SUNDIALS_DIR}/${_sundials_libdir}" AND EXISTS "${SUNDIALS_DIR}/include")
        # Find cvode library (try .so then .a)
        find_library(_sundials_cvode NAMES sundials_cvode
            PATHS "${SUNDIALS_DIR}/${_sundials_libdir}" NO_DEFAULT_PATH)
        find_library(_sundials_nvec NAMES sundials_nvecserial
            PATHS "${SUNDIALS_DIR}/${_sundials_libdir}" NO_DEFAULT_PATH)
        if(_sundials_cvode AND _sundials_nvec)
            set(SUNDIALS_FOUND TRUE)
            set(SUNDIALS_INCLUDE_DIR "${SUNDIALS_DIR}/include")
            set(SUNDIALS_LIBRARIES "${_sundials_cvode}" "${_sundials_nvec}")
            message(STATUS "SUNDIALS found at ${SUNDIALS_DIR} (${_sundials_libdir})")
            break()
        endif()
        unset(_sundials_cvode CACHE)
        unset(_sundials_nvec CACHE)
    endif()
endforeach()
if(NOT SUNDIALS_FOUND)
    message(STATUS "SUNDIALS not found at ${SUNDIALS_DIR}")
endif()

# Find BOOST for optional QSP features
# Checks BOOST_ROOT env var (set by HPC modules), then fallback path
if(DEFINED ENV{BOOST_ROOT})
    set(BOOST_ROOT "$ENV{BOOST_ROOT}" CACHE PATH "Boost installation directory" FORCE)
else()
    set(BOOST_ROOT "$ENV{HOME}/lib/boost_1_70_0" CACHE PATH "Boost installation directory")
endif()
set(Boost_FOUND FALSE)
foreach(_boost_libdir "lib" "lib64")
    if(EXISTS "${BOOST_ROOT}/${_boost_libdir}" AND EXISTS "${BOOST_ROOT}/include")
        find_library(_boost_serial NAMES boost_serialization
            PATHS "${BOOST_ROOT}/${_boost_libdir}" NO_DEFAULT_PATH)
        if(_boost_serial)
            set(Boost_FOUND TRUE)
            set(Boost_INCLUDE_DIR "${BOOST_ROOT}/include")
            set(Boost_LIBRARIES "${_boost_serial}")
            message(STATUS "Boost found at ${BOOST_ROOT} (${_boost_libdir})")
            break()
        endif()
        unset(_boost_serial CACHE)
    endif()
endforeach()
if(NOT Boost_FOUND)
    message(STATUS "Boost not found at ${BOOST_ROOT}")
endif()

# Find FLAMEGPU2 via FetchContent
include(FetchContent)

if(NOT TARGET flamegpu)
    if(FLAMEGPU_ROOT AND EXISTS "${FLAMEGPU_ROOT}/CMakeLists.txt")
        message(STATUS "Using local FLAMEGPU2 from: ${FLAMEGPU_ROOT}")
        add_subdirectory(${FLAMEGPU_ROOT} ${CMAKE_CURRENT_BINARY_DIR}/flamegpu)
    else()
        message(STATUS "Fetching FLAMEGPU2 from GitHub...")
        FetchContent_Declare(
            flamegpu
            GIT_REPOSITORY https://github.com/FLAMEGPU/FLAMEGPU2.git
            GIT_TAG        v2.0.0-rc.4
            GIT_SHALLOW    TRUE
        )
        FetchContent_MakeAvailable(flamegpu)
    endif()
endif()

# Define executable with ALL source files
add_executable(pdac
    main.cu
    model_definition.cu
    model_layers.cu
    initialization.cu
    ../pde/pde_integration.cu
    ../pde/pde_solver.cu
    ../qsp/LymphCentral_wrapper.cpp
    ../qsp/cvode/CVODEBase.cpp
    ../qsp/ode/ODE_system.cpp
    ../qsp/ode/QSPParam.cpp
    ../qsp/qsp_integration.cu
    ../core/ParamBase.cpp
    ../core/model_functions.cu
    ../abm/gpu_param.cu
)

# Link against FLAMEGPU2
target_link_libraries(pdac PRIVATE flamegpu)
target_compile_definitions(pdac PRIVATE FLAMEGPU_SEATBELTS=0)

# Link against SUNDIALS if available (optional QSP support)
if(SUNDIALS_FOUND)
    message(STATUS "SUNDIALS found - QSP coupling enabled")
    target_link_libraries(pdac PRIVATE ${SUNDIALS_LIBRARIES})
    target_include_directories(pdac PRIVATE ${SUNDIALS_INCLUDE_DIR})
    target_compile_definitions(pdac PRIVATE QSP_CVODE_ENABLED=1)
else()
    message(WARNING "SUNDIALS not found - QSP coupling disabled. Set SUNDIALS_DIR to enable.")
endif()

# Link against Boost if available
if(Boost_FOUND)
    message(STATUS "Boost found - QSP serialization enabled")
    target_link_libraries(pdac PRIVATE ${Boost_LIBRARIES})
    target_include_directories(pdac SYSTEM PRIVATE ${Boost_INCLUDE_DIR})
else()
    message(WARNING "Boost not found - QSP serialization disabled. Set BOOST_ROOT to enable.")
endif()

cmake_path(GET CMAKE_CURRENT_SOURCE_DIR PARENT_PATH MY_PARENT_DIR)
# Include directories
target_include_directories(pdac PRIVATE
    ${MY_PARENT_DIR}/core
    ${MY_PARENT_DIR}/pde
    ${MY_PARENT_DIR}/agents
    ${MY_PARENT_DIR}/qsp
    ${MY_PARENT_DIR}/abm
)

# Enable separable compilation for CUDA (required by FLAMEGPU2)
set_target_properties(pdac PROPERTIES
    CUDA_SEPARABLE_COMPILATION ON
    CUDA_RESOLVE_DEVICE_SYMBOLS ON
)

target_compile_options(pdac PRIVATE
    $<$<COMPILE_LANGUAGE:CUDA>:--diag-suppress=1301>
)

# Boost 1.82+ uses std::source_location in throw_exception.hpp which triggers
# an nvcc bug with consteval. Disable it for CUDA compilation.
target_compile_definitions(pdac PRIVATE
    $<$<COMPILE_LANGUAGE:CUDA>:BOOST_NO_CXX20_HDR_SOURCE_LOCATION>
)

# Build type
if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release)
endif()

# Compiler flags
if(CMAKE_BUILD_TYPE STREQUAL "Debug")
    target_compile_options(pdac PRIVATE
        $<$<COMPILE_LANGUAGE:CUDA>:-G>
    )
endif()

# Output directory
set_target_properties(pdac PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin
)

# Installation
install(TARGETS pdac DESTINATION bin)

# ============================================================================
# PDE Solver Validation Tests (no FLAMEGPU dependency — standalone CUDA only)
# ============================================================================
add_executable(pde_test
    ../pde/pde_test.cu
    ../pde/pde_solver.cu
)

set_target_properties(pde_test PROPERTIES
    CUDA_SEPARABLE_COMPILATION ON
    RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin
)

target_include_directories(pde_test PRIVATE
    ${MY_PARENT_DIR}/pde
)

target_compile_options(pde_test PRIVATE
    $<$<COMPILE_LANGUAGE:CUDA>:--diag-suppress=1301>
)

# Print configuration summary
message(STATUS "")
message(STATUS "=== PDAC GPU Configuration ===")
message(STATUS "Build type: ${CMAKE_BUILD_TYPE}")
message(STATUS "CUDA architectures: ${CMAKE_CUDA_ARCHITECTURES}")
message(STATUS "Runtime Compilation (RTC): ${FLAMEGPU_ENABLE_RTC}")
message(STATUS "Output directory: ${CMAKE_BINARY_DIR}/bin")
message(STATUS "")
