// =============================================================================
// Testbench for TDC Channel
// =============================================================================
// Tests: Edge detection, timestamp capture, pipeline timing, random pulse input
// Note: CARRY4 primitives won't simulate accurate timing in behavioral sim
//       This tests the logic/FSM behavior, not actual delay line performance
// =============================================================================

`timescale 1ps / 1ps  // 1ps resolution for sub-ns testing

module tb_tdc_channel;

    // =========================================================================
    // Parameters
    // =========================================================================
    parameter CLK_PERIOD = 5000;  // 5ns = 200MHz
    parameter NTAPS = 160;

    // Random signal generator parameters
    parameter RANDOM_TEST_DURATION = 100000000;  // 100us in ps
    parameter MIN_PULSE_GAP_PS = 50000;          // 50ns minimum gap
    parameter MAX_PULSE_GAP_PS = 500000;         // 500ns maximum gap
    parameter PULSE_WIDTH_PS = 1000;             // 1ns pulse width

    // =========================================================================
    // Signals
    // =========================================================================
    reg         clk;
    reg         rst_n;
    reg         enable;
    reg         hit;

    // Random signal generator
    reg         random_hit_enable;
    reg         random_hit_signal;
    integer     random_seed;

    wire        ts_valid;
    wire [39:0] timestamp;
    wire [3:0]  channel_id;

    // Test monitoring
    integer     pulse_count;
    integer     valid_count;
    reg [39:0]  last_timestamp;
    reg [39:0]  prev_timestamp;
    reg [63:0]  hit_time_ps;

    // Statistics
    real        total_interval_ps;
    real        min_interval_ps;
    real        max_interval_ps;
    reg [63:0]  last_pulse_time_ps;

    // =========================================================================
    // Clock Generation (200 MHz)
    // =========================================================================
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // =========================================================================
    // Random Rising Edge Generator (Simulates Real-Time Input)
    // =========================================================================
    // Generates random pulses with:
    //   - Random intervals (Poisson-like distribution)
    //   - Random phase within clock cycle (uniform)
    //   - Optional jitter simulation
    // =========================================================================

    // Combine manual hits with random generator
    wire hit_combined = hit | random_hit_signal;

    // Random pulse generator process
    initial begin
        random_hit_signal = 0;
        random_hit_enable = 0;
        random_seed = 12345;  // Seed for reproducibility
        last_pulse_time_ps = 0;
        total_interval_ps = 0;
        min_interval_ps = 1e12;
        max_interval_ps = 0;
    end

    // Random signal generation task (runs in background)
    task automatic random_signal_generator;
        input integer duration_ps;
        input integer min_gap_ps;
        input integer max_gap_ps;
        input integer pulse_width_ps;

        integer gap_ps;
        integer phase_ps;
        integer elapsed_ps;
        integer pulse_num;
        real interval_ps;
        begin
            elapsed_ps = 0;
            pulse_num = 0;
            $display("\n[%0t] === Random Signal Generator Started ===", $time);
            $display("       Duration: %0d us", duration_ps / 1000000);
            $display("       Gap range: %0d - %0d ns", min_gap_ps/1000, max_gap_ps/1000);

            while (elapsed_ps < duration_ps && random_hit_enable) begin
                // Generate random gap (exponential-ish distribution for realism)
                gap_ps = min_gap_ps + ($urandom(random_seed) % (max_gap_ps - min_gap_ps));

                // Add some jitter variation (±10% of gap)
                gap_ps = gap_ps + ($urandom(random_seed) % (gap_ps/5)) - (gap_ps/10);
                if (gap_ps < min_gap_ps) gap_ps = min_gap_ps;

                // Random phase within clock period
                phase_ps = $urandom(random_seed) % CLK_PERIOD;

                // Wait for the gap
                #(gap_ps);
                elapsed_ps = elapsed_ps + gap_ps;

                // Track statistics
                if (last_pulse_time_ps > 0) begin
                    interval_ps = $time - last_pulse_time_ps;
                    total_interval_ps = total_interval_ps + interval_ps;
                    if (interval_ps < min_interval_ps) min_interval_ps = interval_ps;
                    if (interval_ps > max_interval_ps) max_interval_ps = interval_ps;
                end
                last_pulse_time_ps = $time;

                // Generate pulse
                random_hit_signal = 1;
                pulse_num = pulse_num + 1;

                if (pulse_num % 50 == 0) begin
                    $display("[%0t] Random pulse #%0d (phase=%0dps)", $time, pulse_num, phase_ps);
                end

                #(pulse_width_ps);
                random_hit_signal = 0;
            end

            $display("[%0t] === Random Signal Generator Stopped ===", $time);
            $display("       Total pulses: %0d", pulse_num);
            if (pulse_num > 1) begin
                $display("       Avg interval: %0.1f ns", total_interval_ps / (pulse_num-1) / 1000.0);
                $display("       Min interval: %0.1f ns", min_interval_ps / 1000.0);
                $display("       Max interval: %0.1f ns", max_interval_ps / 1000.0);
            end
        end
    endtask

    // Poisson-distributed random generator (more realistic for photon detection)
    task automatic poisson_signal_generator;
        input integer duration_ps;
        input real avg_rate_mhz;  // Average event rate in MHz

        real lambda;              // Events per ps
        real u;
        integer gap_ps;
        integer elapsed_ps;
        integer pulse_num;
        begin
            lambda = avg_rate_mhz / 1e6;  // Convert MHz to events per ps
            elapsed_ps = 0;
            pulse_num = 0;

            $display("\n[%0t] === Poisson Signal Generator Started ===", $time);
            $display("       Duration: %0d us", duration_ps / 1000000);
            $display("       Average rate: %0.2f MHz", avg_rate_mhz);

            while (elapsed_ps < duration_ps && random_hit_enable) begin
                // Generate exponentially distributed interval (Poisson process)
                u = $urandom(random_seed) / 4294967295.0;  // Uniform [0,1)
                if (u < 1e-10) u = 1e-10;  // Avoid log(0)
                gap_ps = -$ln(u) / lambda;

                // Clamp to reasonable range
                if (gap_ps < 10000) gap_ps = 10000;      // Min 10ns
                if (gap_ps > 10000000) gap_ps = 10000000; // Max 10us

                #(gap_ps);
                elapsed_ps = elapsed_ps + gap_ps;

                // Generate pulse
                random_hit_signal = 1;
                pulse_num = pulse_num + 1;

                if (pulse_num % 100 == 0) begin
                    $display("[%0t] Poisson pulse #%0d", $time, pulse_num);
                end

                #(PULSE_WIDTH_PS);
                random_hit_signal = 0;
            end

            $display("[%0t] === Poisson Generator Stopped: %0d pulses ===", $time, pulse_num);
        end
    endtask

    // =========================================================================
    // DUT Instantiation
    // =========================================================================
    tdc_channel #(
        .NTAPS(NTAPS),
        .CHANNEL_ID(5)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .enable(enable),
        .hit(hit_combined),  // Use combined signal (manual + random)
        .ts_valid(ts_valid),
        .timestamp(timestamp),
        .channel_id(channel_id)
    );

    // =========================================================================
    // Timestamp Capture and Analysis
    // =========================================================================
    always @(posedge clk) begin
        if (ts_valid) begin
            valid_count <= valid_count + 1;
            prev_timestamp <= last_timestamp;
            last_timestamp <= timestamp;
            $display("[%0t] Timestamp #%0d: coarse=%0d (0x%08h), fine=%0d, channel=%0d",
                     $time, valid_count,
                     timestamp[39:8], timestamp[39:8],
                     timestamp[7:0],
                     channel_id);

            // Check channel ID
            if (channel_id != 5) begin
                $display("  ERROR: Expected channel_id=5, got %0d", channel_id);
            end

            // Check timestamp is increasing
            if (valid_count > 0 && timestamp[39:8] < prev_timestamp[39:8]) begin
                $display("  WARNING: Coarse timestamp not monotonic!");
            end
        end
    end

    // =========================================================================
    // Test Tasks
    // =========================================================================

    // Generate a single pulse with specified delay from clock edge
    task single_pulse;
        input integer delay_ps;  // Delay from next rising clock edge
        input integer width_ps;  // Pulse width
        begin
            @(posedge clk);
            #(delay_ps);
            hit_time_ps = $time;
            hit = 1;
            #(width_ps);
            hit = 0;
            pulse_count = pulse_count + 1;
            $display("[%0t] Pulse #%0d sent (delay=%0dps from clk edge)",
                     hit_time_ps, pulse_count, delay_ps);
        end
    endtask

    // Generate random pulses to simulate real-time signal
    task random_pulses;
        input integer num_pulses;
        input integer min_interval_ns;
        input integer max_interval_ns;
        integer i, interval, phase;
        begin
            $display("\n--- Random Pulse Generation: %0d pulses ---", num_pulses);
            for (i = 0; i < num_pulses; i = i + 1) begin
                interval = min_interval_ns + ($urandom % (max_interval_ns - min_interval_ns + 1));
                phase = $urandom % CLK_PERIOD;

                #(interval * 1000);
                single_pulse(phase, 500);
            end
        end
    endtask

    // Test fine time resolution by sweeping phase
    task test_fine_resolution;
        integer i;
        begin
            $display("\n--- Fine Resolution Sweep ---");
            for (i = 0; i < 10; i = i + 1) begin
                single_pulse(i * 500, 500);  // 500ps steps
                #(50 * 1000);  // 50ns between pulses
            end
        end
    endtask

    // =========================================================================
    // Main Test Sequence
    // =========================================================================
    initial begin
        // Initialize
        rst_n = 0;
        enable = 0;
        hit = 0;
        pulse_count = 0;
        valid_count = 0;
        last_timestamp = 0;
        prev_timestamp = 0;

        $display("============================================================");
        $display("   TDC Channel Testbench");
        $display("============================================================");
        $display("Clock period: %0d ps (%0d MHz)", CLK_PERIOD, 1000000/CLK_PERIOD);
        $display("Number of taps: %0d", NTAPS);
        $display("============================================================\n");

        // Reset sequence
        #(CLK_PERIOD * 10);
        rst_n = 1;
        #(CLK_PERIOD * 5);

        // -----------------------------------------------------------------
        // Test 1: Pulse while disabled
        // -----------------------------------------------------------------
        $display("\n=== Test 1: Pulse While Disabled ===");
        single_pulse(1000, 500);
        #(CLK_PERIOD * 10);

        if (valid_count > 0) begin
            $display("FAIL: Captured timestamp while disabled!");
        end else begin
            $display("PASS: No capture while disabled");
        end

        // -----------------------------------------------------------------
        // Test 2: Enable and basic capture
        // -----------------------------------------------------------------
        $display("\n=== Test 2: Enable and Basic Capture ===");
        enable = 1;
        #(CLK_PERIOD * 10);

        single_pulse(1000, 500);
        #(CLK_PERIOD * 10);  // Wait for pipeline (4 cycles + margin)

        if (valid_count >= 1) begin
            $display("PASS: Timestamp captured after enable");
        end else begin
            $display("FAIL: No timestamp captured!");
        end

        // -----------------------------------------------------------------
        // Test 3: Fine resolution sweep
        // -----------------------------------------------------------------
        $display("\n=== Test 3: Fine Resolution Sweep ===");
        test_fine_resolution();
        #(CLK_PERIOD * 20);

        // -----------------------------------------------------------------
        // Test 4: Random pulse train
        // -----------------------------------------------------------------
        $display("\n=== Test 4: Random Pulse Train ===");
        random_pulses(20, 100, 500);
        #(CLK_PERIOD * 50);

        // -----------------------------------------------------------------
        // Test 5: Rapid consecutive pulses
        // -----------------------------------------------------------------
        $display("\n=== Test 5: Rapid Consecutive Pulses ===");
        // Note: Back-to-back pulses closer than pipeline depth may be missed
        repeat(5) begin
            single_pulse(1000, 500);
            #(CLK_PERIOD * 6);  // Just beyond pipeline latency
        end
        #(CLK_PERIOD * 20);

        // -----------------------------------------------------------------
        // Test 6: Reset during operation
        // -----------------------------------------------------------------
        $display("\n=== Test 6: Reset During Operation ===");
        single_pulse(1000, 500);
        #(CLK_PERIOD * 2);

        rst_n = 0;
        #(CLK_PERIOD * 5);
        rst_n = 1;
        #(CLK_PERIOD * 10);

        single_pulse(1000, 500);
        #(CLK_PERIOD * 10);

        // -----------------------------------------------------------------
        // Test 7: Random Rising Edge Generator (Real-Time Simulation)
        // -----------------------------------------------------------------
        $display("\n=== Test 7: Random Rising Edge Generator ===");
        $display("Simulating random input pulses on tdc_hit...");

        // Reset counters for this test
        valid_count = 0;

        // Enable random generator
        random_hit_enable = 1;

        // Run random signal generator for 50us
        // Parameters: duration, min_gap, max_gap, pulse_width (all in ps)
        random_signal_generator(
            50000000,    // 50us duration
            30000,       // 30ns minimum gap
            200000,      // 200ns maximum gap
            1000         // 1ns pulse width
        );

        random_hit_enable = 0;
        #(CLK_PERIOD * 50);

        $display("Captured %0d timestamps from random generator", valid_count);

        // -----------------------------------------------------------------
        // Test 8: Poisson-Distributed Events (Photon Detection Simulation)
        // -----------------------------------------------------------------
        $display("\n=== Test 8: Poisson-Distributed Events ===");
        $display("Simulating photon-like random arrivals...");

        valid_count = 0;
        random_hit_enable = 1;

        // Run Poisson generator: 5MHz average rate for 20us
        poisson_signal_generator(
            20000000,    // 20us duration
            5.0          // 5 MHz average rate
        );

        random_hit_enable = 0;
        #(CLK_PERIOD * 50);

        $display("Captured %0d timestamps from Poisson generator", valid_count);

        // -----------------------------------------------------------------
        // Test 9: Burst with Random Timing (Stress Test)
        // -----------------------------------------------------------------
        $display("\n=== Test 9: High-Rate Random Burst ===");

        valid_count = 0;
        random_hit_enable = 1;

        // High rate burst: 10us, 10-30ns gaps (~50MHz peak rate)
        random_signal_generator(
            10000000,    // 10us duration
            10000,       // 10ns minimum gap
            30000,       // 30ns maximum gap
            500          // 0.5ns pulse width
        );

        random_hit_enable = 0;
        #(CLK_PERIOD * 100);

        $display("Captured %0d timestamps from high-rate burst", valid_count);

        // -----------------------------------------------------------------
        // Summary
        // -----------------------------------------------------------------
        $display("\n============================================================");
        $display("   Test Summary");
        $display("============================================================");
        $display("Total pulses sent:       %0d", pulse_count);
        $display("Total timestamps valid:  %0d", valid_count);
        $display("============================================================\n");

        #(CLK_PERIOD * 10);
        $finish;
    end

    // Timeout watchdog
    initial begin
        #500000000;  // 500us timeout (in ps)
        $display("ERROR: Simulation timeout!");
        $finish;
    end

    // Waveform dump
    initial begin
        $dumpfile("tb_tdc_channel.vcd");
        $dumpvars(0, tb_tdc_channel);
    end

endmodule
