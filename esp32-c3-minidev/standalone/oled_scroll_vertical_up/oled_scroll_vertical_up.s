# =====================================================================
# Project:     Bare-Metal ESP32-C3 Assembly SSD1306 Upward Scroll Engine
# Name:        oled_scroll_vertical_up
# Author:      agguro
# Date:        August 15, 2026
# Description: Pure assembly bare-metal driver for ESP32-C3 initializing 
#              an SSD1306 OLED display via software I2C. Performs continuous
#              upward byte-level scrolling with bitwise carry propagation 
#              across 5 vertical display pages for all 72 columns.
# =====================================================================

.section .text
.option norelax
. = 0                      # Start cleanly at address 0 for the flat binary payload

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
    li sp, 0x3FCE0000
    li t2, 0x7FFFBBFF      # Bitmask to clear watchdog write-protection bits

    # =========================================================
    # BLOCK: WATCHDOG & DEBUG INTERFERENCE DISABLE
    # =========================================================

    # Disable Timer Group 0 (TG0) Watchdog Timer
    li t0, 0x6001F064
    li t1, 0x50D83AA1
    sw t1, 0(t0)
    li t0, 0x6001F048
    lw t3, 0(t0)
    and t3, t3, t2
    sw t3, 0(t0)

    # Disable Timer Group 1 (TG1) Watchdog Timer
    li t0, 0x60020064
    li t1, 0x50D83AA1
    sw t1, 0(t0)
    li t0, 0x60020048
    lw t3, 0(t0)
    and t3, t3, t2
    sw t3, 0(t0)

    # Disable RTC System Watchdog Timer
    li t0, 0x600080A8
    li t1, 0x50D83AA1
    sw t1, 0(t0)
    li t0, 0x60008090
    lw t3, 0(t0)
    and t3, t3, t2
    sw t3, 0(t0)

    # Disable Serial Wire Debug (SWD) / JTAG interference
    li t0, 0x600080B8
    li t1, 0x8F1D312A
    sw t1, 0(t0)
    li t0, 0x600080B4
    lw t3, 0(t0)
    li t4, 0x80000000
    or t3, t3, t4
    sw t3, 0(t0)

    # =========================================================
    # BLOCK: GPIO CONFIGURATION FOR I2C & STATUS LED
    # =========================================================

    # Configure IO_MUX pull-ups for SDA (GPIO 5) and SCL (GPIO 6)
    li t0, 0x60009018
    li t1, (1 << 12) | (1 << 8)
    sw t1, 0(t0)
    li t0, 0x6000901C
    li t1, (1 << 12) | (1 << 8)
    sw t1, 0(t0)

    # Set GPIO 5 and 6 as Open-Drain drivers
    li t0, 0x60004088
    li t1, (1 << 2)
    sw t1, 0(t0)
    li t0, 0x6000408C
    li t1, (1 << 2)
    sw t1, 0(t0)

    # Enable outputs for SDA (GPIO 5), SCL (GPIO 6), and LED (GPIO 8)
    li t0, 0x60004020
    li t1, (1 << 5) | (1 << 6) | (1 << 8)
    sw t1, 0(t0)

    # Drive I2C data/clock lines HIGH initially (open-drain released)
    li s0, 0x60004008
    li s1, 0x6000400C
    li t1, (1 << 5) | (1 << 6)
    sw t1, 0(s0)

    # Short stabilization delay after display power-up
    li t5, 500000
.L_boot_delay:
    li t6, 1
    sub t5, t5, t6
    bnez t5, .L_boot_delay


    # =========================================================
    # BLOCK: SSD1306 OLED INITIALIZATION SEQUENCE
    # =========================================================
.L_init_display:
    la s4, ssd1306_init_cmds
    li s5, 25              # Total initialization command bytes

.L_init_loop:
    beqz s5, .L_start_app
    lbu a0, 0(s4)
    jal ssd1306_send_cmd
    addi s4, s4, 1
    addi s5, s5, -1
    j .L_init_loop


# =========================================================
# BLOCK: MAIN APPLICATION & ANIMATION LOOP
# =========================================================
.L_start_app:
    # Copy initial source font data into RAM framebuffer
    la t0, v_text_source
    la t1, framebuffer
    li t2, 360             # 5 pages * 72 columns = 360 bytes
.L_copy_loop:
    beqz t2, .L_copy_done
    lbu t3, 0(t0)
    sb t3, 0(t1)
    addi t0, t0, 1
    addi t1, t1, 1
    addi t2, t2, -1
    j .L_copy_loop
.L_copy_done:

main_loop:
    # Turn status LED ON per animation frame (GPIO 8 active low)
    li t1, 0x100
    sw t1, 0(s1)

    # Execute upward scroll step across all 72 columns and 5 pages
    jal scroll_up_step

    # Flush updated framebuffer to display controller over I2C
    jal fb_flush

    # Turn status LED OFF
    li t1, 0x100
    sw t1, 0(s0)

    # Frame rate delay loop for scroller speed control
    li t5, 40000
.L_anim_delay:
    li t6, 1
    sub t5, t5, t6
    bnez t5, .L_anim_delay

    j main_loop


