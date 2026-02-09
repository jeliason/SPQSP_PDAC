#include "pde_solver.cuh"
#include <iostream>
#include <cstring>
#include <cmath>

namespace PDAC {

// CUDA error checking macro
#define CUDA_CHECK(call) \
    do { \
        cudaError_t error = call; \
        if (error != cudaSuccess) { \
            std::cerr << "CUDA error at " << __FILE__ << ":" << __LINE__ \
                      << " - " << cudaGetErrorString(error) << std::endl; \
            exit(EXIT_FAILURE); \
        } \
    } while(0)

// ============================================================================
// CUDA Kernels
// ============================================================================

__global__ void diffusion_reaction_kernel(
    const float* __restrict__ C_curr,
    float* __restrict__ C_next,
    const float* __restrict__ sources,
    int nx, int ny, int nz,
    float D, float lambda, float dt, float dx)
{
    int x = blockIdx.x * blockDim.x + threadIdx.x;
    int y = blockIdx.y * blockDim.y + threadIdx.y;
    int z = blockIdx.z * blockDim.z + threadIdx.z;
    
    if (x >= nx || y >= ny || z >= nz) return;
    
    int idx = z * (nx * ny) + y * nx + x;
    
    float C = C_curr[idx];
    
    // Compute Laplacian using 7-point stencil
    float laplacian = 0.0f;
    float dx2 = dx * dx;
    int neighbor_count = 0;
    
    // X-direction
    if (x > 0) {
        laplacian += (C_curr[idx - 1] - C) / dx2;
        neighbor_count++;
    } else {
        // Neumann BC: zero flux (reflective)
        laplacian += 0.0f;
    }
    
    if (x < nx - 1) {
        laplacian += (C_curr[idx + 1] - C) / dx2;
        neighbor_count++;
    } else {
        laplacian += 0.0f;
    }
    
    // Y-direction
    if (y > 0) {
        laplacian += (C_curr[idx - nx] - C) / dx2;
        neighbor_count++;
    } else {
        laplacian += 0.0f;
    }
    
    if (y < ny - 1) {
        laplacian += (C_curr[idx + nx] - C) / dx2;
        neighbor_count++;
    } else {
        laplacian += 0.0f;
    }
    
    // Z-direction
    if (z > 0) {
        laplacian += (C_curr[idx - nx * ny] - C) / dx2;
        neighbor_count++;
    } else {
        laplacian += 0.0f;
    }
    
    if (z < nz - 1) {
        laplacian += (C_curr[idx + nx * ny] - C) / dx2;
        neighbor_count++;
    } else {
        laplacian += 0.0f;
    }
    
    // Reaction-diffusion-decay equation: dC/dt = D*∇²C - λ*C + S
    float diffusion = D * laplacian;
    float decay = -lambda * C;
    float source = sources[idx];
    
    // Forward Euler time integration
    C_next[idx] = C + dt * (diffusion + decay + source);
    
    // Ensure non-negative concentrations
    if (C_next[idx] < 0.0f) {
        C_next[idx] = 0.0f;
    }
}

__global__ void copy_substrate_kernel(
    const float* __restrict__ src,
    float* __restrict__ dst,
    int n)
{
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx < n) {
        dst[idx] = src[idx];
    }
}

// Kernel: Read concentration at specific voxel for all agents
__global__ void read_concentrations_at_voxels(
    const float* __restrict__ d_concentrations,
    const int* __restrict__ d_agent_x,
    const int* __restrict__ d_agent_y,
    const int* __restrict__ d_agent_z,
    float* __restrict__ d_agent_concentrations,
    int num_agents,
    int substrate_idx,
    int nx, int ny, int nz)
{
    int agent_idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (agent_idx >= num_agents) return;
    
    int x = d_agent_x[agent_idx];
    int y = d_agent_y[agent_idx];
    int z = d_agent_z[agent_idx];
    
    // Bounds check
    if (x < 0 || x >= nx || y < 0 || y >= ny || z < 0 || z >= nz) {
        d_agent_concentrations[agent_idx] = 0.0f;
        return;
    }
    
    // Compute flat index: substrate_offset + z*(nx*ny) + y*nx + x
    int voxel_idx = z * (nx * ny) + y * nx + x;
    int total_voxels = nx * ny * nz;
    int concentration_idx = substrate_idx * total_voxels + voxel_idx;
    
    d_agent_concentrations[agent_idx] = d_concentrations[concentration_idx];
}

