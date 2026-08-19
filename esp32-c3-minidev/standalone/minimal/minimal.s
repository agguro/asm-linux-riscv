# =====================================================================
# Project:     Bare-Metal ESP32-C3 Assembly Minimal (Do-Nothing)
# Author:      agguro
# Date:        August 11, 2026
# Description: Pure assembly minimal template with watchdog and system init
# =====================================================================

.section .text
.option norelax
. = 0                    # Start counting cleanly at 0 for the flat binary

    # ---------------------------------------------------------
    # ESP32-C3 ROM IMAGE HEADER V2 (24 bytes)
    # The ESP32-C3 bootloader reads this fixed header from flash 
    # to know how to validate and load the image into memory.
    # ---------------------------------------------------------
    .byte 0xE9               # 0x00: Magic byte for ESP boot image
    .byte 1                  # 0x01: Number of segments
    .byte 2                  # 0x02: SPI mode (2 = DIO, crucial for embedded flash)
    .byte 0                  # 0x03: SPI speed/size (0 = 40MHz / 1MB)
    .word 0x40380000         # 0x04: Entry point address in IRAM
    .word 0                  # 0x08: WP pin / drive settings
    .half 5                  # 0x0C: Chip ID (ESP32-C3 = 5)
    .byte 0                  # 0x0E: Minimum chip revision
    .half 0                  # 0x0F: Min revision full
    .half 0                  # 0x11: Max revision full
    .half 0                  # 0x13: Reserved bytes
    .byte 0                  # 0x15: Append digest flag (0 = no SHA256)
    .byte 0, 0               # 0x16: Padding to make the header exactly 24 bytes

    # ---------------------------------------------------------
    # SEGMENT HEADER (8 bytes)
    # Defines the destination memory region for the binary payload.
    # ---------------------------------------------------------
    .word 0x40380000             # 0x18: Target load address in Instruction RAM (IRAM)
    .word _seg_end - _seg_start  # 0x1C: Dynamic segment length calculation

    # ---------------------------------------------------------
    # SEGMENT DATA - Starts correctly at 0x20
    # ---------------------------------------------------------
    .global _start
_seg_start:
_start:
    # ---------------------------------------------------------
    # 1. CPU & ENVIRONMENT INITIALIZATION
    # ---------------------------------------------------------
    # Block/disable all CPU interrupts during early boot setup
    csrci mstatus, 8

    # Set up the Stack Pointer (sp) to a safe RAM boundary (16-byte aligned, complies with RISC-V ABI)
    li   sp, 0x3FCE0000
    li   t2, 0x7FFFBBFF      # Bitmask used to clear watchdog write-protect bits

    # ---------------------------------------------------------
    # 2. WATCHDOG TIMER (WDT) & DEBUG DISABLE
    # Bare-metal code has no OS/FreeRTOS running, so we must disable 
    # all watchdogs immediately to prevent automatic hardware resets.
    # ---------------------------------------------------------

    # Disable Timer Group 0 (TG0) Watchdog
    li   t0, 0x6001F064      # TG0_WDT_PROTECT register
    li   t1, 0x50D83AA1      # WDT unlock key
    sw   t1, 0(t0)
    li   t0, 0x6001F048      # TG0_WDT_CONFIG0 register
    lw   t3, 0(t0)           # Use t3 to preserve WKEY in t1
    and  t3, t3, t2
    sw   t3, 0(t0)

    # Disable Timer Group 1 (TG1) Watchdog
    li   t0, 0x60020064      # TG1_WDT_PROTECT register
    sw   t1, 0(t0)           # t1 still holds WDT_WKEY (0x50D83AA1)
    li   t0, 0x60020048      # TG1_WDT_CONFIG0 register
    lw   t3, 0(t0)
    and  t3, t3, t2
    sw   t3, 0(t0)

    # Disable RTC Watchdog
    li   t0, 0x600080A8      # RTC_WDT_PROTECT register
    sw   t1, 0(t0)           # t1 still holds WDT_WKEY (0x50D83AA1)
    li   t0, 0x60008090      # RTC_WDT_CONFIG0 register
    lw   t3, 0(t0)
    and  t3, t3, t2
    sw   t3, 0(t0)

    # Disable Serial Wire Debug (SWD) / JTAG interference
    li   t0, 0x600080B8      # SWD_WPROTECT register
    li   t1, 0x8F1D312A      # SWD unlock key
    sw   t1, 0(t0)
    li   t0, 0x600080B4      # SWD_CONF register
    lw   t3, 0(t0)
    li   t4, 0x80000000
    or   t3, t3, t4
    sw   t3, 0(t0)

    # Disconnect USB PHY to ensure clean standalone execution
    li   t0, 0x6004301C      # USB_SERIAL_JTAG_CONF0 register
    li   t3, 0
    sw   t3, 0(t0)

    # ---------------------------------------------------------
    # 3. IDLE / HANG LOOP
    # ---------------------------------------------------------
hang:
    wfi                      # Wait for interrupt (low-power idle state)
    j    hang                # Infinite loop

_seg_end:

    # ---------------------------------------------------------
    # 4. ALIGN + CHECKSUM BYTE (handled by Makefile/Python script)
    # ---------------------------------------------------------
    .align 4