# =========================================================
# ROUTINE: SCROLL_UP_STEP
# Iterates through all 72 columns, shifting each byte upward (right shift)
# with carry propagation across all 5 pages. The overflow from Page 0
# wraps around into the bottom of Page 4.
# =========================================================
scroll_up_step:
    addi sp, sp, -16
    sw ra, 12(sp)
    sw s2, 8(sp)
    sw s3, 4(sp)
    sw s4, 0(sp)

    li s3, 0                # Column loop index X (0 to 71)

.L_col_loop:
    li t0, 72
    bge s3, t0, .L_col_done

    # Base address + offset 288 points directly to Page 4 (Bottom row)
    la t1, framebuffer
    add t1, t1, s3
    addi t1, t1, 288        # Page 4 base address (4 * 72 bytes)

    li s4, 0                # Initialize carry accumulator to 0

    # --- 1. Page 4 (Row 5 - Bottom) ---
    lbu t0, 0(t1)           # Load current byte
    andi t2, t0, 0x01       # Extract bit 0 (carry out to page above)
    slli t2, t2, 7          # Shift carry bit to bit 7 position
    srli t0, t0, 1          # Shift byte right by 1 (scroll upward)
    or t0, t0, s4           # Inject carry from lower page
    sb t0, 0(t1)            # Write back modified byte
    mv s4, t2               # Store carry for next higher page

    # --- 2. Page 3 (Row 4) ---
    addi t1, t1, -72        # Move up 1 page (-72 bytes)
    lbu t0, 0(t1)
    andi t2, t0, 0x01
    slli t2, t2, 7
    srli t0, t0, 1
    or t0, t0, s4
    sb t0, 0(t1)
    mv s4, t2

    # --- 3. Page 2 (Row 3) ---
    addi t1, t1, -72        # Move up 1 page
    lbu t0, 0(t1)
    andi t2, t0, 0x01
    slli t2, t2, 7
    srli t0, t0, 1
    or t0, t0, s4
    sb t0, 0(t1)
    mv s4, t2

    # --- 4. Page 1 (Row 2) ---
    addi t1, t1, -72        # Move up 1 page
    lbu t0, 0(t1)
    andi t2, t0, 0x01
    slli t2, t2, 7
    srli t0, t0, 1
    or t0, t0, s4
    sb t0, 0(t1)
    mv s4, t2

    # --- 5. Page 0 (Row 1 - Top) ---
    addi t1, t1, -72        # Move up to top page (Page 0)
    lbu t0, 0(t1)
    andi t2, t0, 0x01
    slli t2, t2, 7
    srli t0, t0, 1
    or t0, t0, s4
    sb t0, 0(t1)
    mv s4, t2               # Final carry out from top of Page 0

    # --- Wrap around: Inject top carry into the bottom of Page 4 ---
    la t1, framebuffer
    add t1, t1, s3
    addi t1, t1, 288        # Target Page 4 address for column s3
    lbu t0, 0(t1)
    or t0, t0, s4           # Inject carry into bit 7 of Page 4
    sb t0, 0(t1)

    addi s3, s3, 1          # Advance to next column index
    j .L_col_loop

.L_col_done:
    lw s4, 0(sp)
    lw s3, 4(sp)
    lw s2, 8(sp)
    lw ra, 12(sp)
    addi sp, sp, 16
    ret


# =========================================================
# BLOCK: FRAMEBUFFER FLUSH ROUTINE
# Transfers the local 360-byte RAM buffer to the SSD1306 GDDRAM
# =========================================================
fb_flush:
    addi sp, sp, -16
    sw ra, 12(sp)
    sw s2, 8(sp)
    sw s3, 4(sp)

    # Set horizontal column address window (columns 28 to 99)
    li a0, 0x21
    jal ssd1306_send_cmd
    li a0, 28
    jal ssd1306_send_cmd
    li a0, 99
    jal ssd1306_send_cmd

    # Set page address window (pages 0 to 4)
    li a0, 0x22
    jal ssd1306_send_cmd
    li a0, 0x00
    jal ssd1306_send_cmd
    li a0, 0x04
    jal ssd1306_send_cmd

    # Initiate I2C transmission stream
    jal i2c_start
    li a0, 0x78             # SSD1306 I2C slave address (Write)
    jal i2c_write_byte
    li a0, 0x40             # Control byte: Data stream follows
    jal i2c_write_byte

    # Stream out all 360 framebuffer bytes
    la s2, framebuffer
    li s3, 360
.L_flush_loop:
    beqz s3, .L_flush_done
    lbu a0, 0(s2)
    jal i2c_write_byte
    addi s2, s2, 1
    addi s3, s3, -1
    j .L_flush_loop

.L_flush_done:
    jal i2c_stop
    lw s3, 4(sp)
    lw s2, 8(sp)
    lw ra, 12(sp)
    addi sp, sp, 16
    ret


# =========================================================
# BLOCK: SOFTWARE I2C & BIT-BANGING PROTOCOL ROUTINES
# =========================================================
i2c_delay:
    li t5, 40
