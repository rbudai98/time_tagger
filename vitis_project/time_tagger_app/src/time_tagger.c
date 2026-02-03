/*
 * ==============================================================================
 * Time Tagger Driver Implementation
 * ==============================================================================
 * Uses AXI GPIO for control/status interface
 * ==============================================================================
 */

#include "time_tagger.h"
#include "xil_io.h"

/* ==============================================================================
 * Local Macros
 * ============================================================================== */

#define TT_READ(inst, offset)       Xil_In32((inst)->gpio_base_addr + (offset))
#define TT_WRITE(inst, offset, val) Xil_Out32((inst)->gpio_base_addr + (offset), (val))

/* ==============================================================================
 * Function Implementations
 * ============================================================================== */

int TimeTagger_Init(TimeTagger_t *inst, u32 gpio_base_addr) {
    if (inst == NULL) {
        return -1;
    }

    inst->gpio_base_addr = gpio_base_addr;
    inst->num_channels = 1;  /* Single channel in current design */

    /* Perform soft reset */
    TimeTagger_Reset(inst);

    return 0;
}

void TimeTagger_Enable(TimeTagger_t *inst) {
    u32 ctrl = TT_READ(inst, TT_GPIO_CTRL);
    ctrl |= TT_CTRL_ENABLE;
    TT_WRITE(inst, TT_GPIO_CTRL, ctrl);
}

void TimeTagger_Disable(TimeTagger_t *inst) {
    u32 ctrl = TT_READ(inst, TT_GPIO_CTRL);
    ctrl &= ~TT_CTRL_ENABLE;
    TT_WRITE(inst, TT_GPIO_CTRL, ctrl);
}

void TimeTagger_Reset(TimeTagger_t *inst) {
    /* Assert soft reset and clear overflow */
    TT_WRITE(inst, TT_GPIO_CTRL, TT_CTRL_SOFT_RST | TT_CTRL_CLR_OVF);

    /* Wait for reset to complete */
    for (volatile int i = 0; i < 1000; i++);

    /* Clear control register */
    TT_WRITE(inst, TT_GPIO_CTRL, 0);
}

void TimeTagger_ClearOverflow(TimeTagger_t *inst) {
    u32 ctrl = TT_READ(inst, TT_GPIO_CTRL);
    ctrl |= TT_CTRL_CLR_OVF;
    TT_WRITE(inst, TT_GPIO_CTRL, ctrl);

    /* Brief delay then clear the bit */
    for (volatile int i = 0; i < 100; i++);
    ctrl &= ~TT_CTRL_CLR_OVF;
    TT_WRITE(inst, TT_GPIO_CTRL, ctrl);
}

u32 TimeTagger_GetStatus(TimeTagger_t *inst) {
    return TT_READ(inst, TT_GPIO_STATUS);
}

u32 TimeTagger_GetFifoCount(TimeTagger_t *inst) {
    u32 status = TT_READ(inst, TT_GPIO_STATUS);
    return TT_GET_FIFO_COUNT(status);
}

u32 TimeTagger_GetEventCount(TimeTagger_t *inst) {
    u32 status = TT_READ(inst, TT_GPIO_STATUS);
    return TT_GET_EVENT_COUNT(status);
}

int TimeTagger_IsOverflow(TimeTagger_t *inst) {
    return (TT_READ(inst, TT_GPIO_STATUS) & TT_STATUS_OVERFLOW) ? 1 : 0;
}

int TimeTagger_HasData(TimeTagger_t *inst) {
    return (TT_READ(inst, TT_GPIO_STATUS) & TT_STATUS_HAS_DATA) ? 1 : 0;
}

int TimeTagger_IsFifoFull(TimeTagger_t *inst) {
    return (TT_READ(inst, TT_GPIO_STATUS) & TT_STATUS_FIFO_FULL) ? 1 : 0;
}

void TimeTagger_ParseTimestamp(u64 raw, Timestamp_t *ts) {
    if (ts == NULL) return;

    /* Extract fields from 64-bit raw timestamp */
    /* Format: [63:48]=reserved, [47:44]=channel, [43:40]=reserved, [39:8]=coarse, [7:0]=fine */
    ts->fine    = (raw >> 0) & 0xFF;
    ts->coarse  = (raw >> 8) & 0xFFFFFFFF;
    ts->channel = (raw >> 44) & 0x0F;

    /* Calculate absolute time in picoseconds */
    /* Coarse: 5000 ps per count (200 MHz = 5 ns period) */
    /* Fine: ~25 ps per count (160 taps across 4 ns) */
    ts->time_ps = (u64)ts->coarse * 5000ULL + (u64)ts->fine * 25ULL;
}
