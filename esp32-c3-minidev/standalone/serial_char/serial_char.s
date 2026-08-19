# =====================================================================
# Project:     Bare-Metal ESP32-C3 Assembly USB-Serial Transmit & LED ON
# Author:      agguro
# Date:        August 11, 2026
# Description: Pure assembly bare-metal driver to initialize ESP32-C3,
#              disable watchdogs, enable the USB-Serial-JTAG peripheral,
#              turn the status LED on GPIO 8 permanently ON, and 
#              continuously transmit the character 'A' over the USB serial FIFO.
# =====================================================================

.section .text
.option norelax
. = 0                    # Start counting cleanly at 0 for the flat binary

    # ---------------------------------------------------------
    # ESP32-C3 ROM IMAGE HEADER V2 (24 bytes)
    # The ESP32-C3 bootloader reads this fixed header from flash 
    # to validate and load the binary image into instruction RAM.
    # ---------------------------------------------------------
    .byte 0xE9               # 0x00: Magic byte for ESP boot image
    .byte 1                  # 0x01: Segment count
    .byte 2                  # 0x02: SPI mode (2 = DIO, crucial for embedded flash)
    .byte 0                  # 0x03: SPI speed/size (0 = 40MHz / 1MB)
    .word 0x40380000         # 0x04: Entry point address in Instruction RAM (IRAM)
    .word 0                  # 0x08: Write-protect pin / drive settings
    .half 5                  # 0x0C: Chip ID (ESP32-C3 = 5)
    .byte 0                  # 0x0E: Minimum chip revision
    .half 0                  # 0x0F: Min revision full
    .half 0                  # 0x11: Max revision full
    .half 0                  # 0x13: Reserved bytes
    .byte 0                  # 0x15: Append digest flag (0 = no SHA256)
    .byte 0, 0               # 0x16: Padding to make the header exactly 24 bytes

    # ---------------------------------------------------------
    # SEGMENT HEADER (8 bytes)
    # Defines the destination memory region and size for the binary payload.
    # ---------------------------------------------------------
    .word 0x40380000         # 0x18: Target load address in IRAM
    .word _seg_end - _seg_start  # 0x1C: Dynamic segment length calculation

    # ---------------------------------------------------------
    # SEGMENT DATA (Main Entry Point)
    # ---------------------------------------------------------
.global _start
_seg_start:
_start:
    # Block/disable all CPU interrupts during early bare-metal setup
    csrci mstatus, 8

    # Set up the Stack Pointer (sp) to 16-byte aligned RAM boundary
    li   sp, 0x3FCE0000
    li   t2, 0x7FFFBBFF      # Bitmask used to clear watchdog write-protect bits

    # =========================================================
    # BLOCK: WATCHDOG & DEBUG DISABLE INITIALIZATION
    # Disable all hardware watchdogs (TG0, TG1, RTC) and JTAG/SWD interference
    # =========================================================

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

    # Disable Serial Wire Debug (SWD) / JTAG interface interference
    li   t0, 0x600080B8
    li   t1, 0x8F1D312A
    sw   t1, 0(t0)
    li   t0, 0x600080B4
    lw   t3, 0(t0)
    li   t4, 0x80000000
    or   t3, t3, t4
    sw   t3, 0(t0)

    # =========================================================
    # BLOCK: ENABLE USB-SERIAL/JTAG PERIPHERAL
    # Release matrix reset and enable USB pads
    # =========================================================
    li   t0, 0x6004301C      # USB_SERIAL_JTAG_CONF0
    li   t1, 0x00000002      # Bit 1: USB pad enable / release matrix reset
    sw   t1, 0(t0)
    
    # =========================================================
    # BLOCK: GPIO 8 SETUP & PERMANENT LED ON
    # Enable output for GPIO 8 and turn active-low LED ON permanently
    # =========================================================
    li   t0, 0x60004024      # GPIO_ENABLE_W1TS_REG (Enable output for GPIO 8)
    li   t1, 0x100           # Bit 8 for GPIO 8
    sw   t1, 0(t0)

    li   s1, 0x6000400C      # GPIO_OUT_W1TC_REG (Set Low / Clear to turn LED ON)
    sw   t1, 0(s1)           # Turn LED ON permanently

    # =========================================================
    # MAIN LOOP: TRANSMIT CHARACTER 'A' OVER USB FIFO
    # =========================================================
main_loop:
    # Load character 'A' (0x41) directly into register
    li   a1, 0x41

    # Wait until USB FIFO has space (Bit 1 of EP1_CONF_REG == 1)
    li   t0, 0x60043004      
wait_fifo:
    lw   t1, 0(t0)           
    andi t2, t1, 2           
    beqz t2, wait_fifo       

    # Write the byte to the USB TX FIFO
    li   t3, 0x60043000      
    sw   a1, 0(t3)           

    # Flush the FIFO to send the byte (Write 1 to Bit 0: WR_DONE)
    li   t2, 1
    sw   t2, 0(t0)

    j    main_loop
    
_seg_end:

    # ---------------------------------------------------------
    # ALIGNMENT
    # ---------------------------------------------------------
    .align 4
