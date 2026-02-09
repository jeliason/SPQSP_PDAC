# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

SPQSP PDAC is a GPU-accelerated agent-based model (ABM) with CPU QSP coupling for simulating pancreatic ductal adenocarcinoma (PDAC) tumor microenvironment dynamics. It combines:
- **GPU**: Discrete agent-based modeling (cancer cells, T cells, regulatory T cells, MDSCs)
- **GPU**: Continuous PDE-based chemical diffusion (O2, IFN, IL2, IL10, TGFB, CCL2, ArgI, NO, IL12, VEGFA)
- **CPU**: Systemic QSP model via CVODE ODE solver (LymphCentral compartment, 59+ species)
- **Framework**: FLAMEGPU2 for GPU acceleration, SUNDIALS for ODE integration

## Implementation Status

**Phase 1 ✓**: PDE Parameter Alignment
- Updated diffusion coefficients for 10 chemicals (CPU HCC aligned)
- Updated decay rates from param_all_test.xml
- Added 4 new chemicals: ArgI, NO, IL12, VEGFA

**Phase 2 ✓**: Agent Behavior Alignment
- Cancer cell killing probability formula verified
- T cell state transitions (EFF→CYT→SUPP) verified
- PDL1 upregulation dynamics aligned
- Hill function parameters extracted and documented

**Phase 3 ✓**: QSP-ABM Coupling Infrastructure
- Created LymphCentral_wrapper class for CVODE integration
- Implemented CPU-GPU data exchange protocol
- Updated CMakeLists.txt for SUNDIALS support
- Architecture ready for full CVODE ODE system integration

**Phase 4 ✓**: Parameter Extraction and Alignment
- Extracted 85+ behavioral and chemical parameters
- Created PARAMETER_REFERENCE.md with complete documentation
- Parameter verification script: all values match expected
- Movement probabilities, division intervals, lifespan parameters verified

**Phase 5 ⏳**: Validation and Testing (In Progress)
- Unit tests planned for PDE solver, agent movement, state transitions
- Integration tests for small (10³) and full (51³) grids
- Comparative validation with GPU vs CPU outputs
- Performance benchmarking and numerical stability tests

## Build Commands

```bash
# Build (release)
cd PDAC/sim && ./build.sh

# Build (debug)
./build.sh --debug

# Set CUDA architecture (75=RTX 20xx, 80=A100, 86=RTX 30xx, 89=RTX 40xx)
./build.sh --cuda-arch 86

# Use local FLAMEGPU2 source
./build.sh --flamegpu ~/FLAMEGPU2

# Clean build
./build.sh --clean
```

Output binary: `PDAC/sim/build/bin/pdac`

## Running Simulations

```bash
./build/bin/pdac [options]
  -g, --grid-size N        Grid size (default: 51)
  -s, --steps N            Simulation steps (default: 500)
  -r, --radius N           Initial tumor radius (default: 5)
  -t, --tcells N           Initial T cell count (default: 50)
  --tregs N                Initial TReg count (default: 10)
  --mdscs N                Initial MDSC count (default: 5)
  -m, --move-steps N       Movement iterations per ABM step (default: 111)
```

## Architecture

### Directory Structure
```
PDAC/
├── sim/          # Main simulation (main.cu, model_definition.cu)
├── agents/       # Agent CUDA device functions (cancer_cell.cuh, t_cell.cuh, t_reg.cuh, mdsc.cuh)
├── core/         # Shared definitions and enums (common.cuh)
└── pde/          # Chemical transport solver (pde_solver.cu/cuh, pde_integration.cu/cuh)
SP_QSP_shared/    # CPU-side ABM base classes (ABM_Base/, Numerical_Adaptor/)
BioFVM/           # Diffusion solver library
```

### Agent Types (PDAC namespace in core/common.cuh)
- **CancerCell**: States - Stem, Progenitor, PDL1+, PDL1-, Senescent
- **TCell**: States - Effector, Cytotoxic, Suppressed
- **TReg**: Regulatory T cells
- **MDSC**: Myeloid-Derived Suppressor Cells

### Key Patterns

**Two-Phase Conflict Resolution**: Agents use intent-based movement/division:
1. Phase 1: Select targets, broadcast intent via `MSG_INTENT` messages
2. Phase 2: Execute actions after checking for conflicts

**Spatial Messaging**: All agents broadcast location via `MSG_CELL_LOCATION`, receivers query 26-neighborhood (Moore neighborhood).

**Agent-PDE Coupling**: Each ABM step runs multiple PDE substeps. Chemical concentrations are read into agent `local_*` variables, agents compute source/sink terms, PDE solver advances diffusion.

### Agent Function Naming Convention
Functions are prefixed by agent type: `cancer_broadcast_location`, `tcell_scan_neighbors`, `treg_compute_suppression`, `mdsc_movement`, etc.

### Voxel Capacity Constants (common.cuh)
- `MAX_T_PER_VOXEL = 8` (empty voxel)
- `MAX_T_PER_VOXEL_WITH_CANCER = 1`
- `MAX_CANCER_PER_VOXEL = 1`
- `MAX_MDSC_PER_VOXEL = 1`

## Dependencies

- CUDA Toolkit 11.0+
- CMake 3.18+
- C++17 compiler
- FLAMEGPU2 v2.0.0-rc.4 (auto-fetched via CMake FetchContent)
