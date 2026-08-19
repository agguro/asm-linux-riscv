# =====================================================================
# Project:     Bare-Metal ESP32-C3 Assembly SSD1306 Downward Scroll
# Name:        oled_scroll_vertical_down
# Author:      agguro
# Date:        August 15, 2026
# Description: Pure assembly driver to initialize SSD1306 OLED, 
#              copy static data, and perform continuous downward 
#              byte-level scrolling with carry propagation.
# =====================================================================

.section .text
.option norelax
. = 0                  # Start at address 0

    # ---------------------------------------------------------
    # ESP32-C3 ROM IMAGE HEADER
    # ---------------------------------------------------------
    .byte 0xE9
    .byte 1
    .byte 2
    .byte 0
    .word 0x40380000
    .word 0
    .half 5
    .byte 0
    .half 0
    .half 0
    .half 0
    .byte 0
    .byte 0, 0

    .word 0x40380000
    .word _seg_end - _seg_start

.global _start
.global _seg_start
_seg_start:
_start:
    # Disable CPU interrupts
    csrci mstatus, 8

    # Initialize Stack Pointer
    li   sp, 0x3FCE0000
    li   t2, 0x7FFFBBFF

    # =========================================================
    # DISABLE WATCHDOG TIMERS
    # =========================================================
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

    # Disable JTAG/SWD
    li   t0, 0x600080B8
    li   t1, 0x8F1D312A
    sw   t1, 0(t0)
    li   t0, 0x600080B4
    lw   t3, 0(t0)
    li   t4, 0x80000000
    or   t3, t3, t4
    sw   t3, 0(t0)

    # =========================================================
    # GPIO CONFIGURATION
    # =========================================================
    # Set SDA and SCL pull-ups
    li   t0, 0x60009018
    li   t1, (1 << 12) | (1 << 8)
    sw   t1, 0(t0)
    li   t0, 0x6000901C
    sw   t1, 0(t0)

    # Set as Open-Drain
    li   t0, 0x60004088
    li   t1, (1 << 2)
    sw   t1, 0(t0)
    li   t0, 0x6000408C
    sw   t1, 0(t0)

    # Enable outputs (GPIO 5, 6, 8)
    li   t0, 0x60004020
    li   t1, (1 << 5) | (1 << 6) | (1 << 8)
    sw   t1, 0(t0)

    # Set I2C pins High
    li   s0, 0x60004008
    li   s1, 0x6000400C
    li   t1, (1 << 5) | (1 << 6)
    sw   t1, 0(s0)

    # Stabilization delay
    li   t5, 500000
.L_boot_delay:
    li   t6, 1
    sub  t5, t5, t6
    bnez t5, .L_boot_delay

    # =========================================================
    # INITIALIZE DISPLAY
    # =========================================================
.L_init:
    la   s4, ssd1306_init_cmds
    li   s5, 25
.L_init_loop:
    beqz s5, .L_init_complete
    lbu  a0, 0(s4)
    jal  ssd1306_send_cmd
    addi s4, s4, 1
    addi s5, s5, -1
    j    .L_init_loop

.L_init_complete:
    # Copy source to framebuffer
    la   t0, v_text_source
    la   t1, framebuffer
    li   t2, 360
.L_copy:
    beqz t2, main_loop
    lbu  t3, 0(t0)
    sb   t3, 0(t1)
    addi t0, t0, 1
    addi t1, t1, 1
    addi t2, t2, -1
    j    .L_copy

main_loop:
    # LED ON (active low)
    li   t1, 0x100
    sw   t1, 0(s1)

    jal  scroll_down_step
    jal  fb_flush

    # LED OFF
    sw   t1, 0(s0)

    # Frame delay
    li   t5, 40000
.L_delay:
    li   t6, 1
    sub  t5, t5, t6
    bnez t5, .L_delay
    j    main_loop

# =========================================================
# ROUTINE: SCROLL_DOWN_STEP
# Shifts bits left (Downward scroll) with carry propagation
# =========================================================
scroll_down_step:
    addi sp, sp, -16
    sw   ra, 12(sp)
    sw   s2, 8(sp)
    sw   s3, 4(sp)
    sw   s4, 0(sp)

    li   s3, 0                       # Column loop 0-71
