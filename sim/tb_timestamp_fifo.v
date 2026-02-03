// =============================================================================
// Testbench for Timestamp FIFO
// =============================================================================
// Tests: FIFO operations, overflow handling, AXI-Stream protocol
// =============================================================================

`timescale 1ns / 1ps

module tb_timestamp_fifo;

    // =========================================================================
    // Parameters
    // =========================================================================
    parameter CLK_PERIOD = 5;     // 5ns = 200MHz
    parameter FIFO_DEPTH = 64;    // Smaller depth for faster simulation
    parameter DATA_WIDTH = 64;

    // =========================================================================
    // Signals
    // =========================================================================
    reg         clk;
    reg         rst_n;

    // Write interface
    reg         ts_valid;
    reg  [39:0] timestamp;
    reg  [3:0]  channel_id;
    reg         clear_overflow;

    // AXI-Stream read interface
    wire        m_axis_tvalid;
    reg         m_axis_tready;
    wire [63:0] m_axis_tdata;
    wire        m_axis_tlast;

    // Status
    wire [15:0] fifo_count;
    wire        fifo_full;
    wire        fifo_empty;
    wire        overflow_flag;

    // Test monitoring
    integer write_count;
    integer read_count;
    integer error_count;

    // Expected data for verification
    reg [63:0] expected_data [0:FIFO_DEPTH-1];
    integer expected_idx;

    // =========================================================================
    // Clock Generation
    // =========================================================================
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // =========================================================================
    // DUT
    // =========================================================================
    timestamp_fifo #(
        .FIFO_DEPTH(FIFO_DEPTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .ts_valid(ts_valid),
        .timestamp(timestamp),
        .channel_id(channel_id),
        .clear_overflow(clear_overflow),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready),
        .m_axis_tdata(m_axis_tdata),
        .m_axis_tlast(m_axis_tlast),
        .fifo_count(fifo_count),
        .fifo_full(fifo_full),
        .fifo_empty(fifo_empty),
        .overflow_flag(overflow_flag)
    );

    // =========================================================================
    // Write Task
    // =========================================================================
    task write_timestamp;
        input [39:0] ts;
        input [3:0]  ch;
        begin
            @(posedge clk);
            ts_valid <= 1;
            timestamp <= ts;
            channel_id <= ch;

            // Store expected output (packet format)
            if (!fifo_full && write_count < FIFO_DEPTH) begin
                expected_data[write_count % FIFO_DEPTH] = {16'h0, ch, 4'h0, ts};
            end

            @(posedge clk);
            ts_valid <= 0;
            write_count = write_count + 1;
            $display("[%0t] Write #%0d: ts=0x%010h, ch=%0d, count=%0d",
                     $time, write_count, ts, ch, fifo_count);
        end
    endtask

    // Burst write
    task burst_write;
        input integer num_writes;
        integer i;
        begin
            for (i = 0; i < num_writes; i = i + 1) begin
                write_timestamp({32'd1000 + i, 8'd0}, i % 16);
            end
        end
    endtask

    // =========================================================================
    // Read Monitoring
    // =========================================================================
    always @(posedge clk) begin
        if (m_axis_tvalid && m_axis_tready) begin
            $display("[%0t] Read  #%0d: data=0x%016h, ch=%0d, coarse=%0d, fine=%0d",
                     $time, read_count,
                     m_axis_tdata,
                     m_axis_tdata[47:44],
                     m_axis_tdata[39:8],
                     m_axis_tdata[7:0]);

            // Verify tlast is always 1 (each timestamp is its own packet)
            if (!m_axis_tlast) begin
                $display("  ERROR: tlast should be 1!");
                error_count = error_count + 1;
            end

            read_count = read_count + 1;
        end
    end

    // =========================================================================
    // Utility Tasks
    // =========================================================================

    task print_status;
        begin
            $display("[%0t] Status: count=%0d, empty=%b, full=%b, overflow=%b",
                     $time, fifo_count, fifo_empty, fifo_full, overflow_flag);
        end
    endtask

    task drain_fifo;
        begin
            m_axis_tready = 1;
            wait(fifo_empty);
            #(CLK_PERIOD * 5);
            m_axis_tready = 0;
        end
    endtask

    // =========================================================================
    // Main Test Sequence
    // =========================================================================
    initial begin
        // Initialize
        rst_n = 0;
        ts_valid = 0;
        timestamp = 0;
        channel_id = 0;
        clear_overflow = 0;
        m_axis_tready = 0;
        write_count = 0;
        read_count = 0;
        error_count = 0;
        expected_idx = 0;

        $display("============================================================");
        $display("   Timestamp FIFO Testbench");
        $display("============================================================");
        $display("FIFO Depth: %0d", FIFO_DEPTH);
        $display("Data Width: %0d bits", DATA_WIDTH);
        $display("============================================================\n");

        #(CLK_PERIOD * 10);
        rst_n = 1;
        #(CLK_PERIOD * 5);

        // -----------------------------------------------------------------
        // Test 1: Basic Write/Read
        // -----------------------------------------------------------------
        $display("\n=== Test 1: Basic Write/Read ===");

        // Write a few entries
        write_timestamp(40'h12345678AB, 4'd3);
        write_timestamp(40'hDEADBEEF00, 4'd7);
        write_timestamp(40'h0000000001, 4'd0);
        #(CLK_PERIOD * 5);

        print_status();

        if (fifo_count != 3) begin
            $display("FAIL: Expected count=3, got %0d", fifo_count);
            error_count = error_count + 1;
        end

        // Read them back
        m_axis_tready = 1;
        #(CLK_PERIOD * 10);
        m_axis_tready = 0;

        print_status();

        if (!fifo_empty) begin
            $display("FAIL: FIFO should be empty");
            error_count = error_count + 1;
        end else begin
            $display("PASS: Basic write/read");
        end

        // -----------------------------------------------------------------
        // Test 2: Fill to Full
        // -----------------------------------------------------------------
        $display("\n=== Test 2: Fill FIFO to Full ===");

        burst_write(FIFO_DEPTH);
        #(CLK_PERIOD * 5);

        print_status();

        if (!fifo_full) begin
            $display("FAIL: FIFO should be full");
            error_count = error_count + 1;
        end else begin
            $display("PASS: FIFO full after %0d writes", FIFO_DEPTH);
        end

        drain_fifo();

        // -----------------------------------------------------------------
        // Test 3: Overflow Detection
        // -----------------------------------------------------------------
        $display("\n=== Test 3: Overflow Detection ===");

        // Write more than FIFO can hold
        burst_write(FIFO_DEPTH + 10);
        #(CLK_PERIOD * 5);

        print_status();

        if (!overflow_flag) begin
            $display("FAIL: Overflow flag should be set");
            error_count = error_count + 1;
        end else begin
            $display("PASS: Overflow flag correctly set");
        end

        // Drain and check count
        drain_fifo();
        $display("Reads after overflow: %0d (expected: %0d)", read_count, FIFO_DEPTH * 2 + 3);

        // Clear overflow flag
        clear_overflow = 1;
        #(CLK_PERIOD * 2);
        clear_overflow = 0;
        #(CLK_PERIOD * 2);

        if (overflow_flag) begin
            $display("FAIL: Overflow flag should be cleared");
            error_count = error_count + 1;
        end else begin
            $display("PASS: Overflow flag cleared");
        end

        // -----------------------------------------------------------------
        // Test 4: Concurrent Read/Write
        // -----------------------------------------------------------------
        $display("\n=== Test 4: Concurrent Read/Write ===");

        read_count = 0;
        write_count = 0;

        fork
            // Writer thread
            begin
                repeat(30) begin
                    write_timestamp($urandom, $urandom % 16);
                    #(CLK_PERIOD * 2);
                end
            end

            // Reader thread (slower than writer initially, then catches up)
            begin
                #(CLK_PERIOD * 20);  // Let FIFO fill a bit
                m_axis_tready = 1;
                #(CLK_PERIOD * 100);
                m_axis_tready = 0;
            end
        join

        #(CLK_PERIOD * 10);
        print_status();

        drain_fifo();
        $display("Writes: %0d, Reads: %0d", write_count, read_count);

        // -----------------------------------------------------------------
        // Test 5: AXI-Stream Backpressure
        // -----------------------------------------------------------------
        $display("\n=== Test 5: AXI-Stream Backpressure ===");

        write_count = 0;
        read_count = 0;

        // Write some data
        burst_write(10);
        #(CLK_PERIOD * 5);

        // Toggle tready to simulate backpressure
        repeat(20) begin
            m_axis_tready = 1;
            #(CLK_PERIOD * 2);
            m_axis_tready = 0;
            #(CLK_PERIOD * 3);
        end

        drain_fifo();

        if (read_count == 10) begin
            $display("PASS: All data read despite backpressure");
        end else begin
            $display("FAIL: Expected 10 reads, got %0d", read_count);
            error_count = error_count + 1;
        end

        // -----------------------------------------------------------------
        // Test 6: Reset During Operation
        // -----------------------------------------------------------------
        $display("\n=== Test 6: Reset During Operation ===");

        burst_write(20);
        #(CLK_PERIOD * 5);
        print_status();

        // Apply reset
        rst_n = 0;
        #(CLK_PERIOD * 5);
        rst_n = 1;
        #(CLK_PERIOD * 5);

        print_status();

        if (!fifo_empty || fifo_count != 0) begin
            $display("FAIL: FIFO should be empty after reset");
            error_count = error_count + 1;
        end else begin
            $display("PASS: FIFO correctly reset");
        end

        // -----------------------------------------------------------------
        // Summary
        // -----------------------------------------------------------------
        $display("\n============================================================");
        $display("   Test Summary");
        $display("============================================================");
        if (error_count == 0) begin
            $display("All tests PASSED");
        end else begin
            $display("FAILED: %0d errors detected", error_count);
        end
        $display("============================================================\n");

        #(CLK_PERIOD * 10);
        $finish;
    end

    // Timeout watchdog
    initial begin
        #1000000;  // 1ms timeout
        $display("ERROR: Simulation timeout!");
        $finish;
    end

    // Waveform dump
    initial begin
        $dumpfile("tb_timestamp_fifo.vcd");
        $dumpvars(0, tb_timestamp_fifo);
    end

endmodule
