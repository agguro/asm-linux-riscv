# =====================================================================
# Project:     Bare-Metal ESP32-C3 Assembly SSD1306 Framebuffer & LED ON
# Author:      agguro
# Date:        August 11, 2026
# Description: Pure assembly bare-metal driver to initialize SSD1306 OLED,
#              render a centered "FRAMEBUFFER" text from RAM, flush via 
#              I2C (SDA=GPIO5, SCL=GPIO6), and keep the LED on GPIO 8 permanently ON
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
    .byte 1                  # 0x01: Segment count
    .byte 2                  # 0x02: SPI mode (2 = DIO)
    .byte 0                  # 0x03: SPI speed/size
    .word 0x40380000         # 0x04: Entry point address in IRAM
    .word 0                  # 0x08: WP pin / drive settings
    .half 5                  # 0x0C: Chip ID (ESP32-C3 = 5)
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
    .word _seg_end - _seg_start  # 0x1C: Dynamic segment length calculation

    # ---------------------------------------------------------
    # SEGMENT DATA (Main Entry Point)
    # ---------------------------------------------------------
.global _start
_seg_start:
_start:
    # Block/disable all CPU interrupts during early boot setup
    csrci mstatus, 8

    # Set up the Stack Pointer (sp) to a safe RAM boundary
    li   sp, 0x3FCE0000
    li   t2, 0x7FFFBBFF      # Bitmask used to clear watchdog write-protect bits

    # =========================================================
    # BLOCK: WATCHDOG & DEBUG DISABLE INITIALIZATION
    # Disable all hardware watchdogs and JTAG/SWD interference
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

    # Disable Serial Wire Debug (SWD) / JTAG interference
    li   t0, 0x600080B8
    li   t1, 0x8F1D312A
    sw   t1, 0(t0)
    li   t0, 0x600080B4
    lw   t3, 0(t0)
    li   t4, 0x80000000
    or   t3, t3, t4
    sw   t3, 0(t0)

    # =========================================================
    # BLOCK: GPIO CONFIGURATION FOR I2C PINS
    # Configure SDA (GPIO 5) and SCL (GPIO 6) MUX and Open-Drain settings
    # =========================================================

    # Activate internal pull-ups for GPIO 5 and 6 via IO_MUX
    li   t0, 0x60009018      # IO_MUX_GPIO5_REG
    li   t1, (1 << 12) | (1 << 8)
    sw   t1, 0(t0)
    li   t0, 0x6000901C      # IO_MUX_GPIO6_REG
    sw   t1, 0(t0)

    # Configure GPIO 5 and 6 hardware as Open-Drain
    li   t0, 0x60004088      # GPIO_PIN5_REG
    li   t1, (1 << 2)
    sw   t1, 0(t0)
    li   t0, 0x6000408C      # GPIO_PIN6_REG
    sw   t1, 0(t0)

    # Set GPIO 5 and 6 as active outputs
    li   t0, 0x60004020      # GPIO_ENABLE_REG
    li   t1, (1 << 5) | (1 << 6)
    sw   t1, 0(t0)

    # Set initial state HIGH (released in open-drain, pulled up)
    li   s0, 0x60004008      # W1TS (Set High)
    li   s1, 0x6000400C      # W1TC (Set Low / Clear)
    li   t1, (1 << 5) | (1 << 6)
    sw   t1, 0(s0)

    # Short stabilization delay after boot
    li   t5, 500000
.L_boot_delay:
    li   t6, 1
    sub  t5, t5, t6
    bnez t5, .L_boot_delay


    # =========================================================
    # BLOCK: SSD1306 OLED INITIALIZATION SEQUENCE (72x40 I2C)
    # Loop through configuration table and send setup commands
    # =========================================================
.L_init_display:
    la   s4, ssd1306_init_cmds
    li   s5, 25              # Number of initialization bytes

.L_init_loop:
    beqz s5, .L_start_static
    lbu  a0, 0(s4)
    jal  ssd1306_send_cmd
    addi s4, s4, 1
    addi s5, s5, -1
    j    .L_init_loop


    # =========================================================
    # BLOCK: STATIC DISPLAY MAIN APPLICATION
    # Build framebuffer content and flush to OLED display RAM
    # =========================================================
.L_start_static:
    jal  build_static_screen
    jal  fb_flush
    j    main_loop


# =========================================================
# BLOCK: SOFTWARE I2C (BIT-BANGING) ROUTINES
# Low-level protocol control for custom SDA/SCL signal timing
# =========================================================
i2c_delay:
    li   t5, 40              # Stable delay loop for ~100kHz
