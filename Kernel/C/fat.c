// fat.c - DAC (Dum Allocation "Chair") filesystem implementation (This does NOT work)
// I just hope i can get FAT working and hopefully also a version of EXT, maybe if i get the smorts EXT-4?
#include <stdint.h>
#include <stdbool.h>

// Function prototypes
const char* fat_init(void);
const char* fat_list_dir(void);
const char* fat_create_file(void);

// BIOS disk read/write functions (defined in kernel.asm)
extern void read_sectors_bios(uint32_t lba, uint16_t count, void* buffer);
extern void write_sectors_bios(uint32_t lba, uint16_t count, void* buffer);

// DAC Filesystem Structures

// Partition entry in DAC (similar to MBR but simpler)
typedef struct {
    uint8_t status;          // 0x00=inactive, 0x80=active/bootable
    uint8_t start_head;      // Starting head
    uint8_t start_sector;    // Starting sector (bits 0-5) and cylinder high bits (6-7)
    uint8_t start_cylinder;  // Starting cylinder low bits
    uint8_t type;           // Partition type (0xDA for DAC filesystem)
    uint8_t end_head;       // Ending head
    uint8_t end_sector;     // Ending sector (bits 0-5) and cylinder high bits (6-7)
    uint8_t end_cylinder;   // Ending cylinder low bits
    uint32_t lba_start;     // LBA of first sector
    uint32_t sector_count;  // Total sectors in partition
} __attribute__((packed)) dac_partition_entry;

// DAC Superblock (first sector of partition)
typedef struct {
    char signature[8];          // "DACFS001"
    uint16_t version;           // Filesystem version (1)
    uint32_t total_blocks;      // Total data blocks
    uint32_t block_size;        // Block size in bytes (512)
    uint32_t bitmap_start;      // Starting block of bitmap
    uint32_t bitmap_blocks;     // Number of bitmap blocks
    uint32_t ftable_start;      // Starting block of file table
    uint32_t ftable_blocks;     // Number of file table blocks
    uint32_t data_start;        // Starting block of data area
    uint32_t root_dir_entry;    // File table index of root directory (always 0)
    char volume_label[32];      // Volume label
    uint32_t created_time;      // Creation timestamp
    uint32_t last_mount;        // Last mount timestamp
    uint32_t free_blocks;       // Count of free blocks
    uint32_t checksum;          // Superblock checksum
    uint8_t reserved[432];      // Reserved space
} __attribute__((packed)) dac_superblock;

// File table entry (32 bytes each)
typedef struct {
    char filename[11];          // 8.3 filename format
    uint8_t attributes;         // File attributes (0x01=read-only, 0x02=hidden, 0x04=system, 0x08=volume label, 0x10=directory, 0x20=archive)
    uint8_t reserved1;
    uint16_t creation_time;     // Creation time
    uint16_t creation_date;     // Creation date
    uint16_t access_date;       // Last access date
    uint16_t first_block;       // First data block (0 if empty)
    uint32_t file_size;         // File size in bytes
    uint16_t last_block;        // Last data block in chain
    uint16_t block_count;       // Number of blocks allocated
    uint32_t modified_time;     // Last modification timestamp
    uint8_t reserved2[6];       // Reserved
} __attribute__((packed)) dac_file_entry;

// Global variables
dac_superblock superblock;
uint8_t current_drive = 0;
uint32_t mounted_partitions = 0;
uint32_t partition_lba[3] = {0, 0, 0};  // LBA addresses for &1, &2, &3
bool partition_valid[3] = {false, false, false};
char* mount_names[3] = {"&1", "&2", "&3"};

// Buffer for disk operations
uint8_t disk_buffer[512];
uint8_t bitmap_buffer[512];
dac_file_entry filetable_buffer[16];  // 16 entries per sector (512/32)

// Output buffer for returning strings
char output_buffer[1024];
uint16_t output_pos = 0;

// Helper functions
void append_string(const char* str);
void append_char(char c);
void append_hex(uint32_t num, uint8_t digits);
void append_number(uint32_t num);
uint32_t calculate_checksum(void* data, uint32_t size);
bool validate_superblock(void);
void read_superblock(uint32_t lba);
void write_superblock(uint32_t lba);
bool scan_partitions(void);
void format_partition(uint32_t lba, uint32_t sector_count, const char* label);
void mount_partition(uint8_t index, uint32_t lba);
void read_bitmap_block(uint32_t block);
void write_bitmap_block(uint32_t block);
void read_filetable_block(uint32_t block);
void write_filetable_block(uint32_t block);
uint16_t find_free_block(void);
uint16_t find_free_file_entry(void);
void mark_block_used(uint16_t block);
void mark_block_free(uint16_t block);

