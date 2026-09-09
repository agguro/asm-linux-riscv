# Makefile voor pure RISC-V 64-bit Linux PIE code

AS = as
LD = ld

BASE_ASFLAGS = -march=rv64gc -mabi=lp64d -fPIC

# -pie maakt er een Position Independent Executable van.
# --dynamic-linker zorgt dat Linux weet welke user-space loader (bootloader) hij moet starten.
# Op 64-bit RISC-V Debian/Armbian is dit het standaard pad.
GLOBAL_LDFLAGS = -pie --dynamic-linker=/lib/ld-linux-riscv64-lp64d.so.1

TARGET = hello
SRCS = hello.s
OBJS = hello.o
LST  = hello.lst

all: release

debug: ASFLAGS = $(BASE_ASFLAGS) -g -a=$(LST)
debug: LDFLAGS = $(GLOBAL_LDFLAGS)
debug: $(TARGET)

release: ASFLAGS = $(BASE_ASFLAGS)
release: LDFLAGS = $(GLOBAL_LDFLAGS) -s
release: $(TARGET)

$(TARGET): $(OBJS)
	$(LD) $(LDFLAGS) -o $(TARGET) $(OBJS)

$(OBJS): $(SRCS)
	$(AS) $(ASFLAGS) -o $@ $<

clean:
	rm -f $(OBJS) $(TARGET) $(LST)

.PHONY: all debug release clean

