# =====================================================================
# Project:     Bare-Metal ESP32-C3 Assembly led_blink (Optimized Register Use)
# Author:      agguro
# Date:        August 11, 2026
# Description: Pure assembly bare-metal led_blink on GPIO 8 using 
#              address-toggling for W1TS/W1TC registers.
# =====================================================================

.equ DELAY, 5000000

.section .text
.option norelax
. = 0                    # Start cleanly at 0 for the flat binary

    # ---------------------------------------------------------
    # ESP32-C3 ROM IMAGE HEADER V2 (24 bytes)
    # ---------------------------------------------------------
    .byte 0xE9                 # 0x00: Magic byte for ESP boot image
    .byte 1                    # 0x01: Number of segments
    .byte 2                    # 0x02: SPI flash mode (2 = DIO)
    .byte 0                    # 0x03: SPI flash speed and size config
    .word 0x40380000           # 0x04: Entry point address in IRAM
    .word 0                    # 0x08: WP pin / drive settings
    .half 5                    # 0x0C: Chip ID (5 = ESP32-C3)
    .byte 0                    # 0x0E: Minimum chip revision
    .half 0                    # 0x0F: Min revision full
    .half 0                    # 0x11: Max revision full
    .half 0                    # 0x13: Reserved bytes
    .byte 0                    # 0x15: Append digest flag
    .byte 0, 0                 # 0x16: Padding alignment bytes

    # ---------------------------------------------------------
    # SEGMENT HEADER (8 bytes)
    # ---------------------------------------------------------
    .word 0x40380000           # 0x18: Target load address in Instruction RAM (IRAM)
    .word 0                    # 0x1C: Dynamic segment length calculation

    # ---------------------------------------------------------
    # SEGMENT DATA (Main Entry Point)
    # ---------------------------------------------------------
    .global _start
_start:
    # ---------------------------------------------------------
    # 1. CPU & ENVIRONMENT INITIALIZATION
    # ---------------------------------------------------------
    csrci mstatus, 8
    li   sp, 0x3FCE0000
    li   t2, 0x7FFFBBFF        # Bitmask used to clear watchdog write-protect bits

    # ---------------------------------------------------------
    # 2. WATCHDOG TIMER (WDT) & DEBUG DISABLE
    # ---------------------------------------------------------
    # Disable Timer Group 0 (TG0) Watchdog
    li   t0, 0x6001F064
    li   t1, 0x50D83AA1
    sw   t1, 0(t0)
    li   t0, 0x6001F048
    lw   t3, 0(t0)
    and  t3, t3, t2
    sw   t3, 0(t0)

    # Disable Timer Group 1 (TG1) Watchdog
    li   t0, 0x60020064
    sw   t1, 0(t0)
    li   t0, 0x60020048
    lw   t3, 0(t0)
    and  t3, t3, t2
    sw   t3, 0(t0)

    # Disable RTC Watchdog
    li   t0, 0x600080A8
    sw   t1, 0(t0)
    li   t0, 0x60008090
    lw   t3, 0(t0)
    and  t3, t3, t2
    sw   t3, 0(t0)

    # Disable Serial Wire Debug (SWD) / JTAG interference
    li   t0, 0x600080B8
    li   t1, 0x8F1D312A
    sw   t1, 0(t0)
    li   t0, 0x600080B4
    lw   t3, 0(t0)
    li   t4, 0x80000000
    or   t3, t3, t4
    sw   t3, 0(t0)

    # Disconnect USB PHY
    li   t0, 0x6004301C
    li   t3, 0
    sw   t3, 0(t0)

    # ---------------------------------------------------------
    # 3. GPIO CONFIGURATION (LED on GPIO 8)
    # ---------------------------------------------------------
    li   t0, 0x60004024        # GPIO_ENABLE_W1TS_REG
    li   t1, 0x100             # Bit 8 set high
    sw   t1, 0(t0)

    # Cache only ONE register base address: 0x60004008 (GPIO_OUT_W1TS_REG)
    li   s0, 0x60004008        

    # ---------------------------------------------------------
    # 4. MAIN BLINK LOOP
    # ---------------------------------------------------------
blink_loop:
    # Write mask to whatever address is currently in s0 (switches between W1TS and W1TC)
    sw   t1, 0(s0)

    # Load delay count from memory using position-independent addressing
.L_delay:
    auipc a0, %pcrel_hi(delay_time)
    lw    t2, %pcrel_lo(.L_delay)(a0)

delay_wait:
    addi t2, t2, -1
    bnez t2, delay_wait

    # Toggle s0 between 0x60004008 and 0x6000400C via XOR (0x08 ^ 0x04 = 0x0C)
    xori s0, s0, 4

    # Repeat endless loop
    j    blink_loop


# ---------------------------------------------------------
# 5. DATA SECTION (Constants & Variables)
# ---------------------------------------------------------
    .align 4
delay_time:
    .word DELAY                # CPU cycle counter threshold for blink delay