// Kernel: Write (add) sources from agents to voxels
__global__ void add_sources_from_agents(
    float* __restrict__ d_sources,
    const int* __restrict__ d_agent_x,
    const int* __restrict__ d_agent_y,
    const int* __restrict__ d_agent_z,
    const float* __restrict__ d_agent_source_rates,
    int num_agents,
    int substrate_idx,
    int nx, int ny, int nz)
{
    int agent_idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (agent_idx >= num_agents) return;
    
    int x = d_agent_x[agent_idx];
    int y = d_agent_y[agent_idx];
    int z = d_agent_z[agent_idx];
    
    // Bounds check
    if (x < 0 || x >= nx || y < 0 || y >= ny || z < 0 || z >= nz) {
        return;
    }
    
    float source_rate = d_agent_source_rates[agent_idx];
    
    // Skip if no source
    if (source_rate == 0.0f) return;
    
    // Compute flat index
    int voxel_idx = z * (nx * ny) + y * nx + x;
    int total_voxels = nx * ny * nz;
    int source_idx = substrate_idx * total_voxels + voxel_idx;
    
    // Atomic add (multiple agents may be in same voxel)
    atomicAdd(&d_sources[source_idx], source_rate);
}

__global__ void add_source_kernel(
    float* __restrict__ sources,
    int idx,
    float value)
{
    if (threadIdx.x == 0 && blockIdx.x == 0) {
        sources[idx] += value;
    }
}

// ============================================================================
// PDESolver Implementation
// ============================================================================

PDESolver::PDESolver(const PDEConfig& config) 
    : config_(config),
      d_concentrations_current_(nullptr),
      d_concentrations_next_(nullptr),
      d_sources_(nullptr),
      h_temp_buffer_(nullptr)
{
    // Validate config
    if (config_.nx <= 0 || config_.ny <= 0 || config_.nz <= 0) {
        throw std::runtime_error("Invalid grid dimensions");
    }
    if (config_.num_substrates <= 0 || config_.num_substrates > NUM_SUBSTRATES) {
        throw std::runtime_error("Invalid number of substrates");
    }
}

PDESolver::~PDESolver() {
    if (d_concentrations_current_) CUDA_CHECK(cudaFree(d_concentrations_current_));
    if (d_concentrations_next_) CUDA_CHECK(cudaFree(d_concentrations_next_));
    if (d_sources_) CUDA_CHECK(cudaFree(d_sources_));
    if (h_temp_buffer_) delete[] h_temp_buffer_;
}

void PDESolver::initialize() {
    int total_voxels = config_.nx * config_.ny * config_.nz;
    size_t total_size = total_voxels * config_.num_substrates * sizeof(float);
    
    // Allocate device memory
    CUDA_CHECK(cudaMalloc(&d_concentrations_current_, total_size));
    CUDA_CHECK(cudaMalloc(&d_concentrations_next_, total_size));
    CUDA_CHECK(cudaMalloc(&d_sources_, total_size));
    
    // Initialize to zero
    CUDA_CHECK(cudaMemset(d_concentrations_current_, 0, total_size));
    CUDA_CHECK(cudaMemset(d_concentrations_next_, 0, total_size));
    CUDA_CHECK(cudaMemset(d_sources_, 0, total_size));
    
    // Allocate host buffer for transfers
    h_temp_buffer_ = new float[total_voxels];
    
    std::cout << "PDE Solver initialized:" << std::endl;
    std::cout << "  Grid: " << config_.nx << "x" << config_.ny << "x" << config_.nz << std::endl;
    std::cout << "  Substrates: " << config_.num_substrates << std::endl;
    std::cout << "  Total memory: " << (3 * total_size) / (1024.0 * 1024.0) << " MB" << std::endl;
    std::cout << "  PDE timestep: " << config_.dt_pde << " s" << std::endl;
    std::cout << "  Substeps per ABM step: " << config_.substeps_per_abm << std::endl;
}

void PDESolver::solve_timestep() {
    // CUDA grid configuration
    dim3 block(8, 8, 8);
    dim3 grid(
        (config_.nx + block.x - 1) / block.x,
        (config_.ny + block.y - 1) / block.y,
        (config_.nz + block.z - 1) / block.z
    );
    
    int voxels_per_substrate = config_.nx * config_.ny * config_.nz;
    
    // Solve for each substrate
    for (int sub = 0; sub < config_.num_substrates; sub++) {
        float D = config_.diffusion_coeffs[sub];
        float lambda = config_.decay_rates[sub];
        
        // Pointers to this substrate's data
        float* C_curr = d_concentrations_current_ + sub * voxels_per_substrate;
        float* C_next = d_concentrations_next_ + sub * voxels_per_substrate;
        float* sources = d_sources_ + sub * voxels_per_substrate;
        
        // Run substeps (explicit scheme requires small timesteps for stability)
        for (int step = 0; step < config_.substeps_per_abm; step++) {
            // Launch diffusion kernel
            diffusion_reaction_kernel<<<grid, block>>>(
                C_curr, C_next, sources,
                config_.nx, config_.ny, config_.nz,
                D, lambda, config_.dt_pde, config_.voxel_size
            );
            CUDA_CHECK(cudaGetLastError());
            
            // Swap buffers for next iteration
            float* temp = C_curr;
            C_curr = C_next;
            C_next = temp;
        }
        
        // Copy final result back to current buffer
        if (config_.substeps_per_abm % 2 == 1) {
            int threads = 256;
            int blocks = (voxels_per_substrate + threads - 1) / threads;
            copy_substrate_kernel<<<blocks, threads>>>(
                C_next, C_curr, voxels_per_substrate
            );
            CUDA_CHECK(cudaGetLastError());
        }
    }
    
    CUDA_CHECK(cudaDeviceSynchronize());
}

