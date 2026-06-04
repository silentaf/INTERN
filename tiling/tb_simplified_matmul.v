`timescale 1ns / 1ps

module tb_simple_tiled_example;

    localparam N      = 4;        
    localparam DATA_W = 8;
    localparam PSUM_W = 16;
    localparam MAT_SZ = 8;       // 8x8 Matrix
    
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

    integer r, c, val;

    initial begin
        clk   = 0;
        reset = 1;
        start = 0;
        
        #50;
        reset = 0;
        #50;
        
        $display("================================================================");
        $display("       SIMPLE TILED TESTBENCH (8x8 Matrix on 4x4 Array)         ");
        $display("================================================================");
        
        // Initialize A as an Identity Matrix
        // Initialize B as Sequential numbers (1, 2, 3...)
        // Because A is an Identity Matrix, C = A*B should exactly equal B!
        val = 1;
        for (r = 0; r < MAT_SZ; r = r + 1) begin
            for (c = 0; c < MAT_SZ; c = c + 1) begin
                if (r == c) u_controller.sram_A[r][c] = 1;
                else        u_controller.sram_A[r][c] = 0;
                
                u_controller.sram_B[r][c] = val;
                u_controller.sram_C[r][c] = 0; 
                val = val + 1;
            end
        end

        $display("Matrix A (Identity):");
        for (r = 0; r < MAT_SZ; r = r + 1) begin
            $display("%d %d %d %d %d %d %d %d", 
                u_controller.sram_A[r][0], u_controller.sram_A[r][1], u_controller.sram_A[r][2], u_controller.sram_A[r][3],
                u_controller.sram_A[r][4], u_controller.sram_A[r][5], u_controller.sram_A[r][6], u_controller.sram_A[r][7]);
        end
        $display("");

        $display("Matrix B (Sequential 1 to 64):");
        for (r = 0; r < MAT_SZ; r = r + 1) begin
            $display("%2d %2d %2d %2d %2d %2d %2d %2d", 
                u_controller.sram_B[r][0], u_controller.sram_B[r][1], u_controller.sram_B[r][2], u_controller.sram_B[r][3],
                u_controller.sram_B[r][4], u_controller.sram_B[r][5], u_controller.sram_B[r][6], u_controller.sram_B[r][7]);
        end
        $display("");

        $display("Starting hardware computation...");
        start = 1;
        @(posedge clk);
        start = 0;

        @(posedge done);
        #40;
        $display("Hardware execution completed!");
        
        $display("\n--- RESULT MATRIX C ---");
        $display("Since C = A * B, and A is an identity matrix, C should be exactly equal to B!");
        for (r = 0; r < MAT_SZ; r = r + 1) begin
            $display("%4d %4d %4d %4d %4d %4d %4d %4d", 
                     u_controller.sram_C[r][0], u_controller.sram_C[r][1], 
                     u_controller.sram_C[r][2], u_controller.sram_C[r][3],
                     u_controller.sram_C[r][4], u_controller.sram_C[r][5], 
                     u_controller.sram_C[r][6], u_controller.sram_C[r][7]);
        end
        $display("================================================================");
        
        $finish;
    end
endmodule
