# =====================================================================
# Project:     Bare-Metal ESP32-C3 Assembly SSD1306 OLED & I2C Driver
# Author:      agguro
# Date:        August 11, 2026
# Description: Pure assembly bare-metal driver for SSD1306 OLED display 
#              via bit-banged I2C (SDA=GPIO5, SCL=GPIO6) with LED on GPIO8
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
    .word 0x40380000             # 0x18: Target load address in Instruction RAM (IRAM)
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
    # Configure SDA (GPIO 5) and SCL (GPIO 6) MUX settings
    # =========================================================
    li   t0, 0x60009018      # IO_MUX_GPIO5_REG (SDA)
    li   t1, (1 << 12) | (1 << 8)
    sw   t1, 0(t0)
    li   t0, 0x6000901C      # IO_MUX_GPIO6_REG (SCL)
    sw   t1, 0(t0)

    li   t0, 0x60004088      # GPIO_PIN5_REG (Pull-up / Open-drain configuration)
    li   t1, (1 << 2)
    sw   t1, 0(t0)
    li   t0, 0x6000408C      # GPIO_PIN6_REG
    sw   t1, 0(t0)

    # Boot stabilization delay for display power-up
    li   t5, 500000
.L_boot_delay:
    li   t6, 1
    sub  t5, t5, t6
    bnez t5, .L_boot_delay


    # =========================================================
    # BLOCK: SSD1306 OLED INITIALIZATION SEQUENCE
    # Iterate through command table and send setup bytes over I2C
    # =========================================================
.L_init_display:
    la   s4, ssd1306_init_cmds
    li   s5, 25

.L_init_loop:
    beqz s5, .L_do_clear
    lbu  a0, 0(s4)
    jal  ssd1306_send_cmd
    addi s4, s4, 1
    addi s5, s5, -1
    j    .L_init_loop


    # =========================================================
    # BLOCK: SCREEN CLEAR & BORDER RENDERING
    # Fill RAM buffer with zeros and draw the visual boundary frame
    # =========================================================
.L_do_clear:
    li   a0, 0x00
    jal  oled_fill_screen

    jal  draw_screen_border


    # =========================================================
    # BLOCK: MAIN EXECUTION LOOP & LED ON
    # Enable GPIOs, turn LED ON permanently, and hang
    # =========================================================
main_loop:
    li   t0, 0x60004020      # GPIO_ENABLE_REG (Enable output for pins 5, 6, 8)
    li   t1, (1 << 5) | (1 << 6) | (1 << 8)
    sw   t1, 0(t0)

    li   t1, 0x100           # Bit 8 for GPIO 8 LED
    li   s0, 0x6000400C      # GPIO_OUT_W1TC_REG (Set Low / Clear to turn LED ON)
    sw   t1, 0(s0)

hang:
    j    hang                # Infinite halt loop


# =========================================================
# ROUTINE: ABI-PROOF OLED FILL SCREEN
# Clears or fills the active display RAM area
# =========================================================
oled_fill_screen:
    addi sp, sp, -16
    sw   ra, 12(sp)
    sw   s4, 8(sp)
    sw   s3, 4(sp)
    mv   s4, a0

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

    li   s3, 360
.L_fill_loop:
    beqz s3, .L_fill_done
    mv   a0, s4
    jal  i2c_write_byte
    li   t6, 1
    sub  s3, s3, t6
    j    .L_fill_loop

.L_fill_done:
    jal  i2c_stop
    lw   s3, 4(sp)
    lw   s4, 8(sp)
    lw   ra, 12(sp)
    addi sp, sp, 16
    ret


# =========================================================
# ROUTINE: ABI-PROOF DRAW SCREEN BORDER (72x40)
# Draws structural frame bytes around screen edges
# =========================================================
draw_screen_border:
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

    li   s3, 0               # Page loop index (0 to 4)
.L_page_loop:
    li   s2, 0               # Column loop index (0 to 71)

