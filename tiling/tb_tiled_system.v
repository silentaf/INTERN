`timescale 1ns / 1ps

// ============================================================================
// MODULE: tb_tiled_system (Simulation Top-Level Wrapper)
// ============================================================================
module tb_tiled_system;

    localparam N      = 4;        
    localparam DATA_W = 8;
    localparam PSUM_W = 16;
    localparam MAT_SZ = 16;       
    localparam T      = MAT_SZ / N; 

    reg  clk;
    reg  reset;
    reg  start;
    wire done;
    
    wire load_weights;
    wire [(N*N)*DATA_W-1:0] out_weights_flat;
    wire [N*DATA_W-1:0]     out_pixels_left;
    wire [N*PSUM_W-1:0]     out_psums_top;
    wire [N*PSUM_W-1:0]     flat_in_psums_bottom;
    wire [N*DATA_W-1:0]     out_pixels_right;

    always #10 clk = ~clk;

    // Instantiate Controller FSM
    tiled_systolic_controller #(
        .N(N),
        .DATA_W(DATA_W),
        .PSUM_W(PSUM_W),
        .MAT_SZ(MAT_SZ)
    ) u_controller (
        .clk(clk),
        .reset(reset),
        .start(start),
        .done(done),
        .load_weights(load_weights),
        .out_weights_flat(out_weights_flat),
        .out_pixels_left(out_pixels_left),
        .out_psums_top(out_psums_top),
        .flat_in_psums_bottom(flat_in_psums_bottom)
    );

    // Instantiate your parameterized Systolic Array Core
    param_ai_accelerator #(
        .N(N),
        .DATA_W(DATA_W),
        .PSUM_W(PSUM_W)
    ) u_systolic_array (
        .clk(clk),
        .reset(reset),
        .load_weights(load_weights),
        .in_weights_flat(out_weights_flat),
        .raw_in_pixels_left(out_pixels_left),
        .in_psums_top(out_psums_top),
        .flat_out_psums_bottom(flat_in_psums_bottom),
        .out_pixels_right(out_pixels_right)
    );

    reg [PSUM_W-1:0] ref_C [0:MAT_SZ-1][0:MAT_SZ-1]; 
    integer r, c, k_idx;
    integer errors;

    initial begin
        clk   = 0;
        reset = 1;
        start = 0;
        errors = 0;
        
        #100;
        reset = 0;
        #40;
        
        $display("================================================================");
        $display("          STARTING TILED SYSTOLIC ARRAY VERIFICATION            ");
        $display("================================================================");
        $display("Matrix Size: %0dx%0d  |  Systolic Array Size: %0dx%0d", MAT_SZ, MAT_SZ, N, N);
        
        $display("[INFO] Initializing random integer matrices in SRAM...");
        for (r = 0; r < MAT_SZ; r = r + 1) begin
            for (c = 0; c < MAT_SZ; c = c + 1) begin
                u_controller.sram_A[r][c] = $random % 11;
                u_controller.sram_B[r][c] = $random % 11;
                u_controller.sram_C[r][c] = 0; 
                ref_C[r][c] = 0;
            end
        end

        // Compute Golden Reference
        for (r = 0; r < MAT_SZ; r = r + 1) begin
            for (c = 0; c < MAT_SZ; c = c + 1) begin
                for (k_idx = 0; k_idx < MAT_SZ; k_idx = k_idx + 1) begin
                    ref_C[r][c] = ref_C[r][c] + 
                        (u_controller.sram_A[r][k_idx] * u_controller.sram_B[k_idx][c]);
                end
            end
        end

        $display("[INFO] Triggering Tiled Systolic Controller FSM...");
        start = 1;
        @(posedge clk);
        start = 0;

        @(posedge done);
        #40;
        $display("[INFO] Tiled hardware execution completed!");

        $display("[INFO] Verifying hardware SRAM C against reference C...");
        for (r = 0; r < MAT_SZ; r = r + 1) begin
            for (c = 0; c < MAT_SZ; c = c + 1) begin
                if (u_controller.sram_C[r][c] !== ref_C[r][c]) begin
                    $display("[ERROR] Mismatch at C[%0d][%0d]! HW=%0d, Ref=%0d", 
                             r, c, u_controller.sram_C[r][c], ref_C[r][c]);
                    errors = errors + 1;
                end
            end
        end

        $display("================================================================");
        if (errors == 0) begin
            $display(" SUCCESS: Tiled hardware MatMul matches Reference 100%%!");
            $display(" Verified Matrix multiplication using %0dx%0d blocks successfully.", N, N);
        end else begin
            $display(" FAILURE: Found %0d mismatches in output matrix calculation.", errors);
        end
        $display("================================================================");
        
        $finish;
    end

    // Cycle Debug Print
    always @(posedge clk) begin
        if (u_controller.current_state == u_controller.STATE_STREAM_A) begin
            $display("[CYCLE_DEBUG] Time=%0d ns | cycle_cnt=%0d | flat_in_psums_bottom=%h", 
                     $time, u_controller.cycle_cnt, flat_in_psums_bottom);
        end
    end

endmodule
