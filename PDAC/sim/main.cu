#include "flamegpu/flamegpu.h"
#include <iostream>
#include <memory>

#include "../core/common.cuh"
#include "../pde/pde_integration.cuh"
#include "initialization.cuh"
#include "gpu_param.h"
#include "../qsp/LymphCentral_wrapper.h"
#include "../core/model_functions.cuh"

namespace PDAC {
    std::unique_ptr<flamegpu::ModelDescription> buildModel(
        int grid_x, int grid_y, int grid_z, float voxel_size,
        const PDAC::GPUParam& gpu_params);

    // void set_internal_params(flamegpu::ModelDescription& model, 
    //                          const LymphCentralWrapper& lymph);
}

// ============================================================================
// Simulation Monitoring Functions
// ============================================================================

FLAMEGPU_STEP_FUNCTION(stepCounter) {
    unsigned int step = FLAMEGPU->environment.getProperty<unsigned int>("current_step");
    FLAMEGPU->environment.setProperty<unsigned int>("current_step", step + 1);

    if (step % 50 == 0) {
        const unsigned int cancer_count = FLAMEGPU->agent(PDAC::AGENT_CANCER_CELL).count();
        const unsigned int tcell_count = FLAMEGPU->agent(PDAC::AGENT_TCELL).count();
        const unsigned int treg_count = FLAMEGPU->agent(PDAC::AGENT_TREG).count();
        const unsigned int mdsc_count = FLAMEGPU->agent(PDAC::AGENT_MDSC).count();
        std::cout << "Step " << step
                  << ": Cancer=" << cancer_count
                  << ", T cells=" << tcell_count
                  << ", TRegs=" << treg_count
                  << ", MDSCs=" << mdsc_count << std::endl;
    }
}

FLAMEGPU_EXIT_CONDITION(checkSimulationEnd) {
    const unsigned int cancer_count = FLAMEGPU->agent(PDAC::AGENT_CANCER_CELL).count();
    if (cancer_count == 0) {
        std::cout << "\nAll cancer cells eliminated!" << std::endl;
        return flamegpu::EXIT;
    }
    return flamegpu::CONTINUE;
}

// ============================================================================
// Main
// ============================================================================

int main(int argc, const char** argv) {
    // Check for -p flag (XML path override)
    std::string param_file = "/home/chase/SPQSP/SPQSP_PDAC-main/PDAC/sim/resource/param_all_test.xml";
    for (int i = 1; i < argc; i++) {
        if (std::string(argv[i]) == "-p" && i + 1 < argc) {
            param_file = argv[++i];
            break;
        }
    }

    // Load XML parameters
    std::cout << "Loading parameters from: " << param_file << std::endl;
    PDAC::GPUParam gpu_params;
    try {
        gpu_params.initializeParams(param_file);
        std::cout << "Parameters loaded successfully." << std::endl;
    } catch (const std::exception& e) {
        std::cerr << "ERROR: Failed to load parameters from XML: " << e.what() << std::endl;
        return 1;
    }

    // Parse configuration from command line
    PDAC::SimulationConfig config;
    config.parseCommandLine(argc, argv, gpu_params);
    config.print();

    // Seed random number generator
    srand(config.random_seed);
    
    // ========== BUILD MODEL ==========
    std::cout << "Building FLAME GPU 2 model..." << std::endl;
    auto model = PDAC::buildModel(
        config.grid_x, config.grid_y, config.grid_z,
        config.voxel_size,
        gpu_params);
    
    // ========== INITIALIZE PDE SOLVER ==========
    std::cout << "Initializing PDE solver..." << std::endl;
    PDAC::initialize_pde_solver(
        config.grid_x, config.grid_y, config.grid_z, 
        config.voxel_size, config.dt_abm, config.molecular_steps,
         gpu_params);
    
    // Store PDE device pointers in model environment
    PDAC::set_pde_pointers_in_environment(*model);

    //     TODO
    // Process internal parameters from env params and new QSP params
    // ========== INITIALIZE QSP SOLVER ==========
    PDAC::LymphCentralWrapper _lymph;
    _lymph.initialize(param_file);
    PDAC::set_internal_params(*model, _lymph);

    // ========== ADD STEP FUNCTIONS ==========
    model->addStepFunction(stepCounter);
    model->addExitCondition(checkSimulationEnd);
    
    // ========== CREATE SIMULATION ==========
    std::cout << "Creating CUDA simulation..." << std::endl;
    flamegpu::CUDASimulation simulation(*model);
    simulation.SimulationConfig().steps = config.steps;
    simulation.SimulationConfig().random_seed = config.random_seed;
    
    // ========== INITIALIZE AGENTS ==========
    if (config.init_method == 0) {
        std::cout << "Initializing agents with random distribution..." << std::endl;
        PDAC::initializeAllAgents(simulation, *model, config);
    } else { // do nothing, no other options right now
        std::cout << "Broken initialization" << std::endl;
        return 1;
    }
    
    // ========== RUN SIMULATION ==========
    std::cout << "\n=== Starting Simulation ===" << std::endl;
    simulation.simulate();
    
    // ========== REPORT RESULTS ==========
    std::cout << "\n=== Simulation Complete ===" << std::endl;
    
    flamegpu::AgentVector final_cancer(model->Agent(PDAC::AGENT_CANCER_CELL));
    flamegpu::AgentVector final_tcells(model->Agent(PDAC::AGENT_TCELL));
    flamegpu::AgentVector final_tregs(model->Agent(PDAC::AGENT_TREG));
    flamegpu::AgentVector final_mdscs(model->Agent(PDAC::AGENT_MDSC));
    
    simulation.getPopulationData(final_cancer);
    simulation.getPopulationData(final_tcells);
    simulation.getPopulationData(final_tregs);
    simulation.getPopulationData(final_mdscs);

    std::cout << "\nFinal Population Counts:" << std::endl;
    std::cout << "  Cancer cells: " << final_cancer.size() << std::endl;
    std::cout << "  T cells: " << final_tcells.size() << std::endl;
    std::cout << "  TRegs: " << final_tregs.size() << std::endl;
    std::cout << "  MDSCs: " << final_mdscs.size() << std::endl;

    // Count T cell states
    if (final_tcells.size() > 0) {
        int eff_count = 0, cyt_count = 0, supp_count = 0;
        for (unsigned int i = 0; i < final_tcells.size(); i++) {
            int state = final_tcells[i].getVariable<int>("cell_state");
            if (state == PDAC::T_CELL_EFF) eff_count++;
            else if (state == PDAC::T_CELL_CYT) cyt_count++;
            else if (state == PDAC::T_CELL_SUPP) supp_count++;
        }
        std::cout << "  T cell states - Effector: " << eff_count
                  << ", Cytotoxic: " << cyt_count
                  << ", Suppressed: " << supp_count << std::endl;
    }
    
    // ========== CLEANUP ==========
    PDAC::cleanup_pde_solver();
    
    std::cout << "\nSimulation finished successfully." << std::endl;
    
    return 0;
}