.L_i2c_d:
    li   t6, 1
    sub  t5, t5, t6
    bnez t5, .L_i2c_d
    ret

sda_high:
    li   t0, 0x60004008      # W1TS
    li   t1, (1 << 5)
    sw   t1, 0(t0)
    ret

sda_low:
    li   t0, 0x6000400C      # W1TC
    li   t1, (1 << 5)
    sw   t1, 0(t0)
    ret

scl_high:
    li   t0, 0x60004008      # W1TS
    li   t1, (1 << 6)
    sw   t1, 0(t0)
    ret

scl_low:
    li   t0, 0x6000400C      # W1TC
    li   t1, (1 << 6)
    sw   t1, 0(t0)
    ret

i2c_start:
    addi sp, sp, -16
    sw   ra, 12(sp)
    jal  sda_high
    jal  scl_high
    jal  i2c_delay
    jal  sda_low
    jal  i2c_delay
    jal  scl_low
    jal  i2c_delay
    lw   ra, 12(sp)
    addi sp, sp, 16
    ret

i2c_stop:
    addi sp, sp, -16
    sw   ra, 12(sp)
    jal  sda_low
    jal  scl_high
    jal  i2c_delay
    jal  sda_high
    jal  i2c_delay
    lw   ra, 12(sp)
    addi sp, sp, 16
    ret

i2c_write_byte:
    addi sp, sp, -16
    sw   ra, 12(sp)
    sw   s2, 8(sp)
    mv   s2, a0
    li   t3, 8

.L_bit_loop:
    beqz t3, .L_write_ack
    andi t4, s2, 0x80
    bnez t4, .L_send_one
    jal  sda_low
    j    .L_clock_bit
.L_send_one:
    jal  sda_high

.L_clock_bit:
    jal  i2c_delay
    jal  scl_high
    jal  i2c_delay
    jal  scl_low
    jal  i2c_delay
    slli s2, s2, 1
    li   t6, 1
    sub  t3, t3, t6
    j    .L_bit_loop

.L_write_ack:
    jal  sda_high            # Release SDA (Slave pulls low for ACK)
    jal  i2c_delay
    jal  scl_high            # 9th clock pulse
    jal  i2c_delay
    jal  scl_low
    jal  i2c_delay
    lw   s2, 8(sp)
    lw   ra, 12(sp)
    addi sp, sp, 16
    ret


# =========================================================
# BLOCK: SSD1306 COMMAND WRAPPER
# Protocol wrapper to send single command bytes over I2C
# =========================================================
ssd1306_send_cmd:
    addi sp, sp, -16
    sw   ra, 12(sp)
    mv   a2, a0
    jal  i2c_start
    li   a0, 0x78            # Address 0x3C << 1 (Write)
    jal  i2c_write_byte
    li   a0, 0x80            # Control byte (Command stream format)
    jal  i2c_write_byte
    mv   a0, a2
    jal  i2c_write_byte
    jal  i2c_stop
    lw   ra, 12(sp)
    addi sp, sp, 16
    ret


# =========================================================
# ROUTINE: BUILD STATIC SCREEN
# Clear framebuffer to black and copy centered font data
# =========================================================
build_static_screen:
    addi sp, sp, -16
    sw   ra, 12(sp)
    sw   s2, 8(sp)
    sw   s3, 4(sp)

    # 1. Clear framebuffer buffer to 0 (Black)
    la   t0, framebuffer
    li   t1, 360
    li   t3, 0
.L_clr_fb:
    sb   t3, 0(t0)
    addi t0, t0, 1
    addi t1, t1, -1
    bnez t1, .L_clr_fb

    # 2. Copy "FRAMEBUFFER" text data to center (Page 2, Column 2)
    la   t0, framebuffer
    li   t1, 144             # Page 2 start offset (2 * 72)
    add  t0, t0, t1
    addi t0, t0, 2           # Column 2 offset (centered for 68 bytes on 72-width)

    la   t1, text_framebuffer
    li   t2, 68              # Total font payload bytes
.L_copy_txt:
    beqz t2, .L_copy_done
    lbu  t3, 0(t1)
    sb   t3, 0(t0)
    addi t1, t1, 1
    addi t0, t0, 1
    addi t2, t2, -1
    j    .L_copy_txt

.L_copy_done:
    lw   s3, 4(sp)
    lw   s2, 8(sp)
    lw   ra, 12(sp)
    addi sp, sp, 16
    ret


