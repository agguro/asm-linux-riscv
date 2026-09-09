.global _start

# Deze macro genereert exact 0 runtime-instructies.
# Hij maakt een lokaal symbool aan dat het verschil tussen twee labels bevat.
.macro define_string name, text
\name:
    .ascii "\text"
\name\()_end:
.set \name\()_len, (\name\()_end - \name)
.endm

.section .rodata
# De macro definieert de string en berekent de lengte compile-time.
# Er worden GEEN .global statements aangemaakt. Alles blijft privé.
define_string msg, "Hello, World!\n"

.section .text
_start:
    # sys_write(stdout, msg, msg_len)
    li a7, 64               # syscall 64 = sys_write
    li a0, 1                # file descriptor 1 = stdout
    la a1, msg              # laad het adres van de string (PIE-veilig)

    # Omdat msg_len een pure, lokale constante is, dwingen we hier
    # de absolute waarde af. Dit compileert naar exact één 'addi' instructie.
    # 0 bytes runtime-overhead, de assembler/linker lost dit op!
    li a2, msg_len          
    ecall

    # sys_exit(0)
    li a7, 93               # syscall 93 = sys_exit
    li a0, 0                # exit code 0
    ecall
