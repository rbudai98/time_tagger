# ==============================================================================
# Time Tagger ZC706 Block Design Creation Script
# ==============================================================================
# Creates a Zynq PS7 block design with:
#   - ZYNQ7 Processing System (PS)
#   - AXI DMA for timestamp streaming
#   - AXI GPIO for control/status (simpler than custom AXI-Lite)
#   - AXI Interconnect
#   - Clock generation (200 MHz for TDC)
#
# The time_tagger RTL is instantiated outside the block design and connected
# via the top_level.v file.
# ==============================================================================

# Set project parameters
set project_name "fmc_time_tagger"
set project_dir  "[file dirname [info script]]/.."
set board_part   "xilinx.com:zc706:part0:1.4"
set part         "xc7z045ffg900-2"

# Create project
create_project ${project_name} ${project_dir}/vivado_project -part ${part} -force
set_property board_part ${board_part} [current_project]

# Add HDL sources
add_files -norecurse [glob ${project_dir}/hdl/*.v]
update_compile_order -fileset sources_1

# Add constraints
add_files -fileset constrs_1 -norecurse ${project_dir}/constraints/zc706_time_tagger.xdc

# ==============================================================================
# Create Block Design
# ==============================================================================

create_bd_design "system"

# Add ZYNQ7 Processing System
create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 processing_system7_0

# Apply ZC706 board preset
apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 \
    -config {make_external "FIXED_IO, DDR" \
             apply_board_preset "1" \
             Master "Disable" \
             Slave "Disable" } \
    [get_bd_cells processing_system7_0]

# Configure PS7 for our needs
set_property -dict [list \
    CONFIG.PCW_USE_S_AXI_HP0 {1} \
    CONFIG.PCW_USE_FABRIC_INTERRUPT {1} \
    CONFIG.PCW_IRQ_F2P_INTR {1} \
    CONFIG.PCW_UART1_PERIPHERAL_ENABLE {1} \
    CONFIG.PCW_UART1_UART1_IO {MIO 48 .. 49} \
    CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {100} \
    CONFIG.PCW_FPGA1_PERIPHERAL_FREQMHZ {200} \
    CONFIG.PCW_EN_CLK1_PORT {1} \
] [get_bd_cells processing_system7_0]

# ==============================================================================
# Add Clocking Wizard (for precise 200 MHz TDC clock)
# ==============================================================================

create_bd_cell -type ip -vlnv xilinx.com:ip:clk_wiz:6.0 clk_wiz_0

set_property -dict [list \
    CONFIG.PRIM_SOURCE {No_buffer} \
    CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {200.000} \
    CONFIG.CLKOUT1_USED {true} \
    CONFIG.CLKOUT2_USED {false} \
    CONFIG.USE_LOCKED {true} \
    CONFIG.USE_RESET {true} \
    CONFIG.RESET_TYPE {ACTIVE_LOW} \
] [get_bd_cells clk_wiz_0]

# Connect clocking
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK1] [get_bd_pins clk_wiz_0/clk_in1]
connect_bd_net [get_bd_pins processing_system7_0/FCLK_RESET0_N] [get_bd_pins clk_wiz_0/resetn]

# ==============================================================================
# Add Processor System Reset modules
# ==============================================================================

create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 rst_ps7_100M
create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 rst_clk_200M

# Connect resets
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] [get_bd_pins rst_ps7_100M/slowest_sync_clk]
connect_bd_net [get_bd_pins clk_wiz_0/clk_out1] [get_bd_pins rst_clk_200M/slowest_sync_clk]
connect_bd_net [get_bd_pins processing_system7_0/FCLK_RESET0_N] [get_bd_pins rst_ps7_100M/ext_reset_in]
connect_bd_net [get_bd_pins clk_wiz_0/locked] [get_bd_pins rst_clk_200M/ext_reset_in]

# ==============================================================================
# Add AXI Interconnect for Control (GP0)
# ==============================================================================

create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 axi_interconnect_0
set_property -dict [list CONFIG.NUM_MI {2}] [get_bd_cells axi_interconnect_0]

# Connect PS GP0 to interconnect
connect_bd_intf_net [get_bd_intf_pins processing_system7_0/M_AXI_GP0] \
                    [get_bd_intf_pins axi_interconnect_0/S00_AXI]

connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] \
               [get_bd_pins axi_interconnect_0/ACLK]
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] \
               [get_bd_pins axi_interconnect_0/S00_ACLK]
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] \
               [get_bd_pins axi_interconnect_0/M00_ACLK]
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] \
               [get_bd_pins axi_interconnect_0/M01_ACLK]

connect_bd_net [get_bd_pins rst_ps7_100M/interconnect_aresetn] \
               [get_bd_pins axi_interconnect_0/ARESETN]
connect_bd_net [get_bd_pins rst_ps7_100M/peripheral_aresetn] \
               [get_bd_pins axi_interconnect_0/S00_ARESETN]
connect_bd_net [get_bd_pins rst_ps7_100M/peripheral_aresetn] \
               [get_bd_pins axi_interconnect_0/M00_ARESETN]
connect_bd_net [get_bd_pins rst_ps7_100M/peripheral_aresetn] \
               [get_bd_pins axi_interconnect_0/M01_ARESETN]

connect_bd_net [get_bd_pins processing_system7_0/M_AXI_GP0_ACLK] \
               [get_bd_pins processing_system7_0/FCLK_CLK0]

# ==============================================================================
# Add AXI DMA
# ==============================================================================

create_bd_cell -type ip -vlnv xilinx.com:ip:axi_dma:7.1 axi_dma_0

set_property -dict [list \
    CONFIG.c_include_sg {0} \
    CONFIG.c_sg_include_stscntrl_strm {0} \
    CONFIG.c_include_mm2s {0} \
    CONFIG.c_include_s2mm {1} \
    CONFIG.c_s2mm_burst_size {256} \
    CONFIG.c_m_axi_s2mm_data_width {64} \
    CONFIG.c_s_axis_s2mm_tdata_width {64} \
] [get_bd_cells axi_dma_0]

# Connect DMA control port to interconnect
connect_bd_intf_net [get_bd_intf_pins axi_interconnect_0/M00_AXI] \
                    [get_bd_intf_pins axi_dma_0/S_AXI_LITE]

connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] \
               [get_bd_pins axi_dma_0/s_axi_lite_aclk]
connect_bd_net [get_bd_pins rst_ps7_100M/peripheral_aresetn] \
               [get_bd_pins axi_dma_0/axi_resetn]

# ==============================================================================
# Add AXI Interconnect for HP0 (AXI4 to AXI3 protocol conversion)
# ==============================================================================

create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 axi_interconnect_hp0
set_property -dict [list \
    CONFIG.NUM_SI {1} \
    CONFIG.NUM_MI {1} \
] [get_bd_cells axi_interconnect_hp0]

# Connect DMA memory port to HP0 interconnect
connect_bd_intf_net [get_bd_intf_pins axi_dma_0/M_AXI_S2MM] \
                    [get_bd_intf_pins axi_interconnect_hp0/S00_AXI]

# Connect HP0 interconnect to PS7 HP0 port
connect_bd_intf_net [get_bd_intf_pins axi_interconnect_hp0/M00_AXI] \
                    [get_bd_intf_pins processing_system7_0/S_AXI_HP0]

# Clock connections for HP0 interconnect
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] \
               [get_bd_pins axi_interconnect_hp0/ACLK]
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] \
               [get_bd_pins axi_interconnect_hp0/S00_ACLK]
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] \
               [get_bd_pins axi_interconnect_hp0/M00_ACLK]

# Reset connections for HP0 interconnect
connect_bd_net [get_bd_pins rst_ps7_100M/interconnect_aresetn] \
               [get_bd_pins axi_interconnect_hp0/ARESETN]
connect_bd_net [get_bd_pins rst_ps7_100M/peripheral_aresetn] \
               [get_bd_pins axi_interconnect_hp0/S00_ARESETN]
connect_bd_net [get_bd_pins rst_ps7_100M/peripheral_aresetn] \
               [get_bd_pins axi_interconnect_hp0/M00_ARESETN]

# DMA and HP0 clock connections
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] \
               [get_bd_pins axi_dma_0/m_axi_s2mm_aclk]
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] \
               [get_bd_pins processing_system7_0/S_AXI_HP0_ACLK]

# ==============================================================================
# Add AXI GPIO for Time Tagger Control/Status
# ==============================================================================

create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 axi_gpio_0

set_property -dict [list \
    CONFIG.C_GPIO_WIDTH {32} \
    CONFIG.C_GPIO2_WIDTH {32} \
    CONFIG.C_IS_DUAL {1} \
    CONFIG.C_ALL_INPUTS {0} \
    CONFIG.C_ALL_OUTPUTS {1} \
    CONFIG.C_ALL_INPUTS_2 {1} \
] [get_bd_cells axi_gpio_0]

# Connect GPIO to interconnect
connect_bd_intf_net [get_bd_intf_pins axi_interconnect_0/M01_AXI] \
                    [get_bd_intf_pins axi_gpio_0/S_AXI]

connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] \
               [get_bd_pins axi_gpio_0/s_axi_aclk]
connect_bd_net [get_bd_pins rst_ps7_100M/peripheral_aresetn] \
               [get_bd_pins axi_gpio_0/s_axi_aresetn]

# ==============================================================================
# Add AXI4-Stream Data FIFO (for clock domain crossing)
# ==============================================================================

create_bd_cell -type ip -vlnv xilinx.com:ip:axis_data_fifo:2.0 axis_data_fifo_0

set_property -dict [list \
    CONFIG.TDATA_NUM_BYTES {8} \
    CONFIG.IS_ACLK_ASYNC {1} \
    CONFIG.FIFO_DEPTH {2048} \
    CONFIG.HAS_TLAST {1} \
    CONFIG.HAS_TKEEP {1} \
] [get_bd_cells axis_data_fifo_0]

# Connect FIFO clocks (async: 200MHz write, 100MHz read)
connect_bd_net [get_bd_pins clk_wiz_0/clk_out1] [get_bd_pins axis_data_fifo_0/s_axis_aclk]
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] [get_bd_pins axis_data_fifo_0/m_axis_aclk]
connect_bd_net [get_bd_pins rst_clk_200M/peripheral_aresetn] [get_bd_pins axis_data_fifo_0/s_axis_aresetn]

# Connect FIFO output to DMA
connect_bd_intf_net [get_bd_intf_pins axis_data_fifo_0/M_AXIS] \
                    [get_bd_intf_pins axi_dma_0/S_AXIS_S2MM]

# ==============================================================================
# Create External Ports for Time Tagger Connection
# ==============================================================================

# Clocks and resets
create_bd_port -dir O clk_200mhz
create_bd_port -dir O clk_100mhz
create_bd_port -dir O rst_200m_n
create_bd_port -dir O rst_100m_n

connect_bd_net [get_bd_pins clk_wiz_0/clk_out1] [get_bd_ports clk_200mhz]
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] [get_bd_ports clk_100mhz]
connect_bd_net [get_bd_pins rst_clk_200M/peripheral_aresetn] [get_bd_ports rst_200m_n]
connect_bd_net [get_bd_pins rst_ps7_100M/peripheral_aresetn] [get_bd_ports rst_100m_n]

# GPIO control/status ports
create_bd_port -dir O -from 31 -to 0 gpio_ctrl
create_bd_port -dir I -from 31 -to 0 gpio_status

connect_bd_net [get_bd_pins axi_gpio_0/gpio_io_o] [get_bd_ports gpio_ctrl]
connect_bd_net [get_bd_ports gpio_status] [get_bd_pins axi_gpio_0/gpio2_io_i]

# AXI-Stream input from time tagger (to async FIFO)
create_bd_port -dir I s_axis_tvalid
create_bd_port -dir O s_axis_tready
create_bd_port -dir I -from 63 -to 0 s_axis_tdata
create_bd_port -dir I s_axis_tlast
create_bd_port -dir I -from 7 -to 0 s_axis_tkeep

connect_bd_net [get_bd_ports s_axis_tvalid] [get_bd_pins axis_data_fifo_0/s_axis_tvalid]
connect_bd_net [get_bd_pins axis_data_fifo_0/s_axis_tready] [get_bd_ports s_axis_tready]
connect_bd_net [get_bd_ports s_axis_tdata] [get_bd_pins axis_data_fifo_0/s_axis_tdata]
connect_bd_net [get_bd_ports s_axis_tlast] [get_bd_pins axis_data_fifo_0/s_axis_tlast]
connect_bd_net [get_bd_ports s_axis_tkeep] [get_bd_pins axis_data_fifo_0/s_axis_tkeep]

# NOTE: tdc_hit_0 is NOT a block design port - it connects directly to RTL
# in top_level.v. The BD doesn't need to know about it.

# ==============================================================================
# Connect Interrupts
# ==============================================================================

create_bd_cell -type ip -vlnv xilinx.com:ip:xlconcat:2.1 xlconcat_0
set_property -dict [list CONFIG.NUM_PORTS {1}] [get_bd_cells xlconcat_0]

connect_bd_net [get_bd_pins axi_dma_0/s2mm_introut] [get_bd_pins xlconcat_0/In0]
connect_bd_net [get_bd_pins xlconcat_0/dout] [get_bd_pins processing_system7_0/IRQ_F2P]

# ==============================================================================
# Assign Addresses
# ==============================================================================

assign_bd_address

# Set specific addresses for easy software access
set_property offset 0x40400000 [get_bd_addr_segs {processing_system7_0/Data/SEG_axi_dma_0_Reg}]
set_property offset 0x41200000 [get_bd_addr_segs {processing_system7_0/Data/SEG_axi_gpio_0_Reg}]

# ==============================================================================
# Validate and Save
# ==============================================================================

validate_bd_design
save_bd_design

# Create HDL wrapper (let Vivado manage it)
make_wrapper -files [get_files ${project_dir}/vivado_project/${project_name}.srcs/sources_1/bd/system/system.bd] -top
add_files -norecurse ${project_dir}/vivado_project/${project_name}.gen/sources_1/bd/system/hdl/system_wrapper.v

# ==============================================================================
# Generate Output Products
# ==============================================================================

generate_target all [get_files ${project_dir}/vivado_project/${project_name}.srcs/sources_1/bd/system/system.bd]

puts "=========================================="
puts "Block design created successfully!"
puts ""
puts "IMPORTANT: You need to set the custom top-level wrapper as the top module:"
puts "  1. Set 'top_level' as the top module in sources_1"
puts "  2. The top_level.v instantiates system_wrapper and time_tagger_top"
puts ""
puts "Next steps:"
puts "  1. Run synthesis: launch_runs synth_1 -jobs 4"
puts "  2. Run implementation: launch_runs impl_1 -jobs 4"
puts "  3. Generate bitstream: launch_runs impl_1 -to_step write_bitstream"
puts "  4. Export hardware: write_hw_platform -fixed -include_bit -force system_wrapper.xsa"
puts "=========================================="