# =========================================================
# ROUTINE: FRAMEBUFFER FLUSH
# Transfer entire RAM framebuffer buffer via I2C to display RAM
# =========================================================
fb_flush:
    addi sp, sp, -16
    sw   ra, 12(sp)
    sw   s2, 8(sp)
    sw   s3, 4(sp)

    li   a0, 0x21
    jal  ssd1306_send_cmd
    li   a0, 28
    jal  ssd1306_send_cmd
    li   a0, 99
    jal  ssd1306_send_cmd

    li   a0, 0x22
    jal  ssd1306_send_cmd
    li   a0, 0x00
    jal  ssd1306_send_cmd
    li   a0, 0x04
    jal  ssd1306_send_cmd

    jal  i2c_start
    li   a0, 0x78
    jal  i2c_write_byte
    li   a0, 0x40
    jal  i2c_write_byte

    la   s2, framebuffer
    li   s3, 360
.L_flush_loop:
    beqz s3, .L_flush_done
    lbu  a0, 0(s2)
    jal  i2c_write_byte
    addi s2, s2, 1
    addi s3, s3, -1
    j    .L_flush_loop

.L_flush_done:
    jal  i2c_stop
    lw   s3, 4(sp)
    lw   s2, 8(sp)
    lw   ra, 12(sp)
    addi sp, sp, 16
    ret


# =========================================================
# BLOCK: MAIN EXECUTION LOOP & PERMANENT LED ON
# Enable GPIO 8 output, turn active-low LED ON permanently, and halt
# =========================================================
main_loop:
    li   t0, 0x60004020      # GPIO_ENABLE_REG (Enable output for GPIO 8)
    li   t1, (1 << 8)
    sw   t1, 0(t0)

    li   t1, 0x100           # Bit 8 for GPIO 8 LED
    li   s0, 0x6000400C      # GPIO_OUT_W1TC_REG (Clear / Pull Low to turn LED ON)
    sw   t1, 0(s0)

hang:
    j    hang                # Infinite halt loop


# =========================================================
# BLOCK: DATA SECTION
# Constants and font payload byte arrays for the display
# =========================================================
    .align 4
ssd1306_init_cmds:
    .byte 0xAE       # Display OFF
    .byte 0xD5, 0x80 # Set display clock divide ratio/oscillator frequency
    .byte 0xA8, 0x27 # Set multiplex ratio (40 rows)
    .byte 0xD3, 0x00 # Set display offset
    .byte 0x40       # Set start line address
    .byte 0x8D, 0x14 # Charge pump setting (Enable charge pump during display on)
    .byte 0x20, 0x00 # Set memory addressing mode (0x00 = horizontal mode)
    .byte 0xA1       # Set segment re-map (column address 0 mapped to seg 127)
    .byte 0xC8       # Set COM output scan direction
    .byte 0xDA, 0x12 # Set COM pins hardware configuration
    .byte 0x81, 0xCF # Set contrast control register
    .byte 0xD9, 0xF1 # Set pre-charge period
    .byte 0xDB, 0x40 # Set VCOMH deselect level
    .byte 0xA4       # Entire display on (resume to RAM content)
    .byte 0xA6       # Set normal display (not inverted)
    .byte 0xAF       # Display ON

# Font data for "FRAMEBUFFER" (68 bytes)
    .align 4
text_framebuffer:   
    .byte 0x00, 0x7F, 0x09, 0x09, 0x01, 0x00               # F
    .byte 0x00, 0x7F, 0x09, 0x19, 0x66, 0x00               # R
    .byte 0x00, 0x7C, 0x12, 0x11, 0x12, 0x7C, 0x00         # A
    .byte 0x00, 0x7F, 0x02, 0x04, 0x02, 0x7F, 0x00         # M
    .byte 0x00, 0x7F, 0x49, 0x49, 0x41, 0x00               # E
    .byte 0x00, 0x7F, 0x49, 0x49, 0x36, 0x00               # B
    .byte 0x00, 0x3F, 0x40, 0x40, 0x3F, 0x00               # U
    .byte 0x00, 0x7F, 0x09, 0x09, 0x01, 0x00               # F
    .byte 0x00, 0x7F, 0x09, 0x09, 0x01, 0x00               # F
    .byte 0x00, 0x7F, 0x49, 0x49, 0x41, 0x00               # E
    .byte 0x00, 0x7F, 0x09, 0x19, 0x66, 0x00               # R

# Framebuffer allocation in RAM (360 bytes)
    .section .bss
    .align 4
framebuffer:
    .skip 360

_seg_end:
    .align 4
