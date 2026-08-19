# =====================================================================
# Project:     Bare-Metal ESP32-C3 Assembly SSD1306 Text Scroller & LED
# Name:        oled_pure_host_payload
# Author:      agguro
# =====================================================================

.section .text
.option norelax
.global _start

_start:
    # 1. Disable all interrupts globally
    csrci mstatus, 8
    csrw  mie, zero

    # 2. Setup Stack Pointer in safe Internal SRAM
    li    sp, 0x3FCE0000

    # 3. Nuke ALL Watchdogs immediately
    # TIMG0 WDT
    li    t0, 0x6001F064
    li    t1, 0x50D83AA1
    sw    t1, 0(t0)
    li    t0, 0x6001F048
    sw    zero, 0(t0)

    # TIMG1 WDT
    li    t0, 0x60020064
    li    t1, 0x50D83AA1
    sw    t1, 0(t0)
    li    t0, 0x60020048
    sw    zero, 0(t0)

    # RTC WDT
    li    t0, 0x600080A8
    li    t1, 0x50D83AA1
    sw    t1, 0(t0)
    li    t0, 0x60008098
    sw    zero, 0(t0)

    # Super WDT
    li    t0, 0x600080B8
    li    t1, 0x8F1D312A
    sw    t1, 0(t0)
    li    t0, 0x600080B4
    li    t1, 0x80000000
    sw    t1, 0(t0)

    # 4. Setup GPIO for Status LED (GPIO 8) and I2C (SDA=5, SCL=6)
    li    t0, 0x60009018
    li    t1, (1 << 12) | (1 << 8)
    sw    t1, 0(t0)
    li    t0, 0x6000901C
    li    t1, (1 << 12) | (1 << 8)
    sw    t1, 0(t0)

    li    t0, 0x60004020
    li    t1, (1 << 5) | (1 << 6) | (1 << 8)
    sw    t1, 0(t0)

    li    s0, 0x60004008        # GPIO OUT SET
    li    s1, 0x6000400C        # GPIO OUT W1TC (Clear)

    # 5. Boot stabilization delay
    li    t5, 2000000
.L_boot_wait:
    addi  t5, t5, -1
    bnez  t5, .L_boot_wait

    # 6. Clear Framebuffer in DRAM (Safe D-Bus address)
    li    t0, 0x3FCD0000
    li    t1, 360
.L_clear_fb:
    beqz  t1, .L_init_oled
    sb    zero, 0(t0)
    addi  t0, t0, 1
    addi  t1, t1, -1
    j     .L_clear_fb

    # 7. Initialize SSD1306 OLED
.L_init_oled:
    la    s4, ssd1306_init_cmds
    li    s5, 26
.L_cmd_loop:
    beqz  s5, .L_main_loop
    lbu   a0, 0(s4)
    jal   ssd1306_send_cmd
    addi  s4, s4, 1
    addi  s5, s5, -1
    j     .L_cmd_loop

# =========================================================
# MAIN SCROLLER LOOP (Via Host Payload)
# =========================================================
.L_main_loop:
    li    s6, 71                # Start offset

.L_scroll_tick:
    # LED ON per frame start
    li    t1, (1 << 8)
    sw    t1, 0(s1)

    # Render & Flush
    mv    a0, s6
    jal   render_frame
    jal   flush_framebuffer

    # LED OFF
    sw    t1, 0(s0)

    # Next offset (Modulo 72)
    addi  s6, s6, -1
    bgez  s6, .L_no_reset
    li    s6, 71
.L_no_reset:

    j     .L_scroll_tick


# =========================================================
# RENDER ROUTINE (D-Bus Safe)
# =========================================================
render_frame:
    addi  sp, sp, -16
    sw    ra, 12(sp)
    sw    s2, 8(sp)
    mv    s2, a0                # s2 = offset

    li    s3, 0                 # Page loop (0 to 4)
.L_p_loop:
    li    t0, 0x3FCD0000        # Framebuffer DRAM base
    li    t1, 72
    mul   t2, s3, t1
    add   s4, t0, t2            # s4 = target row in FB

    li    s5, 0                 # Column loop (0 to 71)
.L_c_loop:
    add   t3, s5, s2
    li    t4, 72
    remu  t3, t3, t4            # Modulo 72

    la    t5, scroll_source
    add   t5, t5, t3
    lbu   t0, 0(t5)             # Load from source

    sb    t0, 0(s4)             # Store to FB DRAM

    addi  s4, s4, 1
    addi  s5, s5, 1
    li    t1, 72
    bne   s5, t1, .L_c_loop

    addi  s3, s3, 1
    li    t1, 5
    bne   s3, t1, .L_p_loop

    lw    s2, 8(sp)
    lw    ra, 12(sp)
    addi  sp, sp, 16
    ret


