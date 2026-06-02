# ==============================================================================
# INTERACTIVE SYSTOLIC ARRAY ARCHITECTURAL EXPLORER (2x2 to 256x256)
# ==============================================================================
# This interactive Python tool allows you to explore the latency, clock cycles,
# DSP usage, and throughput (GOPS) for multiplying large matrices on various
# systolic array sizes ranging from 2x2 up to 256x256.
# ==============================================================================

import sys

def print_dashboard(matrix_size, clk_mhz):
    # Array sizes to evaluate
    array_sizes = [2, 4, 8, 16, 32, 64, 128, 256]
    
    # Total mathematical operations in matrix multiplication: 2 * N^3
    total_ops = 2 * (matrix_size ** 3)
    
    print("\n" + "="*95)
    print(f"               SYSTOLIC ARRAY ARCHITECTURAL EXPLORER REPORT")
    print("="*95)
    print(f"  Target Matrix Size  : {matrix_size} x {matrix_size}")
    print(f"  Clock Frequency     : {clk_mhz} MHz  (1 cycle = {1000.0/clk_mhz:.2f} ns)")
    print(f"  Total Math Operations: {total_ops:,} Operations (MACs)")
    print("="*95)
    
    # Header
    print(f"{'Array Size':<12} | {'PEs (DSPs)':<12} | {'Tile Count T':<14} | {'Total Cycles':<16} | {'Real Latency':<18} | {'Throughput':<12}")
    print("-" * 95)
    
    for H in array_sizes:
        if matrix_size % H != 0:
            # Skip if matrix size is not perfectly divisible by array size
            print(f"{f'{H}x{H}':<12} | {H*H:<12,} | {f'{matrix_size//H}x{matrix_size//H}':<14} | {'Non-divisible':<16} | {'N/A':<18} | {'N/A':<12}")
            continue
            
        T = matrix_size // H
        
        # 1. Weight Load Cycles: Preloading H x H weights takes H cycles, T*T times
        weight_load_cycles = (T * T) * H
        
        # 2. Execution Cycles: (3H - 2) cycles per block run, T*T*T times
        execution_cycles = (T * T * T) * (3 * H - 2)
        
        # 3. Total Cycles
        total_cycles = weight_load_cycles + execution_cycles
        
        # 4. Physical Latency in Milliseconds
        latency_ms = (total_cycles / (clk_mhz * 1e6)) * 1000.0
        
        # 5. Throughput in GOPS (Giga-Operations Per Second)
        latency_sec = latency_ms / 1000.0
        gops = (total_ops / 1e9) / latency_sec if latency_sec > 0 else 0
        
        # 6. Active PE Efficiency
        active_mac_cycles = (T * T * T) * H
        efficiency = (active_mac_cycles / total_cycles) * 100.0
        
        # Format Latency string
        if latency_ms < 1.0:
            latency_str = f"{latency_ms * 1000.0:.2f} us" # Microseconds
        elif latency_ms >= 1000.0:
            latency_str = f"{latency_ms / 1000.0:.3f} s"  # Seconds
        else:
            latency_str = f"{latency_ms:.3f} ms"          # Milliseconds
            
        print(f"{f'{H}x{H}':<12} | {H*H:<12,} | {f'{T}x{T}':<14} | {total_cycles:<16,} | {latency_str:<18} | {gops:<7.2f} GOPS")
        
    print("-" * 95)
    print("  Note: PE/DSP count scales quadratically (H^2). Larger arrays give exponential speedups")
    print("        but consume more silicon area and routing resources on your FPGA chip.")
    print("="*95 + "\n")

if __name__ == "__main__":
    # Set default parameters
    matrix_size = 1024
    clk_mhz = 100.0
    
    # Check for command line arguments
    if len(sys.argv) > 1:
        try:
            matrix_size = int(sys.argv[1])
        except ValueError:
            print("Invalid matrix size argument. Using default 1024.")
            
    if len(sys.argv) > 2:
        try:
            clk_mhz = float(sys.argv[2])
        except ValueError:
            print("Invalid clock frequency argument. Using default 100 MHz.")
            
    # Print the report
    print_dashboard(matrix_size, clk_mhz)
    
    print("  [TIP] You can run this script with custom matrix size and clock frequency arguments!")
    print("   Example:  python check_systolic_metrics.py 2048 200")
    print("             (Calculates for 2048x2048 matrix at 200 MHz clock)\n")
