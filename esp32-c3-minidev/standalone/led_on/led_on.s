# =====================================================================
# Project:     Bare-Metal ESP32-C3 Assembly LED On
# Author:      agguro
# Date:        August 11, 2026
# Description: Pure assembly bare-metal permanent LED ON on GPIO 8 for ESP32-C3
# =====================================================================

.section .text
.option norelax
. = 0                    # Start cleanly at 0 for the flat binary

    # ---------------------------------------------------------
    # ESP32-C3 ROM IMAGE HEADER V2 (24 bytes)
    # The ESP32-C3 bootloader reads this fixed header from flash 
    # to know how to validate and load the image into memory.
    # ---------------------------------------------------------
    .byte 0xE9               # 0x00: Magic byte for ESP boot image
    .byte 1                  # 0x01: Number of segments
    .byte 2                  # 0x02: SPI flash mode (2 = DIO)
    .byte 0                  # 0x03: SPI flash speed and size config
    .word 0x40380000         # 0x04: Entry point address in IRAM
    .word 0                  # 0x08: WP pin / drive settings
    .half 5                  # 0x0C: Chip ID (5 = ESP32-C3)
    .byte 0                  # 0x0E: Minimum chip revision
    .half 0                  # 0x0F: Min revision full
    .half 0                  # 0x11: Max revision full
    .half 0                  # 0x13: Reserved bytes
    .byte 0                  # 0x15: Append digest flag
    .byte 0, 0               # 0x16: Padding alignment bytes

    # ---------------------------------------------------------
    # SEGMENT HEADER (8 bytes)
    # Defines the destination memory region for the binary payload.
    # ---------------------------------------------------------
    .word 0x40380000         # 0x18: Target load address in Instruction RAM (IRAM)
    .word _seg_end - _seg_start  # 0x1C: Segment length

    # ---------------------------------------------------------
    # SEGMENT DATA (Main Entry Point)
    # ---------------------------------------------------------
    .global _start
_seg_start:
_start:
    # ---------------------------------------------------------
    # 1. CPU & ENVIRONMENT INITIALIZATION
    # ---------------------------------------------------------
    # Block/disable all CPU interrupts during early boot setup
    csrci mstatus, 8

    # Set up the Stack Pointer (sp) to a safe RAM boundary
    li   sp, 0x3FCE0000
    li   t2, 0x7FFFBBFF      # Bitmask used to clear watchdog write-protect bits

    # ---------------------------------------------------------
    # 2. WATCHDOG TIMER (WDT) & DEBUG DISABLE
    # Bare-metal code has no OS/FreeRTOS running, so we must disable 
    # all watchdogs immediately to prevent automatic hardware resets.
    # ---------------------------------------------------------

    # Disable Timer Group 0 (TG0) Watchdog
    li   t0, 0x6001F064      # WDT wprotect register
    li   t1, 0x50D83AA1      # Unlock magic key
    sw   t1, 0(t0)
    li   t0, 0x6001F048      # WDT config register
    lw   t3, 0(t0)
    and  t3, t3, t2
    sw   t3, 0(t0)

    # Disable Timer Group 1 (TG1) Watchdog
    li   t0, 0x60020064      # WDT wprotect register
    sw   t1, 0(t0)
    li   t0, 0x60020048      # WDT config register
    lw   t3, 0(t0)
    and  t3, t3, t2
    sw   t3, 0(t0)

    # Disable RTC Watchdog
    li   t0, 0x600080A8      # RTC WDT wprotect register
    sw   t1, 0(t0)
    li   t0, 0x60008090      # RTC WDT config register
    lw   t3, 0(t0)
    and  t3, t3, t2
    sw   t3, 0(t0)

    # Disable Serial Wire Debug (SWD) / JTAG interference
    li   t0, 0x600080B8
    li   t1, 0x8F1D312A      # SWD unlock key
    sw   t1, 0(t0)
    li   t0, 0x600080B4
    lw   t3, 0(t0)
    li   t4, 0x80000000
    or   t3, t3, t4
    sw   t3, 0(t0)

    # Disconnect USB PHY to ensure clean standalone execution
    li   t0, 0x6004301C
    li   t3, 0
    sw   t3, 0(t0)

    # ---------------------------------------------------------
    # 3. GPIO CONFIGURATION & PERMANENT LED ON
    # ---------------------------------------------------------
    # Configure GPIO 8 as an output using the Write-1-to-Set (W1TS) enable register
    li   t0, 0x60004024      # GPIO_ENABLE_W1TS_REG
    li   t1, 0x100           # Bit 8 for GPIO 8 (1 << 8 = 256 / 0x100)
    sw   t1, 0(t0)

    # Set GPIO 8 output low/high depending on board wiring (using clear/set register)
    li   s0, 0x6000400C      # GPIO_OUT_W1TC_REG (Clear register / active-low LED ON)
    sw   t1, 0(s0)           # Turn LED ON

    # ---------------------------------------------------------
    # 4. INFINITE HALT LOOP
    # ---------------------------------------------------------
hlt:
    j    hlt                 # Hang indefinitely; the LED remains permanently lit

_seg_end:
    .align 4
