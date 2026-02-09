#ifndef PDAC_QSP_LYMPHCENTRAL_WRAPPER_H
#define PDAC_QSP_LYMPHCENTRAL_WRAPPER_H

#include <string>
#include <vector>
#include <memory>

// Include actual HCC ODE system classes
#include "ode/ODE_system.h"
#include "ode/QSPParam.h"
#include "cvode/MolecularModelCVode.h"

/**
 * @file LymphCentral_wrapper.h
 * @brief CPU-side wrapper for HCC QSP/ODE model integration with GPU ABM
 *
 * This wrapper encapsulates the actual HCC ODE_system (59+ species) and handles:
 * - Initialization from param_all_test.xml
 * - Time stepping with CVODE solver
 * - Data exchange between GPU ABM and CPU QSP:
 *   - ABM → QSP: Tumor microenvironment signals (cancer deaths, T cell recruitment)
 *   - QSP → ABM: Drug concentrations, systemic immune responses
 */

namespace PDAC {

/**
 * @struct QSPState
 * @brief QSP model state relevant for ABM coupling
 */
struct QSPState {
    // Drug concentrations (will be transferred to GPU environment)
    double nivo_tumor;          // Nivolumab concentration in tumor
    double cabo_tumor;          // Cabozantinib concentration in tumor

    // T cell pools (central/systemic)
    double teff_central;        // Effector T cells in central compartment
    double treg_central;        // Regulatory T cells in central compartment

    // Other immune mediators relevant to ABM
    double ifn_central;         // IFN-gamma in central compartment
    double il2_central;         // IL-2 in central compartment
    double il10_central;        // IL-10 in central compartment
    double tgfb_central;        // TGF-beta in central compartment

    // Tumor-related signals
    double tumor_capacity;      // Remaining capacity for tumor growth
    double tumor_necrotic_fraction; // Fraction of tumor that is necrotic
};

/**
 * @class LymphCentralWrapper
 * @brief Wrapper for CPU-side HCC QSP model with CVODE ODE solver
 *
 * Wraps the actual CancerVCT::ODE_system (59+ species) from HCC:
 * - Manages CVODE solver lifecycle
 * - Handles data exchange with GPU ABM
 * - Time stepping through ODE system
 * - State management and species access
 */
class LymphCentralWrapper {
public:
    /**
     * Constructor - initializes but does not set up ODE solver
     */
    LymphCentralWrapper();

    /**
     * Destructor - cleans up CVODE resources
     */
    ~LymphCentralWrapper();

    /**
     * Initialize the QSP model from parameter file
     * @param param_filename Path to parameter XML file (e.g., param_all_test.xml)
     * @return true if initialization successful, false otherwise
     */
    bool initialize(const std::string& param_filename);

    /**
     * Advance ODE system by dt seconds
     * @param t Current simulation time (seconds)
     * @param dt Time step (seconds)
     * @return true if successful, false if solver failed
     */
    bool time_step(double t, double dt);

    /**
     * Update QSP state from ABM signals
     * @param cancer_deaths Number of cancer cells killed by T cells in last ABM step
     * @param tcell_kills Number of T cells killed in last ABM step
     * @param teff_recruited Number of effector T cells recruited from central compartment
     * @param treg_recruited Number of regulatory T cells recruited
     * @param tumor_volume Current tumor volume (mm³)
     * @param tumor_cell_count Current total cancer cell count
     */
    void update_from_abm(
        int cancer_deaths,
        int tcell_kills,
        int teff_recruited,
        int treg_recruited,
        double tumor_volume,
        int tumor_cell_count
    );

    /**
     * Get QSP state for transfer to ABM (GPU)
     * @return QSPState containing relevant variables for ABM coupling
     */
    QSPState get_state_for_abm() const;

    /**
     * Get current time in ODE solver
     */
    double get_current_time() const { return _current_time; }

    /**
     * Set current time in ODE solver (for initialization or restart)
     */
    void set_current_time(double t) { _current_time = t; }

    /**
     * Get number of ODE species
     */
    int get_num_species() const;

    /**
     * Get ODE solution at specific species index
     */
    double get_species_value(int species_idx) const;

    /**
     * Set ODE solution at specific species index
     */
    void set_species_value(int species_idx, double value);

    /**
     * Check if ODE solver is initialized
     */
    bool is_initialized() const { return _is_initialized; }

    /**
     * Get underlying ODE system (for advanced usage)
     */
    CancerVCT::ODE_system* get_ode_system() {
        return _qsp_model ? _qsp_model->getSystem() : nullptr;
    }

private:
    // Actual HCC ODE system wrapped in MolecularModelCVode
    std::unique_ptr<MolecularModelCVode<CancerVCT::ODE_system>> _qsp_model;

    // Parameter container
    std::unique_ptr<CancerVCT::QSPParam> _parameters;

    // Model state
    bool _is_initialized;
    double _current_time;

    // ABM coupling variables
    struct {
        int cancer_deaths_last_step;
        int tcell_kills_last_step;
        int teff_recruited_last_step;
        int treg_recruited_last_step;
        double tumor_volume;
        int tumor_cell_count;
    } _abm_signals;

    // Species indices (extracted from ODE_system or defined by SBML model)
    // These will be populated during initialization
    std::vector<int> _drug_species_indices;
    std::vector<int> _immune_species_indices;

    // Helper method to extract species indices from ODE_system
    void _extract_species_indices();

    // Helper method to apply ABM feedback to ODE system
    void _apply_abm_feedback();
};

} // namespace PDAC

#endif // PDAC_QSP_LYMPHCENTRAL_WRAPPER_H
