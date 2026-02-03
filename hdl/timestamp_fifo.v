// =============================================================================
// Timestamp FIFO with AXI-Stream Output
// =============================================================================
// Collects timestamps from TDC channels and outputs via AXI-Stream
// Packet format: 64-bit = {16'h0, channel[3:0], 4'h0, timestamp[39:0]}
// =============================================================================

`timescale 1ns / 1ps

module timestamp_fifo #(
    parameter integer FIFO_DEPTH = 2048,
    parameter integer DATA_WIDTH = 64
)(
    input  wire        clk,
    input  wire        rst_n,

    // Timestamp input interface
    input  wire        ts_valid,
    input  wire [39:0] timestamp,
    input  wire [3:0]  channel_id,

    // Control
    input  wire        clear_overflow,   // Clear sticky overflow flag

    // AXI-Stream Master output
    output wire        m_axis_tvalid,
    input  wire        m_axis_tready,
    output wire [DATA_WIDTH-1:0] m_axis_tdata,
    output wire        m_axis_tlast,

    // Status
    output wire [15:0] fifo_count,
    output wire        fifo_full,
    output wire        fifo_empty,
    output reg         overflow_flag
);

    localparam ADDR_WIDTH = $clog2(FIFO_DEPTH);

    // =========================================================================
    // FIFO Memory - Simple Dual Port RAM pattern for BRAM inference
    // =========================================================================
    
    (* ram_style = "block" *)
    reg [DATA_WIDTH-1:0] fifo_mem [0:FIFO_DEPTH-1];
    
    reg [ADDR_WIDTH-1:0] wr_addr;
    reg [ADDR_WIDTH-1:0] rd_addr;
    reg [ADDR_WIDTH:0]   count_reg;  // Extra bit for full detection
    
    assign fifo_count = {{(16-ADDR_WIDTH-1){1'b0}}, count_reg};
    assign fifo_empty = (count_reg == 0);
    assign fifo_full  = (count_reg == FIFO_DEPTH);

    // =========================================================================
    // Write Logic - Separate always block for BRAM write port
    // =========================================================================
    
    wire [DATA_WIDTH-1:0] ts_packet = {16'h0, channel_id, 4'h0, timestamp};
    wire wr_en = ts_valid && !fifo_full;
    
    // BRAM write port - synchronous, no reset on memory
    always @(posedge clk) begin
        if (wr_en) begin
            fifo_mem[wr_addr] <= ts_packet;
        end
    end
    
    // Write address pointer
    always @(posedge clk) begin
        if (!rst_n) begin
            wr_addr <= 0;
            overflow_flag <= 1'b0;
        end else begin
            // Clear overflow flag when requested
            if (clear_overflow) begin
                overflow_flag <= 1'b0;
            end else if (ts_valid && fifo_full) begin
                overflow_flag <= 1'b1;  // Sticky overflow flag
            end

            if (wr_en) begin
                wr_addr <= wr_addr + 1;
            end
        end
    end

    // =========================================================================
    // Read Logic - Separate always block for BRAM read port
    // =========================================================================
    
    reg [DATA_WIDTH-1:0] rd_data_reg;
    reg rd_valid;
    reg rd_pending;
    
    wire rd_en = !fifo_empty && (!rd_valid || m_axis_tready);
    
    // BRAM read port - synchronous read
    always @(posedge clk) begin
        if (rd_en) begin
            rd_data_reg <= fifo_mem[rd_addr];
        end
    end
    
    // Read address and valid logic
    always @(posedge clk) begin
        if (!rst_n) begin
            rd_addr <= 0;
            rd_valid <= 1'b0;
            rd_pending <= 1'b0;
        end else begin
            // Track pending read (1 cycle latency for BRAM)
            rd_pending <= rd_en;
            
            if (m_axis_tready && rd_valid) begin
                rd_valid <= 1'b0;
            end
            
            if (rd_pending) begin
                rd_valid <= 1'b1;
            end
            
            if (rd_en) begin
                rd_addr <= rd_addr + 1;
            end
        end
    end
    
    // =========================================================================
    // FIFO Count Logic
    // =========================================================================
    
    wire do_write = wr_en;
    wire do_read  = rd_en;
    
    always @(posedge clk) begin
        if (!rst_n) begin
            count_reg <= 0;
        end else begin
            case ({do_write, do_read})
                2'b10:   count_reg <= count_reg + 1;  // Write only
                2'b01:   count_reg <= count_reg - 1;  // Read only
                default: count_reg <= count_reg;       // Both or neither
            endcase
        end
    end
    
    assign m_axis_tvalid = rd_valid;
    assign m_axis_tdata  = rd_data_reg;
    assign m_axis_tlast  = 1'b1;  // Each timestamp is its own packet

endmodule