void PDESolver::set_sources(const float* h_sources, int substrate_idx) {
    if (substrate_idx < 0 || substrate_idx >= config_.num_substrates) {
        throw std::runtime_error("Invalid substrate index");
    }
    
    int voxels = config_.nx * config_.ny * config_.nz;
    size_t offset = substrate_idx * voxels * sizeof(float);
    
    CUDA_CHECK(cudaMemcpy(
        d_sources_ + substrate_idx * voxels,
        h_sources,
        voxels * sizeof(float),
        cudaMemcpyHostToDevice
    ));
}

void PDESolver::add_source_at_voxel(int x, int y, int z, int substrate_idx, float value) {
    if (x < 0 || x >= config_.nx || y < 0 || y >= config_.ny || z < 0 || z >= config_.nz) {
        return; // Out of bounds
    }
    
    int voxel_idx = idx(x, y, z);
    int offset = substrate_idx * get_total_voxels() + voxel_idx;
    
    // Atomic add on device (launch simple kernel)
    add_source_kernel<<<1, 1>>>(d_sources_, offset, value);
    CUDA_CHECK(cudaGetLastError());
}

void PDESolver::get_concentrations(float* h_concentrations, int substrate_idx) const {
    if (substrate_idx < 0 || substrate_idx >= config_.num_substrates) {
        throw std::runtime_error("Invalid substrate index");
    }
    
    int voxels = config_.nx * config_.ny * config_.nz;
    
    CUDA_CHECK(cudaMemcpy(
        h_concentrations,
        d_concentrations_current_ + substrate_idx * voxels,
        voxels * sizeof(float),
        cudaMemcpyDeviceToHost
    ));
}

float PDESolver::get_concentration_at_voxel(int x, int y, int z, int substrate_idx) const {
    if (x < 0 || x >= config_.nx || y < 0 || y >= config_.ny || z < 0 || z >= config_.nz) {
        return 0.0f;
    }
    
    int voxel_idx = idx(x, y, z);
    int offset = substrate_idx * get_total_voxels() + voxel_idx;
    
    float value;
    CUDA_CHECK(cudaMemcpy(
        &value,
        d_concentrations_current_ + offset,
        sizeof(float),
        cudaMemcpyDeviceToHost
    ));
    
    return value;
}

float* PDESolver::get_device_concentration_ptr(int substrate_idx) {
    if (substrate_idx < 0 || substrate_idx >= config_.num_substrates) {
        return nullptr;
    }
    return d_concentrations_current_ + substrate_idx * get_total_voxels();
}

float* PDESolver::get_device_source_ptr(int substrate_idx) {
    if (substrate_idx < 0 || substrate_idx >= config_.num_substrates) {
        return nullptr;
    }
    return d_sources_ + substrate_idx * get_total_voxels();
}

void PDESolver::reset_concentrations() {
    int total_voxels = get_total_voxels();
    size_t total_size = total_voxels * config_.num_substrates * sizeof(float);
    CUDA_CHECK(cudaMemset(d_concentrations_current_, 0, total_size));
    CUDA_CHECK(cudaMemset(d_concentrations_next_, 0, total_size));
}

void PDESolver::reset_sources() {
    int total_voxels = get_total_voxels();
    size_t total_size = total_voxels * config_.num_substrates * sizeof(float);
    CUDA_CHECK(cudaMemset(d_sources_, 0, total_size));
}

void PDESolver::set_initial_concentration(int substrate_idx, float value) {
    if (substrate_idx < 0 || substrate_idx >= config_.num_substrates) {
        throw std::runtime_error("Invalid substrate index");
    }
    
    int voxels = get_total_voxels();
    std::vector<float> init_values(voxels, value);
    
    CUDA_CHECK(cudaMemcpy(
        d_concentrations_current_ + substrate_idx * voxels,
        init_values.data(),
        voxels * sizeof(float),
        cudaMemcpyHostToDevice
    ));
}

void PDESolver::swap_buffers() {
    float* temp = d_concentrations_current_;
    d_concentrations_current_ = d_concentrations_next_;
    d_concentrations_next_ = temp;
}

} // namespace PDAC