/*
 * ==============================================================================
 * Time Tagger Driver Header
 * ==============================================================================
 * Uses AXI GPIO for control/status interface
 * ==============================================================================
 */

#ifndef TIME_TAGGER_H
#define TIME_TAGGER_H

#include "xil_types.h"

/* ==============================================================================
 * GPIO Register Offsets (Xilinx AXI GPIO)
 * ============================================================================== */

#define TT_GPIO_CTRL        0x00   /* GPIO channel 1 data (control output) */
#define TT_GPIO_CTRL_TRI    0x04   /* GPIO channel 1 tri-state */
#define TT_GPIO_STATUS      0x08   /* GPIO channel 2 data (status input) */
#define TT_GPIO_STATUS_TRI  0x0C   /* GPIO channel 2 tri-state */

/* Control bits (GPIO channel 1 - output to PL) */
#define TT_CTRL_ENABLE      (1 << 0)
#define TT_CTRL_SOFT_RST    (1 << 1)
#define TT_CTRL_CLR_OVF     (1 << 2)

/* Status bits (GPIO channel 2 - input from PL) */
#define TT_STATUS_RUNNING   (1 << 0)
#define TT_STATUS_OVERFLOW  (1 << 1)
#define TT_STATUS_HAS_DATA  (1 << 2)
#define TT_STATUS_FIFO_FULL (1 << 3)

/* Status field extraction macros */
#define TT_GET_FIFO_COUNT(status)  (((status) >> 4) & 0xFFF)
#define TT_GET_EVENT_COUNT(status) (((status) >> 16) & 0xFFFF)

/* ==============================================================================
 * Data Types
 * ============================================================================== */

typedef struct {
    u32 gpio_base_addr;     /* Base address of AXI GPIO IP */
    u32 num_channels;       /* Number of TDC channels */
} TimeTagger_t;

typedef struct {
    u32 coarse;             /* Coarse counter value (5ns resolution) */
    u8  fine;               /* Fine counter value (~25ps resolution) */
    u8  channel;            /* Channel ID (0-15) */
    u64 time_ps;            /* Absolute time in picoseconds */
} Timestamp_t;

/* ==============================================================================
 * Function Prototypes
 * ============================================================================== */

/**
 * Initialize the time tagger driver
 * @param inst Pointer to driver instance
 * @param gpio_base_addr Base address of AXI GPIO IP
 * @return 0 on success, -1 on failure
 */
int TimeTagger_Init(TimeTagger_t *inst, u32 gpio_base_addr);

/**
 * Enable the time tagger
 * @param inst Pointer to driver instance
 */
void TimeTagger_Enable(TimeTagger_t *inst);

/**
 * Disable the time tagger
 * @param inst Pointer to driver instance
 */
void TimeTagger_Disable(TimeTagger_t *inst);

/**
 * Reset the time tagger
 * @param inst Pointer to driver instance
 */
void TimeTagger_Reset(TimeTagger_t *inst);

/**
 * Clear overflow flag
 * @param inst Pointer to driver instance
 */
void TimeTagger_ClearOverflow(TimeTagger_t *inst);

/**
 * Get status register value
 * @param inst Pointer to driver instance
 * @return Raw status register value
 */
u32 TimeTagger_GetStatus(TimeTagger_t *inst);

/**
 * Get FIFO count
 * @param inst Pointer to driver instance
 * @return Number of timestamps in FIFO (0-4095)
 */
u32 TimeTagger_GetFifoCount(TimeTagger_t *inst);

/**
 * Get event count
 * @param inst Pointer to driver instance
 * @return Total number of events captured (lower 16 bits)
 */
u32 TimeTagger_GetEventCount(TimeTagger_t *inst);

/**
 * Check if overflow occurred
 * @param inst Pointer to driver instance
 * @return 1 if overflow, 0 otherwise
 */
int TimeTagger_IsOverflow(TimeTagger_t *inst);

/**
 * Check if FIFO has data
 * @param inst Pointer to driver instance
 * @return 1 if FIFO has data, 0 if empty
 */
int TimeTagger_HasData(TimeTagger_t *inst);

/**
 * Check if FIFO is full
 * @param inst Pointer to driver instance
 * @return 1 if FIFO is full, 0 otherwise
 */
int TimeTagger_IsFifoFull(TimeTagger_t *inst);

/**
 * Parse raw timestamp data from DMA buffer
 * @param raw Raw 64-bit timestamp from DMA
 * @param ts Pointer to parsed timestamp structure
 */
void TimeTagger_ParseTimestamp(u64 raw, Timestamp_t *ts);

#endif /* TIME_TAGGER_H */
