/*
 * ==============================================================================
 * Time Tagger ZC706 - Bare-Metal Application
 * ==============================================================================
 * Reads timestamps from PL via DMA and outputs via UART
 * Target: Zynq-7000 PS (ARM Cortex-A9)
 * ==============================================================================
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "xil_printf.h"
#include "xil_cache.h"
#include "xparameters.h"
#include "xaxidma.h"
#include "xscugic.h"
#include "xuartps_hw.h"
#include "sleep.h"

/* ==============================================================================
 * Hardware Definitions
 * ============================================================================== */

/* Base addresses (from Vivado address editor) */
#define GPIO_BASE           0x41200000   /* AXI GPIO for control/status */
#define DMA_BASE            XPAR_AXI_DMA_0_BASEADDR

/* GPIO Register Offsets (Xilinx AXI GPIO) */
#define GPIO_DATA           0x00   /* GPIO channel 1 data (control) */
#define GPIO_TRI            0x04   /* GPIO channel 1 tri-state */
#define GPIO2_DATA          0x08   /* GPIO channel 2 data (status) */
#define GPIO2_TRI           0x0C   /* GPIO channel 2 tri-state */

/* Control register bits (GPIO channel 1 output) */
#define TT_CTRL_ENABLE      (1 << 0)
#define TT_CTRL_SOFT_RST    (1 << 1)
#define TT_CTRL_CLR_OVF     (1 << 2)

/* Status register bits (GPIO channel 2 input) */
/* [0]     = Running (enabled)
 * [1]     = Overflow flag
 * [2]     = FIFO has data (not empty)
 * [3]     = FIFO full
 * [15:4]  = FIFO count (12 bits)
 * [31:16] = Event count (lower 16 bits) */
#define TT_STATUS_RUNNING   (1 << 0)
#define TT_STATUS_OVERFLOW  (1 << 1)
#define TT_STATUS_HAS_DATA  (1 << 2)
#define TT_STATUS_FIFO_FULL (1 << 3)

/* DMA buffer configuration */
#define DMA_BUFFER_SIZE     (64 * 1024)  /* 64 KB buffer = 8192 timestamps */
#define TIMESTAMP_SIZE      8            /* 64-bit per timestamp */
#define MAX_TIMESTAMPS      (DMA_BUFFER_SIZE / TIMESTAMP_SIZE)

/* ==============================================================================
 * Global Variables
 * ============================================================================== */

static XAxiDma dma_inst;
static XScuGic intc_inst;

/* DMA buffer - aligned to cache line */
static u8 dma_buffer[DMA_BUFFER_SIZE] __attribute__((aligned(64)));

/* Statistics */
static u32 total_events = 0;
static u32 overflow_count = 0;

/* ==============================================================================
 * Register Access Macros
 * ============================================================================== */

#define GPIO_CTRL_READ()        Xil_In32(GPIO_BASE + GPIO_DATA)
#define GPIO_CTRL_WRITE(val)    Xil_Out32(GPIO_BASE + GPIO_DATA, (val))
#define GPIO_STATUS_READ()      Xil_In32(GPIO_BASE + GPIO2_DATA)

/* Extract fields from status register */
#define GET_FIFO_COUNT(status)  (((status) >> 4) & 0xFFF)   /* 12 bits */
#define GET_EVENT_COUNT(status) (((status) >> 16) & 0xFFFF)

/* ==============================================================================
 * Timestamp Structure
 * ============================================================================== */

typedef struct {
    u32 coarse;         /* 32-bit coarse counter (5 ns resolution @ 200 MHz) */
    u8  fine;           /* 8-bit fine counter (~25 ps resolution) */
    u8  channel;        /* 4-bit channel ID */
    u16 reserved;
} timestamp_t;

/* ==============================================================================
 * Function: Parse timestamp from DMA buffer
 * ============================================================================== */

static void parse_timestamp(u64 raw, timestamp_t *ts) {
    ts->fine    = (raw >> 0) & 0xFF;
    ts->coarse  = (raw >> 8) & 0xFFFFFFFF;
    ts->channel = (raw >> 44) & 0x0F;
}

/* ==============================================================================
 * Function: Convert timestamp to absolute time in picoseconds
 * ============================================================================== */

static u64 timestamp_to_ps(timestamp_t *ts) {
    /* Coarse: 5000 ps per count (200 MHz = 5 ns period) */
    /* Fine: ~25 ps per count (160 taps across 4 ns) */
    u64 coarse_ps = (u64)ts->coarse * 5000ULL;
    u64 fine_ps   = (u64)ts->fine * 25ULL;  /* Approximate */
    return coarse_ps + fine_ps;
}

/* ==============================================================================
 * Function: Initialize DMA
 * ============================================================================== */

