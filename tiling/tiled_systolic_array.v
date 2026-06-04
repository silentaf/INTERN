`timescale 1ns / 1ps

// ============================================================================
// MODULE: tiled_systolic_controller (Nested Loop FSM Manager)
// ============================================================================
module tiled_systolic_controller #(
    parameter N      = 4,         // Default configured to 4x4
    parameter DATA_W = 8,
    parameter PSUM_W = 16,
    parameter MAT_SZ = 16         // Default configured to 16x16 Matrix
) (
    input  wire clk,
    input  wire reset,
    input  wire start,
    
    output reg  done,
    
    // Interface to Systolic Array
    output reg  load_weights,
    output reg  [(N*N)*DATA_W-1:0] out_weights_flat,
    output reg  [N*DATA_W-1:0]     out_pixels_left,
    output reg  [N*PSUM_W-1:0]     out_psums_top,
    input  wire [N*PSUM_W-1:0]     flat_in_psums_bottom
);

    localparam T = MAT_SZ / N;    // Number of tiles (e.g. 16/4 = 4)
    
    // FSM States
    localparam STATE_IDLE       = 3'b000;
    localparam STATE_LOAD_W     = 3'b001; 
    localparam STATE_STREAM_A   = 3'b010; 
    localparam STATE_ACCUM      = 3'b011; 
    localparam STATE_NEXT_TILE  = 3'b100; 
    localparam STATE_DONE       = 3'b101;
    
    reg [2:0] current_state, next_state;
    
    // Loop Counter Registers (I, J, K)
    reg [9:0] i_tile; 
    reg [9:0] j_tile; 
    reg [9:0] k_tile; 
    
    // Cycle Counters for tile execution
    reg [7:0] cycle_cnt;
    localparam STREAM_CYCLES = 3 * N; // Set to exactly 3N cycles (12 cycles for 4x4)

    // Simulated SRAM Buffers
    reg [DATA_W-1:0] sram_A [0:MAT_SZ-1][0:MAT_SZ-1];
    reg [DATA_W-1:0] sram_B [0:MAT_SZ-1][0:MAT_SZ-1];
    reg [PSUM_W-1:0] sram_C [0:MAT_SZ-1][0:MAT_SZ-1]; 

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            current_state <= STATE_IDLE;
        end else begin
            current_state <= next_state;
        end
    end

    // FSM Next State Logic
    always @(*) begin
        case (current_state)
            STATE_IDLE: begin
                if (start) next_state = STATE_LOAD_W;
                else       next_state = STATE_IDLE;
            end
            STATE_LOAD_W: begin
                next_state = STATE_STREAM_A;
            end
            STATE_STREAM_A: begin
                if (cycle_cnt == STREAM_CYCLES - 1)
                    next_state = STATE_ACCUM;
                else
                    next_state = STATE_STREAM_A;
            end
            STATE_ACCUM: begin
                next_state = STATE_NEXT_TILE;
            end
            STATE_NEXT_TILE: begin
                if (i_tile == T - 1) begin
                    if (j_tile == T - 1) begin
                        if (k_tile == T - 1)
                            next_state = STATE_DONE;
                        else
                            next_state = STATE_LOAD_W;
                    end else begin
                        next_state = STATE_LOAD_W;
                    end
                end else begin
                    next_state = STATE_STREAM_A;
                end
            end
            STATE_DONE: begin
                next_state = STATE_IDLE;
            end
            default: next_state = STATE_IDLE;
        endcase
    end

    // FSM Control & Loop Datapath Signals
    integer r, c;
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            i_tile        <= 0;
            j_tile        <= 0;
            k_tile        <= 0;
            cycle_cnt     <= 0;
            load_weights  <= 0;
            done          <= 0;
            out_pixels_left <= 0;
            out_psums_top   <= 0;
        end else begin
            load_weights <= 0;
            
            case (current_state)
                STATE_IDLE: begin
                    i_tile    <= 0;
                    j_tile    <= 0;
                    k_tile    <= 0;
                    cycle_cnt <= 0;
                    done      <= 0;
                end
                
                STATE_LOAD_W: begin
                    load_weights <= 1;
                    cycle_cnt    <= 0;
                    
                    // Flatten B_tile weights
                    for (r = 0; r < N; r = r + 1) begin
                        for (c = 0; c < N; c = c + 1) begin
                            out_weights_flat[((r*N + c)*DATA_W) +: DATA_W] <= 
                                sram_B[k_tile*N + r][j_tile*N + c];
                        end
                    end
                end
                
                STATE_STREAM_A: begin
                    cycle_cnt     <= cycle_cnt + 1;
                    out_psums_top <= 0;
                    
                    // Stream skewed inputs
                    for (r = 0; r < N; r = r + 1) begin
                        if (cycle_cnt < N) begin
                            out_pixels_left[r*DATA_W +: DATA_W] <= 
                                sram_A[i_tile*N + cycle_cnt][k_tile*N + r];
                        end else begin
                            out_pixels_left[r*DATA_W +: DATA_W] <= 0;
                        end
                    end
                    
                    // Capture aligned bottom outputs on cycle: r + 2N
                    for (r = 0; r < N; r = r + 1) begin
                        if (cycle_cnt == (r + 2*N)) begin
                            for (c = 0; c < N; c = c + 1) begin
                                sram_C[i_tile*N + r][j_tile*N + c] <= 
                                    sram_C[i_tile*N + r][j_tile*N + c] + 
                                    flat_in_psums_bottom[c*PSUM_W +: PSUM_W];
                            end
                        end
                    end
                end
                
                STATE_ACCUM: begin
                    cycle_cnt <= 0;
                end
                
                STATE_NEXT_TILE: begin
                    if (i_tile == T - 1) begin
                        i_tile <= 0;
                        if (j_tile == T - 1) begin
                            j_tile <= 0;
                            if (k_tile == T - 1) begin
                                k_tile <= 0;
                            end else begin
                                k_tile <= k_tile + 1;
                            end
                        end else begin
                            j_tile <= j_tile + 1;
                        end
                    end else begin
                        i_tile <= i_tile + 1;
                    end
                end
                
                STATE_DONE: begin
                    done <= 1;
                end
            endcase
        end
    end

endmodule