// Append string to output buffer
void append_string(const char* str) {
    while (*str && output_pos < 1023) {
        output_buffer[output_pos++] = *str++;
    }
    output_buffer[output_pos] = 0;
}

// Append character to output buffer
void append_char(char c) {
    if (output_pos < 1023) {
        output_buffer[output_pos++] = c;
        output_buffer[output_pos] = 0;
    }
}

// Append hex number to output buffer
void append_hex(uint32_t num, uint8_t digits) {
    for (int i = digits - 1; i >= 0; i--) {
        uint8_t nibble = (num >> (i * 4)) & 0xF;
        append_char(nibble < 10 ? '0' + nibble : 'A' + nibble - 10);
    }
}

// Append decimal number to output buffer
void append_number(uint32_t num) {
    char temp[12];
    int i = 0;
    
    if (num == 0) {
        append_char('0');
        return;
    }
    
    while (num > 0) {
        temp[i++] = '0' + (num % 10);
        num /= 10;
    }
    
    for (int j = i - 1; j >= 0; j--) {
        append_char(temp[j]);
    }
}

// Calculate simple checksum
uint32_t calculate_checksum(void* data, uint32_t size) {
    uint32_t sum = 0;
    uint8_t* ptr = (uint8_t*)data;
    for (uint32_t i = 0; i < size; i++) {
        sum += ptr[i];
    }
    return sum;
}

// Validate superblock
bool validate_superblock(void) {
    // Check signature
    if (superblock.signature[0] != 'D' || superblock.signature[1] != 'A' ||
        superblock.signature[2] != 'C' || superblock.signature[3] != 'F' ||
        superblock.signature[4] != 'S' || superblock.signature[5] != '0' ||
        superblock.signature[6] != '0' || superblock.signature[7] != '1') {
        return false;
    }
    
    // Verify checksum (skip checksum field itself)
    uint32_t original_checksum = superblock.checksum;
    superblock.checksum = 0;
    uint32_t calculated = calculate_checksum(&superblock, sizeof(superblock));
    superblock.checksum = original_checksum;
    
    return (calculated == original_checksum);
}

// Read superblock from disk
void read_superblock(uint32_t lba) {
    read_sectors_bios(lba, 1, &superblock);
}

// Write superblock to disk
void write_superblock(uint32_t lba) {
    // Update checksum before writing
    superblock.checksum = 0;
    superblock.checksum = calculate_checksum(&superblock, sizeof(superblock));
    write_sectors_bios(lba, 1, &superblock);
}

// Scan for DAC partitions
bool scan_partitions(void) {
    dac_partition_entry partitions[4];
    
    // Read MBR from boot drive (LBA 0)
    read_sectors_bios(0, 1, disk_buffer);
    
    // Copy partition table (located at offset 0x1BE)
    for (int i = 0; i < 4; i++) {
        partitions[i] = *((dac_partition_entry*)(disk_buffer + 0x1BE + i * 16));
    }
    
    bool found_dac = false;
    
    // Check each partition
    for (int i = 0; i < 4; i++) {
        if (partitions[i].type == 0xDA) {  // DAC filesystem
            append_string("Found DAC partition at LBA 0x");
            append_hex(partitions[i].lba_start, 8);
            append_string("\r\n");
            
            found_dac = true;
            
            // Mount to next available slot (skip &1 which is boot device)
            for (int j = 1; j < 3; j++) {
                if (!partition_valid[j]) {
                    mount_partition(j, partitions[i].lba_start);
                    break;
                }
            }
        }
    }
    
    return found_dac;
}