static int init_dma(void) {
    XAxiDma_Config *cfg;
    int status;
    
    cfg = XAxiDma_LookupConfig(XPAR_AXI_DMA_0_BASEADDR);
    if (!cfg) {
        xil_printf("ERROR: DMA config not found\r\n");
        return XST_FAILURE;
    }
    
    status = XAxiDma_CfgInitialize(&dma_inst, cfg);
    if (status != XST_SUCCESS) {
        xil_printf("ERROR: DMA init failed: %d\r\n", status);
        return XST_FAILURE;
    }
    
    /* Disable interrupts for polling mode */
    XAxiDma_IntrDisable(&dma_inst, XAXIDMA_IRQ_ALL_MASK, XAXIDMA_DEVICE_TO_DMA);
    
    xil_printf("DMA initialized successfully\r\n");
    return XST_SUCCESS;
}

/* ==============================================================================
 * Function: Initialize Time Tagger
 * ============================================================================== */

static int init_time_tagger(void) {
    xil_printf("Time Tagger initializing...\r\n");
    
    /* Soft reset */
    GPIO_CTRL_WRITE(TT_CTRL_SOFT_RST | TT_CTRL_CLR_OVF);
    usleep(1000);
    
    /* Clear reset, enable time tagger */
    GPIO_CTRL_WRITE(TT_CTRL_ENABLE);
    
    xil_printf("Time Tagger enabled\r\n");
    return XST_SUCCESS;
}

/* ==============================================================================
 * Function: Start DMA transfer
 * ============================================================================== */

static int start_dma_transfer(void) {
    int status;
    
    /* Invalidate cache for DMA buffer */
    Xil_DCacheInvalidateRange((UINTPTR)dma_buffer, DMA_BUFFER_SIZE);
    
    /* Start S2MM (Stream to Memory-Mapped) transfer */
    status = XAxiDma_SimpleTransfer(&dma_inst, (UINTPTR)dma_buffer,
                                    DMA_BUFFER_SIZE, XAXIDMA_DEVICE_TO_DMA);
    if (status != XST_SUCCESS) {
        xil_printf("ERROR: DMA transfer failed: %d\r\n", status);
        return XST_FAILURE;
    }
    
    return XST_SUCCESS;
}

/* ==============================================================================
 * Function: Wait for DMA completion
 * ============================================================================== */

static int wait_dma_complete(u32 timeout_ms) {
    u32 elapsed = 0;
    
    while (XAxiDma_Busy(&dma_inst, XAXIDMA_DEVICE_TO_DMA)) {
        usleep(1000);
        elapsed++;
        if (elapsed >= timeout_ms) {
            return XST_FAILURE;  /* Timeout */
        }
    }
    
    /* Invalidate cache after DMA completes */
    Xil_DCacheInvalidateRange((UINTPTR)dma_buffer, DMA_BUFFER_SIZE);
    
    return XST_SUCCESS;
}

/* ==============================================================================
 * Function: Process and print timestamps
 * ============================================================================== */

static void process_timestamps(int count) {
    u64 *raw_ts = (u64 *)dma_buffer;
    timestamp_t ts;
    int i;
    
    for (i = 0; i < count; i++) {
        if (raw_ts[i] == 0) continue;  /* Skip empty entries */
        
        parse_timestamp(raw_ts[i], &ts);
        u64 time_ps = timestamp_to_ps(&ts);
        
        /* Print in human-readable format */
        /* Format: CH:X TIME:XXXXX.XXX ns FINE:XXX */
        xil_printf("CH:%d TIME:%llu.%03llu ns FINE:%d\r\n",
                   ts.channel,
                   (unsigned long long)(time_ps / 1000),
                   (unsigned long long)(time_ps % 1000),
                   ts.fine);
        
        total_events++;
    }
}

/* ==============================================================================
 * Function: Print binary timestamp (for high-speed data logging)
 * ============================================================================== */

static void output_binary_timestamps(int count) {
    /* Header: 4 bytes magic + 4 bytes count */
    u8 header[8] = {'T', 'T', 'A', 'G', 0, 0, 0, 0};
    header[4] = (count >> 0) & 0xFF;
    header[5] = (count >> 8) & 0xFF;
    header[6] = (count >> 16) & 0xFF;
    header[7] = (count >> 24) & 0xFF;
    
    /* Output header */
    for (int i = 0; i < 8; i++) {
        outbyte(header[i]);
    }
    
    /* Output raw timestamp data */
    for (int i = 0; i < count * TIMESTAMP_SIZE; i++) {
        outbyte(dma_buffer[i]);
    }
}

/* ==============================================================================
 * Function: Print status
 * ============================================================================== */

