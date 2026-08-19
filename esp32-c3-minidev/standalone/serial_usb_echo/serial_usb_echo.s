# =====================================================================
# Project:     ESP32-C3 Native USB-Serial-JTAG Pure Assembly Echo
# Description: Combined ROM header, startup, and working echo loop
# =====================================================================

.section .text
.option norelax

    # --- ESP32-C3 ROM IMAGE HEADER V2 (24 bytes) ---
    .byte 0xE9               # Magic byte
    .byte 1                  # Number of segments
    .byte 2                  # SPI mode (2 = DIO)
    .byte 0                  # SPI speed/size
    .word 0x40380000         # Entry point address in IRAM
    .word 0                  # WP pin / settings
    .half 5                  # Chip ID (ESP32-C3 = 5)
    .byte 0                  # Min revision
    .half 0, 0, 0, 0         # Reserved
    .byte 0                  # Padding/digest

    # --- SEGMENT HEADER (8 bytes) ---
    .word 0x40380000         # Target load address in IRAM
    .word _seg_end - _seg_start  # Dynamic segment length

.global _start
_seg_start:
_start:
    csrci mstatus, 8
    li   sp, 0x3FCE0000
    li   t2, 0x7FFFBBFF

    # 1. Disable Watchdogs (TG0, TG1, RTC WDT)
    li   t0, 0x6001F064
    li   t1, 0x50D83AA1
    sw   t1, 0(t0)
    li   t0, 0x6001F048
    lw   t3, 0(t0)
    and  t3, t3, t2
    sw   t3, 0(t0)

    li   t0, 0x60020064
    sw   t1, 0(t0)
    li   t0, 0x60020048
    lw   t3, 0(t0)
    and  t3, t3, t2
    sw   t3, 0(t0)

    li   t0, 0x600080A8
    sw   t1, 0(t0)
    li   t0, 0x60008090
    lw   t3, 0(t0)
    and  t3, t3, t2
    sw   t3, 0(t0)

    # 2. Enable USB-Serial-JTAG clock and release reset
    li   t0, 0x600C0010
    lw   t1, 0(t0)
    li   t3, 0x02000000
    or   t1, t1, t3
    sw   t1, 0(t0)

    li   t0, 0x600C0018
    lw   t1, 0(t0)
    li   t3, 0x02000000
    not  t3, t3
    and  t1, t1, t3
    sw   t1, 0(t0)

echo_loop:
    # Native USB-Serial-JTAG Echo Loop
    li   a4, 0x60043000      # USJ base register (0x60043000)
    li   a1, 4               # RX interrupt flag bit
    li   a2, 2               # TX interrupt flag bit

.L_wait_rx:
    lw   a5, 8(a4)           # Read USJ_INT_RAW (0x60043008)
    andi a5, a5, 4
    beqz a5, .L_wait_rx

    lw   a3, 0(a4)           # Read data from USJ_FIFO (0x60043000)
    sw   a1, 20(a4)          # Clear RX interrupt in USJ_INT_CLR (0x60043014)
    andi a3, a3, 0xFF        # Mask to 8-bit

.L_wait_tx:
    lw   a5, 8(a4)           # Read USJ_INT_RAW (0x60043008)
    andi a5, a5, 2
    beqz a5, .L_wait_tx

    sw   a3, 0(a4)           # Write data back to USJ_FIFO (0x60043000)
    
    # CRITICAL: Trigger WR_DONE (bit 0) in EP1_CONF (0x60043004) to flush the packet to PC
    li   t6, 1
    sw   t6, 4(a4)           

    sw   a2, 20(a4)          # Clear TX interrupt in USJ_INT_CLR (0x60043014)
    j    .L_wait_rx

_seg_end:
    .align 4
