# =====================================================================
# Project:     Bare-Metal ESP32-C3 Assembly SSD1306 Text Scroller & LED
# Name:        oled_scroll_horizontal_left
# Author:      agguro
# Date:        August 11, 2026
# Description: Pure assembly bare-metal driver to initialize SSD1306 OLED,
#              render a smooth pixel-based scrolling text engine from 
#              a virtual source buffer, flush via I2C (SDA=GPIO5, SCL=GPIO6), 
#              and control the status LED on GPIO 8.
#
# Copyright 2026 agguro
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# =====================================================================

.section .text
.option norelax
. = 0                  # Start cleanly at address 0 for the flat binary payload

    # ---------------------------------------------------------
    # ESP32-C3 ROM IMAGE HEADER V2 (24 bytes)
    # Required by the ESP32-C3 internal bootloader for validation.
    # ---------------------------------------------------------
    .byte 0xE9             # 0x00: Magic byte for ESP boot image
    .byte 1                # 0x01: Number of loadable segments
    .byte 2                # 0x02: SPI mode (2 = DIO)
    .byte 0                # 0x03: SPI speed/size configuration
    .word 0x40380000       # 0x04: Entry point execution address in IRAM
    .word 0                # 0x08: WP pin and drive settings
    .half 5                # 0x0C: Chip ID (ESP32-C3 = 5)
    .byte 0                # 0x0E: Minimum chip revision
    .half 0                # 0x0F: Minimum full revision
    .half 0                # 0x11: Maximum full revision
    .half 0                # 0x13: Reserved alignment bytes
    .byte 0                # 0x15: Append digest flag
    .byte 0, 0             # 0x16: Padding and alignment bytes

    # ---------------------------------------------------------
    # SEGMENT HEADER (8 bytes)
    # Defines the target memory destination and binary size.
    # ---------------------------------------------------------
    .word 0x40380000       # 0x18: Target load address in Instruction RAM (IRAM)
    .word _seg_end - _seg_start  # 0x1C: Dynamic segment length calculation

    # ---------------------------------------------------------
    # SEGMENT DATA (Main Entry Point)
    # ---------------------------------------------------------
.global _start
.global _seg_start
_seg_start:
_start:
    # Disable all CPU interrupts during early hardware initialization
    csrci mstatus, 8

    # Set up Stack Pointer (sp) to a safe boundary in high internal RAM
    li   sp, 0x3FCE0000
    li   t2, 0x7FFFBBFF      # Bitmask to clear watchdog write-protection bits

    # =========================================================
    # BLOCK: WATCHDOG & DEBUG INTERFERENCE DISABLE
    # =========================================================

    # Disable Timer Group 0 (TG0) Watchdog Timer
    li   t0, 0x6001F064
    li   t1, 0x50D83AA1
    sw   t1, 0(t0)
    li   t0, 0x6001F048
    lw   t3, 0(t0)
    and  t3, t3, t2
    sw   t3, 0(t0)

    # Disable Timer Group 1 (TG1) Watchdog Timer
    li   t0, 0x60020064
    li   t1, 0x50D83AA1
    sw   t1, 0(t0)
    li   t0, 0x60020048
    lw   t3, 0(t0)
    and  t3, t3, t2
    sw   t3, 0(t0)

    # Disable RTC System Watchdog Timer
    li   t0, 0x600080A8
    li   t1, 0x50D83AA1
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
    # BLOCK: GPIO CONFIGURATION FOR I2C & STATUS LED
    # =========================================================

    # Configure IO_MUX pull-ups for SDA (GPIO 5) and SCL (GPIO 6)
    li   t0, 0x60009018
    li   t1, (1 << 12) | (1 << 8)
    sw   t1, 0(t0)
    li   t0, 0x6000901C
    li   t1, (1 << 12) | (1 << 8)
    sw   t1, 0(t0)

    # Set GPIO 5 and 6 as Open-Drain drivers
    li   t0, 0x60004088
    li   t1, (1 << 2)
    sw   t1, 0(t0)
    li   t0, 0x6000408C
    li   t1, (1 << 2)
    sw   t1, 0(t0)

    # Enable outputs for SDA (GPIO 5), SCL (GPIO 6), and LED (GPIO 8)
    li   t0, 0x60004020
    li   t1, (1 << 5) | (1 << 6) | (1 << 8)
    sw   t1, 0(t0)

    # Drive I2C data/clock lines HIGH initially (open-drain released)
    li   s0, 0x60004008
    li   s1, 0x6000400C
    li   t1, (1 << 5) | (1 << 6)
    sw   t1, 0(s0)

    # Short stabilization delay after display power-up
    li   t5, 500000
.L_boot_delay:
    li   t6, 1
    sub  t5, t5, t6
    bnez t5, .L_boot_delay


    # =========================================================
    # BLOCK: SSD1306 OLED INITIALIZATION SEQUENCE
    # =========================================================
.L_init_display:
    la   s4, ssd1306_init_cmds
    li   s5, 25

.L_init_loop:
    beqz s5, .L_start_scroller
    lbu  a0, 0(s4)
    jal  ssd1306_send_cmd
    addi s4, s4, 1
    addi s5, s5, -1
    j    .L_init_loop


    # =========================================================
    # BLOCK: SCROLLER MAIN APPLICATION
    # =========================================================
.L_start_scroller:
    li   s6, 0               # s6 = scroll offset (starts at pixel 0)