.L_col_loop:
    li   t0, 0
    beq  s3, t0, .L_is_top_page
    li   t0, 4
    beq  s3, t0, .L_is_bottom_page

    li   t0, 0
    beq  s2, t0, .L_side_edge
    li   t0, 71
    beq  s2, t0, .L_side_edge
    li   a0, 0x00
    j    .L_send_border_byte

.L_side_edge:
    li   a0, 0xFF
    j    .L_send_border_byte

.L_is_top_page:
    li   t0, 0
    beq  s2, t0, .L_side_edge
    li   t0, 71
    beq  s2, t0, .L_side_edge
    li   a0, 0x01
    j    .L_send_border_byte

.L_is_bottom_page:
    li   t0, 0
    beq  s2, t0, .L_side_edge
    li   t0, 71
    beq  s2, t0, .L_side_edge
    li   a0, 0x80

.L_send_border_byte:
    jal  i2c_write_byte

    addi s2, s2, 1
    li   t0, 72
    bne  s2, t0, .L_col_loop

    addi s3, s3, 1
    li   t0, 5
    bne  s3, t0, .L_page_loop

    jal  i2c_stop
    lw   s3, 4(sp)
    lw   s2, 8(sp)
    lw   ra, 12(sp)
    addi sp, sp, 16
    ret


# =========================================================
# BLOCK: SOFTWARE I2C (BIT-BANGING) ROUTINES
# Low-level signal timing for custom SDA/SCL protocol control
# =========================================================
i2c_delay:
    li   t5, 40
.L_i2c_d:
    li   t6, 1
    sub  t5, t5, t6
    bnez t5, .L_i2c_d
    ret

sda_high:
    li   t0, 0x60004008
    li   t1, (1 << 5)
    sw   t1, 0(t0)
    ret

sda_low:
    li   t0, 0x6000400C
    li   t1, (1 << 5)
    sw   t1, 0(t0)
    ret

scl_high:
    li   t0, 0x60004008
    li   t1, (1 << 6)
    sw   t1, 0(t0)
    ret

scl_low:
    li   t0, 0x6000400C
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
    jal  sda_high
    jal  i2c_delay
    jal  scl_high
    jal  i2c_delay
    jal  scl_low
    jal  i2c_delay
    lw   s2, 8(sp)
    lw   ra, 12(sp)
    addi sp, sp, 16
    ret


# =========================================================
# BLOCK: SSD1306 HIGH-LEVEL HELPERS
# Protocol wrappers for sending commands and data streams
# =========================================================
ssd1306_send_cmd:
    addi sp, sp, -16
    sw   ra, 12(sp)
    mv   a2, a0
    jal  i2c_start
    li   a0, 0x78
    jal  i2c_write_byte
    li   a0, 0x80
    jal  i2c_write_byte
    mv   a0, a2
    jal  i2c_write_byte
    jal  i2c_stop
    lw   ra, 12(sp)
    addi sp, sp, 16
    ret

ssd1306_send_data_stream:
    addi sp, sp, -16
    sw   ra, 12(sp)
    sw   s2, 8(sp)
    sw   s3, 4(sp)
    mv   s2, a0
    mv   s3, a1
    jal  i2c_start
    li   a0, 0x78
    jal  i2c_write_byte
    li   a0, 0x40
    jal  i2c_write_byte
.L_stream_data_loop:
    beqz s3, .L_stream_data_done
    lbu  a0, 0(s2)
    jal  i2c_write_byte
    addi s2, s2, 1
    li   t6, 1
    sub  s3, s3, t6
    j    .L_stream_data_loop
.L_stream_data_done:
    jal  i2c_stop
    lw   s3, 4(sp)
    lw   s2, 8(sp)
    lw   ra, 12(sp)
    addi sp, sp, 16
    ret


# =========================================================
# BLOCK: DATA SECTION
# Constants and initialization byte arrays for the display
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

_seg_end:
    .align 4
