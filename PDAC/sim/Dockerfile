# ============================================================================
# SPQSP_PDAC simulation environment
#
# Layer structure (top = changes least, bottom = changes most):
#   1. CUDA + system deps + SUNDIALS + Boost  (rarely changes)
#   2. FLAMEGPU2 library build                (only on FLAMEGPU version bump)
#   3. Clone + build simulation code          (changes with each code update)
#
# Build:
#   docker build -t spqsp-pdac:latest .
#   docker build --build-arg CUDA_ARCH=89 -t spqsp-pdac:l40s .
#
# Run (interactive shell):
#   docker run --gpus all -it spqsp-pdac:latest
# ============================================================================

FROM nvidia/cuda:12.8.0-devel-ubuntu24.04

ENV DEBIAN_FRONTEND=noninteractive

# ---- Layer 1: System dependencies (cached until base image or deps change) ----
RUN apt-get update -qq && \
    apt-get install -y -qq --no-install-recommends \
        cmake g++ git ca-certificates curl \
        libboost-serialization-dev \
        vim less python3 \
    && rm -rf /var/lib/apt/lists/*

# Build SUNDIALS 6.3.0 from source
ARG SUNDIALS_VER=6.3.0
RUN cd /tmp && \
    curl -sL "https://github.com/LLNL/sundials/releases/download/v${SUNDIALS_VER}/sundials-${SUNDIALS_VER}.tar.gz" | tar xz && \
    cd sundials-${SUNDIALS_VER} && \
    cmake -S . -B build \
        -DCMAKE_INSTALL_PREFIX=/usr/local \
        -DCMAKE_BUILD_TYPE=Release \
        -DBUILD_SHARED_LIBS=ON \
        -DEXAMPLES_ENABLE_C=OFF \
        -DEXAMPLES_ENABLE_CXX=OFF && \
    cmake --build build --parallel $(nproc) && \
    cmake --install build && \
    rm -rf /tmp/sundials-${SUNDIALS_VER}

# ---- Layer 2: FLAMEGPU2 build (cached until version tag changes) ----
ARG CUDA_ARCH=80
ARG FLAMEGPU_TAG=v2.0.0-rc.4

WORKDIR /opt/flamegpu
RUN git clone --branch ${FLAMEGPU_TAG} --depth 1 https://github.com/FLAMEGPU/FLAMEGPU2.git src && \
    mkdir build && cd build && \
    cmake ../src \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_CUDA_ARCHITECTURES=${CUDA_ARCH} \
        -DFLAMEGPU_BUILD_TESTS=OFF \
        -DFLAMEGPU_BUILD_PYTHON=OFF && \
    cmake --build . --parallel $(nproc)

# ---- Layer 3: Simulation code (rebuilds on code changes) ----
ARG BRANCH=main

WORKDIR /workspace
RUN git clone --branch ${BRANCH} https://github.com/jeliason/SPQSP_PDAC.git && \
    cd SPQSP_PDAC/PDAC/sim && \
    cmake -S . -B build \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_CUDA_ARCHITECTURES=${CUDA_ARCH} \
        -DSUNDIALS_DIR=/usr/local \
        -DFLAMEGPU_ROOT=/opt/flamegpu/src && \
    cmake --build build --parallel $(nproc)

WORKDIR /workspace/SPQSP_PDAC/PDAC/sim
CMD ["/bin/bash"]