scroll_loop:
    # Turn status LED ON per frame (active low on GPIO 8)
    li   t1, 0x100
    sw   t1, 0(s1)

    # Render running text into framebuffer based on scroll offset s6
    mv   a0, s6
    jal  render_scroller_frame

    # Send framebuffer to OLED display over I2C
    jal  fb_flush

    # Turn status LED OFF
    li   t1, 0x100
    sw   t1, 0(s0)

    # Increment scroll offset for next frame (shift 1 pixel left)
    addi s6, s6, 1
    li   t0, 72              # Total width of our scroll buffer is 72 columns
    bne  s6, t0, .L_skip_reset
    li   s6, 0               # Wrap around offset when reaching the end
.L_skip_reset:

    # Animation delay loop for scroller speed control
    li   t5, 30000
.L_scroll_delay:
    li   t6, 1
    sub  t5, t5, t6
    bnez t5, .L_scroll_delay

    j    scroll_loop


# =========================================================
# ROUTINE: RENDER SCROLLER FRAME
# Pixel-based horizontal shifting routine: a0 = scroll_offset (s6)
# =========================================================
render_scroller_frame:
    addi sp, sp, -32
    sw   ra, 28(sp)
    sw   s2, 24(sp)
    sw   s3, 20(sp)
    sw   s4, 16(sp)
    sw   s5, 12(sp)
    mv   s2, a0              # s2 = scroll offset

    # Fill all 5 pages of the screen (Page 0 to 4)
    li   s3, 0               # s3 = current page index (0 to 4)

.L_page_blit_loop:
    # Calculate RAM target address for this page in framebuffer
    la   t0, framebuffer
    li   t1, 72
    mul  t2, s3, t1
    add  s4, t0, t2          # s4 = pointer to start of this page in framebuffer

    # Loop over all 72 columns of the screen
    li   s5, 0               # s5 = column counter (0 to 71)

.L_col_blit_loop:
    # Calculate column index to fetch from scroll_source table:
    # index = (column + scroll_offset) % 72
    add  t3, s5, s2          # column + offset
    li   t4, 72
    remu t3, t3, t4          # modulo 72 (wrap around)

    # Fetch correct byte from scroll_source table based on page (s3) and computed column (t3)
    la   t5, scroll_source
    li   t1, 72
    mul  t6, s3, t1          # page offset in scroll_source
    add  t5, t5, t6
    add  t5, t5, t3          # definitive byte address
    lbu  t0, 0(t5)           # load byte

    # Store byte into active framebuffer
    sb   t0, 0(s4)

    # Advance to next column
    addi s4, s4, 1
    addi s5, s5, 1
    li   t1, 72
    bne  s5, t1, .L_col_blit_loop

    # Advance to next page
    addi s3, s3, 1
    li   t1, 5
    bne  s3, t1, .L_page_blit_loop

    lw   s5, 12(sp)
    lw   s4, 16(sp)
    lw   s3, 20(sp)
    lw   s2, 24(sp)
    lw   ra, 28(sp)
    addi sp, sp, 32
    ret


# =========================================================
# BLOCK: FRAMEBUFFER FLUSH ROUTINE
# Transfers local 360-byte RAM buffer to SSD1306 GDDRAM
# =========================================================
fb_flush:
    addi sp, sp, -16
    sw   ra, 12(sp)
    sw   s2, 8(sp)
    sw   s3, 4(sp)

    # Set horizontal column address window (columns 28 to 99)
    li   a0, 0x21
    jal  ssd1306_send_cmd
    li   a0, 28
    jal  ssd1306_send_cmd
    li   a0, 99
    jal  ssd1306_send_cmd

    # Set page address window (pages 0 to 4)
    li   a0, 0x22
    jal  ssd1306_send_cmd
    li   a0, 0x00
    jal  ssd1306_send_cmd
    li   a0, 0x04
    jal  ssd1306_send_cmd

    # Initiate I2C transmission stream
    jal  i2c_start
    li   a0, 0x78
    jal  i2c_write_byte
    li   a0, 0x40
    jal  i2c_write_byte

    # Stream out all 360 framebuffer bytes
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
# BLOCK: SOFTWARE I2C & BIT-BANGING PROTOCOL ROUTINES
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


# =========================================================
# BLOCK: SSD1306 COMMAND WRAPPER
# Protocol wrapper to send single command bytes over I2C
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

# Virtual scroll source buffer (explicitly fully written out: 5 pages * 72 bytes = 360 bytes total)
    .align 4
scroll_source:
    # --- PAGE 0 (72 bytes / 8 rows) ---
    .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00

    # --- PAGE 1 ("SCROLLING" text data + padding = 72 bytes / 8 rows) ---
    .byte 0x00, 0x46, 0x49, 0x49, 0x31, 0x00, 0x00, 0x3E, 0x41
    .byte 0x41, 0x22, 0x00, 0x00, 0x7F, 0x09, 0x19, 0x66, 0x00
    .byte 0x00, 0x3E, 0x41, 0x41, 0x3E, 0x00, 0x00, 0x7F, 0x40
    .byte 0x40, 0x40, 0x00, 0x00, 0x7F, 0x40, 0x40, 0x40, 0x00
    .byte 0x00, 0x41, 0x7F, 0x41, 0x00, 0x00, 0x7F, 0x02, 0x04
    .byte 0x7F, 0x00, 0x00, 0x3E, 0x41, 0x49, 0x3A, 0x00, 0x00
    .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00

    # --- PAGE 2 (72 bytes / 8 rows) ---
    .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00

    # --- PAGE 3 (72 bytes / 8 rows) ---
    .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00

    # --- PAGE 4 (72 bytes / 8 rows) ---
    .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00

# Reserve active Framebuffer in RAM (360 bytes)
    .section .bss
    .align 4
framebuffer:
    .skip 360

_seg_end:
    .align 4
