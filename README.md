# Time Tagger ZC706 Project
#
# High-precision Time-to-Digital Converter (TDC) with AXI DMA streaming
# Target: Xilinx ZC706 Evaluation Board (XC7Z045)
#

## Directory Structure

```
fmc_time_tagger/
├── README.md                       # This file
├── hdl/                            # Verilog RTL sources
│   ├── top_level.v                # Top-level wrapper (instantiates BD + TDC)
│   ├── tdc_channel.v              # TDC core (CARRY4 delay line)
│   └── timestamp_fifo.v           # BRAM FIFO with AXI-Stream output
├── constraints/
│   └── zc706_time_tagger.xdc      # Pin constraints & timing
├── scripts/
│   ├── create_block_design.tcl    # Vivado block design automation
│   └── build.tcl                  # Synthesis and implementation script
└── software/
    └── src/
        ├── main.c                 # Bare-metal application
        ├── time_tagger.h          # Driver header
        └── time_tagger.c          # Driver implementation
```

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│                              ZC706 ZYNQ                                  │
├─────────────────────────────────────────────────────────────────────────┤
│  ┌─────────────────── PL (200 MHz) ──────────────────────────────────┐  │
│  │  ┌─────────────┐   ┌─────────────┐   ┌──────────────────────────┐ │  │
│  │  │  FMC Input  │──▶│ TDC Channel │──▶│   Timestamp FIFO         │ │  │
│  │  │  (SPDM)     │   │ (CARRY4)    │   │   (BRAM, AXI-Stream)     │ │  │
│  │  └─────────────┘   └─────────────┘   └────────────┬─────────────┘ │  │
│  │                                                    │               │  │
│  │  ┌─────────────────────────────────────────────────┼──────────────┐│  │
│  │  │                 AXI Infrastructure              │              ││  │
│  │  │  ┌───────────────┐                              ▼              ││  │
│  │  │  │ AXI-Lite Regs │◀──────────┐     ┌─────────────────────────┐││  │
│  │  │  │ (Ctrl/Status) │           │     │       AXI DMA           │││  │
│  │  │  └───────────────┘           │     │  (S2MM to DDR3)         │││  │
│  │  └──────────────────────────────┼─────┴───────────┬─────────────┘││  │
│  └─────────────────────────────────┼─────────────────┼───────────────┘  │
│                                    │                 │                   │
│  ┌─────────────────── PS (ARM Cortex-A9) ────────────┼───────────────┐  │
│  │                                 │                 ▼                │  │
│  │  ┌──────────────┐    ┌──────────┴───────────────────────────────┐ │  │
│  │  │  Bare-Metal  │    │              DDR3 (1 GB)                 │ │  │
│  │  │  Application │◀──▶│  Ring buffer: ~25M timestamps            │ │  │
│  │  └──────┬───────┘    └──────────────────────────────────────────┘ │  │
│  │         │                                                          │  │
│  │         ▼                                                          │  │
│  │  ┌─────────────────────────────────────────────────────────────┐  │  │
│  │  │  PS UART1 (USB J17) ────▶ Host PC @ 115200-1Mbps            │  │  │
│  │  └─────────────────────────────────────────────────────────────┘  │  │
│  └───────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────┘
```

## Specifications

| Parameter          | Value                              |
|--------------------|------------------------------------|
| TDC Resolution     | ~25 ps (CARRY4 propagation delay)  |
| Coarse Resolution  | 5 ns (200 MHz clock)               |
| Timestamp Width    | 40 bits (32 coarse + 8 fine)       |
| Max Event Rate     | ~50 M events/sec (DMA limited)     |
| FIFO Depth         | 2048 timestamps (PL BRAM)          |
| DDR3 Buffer        | Configurable, up to 1 GB           |
| Output             | UART @ 115200 baud (PS UART1)      |
| Channels           | 1 (expandable to 4+)               |

## Register Map (AXI GPIO @ 0x41200000)

The design uses AXI GPIO for control/status instead of custom AXI-Lite registers:

### GPIO Channel 1 - Control (Output, offset 0x00)
| Bit  | Name      | Description                          |
|------|-----------|--------------------------------------|
| 0    | Enable    | Enable time tagger (1=enabled)       |
| 1    | SoftReset | Soft reset (pulse high to reset)     |
| 2    | ClrOvf    | Clear overflow flag (pulse high)     |
| 31:3 | Reserved  | Reserved                             |

### GPIO Channel 2 - Status (Input, offset 0x08)
| Bit   | Name      | Description                          |
|-------|-----------|--------------------------------------|
| 0     | Running   | Time tagger is enabled               |
| 1     | Overflow  | FIFO overflow occurred (sticky)      |
| 2     | HasData   | FIFO has data (not empty)            |
| 3     | FifoFull  | FIFO is full                         |
| 15:4  | FifoCnt   | FIFO count (12 bits, 0-4095)         |
| 31:16 | EvtCnt    | Event count (lower 16 bits)          |

## Timestamp Format (64-bit AXI-Stream)

```
Bit [63:48] : Reserved (zeros)
Bit [47:44] : Channel ID (4 bits, 0-15)
Bit [43:40] : Reserved (zeros)
Bit [39:8]  : Coarse counter (32 bits, 5 ns resolution)
Bit [7:0]   : Fine counter (8 bits, ~25 ps resolution)
```

## Build Instructions

### 1. Create Vivado Project

```bash
cd fmc_time_tagger
vivado -mode batch -source scripts/create_block_design.tcl
```

### 2. Generate Bitstream

```tcl
# In Vivado TCL console:
launch_runs synth_1 -jobs 8
wait_on_run synth_1
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1
```

### 3. Export Hardware

```tcl
write_hw_platform -fixed -include_bit -force ./system_wrapper.xsa
```

### 4. Build Software (Vitis)

1. Launch Vitis: `vitis -workspace ./vitis_ws`
2. Create platform from `system_wrapper.xsa`
3. Create application project using `software/src/` files
4. Build and deploy to ZC706

## UART Commands

| Command | Description                    |
|---------|--------------------------------|
| `s`     | Print status                   |
| `e`     | Enable time tagger             |
| `d`     | Disable time tagger            |
| `r`     | Reset time tagger              |
| `c`     | Clear overflow flag            |
| `h`     | Show help                      |

## Input Pin Assignments

The default configuration uses the USER SMA connectors on the ZC706:

| Signal    | Connector | ZC706 Pin | Bank    | IOSTD    | Description           |
|-----------|-----------|-----------|---------|----------|----------------------|
| tdc_hit_0 | J36 (SMA) | L25       | HP 33   | LVCMOS18 | Primary TDC input    |

**Note:** Input signal must be 0-1.8V. External 50-ohm termination recommended.

### Alternative FMC LPC Pins (for multi-channel expansion)

| Signal    | FMC Pin  | ZC706 Pin | Description           |
|-----------|----------|-----------|----------------------|
| tdc_hit_1 | LA01_P   | J20       | TDC input channel 1  |
| tdc_hit_2 | LA02_P   | L19       | TDC input channel 2  |
| tdc_hit_3 | LA03_P   | N19       | TDC input channel 3  |
| tdc_hit_4 | LA04_P   | N20       | TDC input channel 4  |

## Performance Notes

1. **TDC Placement**: The CARRY4 chain must be placed in a single column
   for consistent propagation delay. See constraints file.

2. **Clock Domain Crossing**: The design assumes 200 MHz TDC clock and
   100 MHz AXI clock are derived from the same source (PS PLL).

3. **Maximum Event Rate**: Limited by:
   - DMA bandwidth (~400 MB/s to DDR3)
   - UART output rate (for live streaming)
   - FIFO depth (for burst events)

4. **Calibration**: Fine time calibration should be performed by
   feeding a known delay signal and measuring the DNL/INL.

## Future Enhancements

- [ ] Multi-channel support (up to 8 channels)
- [ ] Histogram accumulation in PL
- [ ] Ethernet streaming (GigE via PS)
- [ ] External trigger input
- [ ] Time correlation/coincidence detection
- [ ] Linux driver for higher-level applications

## License

MIT License - See LICENSE file for details.
