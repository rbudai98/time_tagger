# =============================================================================
# Vivado Simulation Script for Timestamp FIFO Test
# =============================================================================

set proj_dir    [file dirname [info script]]/..
set hdl_dir     $proj_dir/hdl
set sim_dir     $proj_dir/sim
set output_dir  $sim_dir/output

file mkdir $output_dir

puts "Running Timestamp FIFO Testbench..."

create_project -in_memory -part xc7z045ffg900-2

add_files -norecurse $hdl_dir/timestamp_fifo.v
add_files -fileset sim_1 -norecurse $sim_dir/tb_timestamp_fifo.v

set_property top tb_timestamp_fifo [get_filesets sim_1]
set_property -name {xsim.simulate.runtime} -value {1ms} -objects [get_filesets sim_1]
set_property -name {xsim.simulate.log_all_signals} -value {true} -objects [get_filesets sim_1]

launch_simulation -simset sim_1 -mode behavioral

add_wave {{/tb_timestamp_fifo/*}}
add_wave {{/tb_timestamp_fifo/dut/*}}

run all

save_wave_config $output_dir/fifo_waves.wcfg

puts "Timestamp FIFO simulation complete."
