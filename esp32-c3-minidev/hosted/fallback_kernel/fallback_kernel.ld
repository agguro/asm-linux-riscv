ENTRY(_start)
SECTIONS
{
    .text 0x40380000 : {
        *(.text._start)
        *(.text*)
    }
    .rodata : { *(.rodata*) }
    .data : { *(.data*) }
    /* .bss removed entirely to prevent uninitialized memory tracking bugs */
}
