# Debug script to check pins and hierarchy
open_project /home/rbudai/Workspace_hdl/fmc_time_tagger/vivado_project/fmc_time_tagger.xpr
open_run synth_1

# Check available pins
puts "=== Checking IOB pins for Bank 33 ==="
set bank33_pins [get_package_pins -filter {BANK == 33}]
puts "Bank 33 pins: $bank33_pins"

# Check port list
puts "\n=== Available ports ==="
puts [get_ports *]

# Check the clk_wiz hierarchy
puts "\n=== Clock wizard pins ==="
puts [get_pins -hierarchical -filter {NAME =~ *clk_wiz*clk_out*}]

# Check what site L25 maps to
puts "\n=== Checking L25 pin ==="
set l25_pin [get_package_pins L25]
if {$l25_pin ne ""} {
    puts "L25 exists: $l25_pin"
    puts "Bank: [get_property BANK $l25_pin]"
    puts "Is IOB: [get_property IS_IOB $l25_pin]"
} else {
    puts "L25 does not exist in this package"
}

close_project
exit
