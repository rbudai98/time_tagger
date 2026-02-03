# =============================================================================
# Makefile for Time Tagger Simulation
# =============================================================================
# Supports: Vivado XSim, Icarus Verilog, Verilator
# =============================================================================

# Directories
HDL_DIR    := ../hdl
SIM_DIR    := .
OUTPUT_DIR := ./output

# Source files
HDL_SRCS := \
    $(HDL_DIR)/tdc_channel.v \
    $(HDL_DIR)/timestamp_fifo.v

# Testbenches
TB_TDC    := tb_tdc_channel.v
TB_FIFO   := tb_timestamp_fifo.v
TB_TOP    := tb_top_level.v

# Default target
.PHONY: all
all: help

# Create output directory
$(OUTPUT_DIR):
	mkdir -p $(OUTPUT_DIR)

# =============================================================================
# Vivado XSim Targets
# =============================================================================

.PHONY: xsim-top xsim-tdc xsim-fifo xsim-gui

# Run integration testbench with XSim (batch mode)
xsim-top: $(OUTPUT_DIR)
	@echo "Running integration test with Vivado XSim..."
	vivado -mode batch -source run_integration_sim.tcl -log $(OUTPUT_DIR)/xsim_top.log -journal $(OUTPUT_DIR)/xsim_top.jou

# Run with GUI for waveform viewing
xsim-gui: $(OUTPUT_DIR)
	@echo "Running integration test with Vivado XSim (GUI)..."
	vivado -mode gui -source run_integration_sim.tcl

# Run TDC channel testbench
xsim-tdc: $(OUTPUT_DIR)
	@echo "Running TDC channel test with Vivado XSim..."
	vivado -mode batch -source run_tdc_sim.tcl -log $(OUTPUT_DIR)/xsim_tdc.log

# Run FIFO testbench
xsim-fifo: $(OUTPUT_DIR)
	@echo "Running FIFO test with Vivado XSim..."
	vivado -mode batch -source run_fifo_sim.tcl -log $(OUTPUT_DIR)/xsim_fifo.log

# =============================================================================
# Icarus Verilog Targets (Open Source Alternative)
# =============================================================================

.PHONY: iverilog-top iverilog-tdc iverilog-fifo

# Compile and run integration test
iverilog-top: $(OUTPUT_DIR)
	@echo "Compiling with Icarus Verilog..."
	iverilog -g2012 -o $(OUTPUT_DIR)/tb_top_level.vvp \
		-DSIMULATION \
		-I$(HDL_DIR) \
		$(HDL_SRCS) $(TB_TOP)
	@echo "Running simulation..."
	vvp $(OUTPUT_DIR)/tb_top_level.vvp | tee $(OUTPUT_DIR)/iverilog_top.log
	@echo "Waveform saved to: tb_top_level.vcd"

# Compile and run TDC test
iverilog-tdc: $(OUTPUT_DIR)
	iverilog -g2012 -o $(OUTPUT_DIR)/tb_tdc_channel.vvp \
		-DSIMULATION \
		-I$(HDL_DIR) \
		$(HDL_DIR)/tdc_channel.v $(TB_TDC)
	vvp $(OUTPUT_DIR)/tb_tdc_channel.vvp | tee $(OUTPUT_DIR)/iverilog_tdc.log

# Compile and run FIFO test
iverilog-fifo: $(OUTPUT_DIR)
	iverilog -g2012 -o $(OUTPUT_DIR)/tb_timestamp_fifo.vvp \
		-DSIMULATION \
		-I$(HDL_DIR) \
		$(HDL_DIR)/timestamp_fifo.v $(TB_FIFO)
	vvp $(OUTPUT_DIR)/tb_timestamp_fifo.vvp | tee $(OUTPUT_DIR)/iverilog_fifo.log

# View waveforms with GTKWave
.PHONY: gtkwave
gtkwave:
	gtkwave tb_top_level.vcd &

# =============================================================================
# Verilator Targets (Fast simulation)
# =============================================================================

.PHONY: verilator-lint verilator-top

# Lint check (fast syntax/style check)
verilator-lint:
	@echo "Running Verilator lint..."
	verilator --lint-only -Wall \
		-I$(HDL_DIR) \
		$(HDL_SRCS)

# Note: Verilator doesn't support CARRY4 primitives directly
# This target is for lint checking only

# =============================================================================
# Utility Targets
# =============================================================================

.PHONY: clean help

clean:
	rm -rf $(OUTPUT_DIR)
	rm -f *.vcd *.wdb *.log *.jou
	rm -rf .Xil xsim.dir
	rm -f vivado*.log vivado*.jou
	rm -f *.pb *.wdb

help:
	@echo "============================================================"
	@echo "  Time Tagger Simulation Makefile"
	@echo "============================================================"
	@echo ""
	@echo "Vivado XSim targets:"
	@echo "  make xsim-top     Run integration testbench (batch)"
	@echo "  make xsim-gui     Run integration testbench (GUI)"
	@echo "  make xsim-tdc     Run TDC channel testbench"
	@echo "  make xsim-fifo    Run FIFO testbench"
	@echo ""
	@echo "Icarus Verilog targets:"
	@echo "  make iverilog-top   Run integration test"
	@echo "  make iverilog-tdc   Run TDC channel test"
	@echo "  make iverilog-fifo  Run FIFO test"
	@echo "  make gtkwave        View waveforms"
	@echo ""
	@echo "Utility:"
	@echo "  make verilator-lint  Lint check with Verilator"
	@echo "  make clean           Remove generated files"
	@echo "============================================================"
