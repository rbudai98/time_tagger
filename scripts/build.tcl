# ==============================================================================
# Build Script - Run after create_block_design.tcl
# ==============================================================================
# Sets top_level as the top module and runs synthesis/implementation
# ==============================================================================

# Open the project
set project_dir  "[file dirname [info script]]/.."
open_project ${project_dir}/vivado_project/fmc_time_tagger.xpr

# Set top_level as the top module (not system_wrapper)
set_property top top_level [current_fileset]
update_compile_order -fileset sources_1

# Ensure constraints file is in project and enabled
set xdc_file "${project_dir}/constraints/zc706_time_tagger.xdc"
if {[llength [get_files -quiet $xdc_file]] == 0} {
    puts "Adding constraints file..."
    add_files -fileset constrs_1 -norecurse $xdc_file
}
# Ensure constraint file is enabled for synthesis and implementation
set_property USED_IN_SYNTHESIS true [get_files $xdc_file]
set_property USED_IN_IMPLEMENTATION true [get_files $xdc_file]

# Check design for errors
puts "=========================================="
puts "Checking design hierarchy..."
puts "=========================================="
report_compile_order -fileset sources_1

# Run synthesis
puts "=========================================="
puts "Starting Synthesis..."
puts "=========================================="
reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1

# Check synthesis status
if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
    puts "ERROR: Synthesis failed!"
    exit 1
}
puts "Synthesis completed successfully!"

# Verify and fix tdc_hit_0 constraint
open_run synth_1
puts "=== Checking port constraints ==="
set tdc_port [get_ports -quiet tdc_hit_0]
if {$tdc_port eq ""} {
    puts "WARNING: Port tdc_hit_0 not found! Checking for similar ports..."
    puts "Available ports matching *tdc*: [get_ports -quiet *tdc*]"
    puts "All ports: [get_ports *]"
} else {
    set current_loc [get_property -quiet PACKAGE_PIN $tdc_port]
    if {$current_loc eq ""} {
        puts "Applying PACKAGE_PIN Y23 to tdc_hit_0..."
        set_property PACKAGE_PIN Y23 $tdc_port
        set_property IOSTANDARD LVCMOS25 $tdc_port
    } else {
        puts "tdc_hit_0 already constrained to $current_loc"
    }
}
close_design

# Apply physical constraints directly before implementation
puts "=========================================="
puts "Applying IO Constraints..."
puts "=========================================="
open_run synth_1
# Force the constraint
set tdc_port [get_ports {tdc_hit_0}]
if {$tdc_port ne ""} {
    set_property PACKAGE_PIN Y23 $tdc_port
    set_property IOSTANDARD LVCMOS25 $tdc_port
    puts "Applied constraints to tdc_hit_0"
} else {
    puts "ERROR: Cannot find port tdc_hit_0!"
    puts "Available ports: [get_ports *]"
    exit 1
}
# Save the constraints
write_xdc -force ${project_dir}/vivado_project/applied_constraints.xdc
close_design

# Add the generated constraints file
add_files -fileset constrs_1 -norecurse ${project_dir}/vivado_project/applied_constraints.xdc

# Run implementation
puts "=========================================="
puts "Starting Implementation..."
puts "=========================================="
launch_runs impl_1 -jobs 4
wait_on_run impl_1

# Check implementation status
if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
    puts "ERROR: Implementation failed!"
    exit 1
}
puts "Implementation completed successfully!"

# Generate bitstream
puts "=========================================="
puts "Generating Bitstream..."
puts "=========================================="
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

puts "Bitstream generation completed!"

# Export hardware platform (XSA file for Vitis)
puts "=========================================="
puts "Exporting Hardware Platform..."
puts "=========================================="
write_hw_platform -fixed -include_bit -force ${project_dir}/vivado_project/fmc_time_tagger.xsa

puts "=========================================="
puts "BUILD COMPLETE!"
puts ""
puts "Output files:"
puts "  Bitstream: vivado_project/fmc_time_tagger.runs/impl_1/top_level.bit"
puts "  XSA file:  vivado_project/fmc_time_tagger.xsa"
puts ""
puts "Next steps for software:"
puts "  1. Launch Vitis: vitis -workspace vitis_ws"
puts "  2. Create platform from fmc_time_tagger.xsa"
puts "  3. Create application using software/src/ files"
puts "  4. Build and deploy to ZC706"
puts "=========================================="
