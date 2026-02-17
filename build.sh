#!/bin/bash

echo "Cleaning..."
rm -f *.bin *.o *.img

echo "Assembling bootloader..."
nasm -f bin boot.asm -o boot.bin

echo "Compiling C Modules..."
gcc -m32 -march=i386 -ffreestanding -fno-PIE -nostdlib -c datest.c -o datest.o
gcc -m32 -march=i386 -ffreestanding -fno-PIE -nostdlib -c fat.c -o fat.o

echo "Assembling Kernel..."
nasm -f elf32 kernel.asm -o kernel.o

echo "Linking Kernel and C..."
# The -Ttext 0x7E00 puts the code at the right spot for your bootloader
ld -m elf_i386 -Ttext 0x7E00 --oformat binary -e start kernel.o datest.o fat.o -o kernel.bin

echo "Creating Image..."
dd if=/dev/zero of=floppy.img bs=512 count=2880
dd if=boot.bin of=floppy.img conv=notrunc
dd if=kernel.bin of=floppy.img bs=512 seek=1 conv=notrunc

echo "Done! Running QEMU..."
qemu-system-x86_64 -fda floppy.img