# =========================================================
# FRAMEBUFFER FLUSH (Software I2C)
# =========================================================
flush_framebuffer:
    addi  sp, sp, -16
    sw    ra, 12(sp)
    sw    s2, 8(sp)
    sw    s3, 4(sp)

    li    a0, 0x21
    jal   ssd1306_send_cmd
    li    a0, 28
    jal   ssd1306_send_cmd
    li    a0, 99
    jal   ssd1306_send_cmd

    li    a0, 0x22
    jal   ssd1306_send_cmd
    li    a0, 0x00
    jal   ssd1306_send_cmd
    li    a0, 0x04
    jal   ssd1306_send_cmd

    jal   i2c_start
    li    a0, 0x78
    jal   i2c_write_byte
    li    a0, 0x40
    jal   i2c_write_byte

    li    s2, 0x3FCD0000
    li    s3, 360
.L_fl_loop:
    beqz  s3, .L_fl_done
    lbu   a0, 0(s2)
    jal   i2c_write_byte
    addi  s2, s2, 1
    addi  s3, s3, -1
    j     .L_fl_loop

.L_fl_done:
    jal   i2c_stop
    lw    s3, 4(sp)
    lw    s2, 8(sp)
    lw    ra, 12(sp)
    addi  sp, sp, 16
    ret


# =========================================================
# I2C BIT-BANGING ROUTINES (SDA=GPIO5, SCL=GPIO6)
# =========================================================
i2c_delay:
    li    t5, 20
.L_i2cd:
    addi  t5, t5, -1
    bnez  t5, .L_i2cd
    ret

sda_high:
    li    t0, 0x60004008
    li    t1, (1 << 5)
    sw    t1, 0(t0)
    ret

sda_low:
    li    t0, 0x6000400C
    li    t1, (1 << 5)
    sw    t1, 0(t0)
    ret

scl_high:
    li    t0, 0x60004008
    li    t1, (1 << 6)
    sw    t1, 0(t0)
    ret

scl_low:
    li    t0, 0x6000400C
    li    t1, (1 << 6)
    sw    t1, 0(t0)
    ret

i2c_start:
    addi  sp, sp, -16
    sw    ra, 12(sp)
    jal   sda_high
    jal   scl_high
    jal   i2c_delay
    jal   sda_low
    jal   i2c_delay
    jal   scl_low
    jal   i2c_delay
    lw    ra, 12(sp)
    addi  sp, sp, 16
    ret

i2c_stop:
    addi  sp, sp, -16
    sw    ra, 12(sp)
    jal   sda_low
    jal   scl_high
    jal   i2c_delay
    jal   sda_high
    jal   i2c_delay
    lw    ra, 12(sp)
    addi  sp, sp, 16
    ret

i2c_write_byte:
    addi  sp, sp, -16
    sw    ra, 12(sp)
    sw    s2, 8(sp)
    mv    s2, a0
    li    t3, 8
.L_bit_w:
    beqz  t3, .L_ack
    andi  t4, s2, 0x80
    bnez  t4, .L_s_one
    jal   sda_low
    j     .L_b_chk
.L_s_one:
    jal   sda_high
.L_b_chk:
    jal   i2c_delay
    jal   scl_high
    jal   i2c_delay
    jal   scl_low
    jal   i2c_delay
    slli  s2, s2, 1
    addi  t3, t3, -1
    j     .L_bit_w
.L_ack:
    jal   sda_high
    jal   i2c_delay
    jal   scl_high
    jal   i2c_delay
    jal   scl_low
    jal   i2c_delay
    lw    s2, 8(sp)
    lw    ra, 12(sp)
    addi  sp, sp, 16
    ret

ssd1306_send_cmd:
    addi  sp, sp, -16
    sw    ra, 12(sp)
    mv    a2, a0
    jal   i2c_start
    li    a0, 0x78
    jal   i2c_write_byte
    li    a0, 0x80
    jal   i2c_write_byte
    mv    a0, a2
    jal   i2c_write_byte
    jal   i2c_stop
    lw    ra, 12(sp)
    addi  sp, sp, 16
    ret


# =========================================================
# DATA & ASSETS
# =========================================================
    .align 4
ssd1306_init_cmds:
    .byte 0xAE, 0x2E, 0xD5, 0x80, 0xA8, 0x27, 0xD3, 0x00, 0x40 
    .byte 0x8D, 0x14, 0x20, 0x00, 0xA1, 0xC8, 0xDA, 0x12, 0x81 
    .byte 0xCF, 0xD9, 0xF1, 0xDB, 0x40, 0xA4, 0xA6, 0xAF       

    .align 4
scroll_source:
    # --- PAGE 0 (72 bytes) ---
    .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00

    # --- PAGE 1 ("S" geisoleerd) ---
    .byte 0x00, 0x46, 0x49, 0x49, 0x31, 0x00, 0x00, 0x00, 0x00 
    .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00

    # --- PAGE 2 (72 bytes) ---
    .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00

    # --- PAGE 3 (72 bytes) ---
    .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00

    # --- PAGE 4 (72 bytes) ---
    .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00

_seg_end:
    .align 4
