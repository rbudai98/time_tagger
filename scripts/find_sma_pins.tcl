# Find correct pins for ZC706 USER_SMA
open_project /home/rbudai/Workspace_hdl/fmc_time_tagger/vivado_project/fmc_time_tagger.xpr
open_run synth_1

# Get board part information
puts "=== Board Part ==="
puts [get_property BOARD_PART [current_project]]

# Check available HP banks (for 1.8V I/O)
puts "\n=== HP Bank pins ==="
foreach bank {33 34 35 10 11 12 13} {
    set pins [get_package_pins -quiet -filter "BANK == $bank"]
    if {[llength $pins] > 0} {
        puts "Bank $bank: [lrange $pins 0 10]..."
    }
}

# Look for pins that might be USER_SMA (typically clock-capable)
puts "\n=== Clock-capable pins in HP banks ==="
set cc_pins [get_package_pins -filter {IS_CLOCK_PIN == 1}]
puts "Total CC pins: [llength $cc_pins]"
puts "First 20: [lrange $cc_pins 0 19]"

# Check what bank specific pins are in
puts "\n=== Check specific pins ==="
foreach pin {H9 G9 Y23 Y24 K25} {
    set p [get_package_pins -quiet $pin]
    if {$p ne ""} {
        puts "$pin: Bank [get_property BANK $p]"
    } else {
        puts "$pin: NOT FOUND"
    }
}

close_project
exit
