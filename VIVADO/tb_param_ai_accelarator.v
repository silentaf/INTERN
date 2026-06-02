`timescale 1ns / 1ps

module tb_param_ai_accelerator;

    // ========================================================================
    // SCALING PARAMETER: Change this to whatever size you want (e.g. 4, 8, 16)
    // ========================================================================
    parameter N = 4;
    parameter DATA_W = 8;
    parameter PSUM_W = 16;

    reg clk;
    reg reset;
    reg load_weights;
    
    reg  [(N*N)*DATA_W-1:0] in_weights_flat;
    reg  [N*DATA_W-1:0]     raw_in_pixels_left;
    reg  [N*PSUM_W-1:0]     in_psums_top;
    
    wire [N*PSUM_W-1:0]     flat_out_psums_bottom;
    wire [N*DATA_W-1:0]     out_pixels_right;

    // Instantiate Unit Under Test (UUT)
    param_ai_accelerator #(
        .N(N),
        .DATA_W(DATA_W),
        .PSUM_W(PSUM_W)
    ) uut (
        .clk(clk),
        .reset(reset),
        .load_weights(load_weights),
        .in_weights_flat(in_weights_flat),
        .raw_in_pixels_left(raw_in_pixels_left),
        .in_psums_top(in_psums_top),
        .flat_out_psums_bottom(flat_out_psums_bottom),
        .out_pixels_right(out_pixels_right)
    );

    // Clock generation (10ns period)
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // Task to set a specific weight in the flattened array easily
    task set_weight(input integer row, input integer col, input [DATA_W-1:0] val);
        begin
            in_weights_flat[((row*N + col)*DATA_W) +: DATA_W] = val;
        end
    endtask

    // Task to set a specific input pixel in the flattened array easily
    task set_pixel(input integer row, input [DATA_W-1:0] val);
        begin
            raw_in_pixels_left[row*DATA_W +: DATA_W] = val;
        end
    endtask
    
    integer r, c;

    initial begin
        // Initialize Inputs
        reset = 1;
        load_weights = 0;
        in_weights_flat = 0;
        raw_in_pixels_left = 0;
        in_psums_top = 0;

        // Wait for global reset to finish
        #100;
        reset = 0;
        #10;
        
        // ====================================================================
        // PHASE 1: Load Weights
        // For demonstration, let's load a matrix where Weight(i,j) = i*N + j + 1
        // W = [ 1  2  3  4 ]
        //     [ 5  6  7  8 ]
        //     [ 9 10 11 12 ]
        //     [13 14 15 16 ]
        // ====================================================================
        load_weights = 1;
        for (r = 0; r < N; r = r + 1) begin
            for (c = 0; c < N; c = c + 1) begin
                set_weight(r, c, (r * N) + c + 1);
            end
        end
        
        // Print the Weight Matrix to the console
        $display("\n=======================================================");
        $display("          WEIGHT MATRIX (Loaded into Array)              ");
        $display("=======================================================");
        for (r = 0; r < N; r = r + 1) begin
            $write("Row %0d: [ ", r);
            for (c = 0; c < N; c = c + 1) begin
                $write("%3d ", (r * N) + c + 1);
            end
            $display("]");
        end
        $display("=======================================================\n");

        #10;
        load_weights = 0;
        
        // ====================================================================
        // PHASE 2: Feed input matrix X to compute X * W
        // We will feed the Identity Matrix (so the output should equal W)
        // X = [ 1 0 0 0 ]
        //     [ 0 1 0 0 ]
        //     [ 0 0 1 0 ]
        //     [ 0 0 0 1 ]
        // ====================================================================
        
        $display("=======================================================");
        $display("          INPUT MATRIX X (Identity Matrix)               ");
        $display("=======================================================");
        for (r = 0; r < N; r = r + 1) begin
            $write("Row %0d: [ ", r);
            for (c = 0; c < N; c = c + 1) begin
                if (r == c) $write("%3d ", 1);
                else        $write("%3d ", 0);
            end
            $display("]");
        end
        $display("=======================================================\n");
        $display("Now flowing data through the array... Watch the outputs below!\n");

        // Send rows one by one (Identity matrix sends a '1' down the diagonal)
        for (r = 0; r < N; r = r + 1) begin
            for (c = 0; c < N; c = c + 1) begin
                if (r == c) set_pixel(c, 1);
                else        set_pixel(c, 0);
            end
            #10; // Wait 1 cycle for next row
        end
        
        // Feed Zeros to push the rest of the data through the array pipeline
        raw_in_pixels_left = 0;
        
        // Wait enough cycles for the pipeline to flush
        // Pipeline latency = (N-1) input skew + N array + (N-1) output skew = 3N - 2 cycles
        #(10 * (3 * N + 5));
        
        $display("\n=======================================================");
        $display("Simulation Complete. Scroll up to see the matrix flow!");
        $display("=======================================================\n");
        $finish;
    end

    // Monitor Outputs (Prints the N outputs from the bottom each cycle)
    always @(posedge clk) begin
        if (!reset && !load_weights) begin
            $write("Time=%0t | Out [ ", $time);
            for (c = 0; c < N; c = c + 1) begin
                $write("Col%0d:%3d ", c, flat_out_psums_bottom[c*PSUM_W +: PSUM_W]);
            end
            $display("]");
        end
    end

endmodule