// Format a partition as DAC
void format_partition(uint32_t lba, uint32_t sector_count, const char* label) {
    // Initialize superblock
    superblock.signature[0] = 'D';
    superblock.signature[1] = 'A';
    superblock.signature[2] = 'C';
    superblock.signature[3] = 'F';
    superblock.signature[4] = 'S';
    superblock.signature[5] = '0';
    superblock.signature[6] = '0';
    superblock.signature[7] = '1';
    
    superblock.version = 1;
    superblock.block_size = 512;
    
    // Calculate filesystem layout (simplified for 16MB = 32768 sectors)
    superblock.total_blocks = sector_count;
    superblock.bitmap_start = 1;
    
    // Bitmap needs 1 bit per block, so 1 block can track 4096 blocks
    superblock.bitmap_blocks = (sector_count + 4095) / 4096;
    
    superblock.ftable_start = superblock.bitmap_start + superblock.bitmap_blocks;
    superblock.ftable_blocks = 4;  // Fixed 4 blocks for file table (64 entries)
    
    superblock.data_start = superblock.ftable_start + superblock.ftable_blocks;
    superblock.root_dir_entry = 0;
    
    // Copy volume label
    for (int i = 0; i < 31 && label[i] != 0; i++) {
        superblock.volume_label[i] = label[i];
    }
    superblock.volume_label[31] = 0;
    
    superblock.created_time = 0x12345678;  // Placeholder timestamp
    superblock.last_mount = 0;
    superblock.free_blocks = sector_count - superblock.data_start;
    
    // Write superblock
    write_superblock(lba);
    
    // Initialize bitmap (mark system blocks as used)
    for (uint32_t i = 0; i < superblock.bitmap_blocks; i++) {
        read_sectors_bios(lba + superblock.bitmap_start + i, 1, bitmap_buffer);
        
        // Clear bitmap
        for (int j = 0; j < 512; j++) {
            bitmap_buffer[j] = 0;
        }
        
        // Mark blocks 0 through data_start-1 as used
        uint32_t blocks_in_this_bitmap = 4096;
        if (i == superblock.bitmap_blocks - 1) {
            blocks_in_this_bitmap = sector_count % 4096;
            if (blocks_in_this_bitmap == 0) blocks_in_this_bitmap = 4096;
        }
        
        uint32_t start_block = i * 4096;
        uint32_t end_block = start_block + blocks_in_this_bitmap;
        
        for (uint32_t block = start_block; block < end_block; block++) {
            if (block < superblock.data_start) {
                // Mark block as used
                uint32_t byte_index = block / 8;
                uint32_t bit_index = block % 8;
                bitmap_buffer[byte_index] |= (1 << bit_index);
            }
        }
        
        write_sectors_bios(lba + superblock.bitmap_start + i, 1, bitmap_buffer);
    }
    
    // Initialize file table (all empty)
    dac_file_entry empty_entry;
    for (int i = 0; i < 11; i++) empty_entry.filename[i] = 0;
    empty_entry.attributes = 0;
    empty_entry.first_block = 0;
    empty_entry.file_size = 0;
    empty_entry.block_count = 0;
    
    for (uint32_t i = 0; i < superblock.ftable_blocks; i++) {
        for (int j = 0; j < 16; j++) {
            filetable_buffer[j] = empty_entry;
        }
        
        // First entry is root directory
        if (i == 0) {
            filetable_buffer[0].filename[0] = '.';
            filetable_buffer[0].filename[1] = 0;
            filetable_buffer[0].attributes = 0x10;  // Directory
            filetable_buffer[0].first_block = 0;
            filetable_buffer[0].file_size = 0;
            filetable_buffer[0].block_count = 0;
        }
        
        write_sectors_bios(lba + superblock.ftable_start + i, 1, filetable_buffer);
    }
    
    append_string("Formatted partition as DAC filesystem\r\n");
}

// Mount a partition
void mount_partition(uint8_t index, uint32_t lba) {
    if (index >= 3) return;
    
    read_superblock(lba);
    
    if (validate_superblock()) {
        partition_lba[index] = lba;
        partition_valid[index] = true;
        
        append_string("Mounted ");
        append_string(mount_names[index]);
        append_string(" as '");
        
        // Print volume label (null-terminated)
        char label[33];
        int label_len = 0;
        for (int i = 0; i < 32; i++) {
            if (superblock.volume_label[i] == 0) break;
            label[label_len++] = superblock.volume_label[i];
        }
        label[label_len] = 0;
        
        append_string(label);
        append_string("'\r\n");
    } else {
        append_string("Invalid DAC filesystem on partition\r\n");
    }
}

// Read a bitmap block
void read_bitmap_block(uint32_t block) {
    uint32_t lba = partition_lba[0] + superblock.bitmap_start + block;
    read_sectors_bios(lba, 1, bitmap_buffer);
}

