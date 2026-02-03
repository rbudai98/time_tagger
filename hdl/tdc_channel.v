// =============================================================================
// TDC Channel - Single channel Time-to-Digital Converter using CARRY4 chain
// =============================================================================
// Resolution: ~25ps per tap (CARRY4 on Zynq-7000)
// Coarse counter: 32-bit @ 200MHz = 5ns resolution
// Total timestamp: 40 bits (32 coarse + 8 fine)
// =============================================================================

`timescale 1ns / 1ps

module tdc_channel #(
    parameter integer NTAPS = 160,      // ~160 × 25ps ≈ 4ns (one clock period)
    parameter integer CHANNEL_ID = 0    // Channel identifier for multi-channel systems
)(
    input  wire        clk,             // 200 MHz system clock
    input  wire        rst_n,           // Active-low reset
    input  wire        enable,          // Channel enable
    input  wire        hit,             // Input pulse to timestamp
    
    // Timestamp output
    output reg         ts_valid,        // Timestamp valid pulse
    output reg  [39:0] timestamp,       // {coarse[31:0], fine_count[7:0]}
    output reg  [3:0]  channel_id       // Channel ID for multi-channel
);

    // =========================================================================
    // CARRY4 Delay Line (TDC Core)
    // =========================================================================
    
    wire [NTAPS:0] carry;
    reg  [NTAPS-1:0] taps;
    
    assign carry[0] = hit;

    genvar i;
    generate
        for (i = 0; i < NTAPS/4; i = i + 1) begin : tdc_chain
            (* DONT_TOUCH = "TRUE" *)
            CARRY4 carry4_inst (
                .CI(carry[i*4]),
                .CO({carry[i*4+4], carry[i*4+3], carry[i*4+2], carry[i*4+1]}),
                .CYINIT(1'b0),
                .DI(4'b0000),
                .S(4'b1111),
                .O()
            );
        end
    endgenerate

    // Sample the carry chain
    always @(posedge clk) begin
        taps <= carry[NTAPS-1:0];
    end

    // =========================================================================
    // Coarse Counter (32-bit free-running)
    // =========================================================================
    
    reg [31:0] coarse_counter;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            coarse_counter <= 32'd0;
        else if (enable)
            coarse_counter <= coarse_counter + 1;
    end

    // =========================================================================
    // Edge Detection
    // =========================================================================
    
    reg hit_d1, hit_d2;
    wire hit_rising;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            hit_d1 <= 1'b0;
            hit_d2 <= 1'b0;
        end else begin
            hit_d1 <= hit;
            hit_d2 <= hit_d1;
        end
    end
    
    assign hit_rising = hit_d1 & ~hit_d2;

    // =========================================================================
    // Population Count (Thermometer to Binary) - Tree-based for timing
    // =========================================================================
    // Count the number of 1s in the tap array to get fine time
    // Uses 2-stage pipelined tree reduction for better timing at 200MHz

    reg [7:0] fine_count;

    // Stage 1: Count 4-bit groups (40 groups of 4 bits each)
    reg [2:0] stage1 [0:39];  // Each can be 0-4
    integer j;

    always @(posedge clk) begin
        for (j = 0; j < 40; j = j + 1) begin
            stage1[j] <= taps[j*4+0] + taps[j*4+1] + taps[j*4+2] + taps[j*4+3];
        end
    end

    // Stage 2: Sum all stage1 results using tree reduction
    reg [7:0] sum_level1 [0:9];   // 10 sums of 4 stage1 values each (max 16 each)
    reg [7:0] sum_level2 [0:1];   // 2 sums of 5 level1 values each (max 80 each)
    reg [7:0] sum_final;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fine_count <= 8'd0;
        end else begin
            // Level 1: Sum groups of 4 stage1 values
            for (j = 0; j < 10; j = j + 1) begin
                sum_level1[j] <= stage1[j*4+0] + stage1[j*4+1] +
                                 stage1[j*4+2] + stage1[j*4+3];
            end

            // Level 2: Sum groups of 5 level1 values
            sum_level2[0] <= sum_level1[0] + sum_level1[1] + sum_level1[2] +
                             sum_level1[3] + sum_level1[4];
            sum_level2[1] <= sum_level1[5] + sum_level1[6] + sum_level1[7] +
                             sum_level1[8] + sum_level1[9];

            // Final sum
            fine_count <= sum_level2[0] + sum_level2[1];
        end
    end

    // =========================================================================
    // Timestamp Capture
    // =========================================================================
    // Pipeline delay to match popcount latency:
    //   Stage 1 (taps->stage1):      1 cycle
    //   Level 1 (stage1->sum_level1): 1 cycle
    //   Level 2 (sum_level1->sum_level2): 1 cycle
    //   Final (sum_level2->fine_count): 1 cycle
    //   Total: 4 cycles from taps sampling to fine_count valid

    reg [31:0] coarse_captured;
    reg [3:0]  capture_pipe;  // 4-stage pipeline for popcount latency

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ts_valid <= 1'b0;
            timestamp <= 40'd0;
            channel_id <= 4'd0;
            capture_pipe <= 4'b0;
            coarse_captured <= 32'd0;
        end else begin
            ts_valid <= 1'b0;

            // Shift the capture pipeline
            capture_pipe <= {capture_pipe[2:0], 1'b0};

            if (enable && hit_rising) begin
                // Capture coarse counter immediately
                coarse_captured <= coarse_counter;
                capture_pipe[0] <= 1'b1;
            end

            // Output timestamp after pipeline delay (when fine_count is valid)
            if (capture_pipe[3]) begin
                timestamp <= {coarse_captured, fine_count};
                channel_id <= CHANNEL_ID[3:0];
                ts_valid <= 1'b1;
            end
        end
    end

endmodule
