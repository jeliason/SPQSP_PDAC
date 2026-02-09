#include "flamegpu/flamegpu.h"
#include <memory>

#include "../core/common.cuh"
#include "../agents/cancer_cell.cuh"
#include "../agents/t_cell.cuh"
#include "../agents/t_reg.cuh"
#include "../agents/mdsc.cuh"

#include "../pde/pde_integration.cuh"
#include "gpu_param.h"
#include "../qsp/ode/ODE_system.h"
#include "../qsp/LymphCentral_wrapper.h"
#include "../qsp/ode/QSP_enum.h"

#define QP(x) CancerVCT::ODE_system::get_class_param(x)

#define AVOGADROS 6.022140857E23 
#define PI 3.1415926525897932384626
static int SEC_PER_DAY = 86400;
static int HOUR_PER_DAY = 24;

namespace PDAC {
// Declare HostFunction objects from pde_integration.cu
// These are defined using FLAMEGPU_HOST_FUNCTION macro which creates
// flamegpu::FLAMEGPU_HOST_FUNCTION_POINTER global variables
extern flamegpu::FLAMEGPU_HOST_FUNCTION_POINTER update_agent_chemicals;
extern flamegpu::FLAMEGPU_HOST_FUNCTION_POINTER collect_agent_sources;
extern flamegpu::FLAMEGPU_HOST_FUNCTION_POINTER solve_pde_step;
extern flamegpu::FLAMEGPU_HOST_FUNCTION_POINTER update_agent_counts;

// Forward declarations
void defineCancerCellAgent(flamegpu::ModelDescription& model, bool include_state_divide);
void defineTCellAgent(flamegpu::ModelDescription& model, bool include_state_divide);
void defineTRegAgent(flamegpu::ModelDescription& model, bool include_state_divide);
void defineMDSCAgent(flamegpu::ModelDescription& model, bool include_state);

// Define the CancerCell agent and its variables
void defineCancerCellAgent(flamegpu::ModelDescription& model, bool include_state_divide) {
    flamegpu::AgentDescription cancer_cell = model.newAgent(AGENT_CANCER_CELL);

    // Identity
    cancer_cell.newVariable<unsigned int>("id");

    // Position (discrete voxel coordinates)
    cancer_cell.newVariable<int>("x");
    cancer_cell.newVariable<int>("y");
    cancer_cell.newVariable<int>("z");

    // State (CancerState enum)
    cancer_cell.newVariable<int>("cell_state", CANCER_STEM);

    // Division control
    cancer_cell.newVariable<int>("divideCD", 0);
    cancer_cell.newVariable<int>("divideFlag", 1);
    cancer_cell.newVariable<int>("divideCountRemaining", 0);
    cancer_cell.newVariable<unsigned int>("stemID", 0);

    cancer_cell.newVariable<float>("local_NO", 0.0f);
    cancer_cell.newVariable<float>("local_ArgI", 0.0f);
    cancer_cell.newVariable<float>("local_TGFB", 0.0f);
    cancer_cell.newVariable<float>("local_O2", 0.0f);
    cancer_cell.newVariable<float>("local_IFNg", 0.0f);
    
    // Molecular state (affects behavior)
    cancer_cell.newVariable<float>("PDL1_surface", 0.0f);      // PDL1 expression level [0-1]
    cancer_cell.newVariable<float>("PDL1_syn_rate", 0.0f);     // Current synthesis rate
    cancer_cell.newVariable<float>("PDL1_syn", 0.0f);
    cancer_cell.newVariable<int>("hypoxic", 0);                // Boolean: O2 below threshold
    
    // Drug effects (computed from local concentrations)
    cancer_cell.newVariable<float>("cabo_effect", 0.0f);       // VEGF inhibition level [0-1]

    // Neighbor counts (computed each step)
    cancer_cell.newVariable<int>("neighbor_Teff_count", 0);
    cancer_cell.newVariable<int>("neighbor_Treg_count", 0);
    cancer_cell.newVariable<int>("neighbor_cancer_count", 0);
    cancer_cell.newVariable<int>("neighbor_MDSC_count", 0);

    // Cached bitmask of available neighbor voxels (no cancer cell, in bounds)
    cancer_cell.newVariable<unsigned int>("available_neighbors", 0u);

    // Lifecycle
    cancer_cell.newVariable<int>("life", 0);
    cancer_cell.newVariable<int>("dead", 0);

    // Intent variables for two-phase conflict resolution
    cancer_cell.newVariable<int>("intent_action", INTENT_NONE);
    cancer_cell.newVariable<int>("target_x", -1);
    cancer_cell.newVariable<int>("target_y", -1);
    cancer_cell.newVariable<int>("target_z", -1);

    // Source/Sink rates
    cancer_cell.newVariable<float>("CCL2_release_rate", 0.0f);
    cancer_cell.newVariable<float>("TGFB_release_rate", 0.0f);
    cancer_cell.newVariable<float>("VEGFA_release_rate", 0.0f);
    cancer_cell.newVariable<float>("O2_uptake_rate", 0.0f);
    cancer_cell.newVariable<float>("IFNg_uptake_rate", 0.0f);

    // Define agent functions - movement functions always needed
    cancer_cell.newFunction("broadcast_location", cancer_broadcast_location)
        .setMessageOutput(MSG_CELL_LOCATION);

    cancer_cell.newFunction("count_neighbors", cancer_count_neighbors)
        .setMessageInput(MSG_CELL_LOCATION);

    cancer_cell.newFunction("update_chemicals", cancer_update_chemicals);
    
    cancer_cell.newFunction("compute_chemical_sources", cancer_compute_chemical_sources);

    cancer_cell.newFunction("select_move_target", cancer_select_move_target)
        .setMessageOutput(MSG_INTENT);

    cancer_cell.newFunction("execute_move", cancer_execute_move)
        .setMessageInput(MSG_INTENT);

    // Division and state functions only in main model
    if (include_state_divide) {
        cancer_cell.newFunction("state_step", cancer_cell_state_step)
            .setAllowAgentDeath(true);

        cancer_cell.newFunction("select_divide_target", cancer_select_divide_target)
            .setMessageOutput(MSG_INTENT);

        {
            flamegpu::AgentFunctionDescription fn = cancer_cell.newFunction("execute_divide", cancer_execute_divide);
            fn.setMessageInput(MSG_INTENT);
            fn.setAgentOutput(cancer_cell);
        }
    }


}

// Define the TCell agent and its variables
void defineTCellAgent(flamegpu::ModelDescription& model, bool include_state_divide) {
    flamegpu::AgentDescription tcell = model.newAgent(AGENT_TCELL);

    // Identity
    tcell.newVariable<unsigned int>("id");

    // Position
    tcell.newVariable<int>("x");
    tcell.newVariable<int>("y");
    tcell.newVariable<int>("z");

    // State: T_CELL_EFF=0, T_CELL_CYT=1, T_CELL_SUPP=2
    tcell.newVariable<int>("cell_state", T_CELL_EFF);

    // Division control
    tcell.newVariable<int>("divide_flag", 0);
    tcell.newVariable<int>("divide_cd", 0);
    tcell.newVariable<int>("divide_limit", 10);

    // Molecular exposure
    tcell.newVariable<float>("local_O2", 0.0f);
    tcell.newVariable<float>("local_IFN", 0.0f);
    tcell.newVariable<float>("local_IL2", 0.0f);
    tcell.newVariable<float>("local_IL10", 0.0f);        // From Tregs (suppressive)
    tcell.newVariable<float>("local_TGFB", 0.0f);        // From Tregs (suppressive)
    tcell.newVariable<float>("local_ArgI", 0.0f);        // From MDSCs (T cell suppression)
    tcell.newVariable<float>("local_NO", 0.0f);          // From MDSCs (T cell suppression)
    tcell.newVariable<float>("local_IL12", 0.0f);        // From macrophages (T cell activation)
    
    // Chemical production/release
    tcell.newVariable<float>("IFNg_release_rate", 0.0f);  // Current release rate (mol/s)
    tcell.newVariable<float>("IL2_release_rate", 0.0f);   // Current release rate (mol/s)
    tcell.newVariable<float>("IFN_release_remain", 0.0f); // Time remaining to release IFN (s)
    tcell.newVariable<float>("IL2_release_remain", 0.0f); // Time remaining to release IL2 (s)
    
    // Molecular exposure (cumulative for decisions)
    tcell.newVariable<float>("IL2_exposure", 0.0f);       // Cumulative IL2 exposure
    tcell.newVariable<float>("IL10_exposure", 0.0f);      // Cumulative suppression
    tcell.newVariable<float>("TGFB_exposure", 0.0f);      // Cumulative suppression
    
    // Drug effects
    tcell.newVariable<float>("PD1_occupancy", 0.0f);      // Fraction of PD1 blocked by Nivo [0-1]
    
    // Functional state (affected by chemicals)
    tcell.newVariable<float>("activation_level", 1.0f);   // Activity level [0-1]
    tcell.newVariable<int>("can_proliferate", 0);         // Boolean: IL2 above threshold

    // Neighbor counts (computed via messaging)
    tcell.newVariable<int>("neighbor_cancer_count", 0);
    tcell.newVariable<int>("neighbor_Treg_count", 0);
    tcell.newVariable<int>("neighbor_all_count", 0);
    tcell.newVariable<float>("max_neighbor_PDL1", 0.0f);
    tcell.newVariable<int>("found_progenitor", 0);

    // Cached bitmask of available neighbor voxels
    tcell.newVariable<unsigned int>("available_neighbors", 0u);

    // Lifecycle
    tcell.newVariable<int>("life", 100);
    tcell.newVariable<int>("dead", 0);

    // Intent variables for two-phase conflict resolution
    tcell.newVariable<int>("intent_action", INTENT_NONE);
    tcell.newVariable<int>("target_x", -1);
    tcell.newVariable<int>("target_y", -1);
    tcell.newVariable<int>("target_z", -1);

    // Define agent functions - movement functions always needed
    tcell.newFunction("broadcast_location", tcell_broadcast_location)
        .setMessageOutput(MSG_CELL_LOCATION);

    tcell.newFunction("scan_neighbors", tcell_scan_neighbors)
        .setMessageInput(MSG_CELL_LOCATION);

    tcell.newFunction("update_chemicals", tcell_update_chemicals);
    
    tcell.newFunction("compute_chemical_sources", tcell_compute_chemical_sources);

    tcell.newFunction("select_move_target", tcell_select_move_target)
        .setMessageOutput(MSG_INTENT);

    tcell.newFunction("execute_move", tcell_execute_move)
        .setMessageInput(MSG_INTENT);

    // Division and state functions only in main model
    if (include_state_divide) {
        tcell.newFunction("state_step", tcell_state_step)
            .setAllowAgentDeath(true);

        tcell.newFunction("select_divide_target", tcell_select_divide_target)
            .setMessageOutput(MSG_INTENT);

        {
            flamegpu::AgentFunctionDescription fn = tcell.newFunction("execute_divide", tcell_execute_divide);
            fn.setMessageInput(MSG_INTENT);
            fn.setAgentOutput(tcell);
        }
    }
}

// Define the TReg agent and its variables
void defineTRegAgent(flamegpu::ModelDescription& model, bool include_state_divide) {
    flamegpu::AgentDescription treg = model.newAgent(AGENT_TREG);

    // Identity
    treg.newVariable<unsigned int>("id");

    // Position
    treg.newVariable<int>("x");
    treg.newVariable<int>("y");
    treg.newVariable<int>("z");

    // Division control
    treg.newVariable<int>("divide_flag", 0);
    treg.newVariable<int>("divide_cd", 0);
    treg.newVariable<int>("divide_limit", 10);

     // Local chemical concentrations
    treg.newVariable<float>("local_O2", 0.0f);
    treg.newVariable<float>("local_IL2", 0.0f);          // Tregs respond to IL2
    treg.newVariable<float>("local_TGFB", 0.0f);         // Positive feedback
    treg.newVariable<float>("local_ArgI", 0.0f);         // From MDSCs (immune suppression)
    treg.newVariable<float>("local_NO", 0.0f);           // From MDSCs (immune suppression)
    
    // Chemical production (Tregs are major source of IL10 and TGF-beta)
    treg.newVariable<float>("IL10_release_rate", 0.0f);
    treg.newVariable<float>("TGFB_release_rate", 0.0f);
    treg.newVariable<float>("IL2_consumption_rate", 0.0f); // Tregs consume IL2
    
    // Molecular exposure
    treg.newVariable<float>("IL2_exposure", 0.0f);
    
    // Functional state
    treg.newVariable<float>("suppression_strength", 1.0f); // Suppressive capacity [0-1]
    treg.newVariable<int>("can_proliferate", 0);

    // Neighbor counts (computed via messaging)
    treg.newVariable<int>("neighbor_Tcell_count", 0);
    treg.newVariable<int>("neighbor_Treg_count", 0);
    treg.newVariable<int>("neighbor_cancer_count", 0);
    treg.newVariable<int>("neighbor_all_count", 0);

    // Cached bitmask of available neighbor voxels
    treg.newVariable<unsigned int>("available_neighbors", 0u);

    // Lifecycle
    treg.newVariable<int>("life", 100);
    treg.newVariable<int>("dead", 0);

    // Intent variables for two-phase conflict resolution
    treg.newVariable<int>("intent_action", INTENT_NONE);
    treg.newVariable<int>("target_x", -1);
    treg.newVariable<int>("target_y", -1);
    treg.newVariable<int>("target_z", -1);

    // Define agent functions - movement functions always needed
    treg.newFunction("broadcast_location", treg_broadcast_location)
        .setMessageOutput(MSG_CELL_LOCATION);

    treg.newFunction("scan_neighbors", treg_scan_neighbors)
        .setMessageInput(MSG_CELL_LOCATION);

    treg.newFunction("update_chemicals", treg_update_chemicals);

    treg.newFunction("compute_chemical_sources", treg_compute_chemical_sources);

    treg.newFunction("select_move_target", treg_select_move_target)
        .setMessageOutput(MSG_INTENT);

    treg.newFunction("execute_move", treg_execute_move)
        .setMessageInput(MSG_INTENT);

    // Division and state functions only in main model
    if (include_state_divide) {
        treg.newFunction("state_step", treg_state_step)
            .setAllowAgentDeath(true);

        treg.newFunction("select_divide_target", treg_select_divide_target)
            .setMessageOutput(MSG_INTENT);

        {
            flamegpu::AgentFunctionDescription fn = treg.newFunction("execute_divide", treg_execute_divide);
            fn.setMessageInput(MSG_INTENT);
            fn.setAgentOutput(treg);
        }
    }
}

// Define the MDSC agent and its variables
// MDSCs are simpler than other cells: movement and life countdown only, no division
void defineMDSCAgent(flamegpu::ModelDescription& model, bool include_state) {
    flamegpu::AgentDescription mdsc = model.newAgent(AGENT_MDSC);

    // Identity
    mdsc.newVariable<unsigned int>("id");

    // Position
    mdsc.newVariable<int>("x");
    mdsc.newVariable<int>("y");
    mdsc.newVariable<int>("z");

    mdsc.newVariable<float>("local_O2", 0.0f);
    mdsc.newVariable<float>("local_CCL2", 0.0f);         // Attracted to CCL2
    mdsc.newVariable<float>("local_TGFB", 0.0f);         // Can be activated by TGF-beta

    // Chemical production (MDSCs produce immunosuppressive factors)
    mdsc.newVariable<float>("ROS_release_rate", 0.0f);   // Reactive oxygen species (deprecated, kept for compatibility)
    mdsc.newVariable<float>("NO_release_rate", 0.0f);    // Nitric oxide
    mdsc.newVariable<float>("ArgI_release_rate", 0.0f);  // Arginase I (immune suppression)
    
    // Functional state
    mdsc.newVariable<float>("suppression_radius", 1.0f); // Local suppression range
    mdsc.newVariable<float>("activation_level", 1.0f);   // Activity level
    
    // Chemotaxis state (for directed migration)
    mdsc.newVariable<float>("CCL2_gradient_x", 0.0f);
    mdsc.newVariable<float>("CCL2_gradient_y", 0.0f);
    mdsc.newVariable<float>("CCL2_gradient_z", 0.0f);

    // Neighbor counts (computed via messaging)
    mdsc.newVariable<int>("neighbor_cancer_count", 0);
    mdsc.newVariable<int>("neighbor_Tcell_count", 0);
    mdsc.newVariable<int>("neighbor_Treg_count", 0);
    mdsc.newVariable<int>("neighbor_MDSC_count", 0);

    // Cached bitmask of available neighbor voxels (no MDSC)
    mdsc.newVariable<unsigned int>("available_neighbors", 0u);

    // Lifecycle
    mdsc.newVariable<int>("life", 100);
    mdsc.newVariable<int>("dead", 0);

    // Intent variables for two-phase conflict resolution
    mdsc.newVariable<int>("intent_action", INTENT_NONE);
    mdsc.newVariable<int>("target_x", -1);
    mdsc.newVariable<int>("target_y", -1);
    mdsc.newVariable<int>("target_z", -1);

    // Define agent functions - movement functions always needed
    mdsc.newFunction("broadcast_location", mdsc_broadcast_location)
        .setMessageOutput(MSG_CELL_LOCATION);

    mdsc.newFunction("scan_neighbors", mdsc_scan_neighbors)
        .setMessageInput(MSG_CELL_LOCATION);

    mdsc.newFunction("update_chemicals", mdsc_update_chemicals);

    mdsc.newFunction("compute_chemical_sources", mdsc_compute_chemical_sources);

    mdsc.newFunction("select_move_target", mdsc_select_move_target)
        .setMessageOutput(MSG_INTENT);

    mdsc.newFunction("execute_move", mdsc_execute_move)
        .setMessageInput(MSG_INTENT);

    // State step only in main model (MDSCs don't divide)
    if (include_state) {
        mdsc.newFunction("state_step", mdsc_state_step)
            .setAllowAgentDeath(true);
    }
}

// Define the spatial message type for cell location broadcasting
void defineCellLocationMessage(flamegpu::ModelDescription& model, float voxel_size, int grid_max) {
    flamegpu::MessageSpatial3D::Description message = model.newMessage<flamegpu::MessageSpatial3D>(MSG_CELL_LOCATION);

    const float env_min = -voxel_size;
    const float env_max = (grid_max + 1) * voxel_size;

    message.setMin(env_min, env_min, env_min);
    message.setMax(env_max, env_max, env_max);
    message.setRadius(1.8f * voxel_size);

    // Message variables (shared by all agent types)
    message.newVariable<int>("agent_type");
    message.newVariable<int>("agent_id");
    message.newVariable<int>("cell_state");
    message.newVariable<float>("PDL1");
    message.newVariable<int>("voxel_x");
    message.newVariable<int>("voxel_y");
    message.newVariable<int>("voxel_z");
}

// Define the spatial message type for intent broadcasting (two-phase conflict resolution)
void defineIntentMessage(flamegpu::ModelDescription& model, float voxel_size, int grid_max) {
    flamegpu::MessageSpatial3D::Description message = model.newMessage<flamegpu::MessageSpatial3D>(MSG_INTENT);

    const float env_min = -voxel_size;
    const float env_max = (grid_max + 1) * voxel_size;

    message.setMin(env_min, env_min, env_min);
    message.setMax(env_max, env_max, env_max);
    message.setRadius(1.8f * voxel_size);

    // Intent message variables
    message.newVariable<int>("agent_type");
    message.newVariable<unsigned int>("agent_id");
    message.newVariable<int>("intent_action");  // INTENT_NONE, INTENT_MOVE, INTENT_DIVIDE
    message.newVariable<int>("target_x");
    message.newVariable<int>("target_y");
    message.newVariable<int>("target_z");
    // Source position for conflict resolution when IDs are equal (e.g., new cells with id=0)
    message.newVariable<int>("source_x");
    message.newVariable<int>("source_y");
    message.newVariable<int>("source_z");
}

// Define environment properties (simulation parameters)
void defineEnvironment(flamegpu::ModelDescription& model,
                       int grid_x, int grid_y, int grid_z,
                       float voxel_size,
                       const PDAC::GPUParam& params) {

    flamegpu::EnvironmentDescription env = model.Environment();

    // Grid dimensions (from config, not XML)
    env.newProperty<int>(ENV_GRID_SIZE_X, grid_x);
    env.newProperty<int>(ENV_GRID_SIZE_Y, grid_y);
    env.newProperty<int>(ENV_GRID_SIZE_Z, grid_z);
    env.newProperty<float>(ENV_VOXEL_SIZE, voxel_size);

    // Simulation tracking
    env.newProperty<unsigned int>("current_step", 0u);

    // Agent count tracking (updated each timestep by host function)
    env.newProperty<unsigned int>("total_cancer_cells", 0u);
    env.newProperty<unsigned int>("total_tcells", 0u);
    env.newProperty<unsigned int>("total_tregs", 0u);
    env.newProperty<unsigned int>("total_mdscs", 0u);
    env.newProperty<unsigned int>("total_agents", 0u);  // Sum of all agents

    // Populate ALL other parameters from XML
    params.populateFlameGPUEnvironment(env);
}

// Define environment properties for a movement submodel
void defineSubmodelEnvironment(flamegpu::ModelDescription& model,
                                int grid_x, int grid_y, int grid_z,
                                float voxel_size) {
    flamegpu::EnvironmentDescription env = model.Environment();

    // Grid dimensions (needed for bounds checking)
    env.newProperty<int>(ENV_GRID_SIZE_X, grid_x);
    env.newProperty<int>(ENV_GRID_SIZE_Y, grid_y);
    env.newProperty<int>(ENV_GRID_SIZE_Z, grid_z);
    env.newProperty<float>(ENV_VOXEL_SIZE, voxel_size);
}

// Define layers for a single cell type's movement submodel
void defineCancerMovementLayers(flamegpu::ModelDescription& model) {
    // Each agent broadcasts in separate layers (FLAMEGPU2 doesn't allow multiple
    // functions outputting to same message list in one layer)
    {
        flamegpu::LayerDescription layer = model.newLayer("broadcast_cancer");
        layer.addAgentFunction(AGENT_CANCER_CELL, "broadcast_location");
    }
    {
        flamegpu::LayerDescription layer = model.newLayer("broadcast_tcell");
        layer.addAgentFunction(AGENT_TCELL, "broadcast_location");
    }
    {
        flamegpu::LayerDescription layer = model.newLayer("broadcast_treg");
        layer.addAgentFunction(AGENT_TREG, "broadcast_location");
    }
    {
        flamegpu::LayerDescription layer = model.newLayer("broadcast_mdsc");
        layer.addAgentFunction(AGENT_MDSC, "broadcast_location");
    }
    // Only cancer cells scan and move
    {
        flamegpu::LayerDescription layer = model.newLayer("scan_cancer");
        layer.addAgentFunction(AGENT_CANCER_CELL, "count_neighbors");
    }
    {
        flamegpu::LayerDescription layer = model.newLayer("select_move_cancer");
        layer.addAgentFunction(AGENT_CANCER_CELL, "select_move_target");
    }
    {
        flamegpu::LayerDescription layer = model.newLayer("execute_move_cancer");
        layer.addAgentFunction(AGENT_CANCER_CELL, "execute_move");
    }
}

void defineTCellMovementLayers(flamegpu::ModelDescription& model) {
    // Each agent broadcasts in separate layers
    {
        flamegpu::LayerDescription layer = model.newLayer("broadcast_cancer");
        layer.addAgentFunction(AGENT_CANCER_CELL, "broadcast_location");
    }
    {
        flamegpu::LayerDescription layer = model.newLayer("broadcast_tcell");
        layer.addAgentFunction(AGENT_TCELL, "broadcast_location");
    }
    {
        flamegpu::LayerDescription layer = model.newLayer("broadcast_treg");
        layer.addAgentFunction(AGENT_TREG, "broadcast_location");
    }
    {
        flamegpu::LayerDescription layer = model.newLayer("broadcast_mdsc");
        layer.addAgentFunction(AGENT_MDSC, "broadcast_location");
    }
    // Only T cells scan and move
    {
        flamegpu::LayerDescription layer = model.newLayer("scan_tcell");
        layer.addAgentFunction(AGENT_TCELL, "scan_neighbors");
    }
    {
        flamegpu::LayerDescription layer = model.newLayer("select_move_tcell");
        layer.addAgentFunction(AGENT_TCELL, "select_move_target");
    }
    {
        flamegpu::LayerDescription layer = model.newLayer("execute_move_tcell");
        layer.addAgentFunction(AGENT_TCELL, "execute_move");
    }
}

void defineTRegMovementLayers(flamegpu::ModelDescription& model) {
    // Each agent broadcasts in separate layers
    {
        flamegpu::LayerDescription layer = model.newLayer("broadcast_cancer");
        layer.addAgentFunction(AGENT_CANCER_CELL, "broadcast_location");
    }
    {
        flamegpu::LayerDescription layer = model.newLayer("broadcast_tcell");
        layer.addAgentFunction(AGENT_TCELL, "broadcast_location");
    }
    {
        flamegpu::LayerDescription layer = model.newLayer("broadcast_treg");
        layer.addAgentFunction(AGENT_TREG, "broadcast_location");
    }
    {
        flamegpu::LayerDescription layer = model.newLayer("broadcast_mdsc");
        layer.addAgentFunction(AGENT_MDSC, "broadcast_location");
    }
    // Only TRegs scan and move
    {
        flamegpu::LayerDescription layer = model.newLayer("scan_treg");
        layer.addAgentFunction(AGENT_TREG, "scan_neighbors");
    }
    {
        flamegpu::LayerDescription layer = model.newLayer("select_move_treg");
        layer.addAgentFunction(AGENT_TREG, "select_move_target");
    }
    {
        flamegpu::LayerDescription layer = model.newLayer("execute_move_treg");
        layer.addAgentFunction(AGENT_TREG, "execute_move");
    }
}

void defineMDSCMovementLayers(flamegpu::ModelDescription& model) {
    // Each agent broadcasts in separate layers
    {
        flamegpu::LayerDescription layer = model.newLayer("broadcast_cancer");
        layer.addAgentFunction(AGENT_CANCER_CELL, "broadcast_location");
    }
    {
        flamegpu::LayerDescription layer = model.newLayer("broadcast_tcell");
        layer.addAgentFunction(AGENT_TCELL, "broadcast_location");
    }
    {
        flamegpu::LayerDescription layer = model.newLayer("broadcast_treg");
        layer.addAgentFunction(AGENT_TREG, "broadcast_location");
    }
    {
        flamegpu::LayerDescription layer = model.newLayer("broadcast_mdsc");
        layer.addAgentFunction(AGENT_MDSC, "broadcast_location");
    }
    // Only MDSCs scan and move
    {
        flamegpu::LayerDescription layer = model.newLayer("scan_mdsc");
        layer.addAgentFunction(AGENT_MDSC, "scan_neighbors");
    }
    {
        flamegpu::LayerDescription layer = model.newLayer("select_move_mdsc");
        layer.addAgentFunction(AGENT_MDSC, "select_move_target");
    }
    {
        flamegpu::LayerDescription layer = model.newLayer("execute_move_mdsc");
        layer.addAgentFunction(AGENT_MDSC, "execute_move");
    }
}

// Build a movement submodel for a specific cell type
void buildCancerMovementSubmodel(flamegpu::ModelDescription& submodel,
                                  int grid_x, int grid_y, int grid_z, float voxel_size) {
    int grid_max = std::max({grid_x, grid_y, grid_z});

    defineSubmodelEnvironment(submodel, grid_x, grid_y, grid_z, voxel_size);
    defineCellLocationMessage(submodel, voxel_size, grid_max);
    defineIntentMessage(submodel, voxel_size, grid_max);

    // All agents need to be defined for broadcasting, but only cancer moves
    defineCancerCellAgent(submodel, false);
    defineTCellAgent(submodel, false);
    defineTRegAgent(submodel, false);
    defineMDSCAgent(submodel, false);

    defineCancerMovementLayers(submodel);
}

void buildTCellMovementSubmodel(flamegpu::ModelDescription& submodel,
                                 int grid_x, int grid_y, int grid_z, float voxel_size) {
    int grid_max = std::max({grid_x, grid_y, grid_z});

    defineSubmodelEnvironment(submodel, grid_x, grid_y, grid_z, voxel_size);
    defineCellLocationMessage(submodel, voxel_size, grid_max);
    defineIntentMessage(submodel, voxel_size, grid_max);

    defineCancerCellAgent(submodel, false);
    defineTCellAgent(submodel, false);
    defineTRegAgent(submodel, false);
    defineMDSCAgent(submodel, false);

    defineTCellMovementLayers(submodel);
}

void buildTRegMovementSubmodel(flamegpu::ModelDescription& submodel,
                                int grid_x, int grid_y, int grid_z, float voxel_size) {
    int grid_max = std::max({grid_x, grid_y, grid_z});

    defineSubmodelEnvironment(submodel, grid_x, grid_y, grid_z, voxel_size);
    defineCellLocationMessage(submodel, voxel_size, grid_max);
    defineIntentMessage(submodel, voxel_size, grid_max);

    defineCancerCellAgent(submodel, false);
    defineTCellAgent(submodel, false);
    defineTRegAgent(submodel, false);
    defineMDSCAgent(submodel, false);

    defineTRegMovementLayers(submodel);
}

void buildMDSCMovementSubmodel(flamegpu::ModelDescription& submodel,
                                int grid_x, int grid_y, int grid_z, float voxel_size) {
    int grid_max = std::max({grid_x, grid_y, grid_z});

    defineSubmodelEnvironment(submodel, grid_x, grid_y, grid_z, voxel_size);
    defineCellLocationMessage(submodel, voxel_size, grid_max);
    defineIntentMessage(submodel, voxel_size, grid_max);

    defineCancerCellAgent(submodel, false);
    defineTCellAgent(submodel, false);
    defineTRegAgent(submodel, false);
    defineMDSCAgent(submodel, false);

    defineMDSCMovementLayers(submodel);
}

// Define main model execution layers (state transitions and division)
void defineMainModelLayers(flamegpu::ModelDescription& model) {
    // Movement submodels loaded in first
    // After all movement submodels, do:
    // 1. Final broadcast and scan to get fresh neighbor data
    // 2. State transitions
    // 3. Division

    // 0. update agent counts
    {
        flamegpu::LayerDescription layer = model.newLayer("update_agent_counts");
        layer.addHostFunction(update_agent_counts);
    }

    // 1-4. Broadcast
    // Each agent broadcasts in separate layers (FLAMEGPU2 doesn't allow multiple
    // functions outputting to same message list in one layer)
    {
        flamegpu::LayerDescription layer = model.newLayer("final_broadcast_cancer");
        layer.addAgentFunction(AGENT_CANCER_CELL, "broadcast_location");
    }
    {
        flamegpu::LayerDescription layer = model.newLayer("final_broadcast_tcell");
        layer.addAgentFunction(AGENT_TCELL, "broadcast_location");
    }
    {
        flamegpu::LayerDescription layer = model.newLayer("final_broadcast_treg");
        layer.addAgentFunction(AGENT_TREG, "broadcast_location");
    }
    {
        flamegpu::LayerDescription layer = model.newLayer("final_broadcast_mdsc");
        layer.addAgentFunction(AGENT_MDSC, "broadcast_location");
    }

    // 5. Scan neighbors
    {
        flamegpu::LayerDescription layer = model.newLayer("final_scan_neighbors");
        layer.addAgentFunction(AGENT_CANCER_CELL, "count_neighbors");
        layer.addAgentFunction(AGENT_TCELL, "scan_neighbors");
        layer.addAgentFunction(AGENT_TREG, "scan_neighbors");
        layer.addAgentFunction(AGENT_MDSC, "scan_neighbors");
    }

    // 6. READ chemicals from PDE to agents
    {
        flamegpu::LayerDescription layer = model.newLayer("read_chemicals_from_pde");
        layer.addHostFunction(update_agent_chemicals);
    }
    
    // 7. Agents update their chemical states (PDL1, activation, etc.)
    {
        flamegpu::LayerDescription layer = model.newLayer("update_chemical_states");
        layer.addAgentFunction(AGENT_CANCER_CELL, "update_chemicals");
        layer.addAgentFunction(AGENT_TCELL, "update_chemicals");
        layer.addAgentFunction(AGENT_TREG, "update_chemicals");
        layer.addAgentFunction(AGENT_MDSC, "update_chemicals");
    }
    
    // 8. Agent state transitions (killing, division decisions, etc.)
    {
        flamegpu::LayerDescription layer = model.newLayer("state_transitions");
        layer.addAgentFunction(AGENT_CANCER_CELL, "state_step");
        layer.addAgentFunction(AGENT_TCELL, "state_step");
        layer.addAgentFunction(AGENT_TREG, "state_step");
        layer.addAgentFunction(AGENT_MDSC, "state_step");
    }

    // 9. Agents compute their chemical production/consumption rates
    {
        flamegpu::LayerDescription layer = model.newLayer("compute_chemical_sources");
        layer.addAgentFunction(AGENT_CANCER_CELL, "compute_chemical_sources");
        layer.addAgentFunction(AGENT_TCELL, "compute_chemical_sources");
        layer.addAgentFunction(AGENT_TREG, "compute_chemical_sources");
        layer.addAgentFunction(AGENT_MDSC, "compute_chemical_sources");
    }
    
    // 10. WRITE agent sources to PDE
    {
        flamegpu::LayerDescription layer = model.newLayer("write_sources_to_pde");
        layer.addHostFunction(collect_agent_sources);
    }
    
    // 11. SOLVE PDE for one timestep
    {
        flamegpu::LayerDescription layer = model.newLayer("solve_pde");
        layer.addHostFunction(solve_pde_step);
    }

    // 12 - 14. Division layers for each cell type
    // Division: FLAMEGPU2 clears message lists when a new layer outputs to them.
    // Each cell type's execute must immediately follow its select to read the correct messages.
    // Note: FLAMEGPU2 doesn't allow multiple functions outputting to the same message in one layer.

    // Cancer cell division (select → execute)
    {
        flamegpu::LayerDescription layer = model.newLayer("select_divide_cancer");
        layer.addAgentFunction(AGENT_CANCER_CELL, "select_divide_target");
    }
    {
        flamegpu::LayerDescription layer = model.newLayer("execute_divide_cancer");
        layer.addAgentFunction(AGENT_CANCER_CELL, "execute_divide");
    }

    // T cell division (select → execute)
    {
        flamegpu::LayerDescription layer = model.newLayer("select_divide_tcell");
        layer.addAgentFunction(AGENT_TCELL, "select_divide_target");
    }
    {
        flamegpu::LayerDescription layer = model.newLayer("execute_divide_tcell");
        layer.addAgentFunction(AGENT_TCELL, "execute_divide");
    }

    // TReg division (select → execute)
    {
        flamegpu::LayerDescription layer = model.newLayer("select_divide_treg");
        layer.addAgentFunction(AGENT_TREG, "select_divide_target");
    }
    {
        flamegpu::LayerDescription layer = model.newLayer("execute_divide_treg");
        layer.addAgentFunction(AGENT_TREG, "execute_divide");
    }
}

// Build the complete model with per-cell-type movement submodels
std::unique_ptr<flamegpu::ModelDescription> buildModel(
    int grid_x, int grid_y, int grid_z, float voxel_size,
    const PDAC::GPUParam& gpu_params) {

    auto model = std::make_unique<flamegpu::ModelDescription>("TNBC_ABM_GPU");

    int grid_max = std::max({grid_x, grid_y, grid_z});

    // Define messages for main model
    defineCellLocationMessage(*model, voxel_size, grid_max);
    defineIntentMessage(*model, voxel_size, grid_max);

    // Define agents with all functions
    defineCancerCellAgent(*model, true);
    defineTCellAgent(*model, true);
    defineTRegAgent(*model, true);
    defineMDSCAgent(*model, true);

    // Define environment with GPU parameters loaded from XML
    defineEnvironment(*model, grid_x, grid_y, grid_z, voxel_size, gpu_params);

    // Update move_steps in environment to match parameters
    int cancer_move_steps = model->Environment().getProperty<int>("PARAM_CANCER_MOVE_STEPS");
    int cancer_stem_move_steps = model->Environment().getProperty<int>("PARAM_CANCER_MOVE_STEPS_STEM");
    int tcell_move_steps = model->Environment().getProperty<int>("PARAM_TCELL_MOVE_STEPS");
    int treg_move_steps = model->Environment().getProperty<int>("PARAM_TCELL_MOVE_STEPS");
    int mdsc_move_steps = model->Environment().getProperty<int>("PARAM_MDSC_MOVE_STEPS");

    // Build and add movement submodels for each cell type
    // Cancer cell movement submodel
    flamegpu::ModelDescription cancerMoveSubmodelDesc("CancerMovementSubmodel");
    buildCancerMovementSubmodel(cancerMoveSubmodelDesc, grid_x, grid_y, grid_z, voxel_size);
    auto cancerMoveSubmodel = model->newSubModel("cancer_movement", cancerMoveSubmodelDesc);
    cancerMoveSubmodel.bindAgent(AGENT_CANCER_CELL, AGENT_CANCER_CELL, true, true);
    cancerMoveSubmodel.bindAgent(AGENT_TCELL, AGENT_TCELL, true, true);
    cancerMoveSubmodel.bindAgent(AGENT_TREG, AGENT_TREG, true, true);
    cancerMoveSubmodel.bindAgent(AGENT_MDSC, AGENT_MDSC, true, true);
    cancerMoveSubmodel.setMaxSteps(cancer_move_steps);

    // T cell movement submodel
    flamegpu::ModelDescription tcellMoveSubmodelDesc("TCellMovementSubmodel");
    buildTCellMovementSubmodel(tcellMoveSubmodelDesc, grid_x, grid_y, grid_z, voxel_size);
    auto tcellMoveSubmodel = model->newSubModel("tcell_movement", tcellMoveSubmodelDesc);
    tcellMoveSubmodel.bindAgent(AGENT_CANCER_CELL, AGENT_CANCER_CELL, true, true);
    tcellMoveSubmodel.bindAgent(AGENT_TCELL, AGENT_TCELL, true, true);
    tcellMoveSubmodel.bindAgent(AGENT_TREG, AGENT_TREG, true, true);
    tcellMoveSubmodel.bindAgent(AGENT_MDSC, AGENT_MDSC, true, true);
    tcellMoveSubmodel.setMaxSteps(tcell_move_steps);

    // TReg movement submodel
    flamegpu::ModelDescription tregMoveSubmodelDesc("TRegMovementSubmodel");
    buildTRegMovementSubmodel(tregMoveSubmodelDesc, grid_x, grid_y, grid_z, voxel_size);
    auto tregMoveSubmodel = model->newSubModel("treg_movement", tregMoveSubmodelDesc);
    tregMoveSubmodel.bindAgent(AGENT_CANCER_CELL, AGENT_CANCER_CELL, true, true);
    tregMoveSubmodel.bindAgent(AGENT_TCELL, AGENT_TCELL, true, true);
    tregMoveSubmodel.bindAgent(AGENT_TREG, AGENT_TREG, true, true);
    tregMoveSubmodel.bindAgent(AGENT_MDSC, AGENT_MDSC, true, true);
    tregMoveSubmodel.setMaxSteps(treg_move_steps);

    // MDSC movement submodel
    flamegpu::ModelDescription mdscMoveSubmodelDesc("MDSCMovementSubmodel");
    buildMDSCMovementSubmodel(mdscMoveSubmodelDesc, grid_x, grid_y, grid_z, voxel_size);
    auto mdscMoveSubmodel = model->newSubModel("mdsc_movement", mdscMoveSubmodelDesc);
    mdscMoveSubmodel.bindAgent(AGENT_CANCER_CELL, AGENT_CANCER_CELL, true, true);
    mdscMoveSubmodel.bindAgent(AGENT_TCELL, AGENT_TCELL, true, true);
    mdscMoveSubmodel.bindAgent(AGENT_TREG, AGENT_TREG, true, true);
    mdscMoveSubmodel.bindAgent(AGENT_MDSC, AGENT_MDSC, true, true);
    mdscMoveSubmodel.setMaxSteps(mdsc_move_steps);

    // Add submodel layers (each runs for its configured number of steps)
    {
        auto layer = model->newLayer("cancer_movement_layer");
        layer.addSubModel(cancerMoveSubmodel);
    }
    {
        auto layer = model->newLayer("tcell_movement_layer");
        layer.addSubModel(tcellMoveSubmodel);
    }
    {
        auto layer = model->newLayer("treg_movement_layer");
        layer.addSubModel(tregMoveSubmodel);
    }
    {
        auto layer = model->newLayer("mdsc_movement_layer");
        layer.addSubModel(mdscMoveSubmodel);
    }

    // Define main model layers (state transitions, division)
    defineMainModelLayers(*model);

    return model;
}

} // namespace PDAC