// Write a bitmap block
void write_bitmap_block(uint32_t block) {
    uint32_t lba = partition_lba[0] + superblock.bitmap_start + block;
    write_sectors_bios(lba, 1, bitmap_buffer);
}

// Read a filetable block
void read_filetable_block(uint32_t block) {
    uint32_t lba = partition_lba[0] + superblock.ftable_start + block;
    read_sectors_bios(lba, 1, filetable_buffer);
}

// Write a filetable block
void write_filetable_block(uint32_t block) {
    uint32_t lba = partition_lba[0] + superblock.ftable_start + block;
    write_sectors_bios(lba, 1, filetable_buffer);
}

// Find a free block
uint16_t find_free_block(void) {
    for (uint32_t i = 0; i < superblock.bitmap_blocks; i++) {
        read_bitmap_block(i);
        
        // Check each byte
        for (int j = 0; j < 512; j++) {
            if (bitmap_buffer[j] != 0xFF) {  // Not all bits set
                // Find free bit
                for (int k = 0; k < 8; k++) {
                    if (!(bitmap_buffer[j] & (1 << k))) {
                        uint16_t block = (i * 4096) + (j * 8) + k;
                        if (block >= superblock.data_start && block < superblock.total_blocks) {
                            return block;
                        }
                    }
                }
            }
        }
    }
    
    return 0;  // No free block
}

// Find a free file table entry
uint16_t find_free_file_entry(void) {
    for (uint32_t i = 0; i < superblock.ftable_blocks; i++) {
        read_filetable_block(i);
        
        for (int j = 0; j < 16; j++) {
            if (filetable_buffer[j].filename[0] == 0 || filetable_buffer[j].filename[0] == 0xE5) {
                return (i * 16) + j;
            }
        }
    }
    
    return 0xFFFF;  // No free entry
}

// Mark block as used
void mark_block_used(uint16_t block) {
    uint32_t bitmap_block = block / 4096;
    uint32_t byte_in_block = (block % 4096) / 8;
    uint32_t bit_in_byte = block % 8;
    
    read_bitmap_block(bitmap_block);
    bitmap_buffer[byte_in_block] |= (1 << bit_in_byte);
    write_bitmap_block(bitmap_block);
    
    superblock.free_blocks--;
}

// Mark block as free
void mark_block_free(uint16_t block) {
    uint32_t bitmap_block = block / 4096;
    uint32_t byte_in_block = (block % 4096) / 8;
    uint32_t bit_in_byte = block % 8;
    
    read_bitmap_block(bitmap_block);
    bitmap_buffer[byte_in_block] &= ~(1 << bit_in_byte);
    write_bitmap_block(bitmap_block);
    
    superblock.free_blocks++;
}

// Main initialization function
const char* fat_init(void) {
    output_pos = 0;
    output_buffer[0] = 0;
    
    append_string("DAC Filesystem Initialization\r\n");
    
    // Mount boot device as &1 (always)
    partition_lba[0] = 0;
    partition_valid[0] = true;
    append_string("Mounted boot device as &1\r\n");
    
    // Scan for existing DAC partitions
    append_string("Scanning for DAC partitions...\r\n");
    if (!scan_partitions()) {
        append_string("No DAC partitions found\r\n");
        
        // Format boot device with DAC (simplified - just create superblock)
        // Note: In real implementation, you'd create a partition table entry first
        append_string("Creating DAC filesystem on boot device...\r\n");
        
        // For simplicity, we'll just format starting at LBA 0
        // In reality, you should create a partition and format that
        format_partition(0, 32768, "NEWVOL");  // 16MB = 32768 sectors
        
        mount_partition(1, 0);  // Mount newly created filesystem as &2
    }
    
    append_string("DAC filesystem ready\r\n");
    
    return output_buffer;
}

