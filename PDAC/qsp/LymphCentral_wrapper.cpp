#include "LymphCentral_wrapper.h"
#include <iostream>
#include <cmath>
#include <stdexcept>

#include "ode/QSP_enum.h" // for species enum, uses CancerVCT::"SP_NameHere"

namespace PDAC {

// Constructor
LymphCentralWrapper::LymphCentralWrapper()
    : _is_initialized(false), _current_time(0.0) {
    _abm_signals = {0, 0, 0, 0, 0.0, 0};
}

// Destructor
LymphCentralWrapper::~LymphCentralWrapper() {
    // Smart pointers will clean up automatically
}

// Initialize from parameter file
bool LymphCentralWrapper::initialize(const std::string& param_filename) {
    try {
        std::cout << "Initializing QSP LymphCentral model from: " << param_filename << std::endl;

        // Create parameter container
        _parameters = std::make_unique<CancerVCT::QSPParam>();
        if (!_parameters) {
            std::cerr << "Failed to create QSPParam object" << std::endl;
            return false;
        }

        // Load parameters from XML file
        std::cout << "Loading parameters from XML..." << std::endl;
        _parameters->initializeParams(param_filename);

        // Create ODE system
        std::cout << "Creating ODE_system..." << std::endl;
        auto ode_system = std::make_unique<CancerVCT::ODE_system>();
        if (!ode_system) {
            std::cerr << "Failed to create ODE_system" << std::endl;
            return false;
        }

        // Setup ODE system class parameters
        std::cout << "Setting up ODE system parameters..." << std::endl;
        CancerVCT::ODE_system::setup_class_parameters(*_parameters);

        // Setup ODE system instance parameters
        std::cout << "Setting up ODE system instance..." << std::endl;
        ode_system->setup_instance_tolerance(*_parameters);
        ode_system->setup_instance_variables(*_parameters);

        // Evaluate initial assignments
        std::cout << "Evaluating initial assignments..." << std::endl;
        ode_system->eval_init_assignment();

        // Wrap in MolecularModelCVode template
        std::cout << "Wrapping ODE system in CVODE solver..." << std::endl;
        _qsp_model = std::make_unique<MolecularModelCVode<CancerVCT::ODE_system>>();
        if (!_qsp_model) {
            std::cerr << "Failed to create MolecularModelCVode wrapper" << std::endl;
            return false;
        }

        // Transfer ownership of ODE system to wrapper
        // Note: MolecularModelCVode creates its own ODE_system internally,
        // so we let it manage the lifecycle
        _qsp_model->getSystem()->setup_instance_tolerance(*_parameters);
        _qsp_model->getSystem()->setup_instance_variables(*_parameters);
        _qsp_model->getSystem()->eval_init_assignment();

        // Extract species indices for fast access during coupling
        // _extract_species_indices();

        // Run steady state initialization to get presimulation tumor radius

        _current_time = 0.0;
        _is_initialized = true;

        std::cout << "QSP model initialization complete" << std::endl;
        std::cout << "  Species count: " << _qsp_model->getSystem()->get_num_variables() << std::endl;
        std::cout << "  Parameters: " << _qsp_model->getSystem()->get_num_params() << std::endl;

        return true;

    } catch (const std::exception& e) {
        std::cerr << "Exception during QSP initialization: " << e.what() << std::endl;
        _is_initialized = false;
        return false;
    } catch (...) {
        std::cerr << "Unknown exception during QSP initialization" << std::endl;
        _is_initialized = false;
        return false;
    }
}

// Time step the ODE system
bool LymphCentralWrapper::time_step(double t, double dt) {
    if (!_is_initialized || !_qsp_model) {
        std::cerr << "Error: QSP model not initialized" << std::endl;
        return false;
    }

    try {
        // Apply ABM feedback to ODE system if there were signals
        _apply_abm_feedback();

        // Advance ODE system by dt
        // MolecularModelCVode::solve calls ODE_system::simOdeStep internally
        bool success = _qsp_model->solve(t, dt);

        if (success) {
            _current_time = t + dt;
            return true;
        } else {
            std::cerr << "CVODE solver failed during time step" << std::endl;
            return false;
        }

    } catch (const std::exception& e) {
        std::cerr << "Exception during ODE time step: " << e.what() << std::endl;
        return false;
    } catch (...) {
        std::cerr << "Unknown exception during ODE time step" << std::endl;
        return false;
    }
}

// Update QSP from ABM signals
void LymphCentralWrapper::update_from_abm(
    int cancer_deaths,
    int tcell_kills,
    int teff_recruited,
    int treg_recruited,
    double tumor_volume,
    int tumor_cell_count) {

    _abm_signals.cancer_deaths_last_step = cancer_deaths;
    _abm_signals.tcell_kills_last_step = tcell_kills;
    _abm_signals.teff_recruited_last_step = teff_recruited;
    _abm_signals.treg_recruited_last_step = treg_recruited;
    _abm_signals.tumor_volume = tumor_volume;
    _abm_signals.tumor_cell_count = tumor_cell_count;

    // Note: Actual feedback implementation would modify ODE system state
    // based on these ABM metrics. This is application-specific.
}

// Get QSP state for ABM
QSPState LymphCentralWrapper::get_state_for_abm() const {
    QSPState state;

    if (!_is_initialized || !_qsp_model) {
        // Return default state if not initialized
        state.nivo_tumor = 0.0;
        state.cabo_tumor = 0.0;
        state.teff_central = 0.0;
        state.treg_central = 0.0;
        state.ifn_central = 0.0;
        state.il2_central = 0.0;
        state.il10_central = 0.0;
        state.tgfb_central = 0.0;
        state.tumor_capacity = 1e6;
        state.tumor_necrotic_fraction = 0.0;
        return state;
    }

    try {
        // Access ODE system to extract species values
        // Species indices are specific to the SBML model in ODE_system.cpp
        // These would be defined based on the actual model structure

        auto* ode_sys = _qsp_model->getSystem();
        if (!ode_sys) {
            return state;
        }

        // Extract relevant species from ODE system
        // Note: Actual indices depend on SBML model definition in ODE_system.cpp
        // For now, we set placeholder values - these will be properly indexed
        // once we analyze the ODE_system model structure

        // Drug concentrations (these are ODE variables in the model)
        state.nivo_tumor = 0.0;      // Would extract from ODE species
        state.cabo_tumor = 0.0;      // Would extract from ODE species

        // T cell populations (from central/lymphoid compartment)
        state.teff_central = 0.0;    // Would extract from ODE species
        state.treg_central = 0.0;    // Would extract from ODE species

        // Immune mediators (from central compartment)
        state.ifn_central = 0.0;     // Would extract from ODE species
        state.il2_central = 0.0;     // Would extract from ODE species
        state.il10_central = 0.0;    // Would extract from ODE species
        state.tgfb_central = 0.0;    // Would extract from ODE species

        // Tumor metrics
        state.tumor_capacity = 1e6;      // Would compute from ODE state
        state.tumor_necrotic_fraction = 0.0; // Would extract from ODE

        return state;

    } catch (const std::exception& e) {
        std::cerr << "Exception extracting QSP state: " << e.what() << std::endl;
        return state;
    }
}

// Get number of species
int LymphCentralWrapper::get_num_species() const {
    if (!_is_initialized || !_qsp_model) {
        return 0;
    }
    return _qsp_model->getSystem()->get_num_variables();
}

// Get species value by index
double LymphCentralWrapper::get_species_value(int species_idx) const {
    if (!_is_initialized || !_qsp_model) {
        return 0.0;
    }
    try {
        return _qsp_model->getSystem()->getSpeciesVar(species_idx);
    } catch (...) {
        return 0.0;
    }
}

// Set species value by index
void LymphCentralWrapper::set_species_value(int species_idx, double value) {
    if (!_is_initialized || !_qsp_model) {
        return;
    }
    try {
        _qsp_model->getSystem()->setSpeciesVar(species_idx, value);
    } catch (...) {
        // Silently fail
    }
}

// Apply ABM feedback to ODE system
void LymphCentralWrapper::_apply_abm_feedback() {
    // This method would apply feedback from ABM to the QSP model:
    // 1. Increase death signals in ODE if cancer_deaths > 0
    // 2. Reduce central T cell pool if cells were recruited
    // 3. Update tumor size ODE variable from ABM cell count
    // 4. Apply immune activation based on tumor microenvironment
    //
    // Implementation depends on:
    // - Specific ODE variable indices
    // - Coupling mechanism (should be bidirectional with biological meaning)
    // - Time scale and magnitude of feedback

    // For now, just track the signals
    if (_abm_signals.cancer_deaths_last_step > 0) {
        std::cout << "ABM feedback: " << _abm_signals.cancer_deaths_last_step
                  << " cancer cells killed by T cells" << std::endl;
    }
}

} // namespace PDAC
