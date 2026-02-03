// =============================================================================
// Top-Level Wrapper for Time Tagger ZC706
// =============================================================================
// Instantiates the Vivado block design (system_wrapper) and the custom
// time_tagger_top module, connecting them together.
// =============================================================================

`timescale 1ns / 1ps

(* DONT_TOUCH = "TRUE" *)
module top_level (
    // DDR interface (directly from PS7)
    inout  wire [14:0] DDR_addr,
    inout  wire [2:0]  DDR_ba,
    inout  wire        DDR_cas_n,
    inout  wire        DDR_ck_n,
    inout  wire        DDR_ck_p,
    inout  wire        DDR_cke,
    inout  wire        DDR_cs_n,
    inout  wire [3:0]  DDR_dm,
    inout  wire [31:0] DDR_dq,
    inout  wire [3:0]  DDR_dqs_n,
    inout  wire [3:0]  DDR_dqs_p,
    inout  wire        DDR_odt,
    inout  wire        DDR_ras_n,
    inout  wire        DDR_reset_n,
    inout  wire        DDR_we_n,
    
    // Fixed IO (directly from PS7)
    inout  wire        FIXED_IO_ddr_vrn,
    inout  wire        FIXED_IO_ddr_vrp,
    inout  wire [53:0] FIXED_IO_mio,
    inout  wire        FIXED_IO_ps_clk,
    inout  wire        FIXED_IO_ps_porb,
    inout  wire        FIXED_IO_ps_srstb,
    
    // TDC Input (directly from FMC)
    input  wire        tdc_hit_0
);

    // =========================================================================
    // Internal signals between block design and time_tagger
    // =========================================================================
    
    // Clocks and resets from block design
    wire clk_200mhz;
    wire clk_100mhz;
    wire rst_200m_n;
    wire rst_100m_n;
    
    // GPIO control/status
    wire [31:0] gpio_ctrl;
    wire [31:0] gpio_status;
    
    // AXI-Stream from time_tagger to block design FIFO
    wire        axis_tvalid;
    wire        axis_tready;
    wire [63:0] axis_tdata;
    wire        axis_tlast;
    wire [7:0]  axis_tkeep;
    
    // =========================================================================
    // Block Design Instance (PS7 + DMA + GPIO + FIFO)
    // =========================================================================
    
    system_wrapper system_i (
        // DDR interface
        .DDR_addr(DDR_addr),
        .DDR_ba(DDR_ba),
        .DDR_cas_n(DDR_cas_n),
        .DDR_ck_n(DDR_ck_n),
        .DDR_ck_p(DDR_ck_p),
        .DDR_cke(DDR_cke),
        .DDR_cs_n(DDR_cs_n),
        .DDR_dm(DDR_dm),
        .DDR_dq(DDR_dq),
        .DDR_dqs_n(DDR_dqs_n),
        .DDR_dqs_p(DDR_dqs_p),
        .DDR_odt(DDR_odt),
        .DDR_ras_n(DDR_ras_n),
        .DDR_reset_n(DDR_reset_n),
        .DDR_we_n(DDR_we_n),
        
        // Fixed IO
        .FIXED_IO_ddr_vrn(FIXED_IO_ddr_vrn),
        .FIXED_IO_ddr_vrp(FIXED_IO_ddr_vrp),
        .FIXED_IO_mio(FIXED_IO_mio),
        .FIXED_IO_ps_clk(FIXED_IO_ps_clk),
        .FIXED_IO_ps_porb(FIXED_IO_ps_porb),
        .FIXED_IO_ps_srstb(FIXED_IO_ps_srstb),
        
        // Clocks and resets to PL
        .clk_200mhz(clk_200mhz),
        .clk_100mhz(clk_100mhz),
        .rst_200m_n(rst_200m_n),
        .rst_100m_n(rst_100m_n),
        
        // GPIO
        .gpio_ctrl(gpio_ctrl),
        .gpio_status(gpio_status),
        
        // AXI-Stream from time_tagger
        .s_axis_tvalid(axis_tvalid),
        .s_axis_tready(axis_tready),
        .s_axis_tdata(axis_tdata),
        .s_axis_tlast(axis_tlast),
        .s_axis_tkeep(axis_tkeep)
        // NOTE: tdc_hit_0 connects directly to tdc_channel, not through BD
    );

    // =========================================================================
    // Time Tagger Instance
    // =========================================================================
    
    // Decode GPIO control register
    // [0]   = Enable
    // [1]   = Soft reset (self-clearing in SW)
    // [2]   = Clear overflow
    // [31:3] = Reserved
    wire tt_enable        = gpio_ctrl[0];
    wire tt_soft_reset    = gpio_ctrl[1];
    wire tt_clear_overflow = gpio_ctrl[2];
    
    // Status register back to PS
    // [0]    = Running (enabled)
    // [1]    = Overflow flag
    // [2]    = FIFO not empty
    // [3]    = FIFO full
    // [15:4] = FIFO count (12 bits, supports up to 4096 depth)
    // [31:16] = Event count (lower 16 bits)
    wire        overflow_flag;
    wire [15:0] fifo_count;
    wire [31:0] event_count;
    wire        fifo_empty;
    wire        fifo_full;

    assign gpio_status = {
        event_count[15:0],           // [31:16]
        fifo_count[11:0],            // [15:4] - 12 bits for FIFO count
        fifo_full,                   // [3]
        ~fifo_empty,                 // [2] - FIFO has data
        overflow_flag,               // [1]
        tt_enable                    // [0]
    };
    
    // Internal timestamp signals
    wire        ts_valid;
    wire [39:0] timestamp;
    wire [3:0]  channel_id;
    
    // TDC Channel
    tdc_channel #(
        .NTAPS(160),
        .CHANNEL_ID(0)
    ) tdc_ch0 (
        .clk(clk_200mhz),
        .rst_n(rst_200m_n & ~tt_soft_reset),
        .enable(tt_enable),
        .hit(tdc_hit_0),
        .ts_valid(ts_valid),
        .timestamp(timestamp),
        .channel_id(channel_id)
    );
    
    // Timestamp FIFO with AXI-Stream output
    timestamp_fifo #(
        .FIFO_DEPTH(2048),
        .DATA_WIDTH(64)
    ) ts_fifo (
        .clk(clk_200mhz),
        .rst_n(rst_200m_n & ~tt_soft_reset),

        // Input from TDC
        .ts_valid(ts_valid),
        .timestamp(timestamp),
        .channel_id(channel_id),

        // Control
        .clear_overflow(tt_clear_overflow),

        // AXI-Stream output
        .m_axis_tvalid(axis_tvalid),
        .m_axis_tready(axis_tready),
        .m_axis_tdata(axis_tdata),
        .m_axis_tlast(axis_tlast),

        // Status
        .fifo_count(fifo_count),
        .fifo_full(fifo_full),
        .fifo_empty(fifo_empty),
        .overflow_flag(overflow_flag)
    );
    
    // tkeep always all-valid for 64-bit data
    assign axis_tkeep = 8'hFF;
    
    // Event counter
    reg [31:0] evt_count_reg;
    always @(posedge clk_200mhz or negedge rst_200m_n) begin
        if (!rst_200m_n || tt_soft_reset)
            evt_count_reg <= 32'd0;
        else if (ts_valid)
            evt_count_reg <= evt_count_reg + 1;
    end
    assign event_count = evt_count_reg;

endmodule
