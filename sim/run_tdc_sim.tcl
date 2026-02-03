# =============================================================================
# Vivado Simulation Script for TDC Channel Test
# =============================================================================

set proj_dir    [file dirname [info script]]/..
set hdl_dir     $proj_dir/hdl
set sim_dir     $proj_dir/sim
set output_dir  $sim_dir/output

file mkdir $output_dir

puts "Running TDC Channel Testbench..."

create_project -in_memory -part xc7z045ffg900-2

add_files -norecurse $hdl_dir/tdc_channel.v
add_files -fileset sim_1 -norecurse $sim_dir/tb_tdc_channel.v

set_property top tb_tdc_channel [get_filesets sim_1]
set_property -name {xsim.simulate.runtime} -value {200us} -objects [get_filesets sim_1]
set_property -name {xsim.simulate.log_all_signals} -value {true} -objects [get_filesets sim_1]

launch_simulation -simset sim_1 -mode behavioral

add_wave {{/tb_tdc_channel/*}}
add_wave {{/tb_tdc_channel/dut/*}}

run all

save_wave_config $output_dir/tdc_channel_waves.wcfg

puts "TDC Channel simulation complete."
