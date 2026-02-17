[bits 16]
[org 0x7C00]

start:
    ; --- ORIGINAL BOOT START (DO NOT CHANGE) ---
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00
    mov [boot_drive], dl

    ; Enable A20
    mov ax, 0x2401
    int 0x15

    ; --- ENTER UNREAL MODE ---
    cli
    lgdt [gdt_descriptor]
    mov eax, cr0
    or al, 1
    mov cr0, eax

    mov bx, 0x08
    mov ds, bx
    mov es, bx

    and al, 0xFE
    mov cr0, eax

    xor ax, ax
    mov ds, ax
    mov es, ax
    sti

    mov ax, 0x0003
    int 0x10
    ; --- END ORIGINAL BOOT START ---

    ; Added: Call detection info
    call detect_system_info
    
    mov si, starting_msg
    call print_string

    ; Added: 2 Second Delay (0x1E8480 microseconds)
    mov ah, 0x86
    mov cx, 0x001E
    mov dx, 0x8480
    int 0x15

    ; --- ORIGINAL LOAD KERNEL (DO NOT CHANGE) ---
    mov byte [retry_count], 3
.load_retry:
    mov ax, 0x0214      ; Read 20 sectors (0x14)
    mov cx, 0x0002      ; Sector 2
    mov dx, [boot_drive]
    mov bx, 0x7E00
    int 0x13
    jnc .load_success
    
    dec byte [retry_count]
    jz disk_error
    xor ax, ax
    int 0x13
    jmp .load_retry

.load_success:
    jmp 0x0000:0x7E00

; --- MODIFIED DETECTION SECTION ---

detect_system_info:
    ; RAM Detection
    mov si, ram_msg
    call print_string
    mov ax, 0xE801
    int 0x15
    jc .fallback
    shr cx, 10
    mov ax, dx
    shr ax, 4
    add ax, cx
    inc ax
    call print_decimal_32
    mov si, mb_msg
    call print_string
    jmp .hd_check
.fallback:
    int 0x12
    call print_decimal_32
    mov si, kb_msg
    call print_string

.hd_check:
    call newline
    mov si, hd_msg
    call print_string
    mov dl, 0x80
    mov ax, 0x4100
    mov bx, 0x55AA
    int 0x13
    mov si, yes_msg
    jnc .print_hd
    mov si, no_msg
.print_hd:
    call print_string
    call newline

    ; Added: CPU Info (Not Implemented as requested)
    mov si, cpu_msg
    call print_string
    mov si, cpu_ni_msg
    call print_string
    call newline
    ret

; --- UTILITIES ---

print_decimal_32:
    pushad
    mov bx, 10
    xor cx, cx
.div32:
    xor dx, dx
    div bx
    push dx
    inc cx
    or ax, ax
    jnz .div32
.pri32:
    pop ax
    add al, '0'
    mov ah, 0x0E
    int 0x10
    loop .pri32
    popad
    ret

print_string:
    lodsb
    or al, al
    jz .done
    mov ah, 0x0E
    int 0x10
    jmp print_string
.done:
    ret

newline:
    mov ax, 0x0E0D
    int 0x10
    mov al, 0x0A
    int 0x10
    ret

disk_error:
    mov si, error_msg
    call print_string
    jmp $

; --- GDT (DO NOT CHANGE) ---
align 16
gdt_start:
    dq 0x0
gdt_data:
    dw 0xFFFF, 0x0000
    db 0x00, 10010010b, 11001111b, 0x00
gdt_end:

align 4
gdt_descriptor:
    dw gdt_end - gdt_start - 1
    dd gdt_start

; --- DATA AREA ---
boot_drive      dw 0
retry_count     db 0
starting_msg    db 13, 10, "Starting DDOS...", 13, 10, 0
ram_msg         db "RAM: ~", 0
kb_msg          db " KB", 0
mb_msg          db " MB", 0
hd_msg          db "HDD: ", 0
cpu_msg         db "CPU: ", 0
cpu_ni_msg      db "Not Implemented", 0  ; Requested placeholder
yes_msg         db "YES", 0
no_msg          db "NO", 0
error_msg       db "Disk Err!", 0

times 510-($-$$) db 0
dw 0xAA55