.L_i2c_d:
    li t6, 1
    sub t5, t5, t6
    bnez t5, .L_i2c_d
    ret

sda_high:
    li t0, 0x60004008
    li t1, (1 << 5)
    sw t1, 0(t0)
    ret

sda_low:
    li t0, 0x6000400C
    li t1, (1 << 5)
    sw t1, 0(t0)
    ret

scl_high:
    li t0, 0x60004008
    li t1, (1 << 6)
    sw t1, 0(t0)
    ret

scl_low:
    li t0, 0x6000400C
    li t1, (1 << 6)
    sw t1, 0(t0)
    ret

i2c_start:
    addi sp, sp, -16
    sw ra, 12(sp)
    jal sda_high
    jal scl_high
    jal i2c_delay
    jal sda_low
    jal i2c_delay
    jal scl_low
    jal i2c_delay
    lw ra, 12(sp)
    addi sp, sp, 16
    ret

i2c_stop:
    addi sp, sp, -16
    sw ra, 12(sp)
    jal sda_low
    jal scl_high
    jal i2c_delay
    jal sda_high
    jal i2c_delay
    lw ra, 12(sp)
    addi sp, sp, 16
    ret

i2c_write_byte:
    addi sp, sp, -16
    sw ra, 12(sp)
    sw s2, 8(sp)
    mv s2, a0
    li t3, 8
.L_bit_loop:
    beqz t3, .L_write_ack
    andi t4, s2, 0x80
    bnez t4, .L_send_one
    jal sda_low
    j .L_clock_bit
.L_send_one:
    jal sda_high
.L_clock_bit:
    jal i2c_delay
    jal scl_high
    jal i2c_delay
    jal scl_low
    jal i2c_delay
    slli s2, s2, 1
    li t6, 1
    sub t3, t3, t6
    j .L_bit_loop
.L_write_ack:
    jal sda_high
    jal i2c_delay
    jal scl_high
    jal i2c_delay
    jal scl_low
    jal i2c_delay
    lw s2, 8(sp)
    lw ra, 12(sp)
    addi sp, sp, 16
    ret

ssd1306_send_cmd:
    addi sp, sp, -16
    sw ra, 12(sp)
    mv a2, a0
    jal i2c_start
    li a0, 0x78
    jal i2c_write_byte
    li a0, 0x80
    jal i2c_write_byte
    mv a0, a2
    jal i2c_write_byte
    jal i2c_stop
    lw ra, 12(sp)
    addi sp, sp, 16
    ret


# =========================================================
# BLOCK: DATA & BSS SECTIONS
# =========================================================
    .align 4
ssd1306_init_cmds:
    .byte 0xAE       # Display OFF
    .byte 0xD5, 0x80 # Set display clock divide ratio/oscillator frequency
    .byte 0xA8, 0x27 # Set multiplex ratio (40 active rows)
    .byte 0xD3, 0x00 # Set display offset
    .byte 0x40       # Set display start line address
    .byte 0x8D, 0x14 # Charge pump setting (Enable internal DC/DC converter)
    .byte 0x20, 0x00 # Set memory addressing mode (0x00 = Horizontal addressing mode)
    .byte 0xA1       # Set segment re-map (Column address 0 mapped to SEG127)
    .byte 0xC8       # Set COM output scan direction (remapped mode)
    .byte 0xDA, 0x12 # Set COM pins hardware configuration
    .byte 0x81, 0xCF # Set contrast control register
    .byte 0xD9, 0xF1 # Set pre-charge period
    .byte 0xDB, 0x40 # Set VCOMH deselect level
    .byte 0xA4       # Entire display ON (resume to RAM content)
    .byte 0xA6       # Set normal display (not inverted)
    .byte 0xAF       # Display ON


# ---------------------------------------------------------
# FONT / TEXT DATA SOURCE (5 pages * 72 bytes = 360 bytes total)
# ---------------------------------------------------------
    .align 4
v_text_source:
    # --- PAGE 0 (72 bytes) ---
    .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00

    # --- PAGE 1 ("SCROLLING" text data - 72 bytes) ---
    .byte 0x00, 0x46, 0x49, 0x49, 0x31, 0x00, 0x00, 0x3E, 0x41, 0x41, 0x22, 0x00, 0x00, 0x7F, 0x09, 0x19, 0x66, 0x00, 0x00, 0x3E, 0x41, 0x41, 0x3E, 0x00, 0x00, 0x7F, 0x40, 0x40, 0x40, 0x00, 0x00, 0x7F, 0x40, 0x40, 0x40, 0x00, 0x00, 0x41, 0x7F, 0x41, 0x00, 0x00, 0x7F, 0x02, 0x04, 0x7F, 0x00, 0x00, 0x3E, 0x41, 0x49, 0x3A, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00

    # --- PAGE 2 (72 bytes) ---
    .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00

    # --- PAGE 3 (72 bytes) ---
    .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00

    # --- PAGE 4 (72 bytes) ---
    .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00

    .section .bss
    .align 4
framebuffer:
    .skip 360

_seg_end:
    .align 4
