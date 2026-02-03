// =============================================================================
// Integration Testbench for Time Tagger Top Level
// =============================================================================
// Tests the complete time tagger system without PS7
// Stubs the system_wrapper (block design) to provide clocks, resets, and
// simulate AXI-Stream DMA readout
// =============================================================================

`timescale 1ps / 1ps  // 1ps resolution for accurate TDC testing

module tb_top_level;

    // =========================================================================
    // Parameters
    // =========================================================================
    parameter CLK_200M_PERIOD = 5000;   // 5ns = 200MHz
    parameter CLK_100M_PERIOD = 10000;  // 10ns = 100MHz
    parameter SIMULATION_TIME = 500000000;  // 500us total simulation

    // =========================================================================
    // Clock and Reset Signals (normally from block design)
    // =========================================================================
    reg clk_200mhz;
    reg clk_100mhz;
    reg rst_200m_n;
    reg rst_100m_n;

    // =========================================================================
    // GPIO Interface (normally from PS7 GPIO)
    // =========================================================================
    reg  [31:0] gpio_ctrl;
    wire [31:0] gpio_status;

    // GPIO Control bit definitions
    localparam CTRL_ENABLE         = 0;
    localparam CTRL_SOFT_RESET     = 1;
    localparam CTRL_CLEAR_OVERFLOW = 2;

    // GPIO Status bit definitions
    localparam STAT_RUNNING        = 0;
    localparam STAT_OVERFLOW       = 1;
    localparam STAT_HAS_DATA       = 2;
    localparam STAT_FIFO_FULL      = 3;
    // [15:4] = FIFO count
    // [31:16] = Event count

    // =========================================================================
    // AXI-Stream Interface (normally to DMA)
    // =========================================================================
    wire        axis_tvalid;
    reg         axis_tready;
    wire [63:0] axis_tdata;
    wire        axis_tlast;
    wire [7:0]  axis_tkeep;

    // =========================================================================
    // TDC Input Signal
    // =========================================================================
    reg tdc_hit_0;

    // =========================================================================
    // Test Monitoring Variables
    // =========================================================================
    integer pulse_count;
    integer captured_count;
    integer dma_read_count;
    reg [63:0] captured_timestamps [0:1023];  // Store captured data
    reg [63:0] pulse_times_ps [0:1023];       // Store actual pulse times

    real total_error_ps;
    real max_error_ps;
    real min_error_ps;

    // =========================================================================
    // Clock Generation
    // =========================================================================
    initial clk_200mhz = 0;
    always #(CLK_200M_PERIOD/2) clk_200mhz = ~clk_200mhz;

    initial clk_100mhz = 0;
    always #(CLK_100M_PERIOD/2) clk_100mhz = ~clk_100mhz;

    // =========================================================================
    // DUT: Time Tagger Core (without PS7 wrapper)
    // =========================================================================
    // We instantiate the internal modules directly since we can't simulate PS7

    wire        tt_enable         = gpio_ctrl[CTRL_ENABLE];
    wire        tt_soft_reset     = gpio_ctrl[CTRL_SOFT_RESET];
    wire        tt_clear_overflow = gpio_ctrl[CTRL_CLEAR_OVERFLOW];

    wire        ts_valid;
    wire [39:0] timestamp;
    wire [3:0]  channel_id;
    wire        overflow_flag;
    wire [15:0] fifo_count;
    wire        fifo_empty;
    wire        fifo_full;

    // TDC Channel Instance
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

    // Timestamp FIFO Instance
    timestamp_fifo #(
        .FIFO_DEPTH(2048),
        .DATA_WIDTH(64)
    ) ts_fifo (
        .clk(clk_200mhz),
        .rst_n(rst_200m_n & ~tt_soft_reset),
        .ts_valid(ts_valid),
        .timestamp(timestamp),
        .channel_id(channel_id),
        .clear_overflow(tt_clear_overflow),
        .m_axis_tvalid(axis_tvalid),
        .m_axis_tready(axis_tready),
        .m_axis_tdata(axis_tdata),
        .m_axis_tlast(axis_tlast),
        .fifo_count(fifo_count),
        .fifo_full(fifo_full),
        .fifo_empty(fifo_empty),
        .overflow_flag(overflow_flag)
    );

    // Event counter
    reg [31:0] event_count;
    always @(posedge clk_200mhz or negedge rst_200m_n) begin
        if (!rst_200m_n || tt_soft_reset)
            event_count <= 32'd0;
        else if (ts_valid)
            event_count <= event_count + 1;
    end

    // Construct status register (matching top_level.v)
    assign gpio_status = {
        event_count[15:0],
        fifo_count[11:0],
        fifo_full,
        ~fifo_empty,
        overflow_flag,
        tt_enable
    };

    // =========================================================================
    // AXI-Stream Monitor (Simulates DMA)
    // =========================================================================
    always @(posedge clk_200mhz) begin
        if (axis_tvalid && axis_tready) begin
            if (dma_read_count < 1024) begin
                captured_timestamps[dma_read_count] <= axis_tdata;
            end
            dma_read_count <= dma_read_count + 1;

            // Decode and display
            $display("[%0t] DMA Read #%0d: ch=%0d, coarse=%0d, fine=%0d, raw=0x%016h",
                     $time,
                     dma_read_count,
                     axis_tdata[47:44],           // channel_id
                     axis_tdata[39:8],            // coarse
                     axis_tdata[7:0],             // fine
                     axis_tdata);
        end
    end

    // =========================================================================
    // Pulse Generation Tasks
    // =========================================================================

    // Generate single pulse with precise timing
    task send_pulse;
        input integer delay_from_clk_ps;  // Delay from next clock edge
        input integer pulse_width_ps;
        begin
            @(posedge clk_200mhz);
            #(delay_from_clk_ps);

            if (pulse_count < 1024) begin
                pulse_times_ps[pulse_count] = $time;
            end

            tdc_hit_0 = 1;
            #(pulse_width_ps);
            tdc_hit_0 = 0;

            pulse_count = pulse_count + 1;
        end
    endtask

    // Generate random pulse train (simulates real photon detection)
    task random_pulse_train;
        input integer num_pulses;
        input integer min_gap_ns;
        input integer max_gap_ns;
        integer i, gap_ns, phase_ps;
        begin
            $display("\n[%0t] Starting random pulse train: %0d pulses, gap=%0d-%0dns",
                     $time, num_pulses, min_gap_ns, max_gap_ns);

            for (i = 0; i < num_pulses; i = i + 1) begin
                // Random gap between pulses
                gap_ns = min_gap_ns + ($urandom % (max_gap_ns - min_gap_ns + 1));
                // Random phase within clock period (0 to 5000ps)
                phase_ps = $urandom % CLK_200M_PERIOD;

                #(gap_ns * 1000);  // Wait gap (convert ns to ps)
                send_pulse(phase_ps, 6000);  // 6000ps pulse width (spans clock edge)
            end
        end
    endtask

    // Generate burst of pulses (tests high rate handling)
    task pulse_burst;
        input integer num_pulses;
        input integer spacing_ns;
        integer i;
        begin
            $display("\n[%0t] Starting pulse burst: %0d pulses @ %0dns spacing",
                     $time, num_pulses, spacing_ns);

            for (i = 0; i < num_pulses; i = i + 1) begin
                send_pulse(1000, 6000);  // Fixed 1ns phase, 6000ps width (spans clock edge)
                #(spacing_ns * 1000 - 7000);  // Subtract pulse overhead
            end
        end
    endtask

    // Generate pulses at specific phases for resolution testing
    task phase_sweep;
        input integer num_steps;
        input integer step_ps;
        integer i, phase;
        begin
            $display("\n[%0t] Starting phase sweep: %0d steps @ %0dps/step",
                     $time, num_steps, step_ps);

            for (i = 0; i < num_steps; i = i + 1) begin
                phase = i * step_ps;
                send_pulse(phase, 6000);  // 6000ps width (spans clock edge)
                #(100 * 1000);  // 100ns between pulses
            end
        end
    endtask

    // =========================================================================
    // DMA Simulation Tasks
    // =========================================================================

    // Simulate periodic DMA readout
    task dma_readout;
        input integer duration_ns;
        begin
            axis_tready = 1;
            #(duration_ns * 1000);
            axis_tready = 0;
        end
    endtask

    // Simulate bursty DMA (more realistic)
    task dma_bursty_readout;
        input integer num_bursts;
        input integer burst_len_ns;
        input integer gap_ns;
        integer i;
        begin
            for (i = 0; i < num_bursts; i = i + 1) begin
                axis_tready = 1;
                #(burst_len_ns * 1000);
                axis_tready = 0;
                #(gap_ns * 1000);
            end
        end
    endtask

    // =========================================================================
    // Status Monitoring
    // =========================================================================
    task print_status;
        begin
            $display("[%0t] STATUS: enable=%b overflow=%b has_data=%b full=%b fifo_cnt=%0d evt_cnt=%0d",
                     $time,
                     gpio_status[STAT_RUNNING],
                     gpio_status[STAT_OVERFLOW],
                     gpio_status[STAT_HAS_DATA],
                     gpio_status[STAT_FIFO_FULL],
                     gpio_status[15:4],
                     gpio_status[31:16]);
        end
    endtask

    // =========================================================================
    // Main Test Sequence
    // =========================================================================
    initial begin
        // Initialize all signals
        rst_200m_n = 0;
        rst_100m_n = 0;
        gpio_ctrl = 32'h0;
        axis_tready = 0;
        tdc_hit_0 = 0;
        pulse_count = 0;
        captured_count = 0;
        dma_read_count = 0;
        total_error_ps = 0;
        max_error_ps = 0;
        min_error_ps = 1e12;

        $display("============================================================");
        $display("   Time Tagger Integration Testbench");
        $display("============================================================");
        $display("Clock: 200MHz (%0d ps period)", CLK_200M_PERIOD);
        $display("TDC Resolution: ~25ps/tap, 160 taps");
        $display("============================================================\n");

        // =====================================================================
        // Reset Sequence
        // =====================================================================
        $display("[%0t] Applying reset...", $time);
        #(CLK_200M_PERIOD * 20);
        rst_200m_n = 1;
        rst_100m_n = 1;
        #(CLK_200M_PERIOD * 10);
        $display("[%0t] Reset released\n", $time);

        // =====================================================================
        // Test 1: Basic Enable/Disable
        // =====================================================================
        $display("============================================================");
        $display("TEST 1: Basic Enable/Disable");
        $display("============================================================");

        // Send pulse while disabled (should NOT be captured)
        send_pulse(1000, 6000);
        #(CLK_200M_PERIOD * 20);
        print_status();

        if (gpio_status[31:16] != 0) begin
            $display("FAIL: Event counted while disabled!");
        end else begin
            $display("PASS: No event captured while disabled");
        end

        // Enable time tagger
        gpio_ctrl[CTRL_ENABLE] = 1;
        #(CLK_200M_PERIOD * 5);
        $display("\n[%0t] Time tagger ENABLED", $time);

        // Send pulse while enabled
        send_pulse(1000, 6000);
        #(CLK_200M_PERIOD * 20);
        print_status();

        // Read out the timestamp
        dma_readout(100);
        #(CLK_200M_PERIOD * 10);

        // =====================================================================
        // Test 2: Phase Resolution Test
        // =====================================================================
        $display("\n============================================================");
        $display("TEST 2: Phase Resolution Sweep");
        $display("============================================================");

        phase_sweep(20, 250);  // 20 steps, 250ps each = 5ns total
        #(CLK_200M_PERIOD * 50);

        // Read all timestamps
        dma_readout(500);
        print_status();

        // =====================================================================
        // Test 3: Random Pulse Train (Real-world simulation)
        // =====================================================================
        $display("\n============================================================");
        $display("TEST 3: Random Pulse Train (Real-world simulation)");
        $display("============================================================");

        // Start DMA in parallel with pulse generation
        fork
            random_pulse_train(50, 100, 1000);  // 50 pulses, 100-1000ns gaps
            begin
                #(10000 * 1000);  // Wait 10us
                dma_bursty_readout(10, 500, 100);  // 10 bursts, 500ns on, 100ns off
            end
        join

        #(CLK_200M_PERIOD * 100);
        print_status();

        // =====================================================================
        // Test 4: High Rate Burst (Stress Test)
        // =====================================================================
        $display("\n============================================================");
        $display("TEST 4: High Rate Burst (Stress Test)");
        $display("============================================================");

        pulse_burst(100, 50);  // 100 pulses @ 50ns = 20 MHz rate
        #(CLK_200M_PERIOD * 100);
        print_status();

        // Drain FIFO
        axis_tready = 1;
        wait(fifo_empty || $time > SIMULATION_TIME);
        axis_tready = 0;
        #(CLK_200M_PERIOD * 20);

        // =====================================================================
        // Test 5: FIFO Overflow Test
        // =====================================================================
        $display("\n============================================================");
        $display("TEST 5: FIFO Overflow Test");
        $display("============================================================");

        // Disable DMA and send many pulses
        axis_tready = 0;
        pulse_burst(2100, 30);  // More than FIFO depth (2048)

        #(CLK_200M_PERIOD * 50);
        print_status();

        if (gpio_status[STAT_OVERFLOW]) begin
            $display("PASS: Overflow flag correctly set");
        end else begin
            $display("FAIL: Overflow flag not set after overflow!");
        end

        // Drain FIFO
        axis_tready = 1;
        wait(fifo_empty);
        axis_tready = 0;
        #(CLK_200M_PERIOD * 20);

        // Clear overflow
        gpio_ctrl[CTRL_CLEAR_OVERFLOW] = 1;
        #(CLK_200M_PERIOD * 2);
        gpio_ctrl[CTRL_CLEAR_OVERFLOW] = 0;
        #(CLK_200M_PERIOD * 5);

        if (!gpio_status[STAT_OVERFLOW]) begin
            $display("PASS: Overflow flag correctly cleared");
        end else begin
            $display("FAIL: Overflow flag not cleared!");
        end

        // =====================================================================
        // Test 6: Soft Reset Test
        // =====================================================================
        $display("\n============================================================");
        $display("TEST 6: Soft Reset Test");
        $display("============================================================");

        // Send some pulses
        pulse_burst(10, 100);
        #(CLK_200M_PERIOD * 50);
        $display("Before reset:");
        print_status();

        // Apply soft reset
        gpio_ctrl[CTRL_SOFT_RESET] = 1;
        #(CLK_200M_PERIOD * 5);
        gpio_ctrl[CTRL_SOFT_RESET] = 0;
        #(CLK_200M_PERIOD * 10);

        $display("After reset:");
        print_status();

        // =====================================================================
        // Test Summary
        // =====================================================================
        $display("\n============================================================");
        $display("   TEST SUMMARY");
        $display("============================================================");
        $display("Total pulses sent:     %0d", pulse_count);
        $display("Total DMA reads:       %0d", dma_read_count);
        $display("Final event count:     %0d", gpio_status[31:16]);
        $display("============================================================\n");

        #(CLK_200M_PERIOD * 100);
        $finish;
    end

    // =========================================================================
    // Timeout Watchdog
    // =========================================================================
    initial begin
        #SIMULATION_TIME;
        $display("\nWARNING: Simulation timeout reached!");
        $finish;
    end

    // =========================================================================
    // Waveform Dump (for viewing in waveform viewer)
    // =========================================================================
    initial begin
        $dumpfile("tb_top_level.vcd");
        $dumpvars(0, tb_top_level);
    end

endmodule
