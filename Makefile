# Variables for tools and flags
ASM = nasm
CC = gcc
LD = ld
CC_FLAGS = -m32 -march=i386 -ffreestanding -fno-PIE -nostdlib -c
LD_FLAGS = -m elf_i386 -Ttext 0x7E00 --oformat binary -e start

# Source directories
KERNEL_DIR = ./Kernel
BOOT_DIR = ./Bootloader
C_DIR = $(KERNEL_DIR)/C

# Output directories
OUT = ./Output
BIN_DIR = $(OUT)/binaries

# Files
C_SOURCES = $(C_DIR)/datest.c
C_OBJECTS = $(patsubst $(C_DIR)/%.c,$(BIN_DIR)/%.o,$(C_SOURCES))
KERNEL_ASM_OBJ = $(BIN_DIR)/kernel.o
BOOT_BIN = $(BIN_DIR)/boot.bin
KERNEL_BIN = $(BIN_DIR)/kernel.bin
IMAGE = $(OUT)/floppy.img

# Image size configuration
IMAGE_SIZE_MB = 4
IMAGE_SIZE_SECTORS = $(shell echo $$(($(IMAGE_SIZE_MB) * 1024 * 1024 / 512)))
SECTORS_PER_TRACK = 18
HEADS = 2
CYLINDERS = $(shell echo $$(($(IMAGE_SIZE_SECTORS) / ($(SECTORS_PER_TRACK) * $(HEADS)))))

# Default target
all: $(IMAGE)
	@echo "Done! Running QEMU..."
	qemu-system-x86_64 -fda $(IMAGE)

# Ensure output directories exist
$(IMAGE): $(BOOT_BIN) $(KERNEL_BIN) | $(BIN_DIR)
	@echo "Creating 4MB floppy image..."
	dd if=/dev/zero of=$(IMAGE) bs=512 count=$(IMAGE_SIZE_SECTORS)
	@echo "Writing bootloader to first sector..."
	dd if=$(BOOT_BIN) of=$(IMAGE) conv=notrunc
	@echo "Writing kernel to sector 1..."
	dd if=$(KERNEL_BIN) of=$(IMAGE) bs=512 seek=1 conv=notrunc
	@echo "Image created with size $(IMAGE_SIZE_MB)MB ($(IMAGE_SIZE_SECTORS) sectors)"

# Alternative target for custom size (usage: make image SIZE=8)
image: 
	@if [ -z "$(SIZE)" ]; then \
		echo "Usage: make image SIZE=<size_in_mb>"; \
		exit 1; \
	fi
	@echo "Creating $(SIZE)MB floppy image..."
	dd if=/dev/zero of=$(IMAGE) bs=512 count=$$(($(SIZE) * 1024 * 1024 / 512))
	dd if=$(BOOT_BIN) of=$(IMAGE) conv=notrunc
	dd if=$(KERNEL_BIN) of=$(IMAGE) bs=512 seek=1 conv=notrunc
	@echo "Image created with size $(SIZE)MB"

# Directory creation
$(BIN_DIR):
	@mkdir -p $(BIN_DIR)
	@mkdir -p $(OUT)

# Rule to link the kernel and C modules
$(KERNEL_BIN): $(KERNEL_ASM_OBJ) $(C_OBJECTS) | $(BIN_DIR)
	@echo "Linking Kernel and C..."
	$(LD) $(LD_FLAGS) $(KERNEL_ASM_OBJ) $(C_OBJECTS) -o $(KERNEL_BIN)

# Rule for assembling the bootloader
$(BOOT_BIN): $(BOOT_DIR)/boot.asm | $(BIN_DIR)
	@echo "Assembling bootloader..."
	$(ASM) -f bin $(BOOT_DIR)/boot.asm -o $(BOOT_BIN)

# Rule for assembling the kernel entry
$(KERNEL_ASM_OBJ): $(KERNEL_DIR)/kernel.asm | $(BIN_DIR)
	@echo "Assembling Kernel..."
	$(ASM) -f elf32 $(KERNEL_DIR)/kernel.asm -o $(KERNEL_ASM_OBJ)

# Pattern rule for compiling C files
$(BIN_DIR)/%.o: $(C_DIR)/%.c | $(BIN_DIR)
	@echo "Compiling C Modules..."
	$(CC) $(CC_FLAGS) $< -o $@

# Cleanup
clean:
	@echo "Cleaning..."
	rm -rf $(OUT)

.PHONY: all clean image