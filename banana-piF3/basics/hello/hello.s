.global _start

.macro mString name, text
\name:
    .ascii "\text"
\name\()_end:
.set \name\()_len, (\name\()_end - \name)
.endm

.section .rodata
# Define the string and calculate the length compile-time.

mString msg, "Hello, World!\n"

.section .text
_start:
    # sys_write(stdout, msg, msg_len)
    li a0, 1                # file descriptor 1 = stdout
    la a1, msg              # load the address of the string (PIE-prove)
    li a2, msg_len

    li a7, 64               # syscall 64 = sys_write
    ecall

    # sys_exit(0)
    li a0, 0                # exit code 0
    li a7, 93               # syscall 93 = sys_exit
    ecall
