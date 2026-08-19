# =====================================================================
# Project:     Bare-Metal ESP32-C3 Assembly SSD1306 Random Pixel & LED ON
# Author:      agguro
# Date:        August 11, 2026
# Description: Pure assembly bare-metal driver to initialize SSD1306 OLED,
#              render a randomized jumping pixel animation using LCG,
#              flush via I2C (SDA=GPIO5, SCL=GPIO6), and keep 
#              the LED on GPIO 8 permanently ON
# =====================================================================

.section .text
.option norelax
. = 0                    # Start cleanly at 0 for the flat binary

# Configuration Constants
.equ ANIM_DELAY, 500000  # Animation delay cycles (increase for slower, decrease for faster)

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
    beqz s5, .L_main_app
    lbu  a0, 0(s4)
    jal  ssd1306_send_cmd
    addi s4, s4, 1
    addi s5, s5, -1
    j    .L_init_loop


# =========================================================
# BLOCK: MAIN APPLICATION (RANDOM PIXEL ANIMATION & LED ON)
# Safely enable GPIO 8, turn active-low LED ON permanently,
# and run randomized jumping pixel animation loop
# =========================================================
.L_main_app:
    # Safely enable output for GPIO 8 (LED) without disabling I2C pins
    li   t0, 0x60004024      # GPIO_ENABLE_W1TS_REG
    li   t1, (1 << 8)
    sw   t1, 0(t0)

    # Turn LED ON permanently (Pull low via W1TC)
    li   t1, 0x100
    li   s0, 0x6000400C
    sw   t1, 0(s0)

    # Clear framebuffer to 0 (Black)
    jal  fb_clear

    # Initialize LCG random seed in s8
    li   s8, 123456789

    # Generate initial random X coordinate (0-71)
    li   t3, 1103515245
    mul  s8, s8, t3
    li   t3, 12345
    add  s8, s8, t3
    li   t3, 72
    remu s6, s8, t3

    # Generate initial random Y coordinate (0-39)
    li   t3, 1103515245
    mul  s8, s8, t3
    li   t3, 12345
    add  s8, s8, t3
    li   t3, 40
    remu s7, s8, t3

    # Draw the initial random pixel
    mv   a0, s6
    mv   a1, s7
    li   a2, 1
    jal  fb_set_pixel
    jal  fb_flush

anim_loop:
    # 1. Clear the previous pixel at (s6, s7)
    mv   a0, s6
    mv   a1, s7
    li   a2, 0
    jal  fb_set_pixel

    # 2. Generate new random X coordinate (0-71) via LCG
    li   t3, 1103515245
    mul  s8, s8, t3
    li   t3, 12345
    add  s8, s8, t3
    li   t3, 72
    remu s6, s8, t3

    # 3. Generate new random Y coordinate (0-39) via LCG
    li   t3, 1103515245
    mul  s8, s8, t3
    li   t3, 12345
    add  s8, s8, t3
    li   t3, 40
    remu s7, s8, t3

    # 4. Set the new random pixel ON at (s6, s7)
    mv   a0, s6
    mv   a1, s7
    li   a2, 1
    jal  fb_set_pixel

    # 5. Flush entire framebuffer to OLED
    jal  fb_flush

    # 6. Animation delay (uses ANIM_DELAY constant defined at the top)
    li   t5, ANIM_DELAY
.L_anim_d:
    li   t6, 1
    sub  t5, t5, t6
    bnez t5, .L_anim_d

    j    anim_loop


# =========================================================
# BLOCK: FRAMEBUFFER ROUTINES
# Clear, draw pixels, and flush buffer to display RAM
# =========================================================

# Clear framebuffer (360 bytes to 0)
fb_clear:
    la   t0, framebuffer
    li   t1, 360
    li   t3, 0
.L_clr_l:
    sb   t3, 0(t0)
    addi t0, t0, 1
    addi t1, t1, -1
    bnez t1, .L_clr_l
    ret

# Set/Clear Pixel: a0 = X (0-71), a1 = Y (0-39), a2 = State (0 or 1)
fb_set_pixel:
    # Check boundaries
    li   t0, 72
    bgeu a0, t0, .L_pixel_out
    li   t0, 40
    bgeu a1, t0, .L_pixel_out

    # Calculate byte index: index = X + (Y / 8) * 72
    srli t0, a1, 3           # t0 = Y / 8
    li   t1, 72
    mul  t0, t0, t1          # t0 = (Y / 8) * 72
    add  t0, t0, a0          # t0 = X + ((Y / 8) * 72)

    la   t2, framebuffer
    add  t2, t2, t0          # t2 = address of byte in RAM
    lbu  t3, 0(t2)           # Fetch current byte

    # Calculate bit mask: bit = Y % 8 -> mask = 1 << (Y & 7)
    andi t4, a1, 7
    li   t5, 1
    sll  t5, t5, t4          # t5 = bitmask

    beqz a2, .L_pixel_off
    # Set pixel ON (OR)
    or   t3, t3, t5
    j    .L_pixel_store
.L_pixel_off:
    # Set pixel OFF (AND NOT)
    not  t5, t5
    and  t3, t3, t5

.L_pixel_store:
    sb   t3, 0(t2)           # Save modified byte back to RAM
.L_pixel_out:
    ret

# Flush framebuffer to OLED (Send all 360 bytes in 1 data stream)
fb_flush:
    addi sp, sp, -16
    sw   ra, 12(sp)
    sw   s2, 8(sp)
    sw   s3, 4(sp)

    # Set column and page address for full screen
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
# BLOCK: DATA & BSS SECTION
# Constants, initialization arrays, and RAM framebuffer
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

# Reserve framebuffer in RAM (360 bytes)
    .section .bss
    .align 4
framebuffer:
    .skip 360

_seg_end:
    .align 4
