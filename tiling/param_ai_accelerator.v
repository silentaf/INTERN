`timescale 1ns / 1ps

// ============================================================================
// MODULE 1: param_ai_accelerator (The NxN Parametrized Top-Level Wrapper)
// ============================================================================
module param_ai_accelerator #(
    parameter N = 4,           
    parameter DATA_W = 8,
    parameter PSUM_W = 16
) (
    input  wire clk,
    input  wire reset,
    input  wire load_weights,
    
    // Flattened weight array: N*N weights
    input  wire [(N*N)*DATA_W-1:0] in_weights_flat,
    
    // Flattened inputs on left (unskewed)
    input  wire [N*DATA_W-1:0] raw_in_pixels_left,
    
    // Flattened partial sums on top
    input  wire [N*PSUM_W-1:0] in_psums_top,
    
    // Final unskewed outputs on bottom
    output wire [N*PSUM_W-1:0] flat_out_psums_bottom,
    
    // Final outputs on right
    output wire [N*DATA_W-1:0] out_pixels_right
);

    // ========================================================================
    // INPUT SKEW BUFFER (Parametrized delay for row 'i')
    // ========================================================================
    wire [N*DATA_W-1:0] skewed_pixels_left;
    
    genvar i, j;
    generate
        for (i = 0; i < N; i = i + 1) begin : skew_row
            if (i == 0) begin
                assign skewed_pixels_left[i*DATA_W +: DATA_W] = raw_in_pixels_left[i*DATA_W +: DATA_W];
            end else begin
                // Shift register of length i
                reg [DATA_W-1:0] delay_regs [0:i-1];
                integer d;
                always @(posedge clk) begin
                    if (reset) begin
                        for (d = 0; d < i; d = d + 1)
                            delay_regs[d] <= 0;
                    end else begin
                        delay_regs[0] <= raw_in_pixels_left[i*DATA_W +: DATA_W];
                        for (d = 1; d < i; d = d + 1)
                            delay_regs[d] <= delay_regs[d-1];
                    end
                end
                assign skewed_pixels_left[i*DATA_W +: DATA_W] = delay_regs[i-1];
            end
        end
    endgenerate

    // ========================================================================
    // SYSTOLIC ARRAY CORE
    // ========================================================================
    wire [N*DATA_W-1:0] core_out_pixels_right;
    wire [N*PSUM_W-1:0] core_out_psums_bottom;
    
    param_array_core #(
        .N(N),
        .DATA_W(DATA_W),
        .PSUM_W(PSUM_W)
    ) core (
        .clk(clk),
        .reset(reset),
        .load_weights(load_weights),
        .in_weights_flat(in_weights_flat),
        .in_pixels_left(skewed_pixels_left),
        .in_psums_top(in_psums_top),
        .out_psums_bottom(core_out_psums_bottom),
        .out_pixels_right(core_out_pixels_right)
    );
    
    assign out_pixels_right = core_out_pixels_right;

    // ========================================================================
    // OUTPUT UN-SKEW BUFFER (Parametrized delay for col 'j')
    // ========================================================================
    generate
        for (j = 0; j < N; j = j + 1) begin : unskew_col
            localparam delay_len = N - 1 - j;
            if (delay_len == 0) begin
                assign flat_out_psums_bottom[j*PSUM_W +: PSUM_W] = core_out_psums_bottom[j*PSUM_W +: PSUM_W];
            end else begin
                // Shift register of length (N-1-j)
                reg [PSUM_W-1:0] delay_regs [0:delay_len-1];
                integer d;
                always @(posedge clk) begin
                    if (reset) begin
                        for (d = 0; d < delay_len; d = d + 1)
                            delay_regs[d] <= 0;
                    end else begin
                        delay_regs[0] <= core_out_psums_bottom[j*PSUM_W +: PSUM_W];
                        for (d = 1; d < delay_len; d = d + 1)
                            delay_regs[d] <= delay_regs[d-1];
                    end
                end
                assign flat_out_psums_bottom[j*PSUM_W +: PSUM_W] = delay_regs[delay_len-1];
            end
        end
    endgenerate

endmodule


// ============================================================================
// MODULE 2: param_array_core (The NxN Grid)
// ============================================================================
module param_array_core #(
    parameter N = 4,
    parameter DATA_W = 8,
    parameter PSUM_W = 16
) (
    input  wire clk,
    input  wire reset,
    input  wire load_weights,
    
    input  wire [(N*N)*DATA_W-1:0] in_weights_flat,
    input  wire [N*DATA_W-1:0]     in_pixels_left,
    input  wire [N*PSUM_W-1:0]     in_psums_top,
    
    output wire [N*PSUM_W-1:0]     out_psums_bottom,
    output wire [N*DATA_W-1:0]     out_pixels_right
);

    wire [DATA_W-1:0] pixel_wires [0:N-1][0:N-1];
    wire [PSUM_W-1:0] psum_wires  [0:N-1][0:N-1];

    genvar r, c;
    generate
        for (r = 0; r < N; r = r + 1) begin : row_gen
            for (c = 0; c < N; c = c + 1) begin : col_gen
                
                wire [DATA_W-1:0] pe_in_pixel;
                wire [PSUM_W-1:0] pe_in_psum;
                wire [DATA_W-1:0] pe_in_weight;
                
                assign pe_in_weight = in_weights_flat[((r*N + c)*DATA_W) +: DATA_W];
                
                if (c == 0) begin
                    assign pe_in_pixel = in_pixels_left[r*DATA_W +: DATA_W];
                end else begin
                    assign pe_in_pixel = pixel_wires[r][c-1];
                end
                
                if (r == 0) begin
                    assign pe_in_psum = in_psums_top[c*PSUM_W +: PSUM_W];
                end else begin
                    assign pe_in_psum = psum_wires[r-1][c];
                end
                
                pe #(
                    .DATA_W(DATA_W),
                    .PSUM_W(PSUM_W)
                ) pe_inst (
                    .clk(clk),
                    .reset(reset),
                    .load_weights(load_weights),
                    .in_pixel(pe_in_pixel),
                    .in_weight(pe_in_weight),
                    .in_psum(pe_in_psum),
                    .out_pixel(pixel_wires[r][c]),
                    .out_psum(psum_wires[r][c])
                );
                
                if (c == N - 1) begin
                    assign out_pixels_right[r*DATA_W +: DATA_W] = pixel_wires[r][c];
                end
                if (r == N - 1) begin
                    assign out_psums_bottom[c*PSUM_W +: PSUM_W] = psum_wires[r][c];
                end
                
            end
        end
    endgenerate

endmodule


// ============================================================================
// MODULE 3: pe (The Single Processing Element)
// ============================================================================
module pe #(
    parameter DATA_W = 8,
    parameter PSUM_W = 16
) (
    input  wire              clk,
    input  wire              reset,
    input  wire              load_weights,
    
    input  wire [DATA_W-1:0] in_pixel,     
    input  wire [DATA_W-1:0] in_weight,    
    input  wire [PSUM_W-1:0] in_psum,      
    
    output reg  [DATA_W-1:0] out_pixel,    
    output reg  [PSUM_W-1:0] out_psum      
);

    reg [DATA_W-1:0] weight_reg;

    always @(posedge clk) begin
        if (reset) begin
            weight_reg <= 0;
            out_pixel  <= 0;
            out_psum   <= 0;
        end else if (load_weights) begin
            weight_reg <= in_weight; 
            out_pixel  <= 0;         
            out_psum   <= 0;
        end else begin
            out_pixel <= in_pixel;
            out_psum  <= in_psum + (in_pixel * weight_reg);
        end
    end

endmodule