static void print_status(void) {
    u32 status = GPIO_STATUS_READ();
    u32 fifo_cnt = GET_FIFO_COUNT(status);
    u32 evt_cnt = GET_EVENT_COUNT(status);

    xil_printf("\r\n=== Time Tagger Status ===\r\n");
    xil_printf("Running:    %s\r\n", (status & TT_STATUS_RUNNING) ? "Yes" : "No");
    xil_printf("Overflow:   %s\r\n", (status & TT_STATUS_OVERFLOW) ? "YES!" : "No");
    xil_printf("FIFO Full:  %s\r\n", (status & TT_STATUS_FIFO_FULL) ? "YES!" : "No");
    xil_printf("FIFO Data:  %s\r\n", (status & TT_STATUS_HAS_DATA) ? "Yes" : "Empty");
    xil_printf("FIFO Count: %lu\r\n", fifo_cnt);
    xil_printf("Event Count (HW): %lu\r\n", evt_cnt);
    xil_printf("Event Count (SW): %lu\r\n", total_events);
    xil_printf("==========================\r\n\r\n");
}

/* ==============================================================================
 * Function: Command handler
 * ============================================================================== */

static void handle_command(char cmd) {
    switch (cmd) {
        case 's':
        case 'S':
            print_status();
            break;
            
        case 'e':
        case 'E':
            GPIO_CTRL_WRITE(TT_CTRL_ENABLE);
            xil_printf("Time Tagger ENABLED\r\n");
            break;
            
        case 'd':
        case 'D':
            GPIO_CTRL_WRITE(0);
            xil_printf("Time Tagger DISABLED\r\n");
            break;
            
        case 'r':
        case 'R':
            GPIO_CTRL_WRITE(TT_CTRL_SOFT_RST);
            usleep(1000);
            GPIO_CTRL_WRITE(TT_CTRL_ENABLE);
            total_events = 0;
            xil_printf("Time Tagger RESET\r\n");
            break;
            
        case 'c':
        case 'C':
            GPIO_CTRL_WRITE(TT_CTRL_ENABLE | TT_CTRL_CLR_OVF);
            usleep(100);
            GPIO_CTRL_WRITE(TT_CTRL_ENABLE);  /* Clear the CLR_OVF bit */
            xil_printf("Overflow flag CLEARED\r\n");
            break;
            
        case 'h':
        case 'H':
        case '?':
            xil_printf("\r\n=== Commands ===\r\n");
            xil_printf("s - Print status\r\n");
            xil_printf("e - Enable time tagger\r\n");
            xil_printf("d - Disable time tagger\r\n");
            xil_printf("r - Reset time tagger\r\n");
            xil_printf("c - Clear overflow flag\r\n");
            xil_printf("h - Show this help\r\n");
            xil_printf("================\r\n\r\n");
            break;
            
        default:
            break;
    }
}

/* ==============================================================================
 * Main Application
 * ============================================================================== */

int main(void) {
    int status;
    int transfer_count = 0;
    
    xil_printf("\r\n");
    xil_printf("============================================\r\n");
    xil_printf("   Time Tagger ZC706 - Bare Metal Demo\r\n");
    xil_printf("============================================\r\n");
    xil_printf("\r\n");
    
    /* Initialize DMA */
    status = init_dma();
    if (status != XST_SUCCESS) {
        xil_printf("FATAL: DMA initialization failed\r\n");
        return -1;
    }
    
    /* Initialize Time Tagger */
    status = init_time_tagger();
    if (status != XST_SUCCESS) {
        xil_printf("FATAL: Time Tagger initialization failed\r\n");
        return -1;
    }
    
    xil_printf("System ready. Press 'h' for help.\r\n\r\n");
    
    /* Main loop */
    while (1) {
        /* Check for UART input (non-blocking) */
        if (XUartPs_IsReceiveData(STDIN_BASEADDRESS)) {
            char cmd = inbyte();
            handle_command(cmd);
        }
        
        /* Check status register */
        u32 status_reg = GPIO_STATUS_READ();
        u32 fifo_cnt = GET_FIFO_COUNT(status_reg);

        /* If FIFO has data, start DMA transfer */
        if (status_reg & TT_STATUS_HAS_DATA) {
            /* Calculate transfer size (limit to buffer size) */
            int ts_count = (fifo_cnt > MAX_TIMESTAMPS) ? MAX_TIMESTAMPS : fifo_cnt;
            int transfer_size = ts_count * TIMESTAMP_SIZE;
            
            /* Clear buffer */
            memset(dma_buffer, 0, DMA_BUFFER_SIZE);
            Xil_DCacheFlushRange((UINTPTR)dma_buffer, DMA_BUFFER_SIZE);
            
            /* Start DMA transfer */
            status = XAxiDma_SimpleTransfer(&dma_inst, (UINTPTR)dma_buffer,
                                            transfer_size, XAXIDMA_DEVICE_TO_DMA);
            
            if (status == XST_SUCCESS) {
                /* Wait for completion (with timeout) */
                if (wait_dma_complete(1000) == XST_SUCCESS) {
                    /* Process received timestamps */
                    process_timestamps(ts_count);
                    transfer_count++;
                }
            }
        }
        
        /* Check for overflow */
        /* Small delay to prevent busy-waiting */
        usleep(100);
    }
    
    return 0;
}
