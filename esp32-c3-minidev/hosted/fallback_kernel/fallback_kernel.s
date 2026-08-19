# =====================================================================
# Project:     Bare-Metal ESP32-C3 Assembly LED Blink & USB Print
# Name:        fallback_kernel.s
# Author:      agguro
# Date:        August 13, 2026
# Description: Pure assembly bare-metal LED blink on GPIO 8 (Active-Low)
#              with text output streamed over Native USB-JTAG.
#              This is the fallback kernel code hardcoded directly into
#              the x86_64 host loader program. It can be modified or
#              used as a template for custom bare-metal kernels.
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

    # ---------------------------------------------------------
    # MAIN ENTRY POINT
    # ---------------------------------------------------------
    .global _start
_start:
    # 1. CPU & ENVIRONMENT INITIALIZATION
    csrci mstatus, 8             # Disable all interrupts

    # Set up the Stack Pointer
    li   sp, 0x3FCE0000
    li   t2, 0x7FFFBBFF          # Watchdog write-protect mask

    # ---------------------------------------------------------
    # 2. WATCHDOG TIMER (WDT) & DEBUG DISABLE
    # ---------------------------------------------------------
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

    # Disable SWD / JTAG interference
    li   t0, 0x600080B8
    li   t1, 0x8F1D312A
    sw   t1, 0(t0)
    li   t0, 0x600080B4
    lw   t3, 0(t0)
    li   t4, 0x80000000
    or   t3, t3, t4
    sw   t3, 0(t0)

    # ---------------------------------------------------------
    # 4. GPIO CONFIGURATION
    # ---------------------------------------------------------
    # Route GPIO8 in the IO_MUX to the standard GPIO function
    li   t0, 0x60009024          # IO_MUX_GPIO8_REG
    li   t1, 0x1000              # MCU_SEL = 1 (GPIO Function)
    sw   t1, 0(t0)

    # Configure GPIO 8 as an output
    li   t0, 0x60004024          # GPIO_ENABLE_W1TS_REG
    li   t1, 0x100               # Bit 8
    sw   t1, 0(t0)

    # ---------------------------------------------------------
    # 5. INFINITE BLINK LOOP
    # ---------------------------------------------------------

# Initialize register and pin mask once
    li   t0, 0x60004008          # Start with GPIO_OUT_W1TS_REG (Set / LED OFF)
    li   t1, 0x100               # Bit 8 for GPIO 8

blink_loop:
    # Write mask to whichever register address is currently in t0
    sw   t1, 0(t0)

    # Delay loop (only written once!)
    li   t2, 5000000
delay_loop:
    addi t2, t2, -1
    bnez t2, delay_loop

    # Toggle t0 between 0x60004008 and 0x6000400C using XOR
    # 0x08 ^ 0x04 = 0x0C  (and 0x0C ^ 0x04 = 0x08)
    xori t0, t0, 4

    j    blink_loop              # Repeat forever