// List directory contents
const char* fat_list_dir(void) {
    output_pos = 0;
    output_buffer[0] = 0;
    
    if (!partition_valid[0] || !validate_superblock()) {
        append_string("No filesystem mounted\r\n");
        return output_buffer;
    }
    
    append_string("Directory listing of &1:\r\n");
    append_string("Name       Size    Blocks\r\n");
    append_string("-------------------------\r\n");
    
    uint16_t entry_count = 0;
    
    // Read all file table blocks
    for (uint32_t i = 0; i < superblock.ftable_blocks; i++) {
        read_filetable_block(i);
        
        for (int j = 0; j < 16; j++) {
            if (filetable_buffer[j].filename[0] != 0 && filetable_buffer[j].filename[0] != 0xE5) {
                // Print filename (8.3 format)
                char name[13];
                int pos = 0;
                
                // Copy main name (8 chars)
                for (int k = 0; k < 8 && filetable_buffer[j].filename[k] != ' '; k++) {
                    name[pos++] = filetable_buffer[j].filename[k];
                }
                
                // Add extension if present
                if (filetable_buffer[j].filename[8] != ' ') {
                    name[pos++] = '.';
                    for (int k = 8; k < 11 && filetable_buffer[j].filename[k] != ' '; k++) {
                        name[pos++] = filetable_buffer[j].filename[k];
                    }
                }
                name[pos] = 0;
                
                append_string(name);
                
                // Pad to 12 characters
                for (int k = pos; k < 12; k++) {
                    append_char(' ');
                }
                
                // Print size
                uint32_t size = filetable_buffer[j].file_size;
                append_number(size);
                
                // Pad size to 8 characters
                if (size < 10) append_string("       ");
                else if (size < 100) append_string("      ");
                else if (size < 1000) append_string("     ");
                else if (size < 10000) append_string("    ");
                else if (size < 100000) append_string("   ");
                else if (size < 1000000) append_string("  ");
                else if (size < 10000000) append_string(" ");
                
                append_string("    ");
                
                // Print block count
                uint16_t blocks = filetable_buffer[j].block_count;
                append_number(blocks);
                append_string("\r\n");
                
                entry_count++;
            }
        }
    }
    
    if (entry_count == 0) {
        append_string("Empty directory\r\n");
    }
    
    // Print free space
    uint32_t free_kb = (superblock.free_blocks * superblock.block_size) / 1024;
    
    append_string("\r\nFree space: ");
    append_number(free_kb);
    append_string(" KB\r\n");
    
    return output_buffer;
}

// Create a new file
const char* fat_create_file(void) {
    output_pos = 0;
    output_buffer[0] = 0;
    
    if (!partition_valid[0] || !validate_superblock()) {
        append_string("No filesystem mounted\r\n");
        return output_buffer;
    }
    
    // Find free file entry
    uint16_t entry_index = find_free_file_entry();
    if (entry_index == 0xFFFF) {
        append_string("File table full\r\n");
        return output_buffer;
    }
    
    // Find free block
    uint16_t block = find_free_block();
    if (block == 0) {
        append_string("No free space\r\n");
        return output_buffer;
    }
    
    // Read the filetable block containing our entry
    uint32_t block_index = entry_index / 16;
    uint32_t entry_in_block = entry_index % 16;
    
    read_filetable_block(block_index);
    
    // Create a simple file entry
    filetable_buffer[entry_in_block].filename[0] = 'N';
    filetable_buffer[entry_in_block].filename[1] = 'E';
    filetable_buffer[entry_in_block].filename[2] = 'W';
    filetable_buffer[entry_in_block].filename[3] = 'F';
    filetable_buffer[entry_in_block].filename[4] = 'I';
    filetable_buffer[entry_in_block].filename[5] = 'L';
    filetable_buffer[entry_in_block].filename[6] = 'E';
    filetable_buffer[entry_in_block].filename[7] = ' ';
    filetable_buffer[entry_in_block].filename[8] = 'T';
    filetable_buffer[entry_in_block].filename[9] = 'X';
    filetable_buffer[entry_in_block].filename[10] = 'T';
    
    filetable_buffer[entry_in_block].attributes = 0x20;  // Archive
    filetable_buffer[entry_in_block].first_block = block;
    filetable_buffer[entry_in_block].file_size = 0;
    filetable_buffer[entry_in_block].last_block = block;
    filetable_buffer[entry_in_block].block_count = 1;
    filetable_buffer[entry_in_block].modified_time = 0x87654321;  // Placeholder
    
    // Mark block as used
    mark_block_used(block);
    
    // Write updated file table
    write_filetable_block(block_index);
    
    // Update superblock (free blocks count changed)
    write_superblock(partition_lba[0]);
    
    append_string("Created file NEWFILE.TXT\r\n");
    
    return output_buffer;
}
