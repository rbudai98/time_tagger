# =============================================================================
# Vivado Simulation Script for Time Tagger Integration Test
# =============================================================================
# Usage:
#   vivado -mode batch -source run_integration_sim.tcl
#   OR in Vivado TCL console: source run_integration_sim.tcl
# =============================================================================

puts "============================================================"
puts "   Time Tagger Integration Simulation"
puts "============================================================"

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
set proj_dir    [file dirname [info script]]/..
set hdl_dir     $proj_dir/hdl
set sim_dir     $proj_dir/sim
set output_dir  $sim_dir/output

# Create output directory
file mkdir $output_dir

# -----------------------------------------------------------------------------
# Create in-memory project
# -----------------------------------------------------------------------------
puts "\nCreating simulation project..."
create_project -in_memory -part xc7z045ffg900-2

# -----------------------------------------------------------------------------
# Add source files
# -----------------------------------------------------------------------------
puts "Adding HDL sources..."
add_files -norecurse [list \
    $hdl_dir/tdc_channel.v \
    $hdl_dir/timestamp_fifo.v \
]

# Add simulation sources
puts "Adding testbench..."
add_files -fileset sim_1 -norecurse [list \
    $sim_dir/tb_top_level.v \
]

# Set simulation top
set_property top tb_top_level [get_filesets sim_1]
set_property top_lib xil_defaultlib [get_filesets sim_1]

# -----------------------------------------------------------------------------
# Simulation settings
# -----------------------------------------------------------------------------
puts "Configuring simulation..."

# Runtime (500us = 500000ns)
set_property -name {xsim.simulate.runtime} -value {500us} -objects [get_filesets sim_1]

# Log all signals for waveform viewing
set_property -name {xsim.simulate.log_all_signals} -value {true} -objects [get_filesets sim_1]

# Waveform database
set_property -name {xsim.simulate.wdb} -value {$output_dir/tb_top_level.wdb} -objects [get_filesets sim_1]

# -----------------------------------------------------------------------------
# Launch Simulation
# -----------------------------------------------------------------------------
puts "\nLaunching simulation..."
launch_simulation -simset sim_1 -mode behavioral

# -----------------------------------------------------------------------------
# Add waveforms
# -----------------------------------------------------------------------------
puts "Adding waveforms..."

# Create wave groups for organized viewing
add_wave_group "Clocks & Reset"
add_wave -into "Clocks & Reset" /tb_top_level/clk_200mhz
add_wave -into "Clocks & Reset" /tb_top_level/rst_200m_n

add_wave_group "TDC Input"
add_wave -into "TDC Input" /tb_top_level/tdc_hit_0
add_wave -into "TDC Input" /tb_top_level/tdc_ch0/hit_rising
add_wave -into "TDC Input" -radix unsigned /tb_top_level/tdc_ch0/coarse_counter

add_wave_group "TDC Output"
add_wave -into "TDC Output" /tb_top_level/ts_valid
add_wave -into "TDC Output" -radix hexadecimal /tb_top_level/timestamp
add_wave -into "TDC Output" -radix unsigned /tb_top_level/channel_id

add_wave_group "FIFO Status"
add_wave -into "FIFO Status" -radix unsigned /tb_top_level/fifo_count
add_wave -into "FIFO Status" /tb_top_level/fifo_empty
add_wave -into "FIFO Status" /tb_top_level/fifo_full
add_wave -into "FIFO Status" /tb_top_level/overflow_flag

add_wave_group "AXI-Stream"
add_wave -into "AXI-Stream" /tb_top_level/axis_tvalid
add_wave -into "AXI-Stream" /tb_top_level/axis_tready
add_wave -into "AXI-Stream" -radix hexadecimal /tb_top_level/axis_tdata

add_wave_group "Control/Status"
add_wave -into "Control/Status" -radix hexadecimal /tb_top_level/gpio_ctrl
add_wave -into "Control/Status" -radix hexadecimal /tb_top_level/gpio_status
add_wave -into "Control/Status" -radix unsigned /tb_top_level/event_count

add_wave_group "Test Counters"
add_wave -into "Test Counters" -radix unsigned /tb_top_level/pulse_count
add_wave -into "Test Counters" -radix unsigned /tb_top_level/dma_read_count

# -----------------------------------------------------------------------------
# Run simulation
# -----------------------------------------------------------------------------
puts "\nRunning simulation..."
run all

# -----------------------------------------------------------------------------
# Save waveform configuration
# -----------------------------------------------------------------------------
puts "Saving waveform configuration..."
save_wave_config $output_dir/time_tagger_waves.wcfg

puts "\n============================================================"
puts "   Simulation Complete"
puts "============================================================"
puts "Waveform: $output_dir/tb_top_level.wdb"
puts "Wave Config: $output_dir/time_tagger_waves.wcfg"
puts "============================================================"
