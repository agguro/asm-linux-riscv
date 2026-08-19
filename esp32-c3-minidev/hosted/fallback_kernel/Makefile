# =====================================================================
# Project:     ESP32-C3 Bare-Metal Kernel Build System
# Target:      fallback_kernel
# =====================================================================

TARGET     = $(shell basename $(CURDIR))
LINKER     = $(TARGET).ld

RV_AS      = riscv64-unknown-elf-as
RV_LD      = riscv64-unknown-elf-ld
RV_OBJ     = riscv64-unknown-elf-objcopy
RV_DUMP    = riscv64-unknown-elf-objdump

RV_ASFLAGS = -march=rv32imc_zicsr -mabi=ilp32
RV_LDFLAGS = -m elf32lriscv -T $(LINKER)

# Build directories
BUILD_ROOT         = build
BUILD_REL          = $(BUILD_ROOT)/release
BUILD_DBG          = $(BUILD_ROOT)/debug

.PHONY: all release debug clean

all: release

# Ensure build directories exist via order-only prerequisites
$(BUILD_REL) $(BUILD_DBG):
	mkdir -p $@

# ---------------------------------------------------------------------
# RELEASE TARGET (Optimized binary output only)
# ---------------------------------------------------------------------
release: $(BUILD_REL)/$(TARGET).bin
	@echo "[BUILD] Release kernel '$(TARGET)' completed in $(BUILD_REL)/"

$(BUILD_REL)/$(TARGET).bin: $(TARGET).s $(LINKER) | $(BUILD_REL)
	$(RV_AS) $(RV_ASFLAGS) -o $(BUILD_REL)/$(TARGET).o $<
	$(RV_LD) $(RV_LDFLAGS) -o $(BUILD_REL)/$(TARGET).elf $(BUILD_REL)/$(TARGET).o
	$(RV_OBJ) -O binary $(BUILD_REL)/$(TARGET).elf $@
	@rm -f $(BUILD_REL)/$(TARGET).o $(BUILD_REL)/$(TARGET).elf

# ---------------------------------------------------------------------
# DEBUG TARGET (Includes ELF, Map, Disassembly Listing, and Hexdump)
# ---------------------------------------------------------------------
debug: $(BUILD_DBG)/$(TARGET).bin $(BUILD_DBG)/$(TARGET).lst $(BUILD_DBG)/$(TARGET).hex
	@echo "[BUILD] Debug kernel '$(TARGET)' completed in $(BUILD_DBG)/"

$(BUILD_DBG)/$(TARGET).bin: $(TARGET).s $(LINKER) | $(BUILD_DBG)
	$(RV_AS) $(RV_ASFLAGS) -g -o $(BUILD_DBG)/$(TARGET).o $<
	$(RV_LD) $(RV_LDFLAGS) -Map $(BUILD_DBG)/$(TARGET).map -o $(BUILD_DBG)/$(TARGET).elf $(BUILD_DBG)/$(TARGET).o
	$(RV_OBJ) -O binary $(BUILD_DBG)/$(TARGET).elf $@
	@rm -f $(BUILD_DBG)/$(TARGET).o

$(BUILD_DBG)/$(TARGET).lst: $(BUILD_DBG)/$(TARGET).elf | $(BUILD_DBG)
	$(RV_DUMP) -D $< > $@

# Generate a clean hexdump formatted as .byte arrays on a single robust line
$(BUILD_DBG)/$(TARGET).hex: $(BUILD_DBG)/$(TARGET).bin | $(BUILD_DBG)
	@python3 -c 'data = open("$<", "rb").read().rstrip(b"\x00"); [print("    .byte " + ", ".join("0x%02x" % b for b in data[i:i+8])) for i in range(0, len(data), 8)]' > $@
	@echo "[INFO] Clean host-ready .byte hexdump generated at $@"

# ---------------------------------------------------------------------
# CLEAN TARGET
# ---------------------------------------------------------------------
clean:
	rm -rf $(BUILD_ROOT)