.L_col_loop:
    li   t0, 72
    bge  s3, t0, .L_col_done

    # Page 0 address
    la   t1, framebuffer
    add  t1, t1, s3

    # Calculate wraparound carry (Bit 7 of Page 4 -> Page 0)
    la   t5, framebuffer
    add  t5, t5, s3
    addi t5, t5, 288
    lbu  t5, 0(t5)
    andi s4, t5, 0x80
    srli s4, s4, 7

    # Loop 5 pages (Page 0 to 4)
    li   s2, 5
.L_pg_loop:
    lbu  t0, 0(t1)
    andi t2, t0, 0x80                # Extract bit 7 (carry out)
    srli t2, t2, 7                   # Prepare carry for next page
    slli t0, t0, 1                   # Shift left (Downwards)
    or   t0, t0, s4                  # Apply carry from above
    sb   t0, 0(t1)
    mv   s4, t2
    addi t1, t1, 72
    addi s2, s2, -1
    bnez s2, .L_pg_loop

    addi s3, s3, 1
    j    .L_col_loop

.L_col_done:
    lw   s4, 0(sp)
    lw   s3, 4(sp)
    lw   s2, 8(sp)
    lw   ra, 12(sp)
    addi sp, sp, 16
    ret

# =========================================================
# UTILITIES: FRAMEBUFFER & I2C
# =========================================================
fb_flush:
    addi sp, sp, -16
    sw   ra, 12(sp)
    sw   s2, 8(sp)
    sw   s3, 4(sp)
    
    li   a0, 0x21; jal ssd1306_send_cmd
    li   a0, 28;   jal ssd1306_send_cmd
    li   a0, 99;   jal ssd1306_send_cmd
    li   a0, 0x22; jal ssd1306_send_cmd
    li   a0, 0x00; jal ssd1306_send_cmd
    li   a0, 0x04; jal ssd1306_send_cmd
    
    jal  i2c_start
    li   a0, 0x78; jal i2c_write_byte
    li   a0, 0x40; jal i2c_write_byte
    
    la   s2, framebuffer
    li   s3, 360
.L_flush_loop:
    beqz s3, .L_flush_end
    lbu  a0, 0(s2)
    jal  i2c_write_byte
    addi s2, s2, 1
    addi s3, s3, -1
    j    .L_flush_loop
.L_flush_end:
    jal  i2c_stop
    lw   s3, 4(sp)
    lw   s2, 8(sp)
    lw   ra, 12(sp)
    addi sp, sp, 16
    ret

i2c_delay:
    li   t5, 40
.L_dly:
    li   t6, 1
    sub  t5, t5, t6
    bnez t5, .L_dly
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
    addi sp, sp, -16; sw ra, 12(sp)
    jal  sda_high; jal scl_high; jal i2c_delay
    jal  sda_low; jal i2c_delay; jal scl_low; jal i2c_delay
    lw   ra, 12(sp); addi sp, sp, 16; ret

i2c_stop:
    addi sp, sp, -16; sw ra, 12(sp)
    jal  sda_low; jal scl_high; jal i2c_delay
    jal  sda_high; jal i2c_delay
    lw   ra, 12(sp); addi sp, sp, 16; ret

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
    j    .L_bit_check
.L_send_one:
    jal  sda_high
.L_bit_check:
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

# =========================================================
# BLOCK: DATA & BSS SECTION
# Constants, initialization arrays, and scroll source font data
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

    .align 4
v_text_source:
    .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    .byte 0x00, 0x46, 0x49, 0x49, 0x31, 0x00, 0x00, 0x3E, 0x41, 0x41, 0x22, 0x00, 0x00, 0x7F, 0x09, 0x19, 0x66, 0x00, 0x00, 0x3E, 0x41, 0x41, 0x3E, 0x00, 0x00, 0x7F, 0x40, 0x40, 0x40, 0x00, 0x00, 0x7F, 0x40, 0x40, 0x40, 0x00, 0x00, 0x41, 0x7F, 0x41, 0x00, 0x00, 0x7F, 0x02, 0x04, 0x7F, 0x00, 0x00, 0x3E, 0x41, 0x49, 0x3A, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00

    .section .bss
    .align 4
framebuffer:
    .skip 360

_seg_end:
    .align 4
