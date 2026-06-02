[bits 16]

global start
global read_sectors_bios
global write_sectors_bios

extern get_test_message

section .text

start:
    ; Save boot drive (passed by bootloader in DL)
    mov [boot_drive], dl

    ; Setup segments for stability
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0xFFFF

    ; ---- Enable A20 line (fast gate) ----
    in al, 0x92
    or al, 2
    out 0x92, al

    ; Set video mode (Clear Screen) - default 80x25
    mov ah, 0x00
    mov al, 0x03
    int 0x10
    mov byte [gui_mode], 0
    mov word [cursor_pos], 0
    mov byte [current_color], 0x07   ; light grey on black
    mov byte [cursor_visible], 1     ; cursor on by default

    mov si, welcome
    call print

main_loop:
    call move_prompt_left
    mov si, prompt_msg
    call print
    call set_vga_cursor              ; direct VGA cursor update
    call read_input

    ; --- Command Checks ---
    mov si, input_buffer

    mov di, test_cmd
    call str_eq
    cmp al, 1
    je do_test

    mov si, input_buffer
    mov di, info_cmd
    call str_eq
    cmp al, 1
    je do_info

    mov si, input_buffer
    mov di, clear_cmd
    call str_eq
    cmp al, 1
    je do_clear

    mov si, input_buffer
    mov di, shutdown_cmd
    call str_eq
    cmp al, 1
    je do_shutdown

    mov si, input_buffer
    mov di, reboot_cmd
    call str_eq
    cmp al, 1
    je do_reboot

    mov si, input_buffer
    mov di, help_cmd
    call str_eq
    cmp al, 1
    je do_help

    mov si, input_buffer
    mov di, echo_cmd
    call str_prefix_eq
    cmp al, 1
    je do_echo

    mov si, input_buffer
    mov di, changegui_cmd
    call str_eq
    cmp al, 1
    je do_changegui

    mov si, input_buffer
    mov di, freeram_cmd
    call str_eq
    cmp al, 1
    je do_freeram

    mov si, input_buffer
    mov di, cpuid_cmd
    call str_eq
    cmp al, 1
    je do_cpuid

    mov si, input_buffer
    mov di, bgcolor_cmd
    call str_prefix_eq
    cmp al, 1
    je do_bgcolor

    mov si, input_buffer
    mov di, txtcolor_cmd
    call str_prefix_eq
    cmp al, 1
    je do_txtcolor

    mov si, input_buffer
    mov di, resetpal_cmd
    call str_eq
    cmp al, 1
    je do_resetpal

    mov si, input_buffer
    mov di, togglecurs_cmd
    call str_eq
    cmp al, 1
    je do_togglecurs

    mov si, input_buffer
    mov di, ver_cmd
    call str_eq
    cmp al, 1
    je do_ver

    mov si, input_buffer
    mov di, umode_cmd
    call str_eq
    cmp al, 1
    je do_umode

    mov si, input_buffer
    mov di, viewsector_cmd
    call str_prefix_eq
    cmp al, 1
    je do_viewsector

    ; If no command matched
    mov si, unknown_msg
    call print
    jmp main_loop

; --- Command Handlers ---

do_test:
    call get_test_message
    mov si, ax
    call print
    call newline
    jmp main_loop

do_info:
    mov si, info_msg
    call print
    jmp main_loop

do_clear:
    call fill_screen_current_color
    jmp main_loop

do_shutdown:
    mov si, shutdown_msg
    call print
    ; APM shutdown
    mov ax, 0x5301
    xor bx, bx
    int 0x15
    jc .apm_fail
    mov ax, 0x530E
    xor bx, bx
    mov cx, 0x0102
    int 0x15
    jc .apm_fail
    mov ax, 0x5307
    mov bx, 0x0001
    mov cx, 0x0003
    int 0x15
    jc .apm_fail
    jmp .apm_fail
.apm_fail:
    mov si, apm_fail_msg
    call print
    cli
    hlt

do_reboot:
    mov si, reboot_msg
    call print
    jmp 0xFFFF:0x0000

do_help:
    mov si, help_msg
    call print
    jmp main_loop

do_echo:
    mov si, input_buffer
    add si, 4
.echo_skip_spaces:
    mov al, [si]
    cmp al, ' '
    je .echo_inc
    jmp .echo_print_start
.echo_inc:
    inc si
    jmp .echo_skip_spaces
.echo_print_start:
    cmp byte [si], '"'
    jne .echo_print_nq
    inc si
.echo_print_q:
    mov al, [si]
    or al, al
    jz .echo_done
    cmp al, '"'
    je .echo_done
    call print_char
    inc si
    jmp .echo_print_q
.echo_print_nq:
.echo_print_nq_loop:
    mov al, [si]
    or al, al
    jz .echo_done
    call print_char
    inc si
    jmp .echo_print_nq_loop
.echo_done:
    call newline
    jmp main_loop

do_changegui:
    cmp byte [gui_mode], 0
    je .set_small
    mov ah, 0x00
    mov al, 0x03
    int 0x10
    mov byte [gui_mode], 0
    mov word [cursor_pos], 0
    mov byte [current_color], 0x07
    mov si, big_msg
    call print
    jmp main_loop
.set_small:
    mov ah, 0x00
    mov al, 0x03
    int 0x10
    mov ax, 0x1112
    mov bl, 0
    int 0x10
    mov byte [gui_mode], 1
    mov word [cursor_pos], 0
    mov byte [current_color], 0x07
    mov si, small_msg
    call print
    jmp main_loop

; -------------------------------------------------------------------
; freeram – display available conventional and extended memory
do_freeram:
    mov si, conventional_msg
    call print
    int 0x12
    call print_dec
    mov si, kb_msg
    call print
    call newline

    mov si, extended_msg
    call print
    mov ah, 0x88
    int 0x15
    jc .no_extmem
    cmp ax, 0
    je .no_extmem
    call print_dec
    mov si, kb_msg
    call print
    call newline
    jmp .check_umode
.no_extmem:
    mov si, not_avail_msg
    call print
    call newline
.check_umode:
    cmp byte [unreal_mode_active], 1
    jne .done_freeram
    mov si, umode_enabled_msg
    call print
    call newline
.done_freeram:
    jmp main_loop

; -------------------------------------------------------------------
; cpuid – display CPU brand string and core count
do_cpuid:
    pushfd
    pop eax
    mov ecx, eax
    xor eax, 0x00200000
    push eax
    popfd
    pushfd
    pop eax
    xor eax, ecx
    jz .no_cpuid

    mov eax, 0x80000000
    cpuid
    cmp eax, 0x80000004
    jb .no_brand

    mov si, cpu_brand_msg
    call print

    mov edi, cpu_name_buffer
    mov eax, 0x80000002
    cpuid
    mov [edi], eax
    mov [edi+4], ebx
    mov [edi+8], ecx
    mov [edi+12], edx

    mov eax, 0x80000003
    cpuid
    mov [edi+16], eax
    mov [edi+20], ebx
    mov [edi+24], ecx
    mov [edi+28], edx

    mov eax, 0x80000004
    cpuid
    mov [edi+32], eax
    mov [edi+36], ebx
    mov [edi+40], ecx
    mov [edi+44], edx

    mov si, cpu_name_buffer
    call print
    call newline
    jmp .core_info

.no_brand:
    mov si, unknown_brand_msg
    call print
    call newline

.core_info:
    xor eax, eax
    cpuid
    cmp eax, 0x0B
    jb .use_leaf1

    xor ecx, ecx
.enum_level:
    mov eax, 0x0B
    cpuid
    mov dl, al
    and dl, 0x1F
    cmp dl, 0
    je .use_leaf1
    cmp dl, 2
    jne .next_sub
    mov si, core_count_msg
    call print
    mov ax, bx
    and ax, 0xFFFF
    call print_dec
    call newline
    jmp .check_umode_cpuid
.next_sub:
    inc ecx
    cmp ecx, 4
    jb .enum_level
    jmp .use_leaf1

.use_leaf1:
    mov eax, 1
    cpuid
    shr ebx, 16
    mov ax, bx
    and ax, 0xFF
    mov si, logical_procs_msg
    call print
    call print_dec
    call newline

.check_umode_cpuid:
    cmp byte [unreal_mode_active], 1
    jne .done_cpuid
    mov si, umode_cpu_msg
    call print
    call newline
.done_cpuid:
    jmp main_loop

.no_cpuid:
    mov si, no_cpuid_msg
    call print
    call newline
    jmp main_loop

; -------------------------------------------------------------------
; bgcolor – set background color and repaint screen
do_bgcolor:
    mov si, input_buffer
    add si, 7
    call skip_spaces
    call parse_hex_nibble
    jc .invalid
    shl al, 4
    and byte [current_color], 0x0F
    or byte [current_color], al
    call fill_screen_current_color
    jmp main_loop
.invalid:
    mov si, invalid_color_msg
    call print
    jmp main_loop

; -------------------------------------------------------------------
; txtcolor – set text color and repaint screen
do_txtcolor:
    mov si, input_buffer
    add si, 8
    call skip_spaces
    call parse_hex_nibble
    jc .invalid
    and byte [current_color], 0xF0
    or byte [current_color], al
    call fill_screen_current_color
    jmp main_loop
.invalid:
    mov si, invalid_color_msg
    call print
    jmp main_loop

; -------------------------------------------------------------------
; resetpal – reset palette to default black bg, light grey text
do_resetpal:
    mov byte [current_color], 0x07
    call fill_screen_current_color
    jmp main_loop

; -------------------------------------------------------------------
; togglecurs – toggle hardware cursor on/off
do_togglecurs:
    xor byte [cursor_visible], 1
    cmp byte [cursor_visible], 0
    je .off
    call fill_screen_current_color
    call enable_cursor
    jmp main_loop
.off:
    call disable_cursor
    jmp main_loop

; -------------------------------------------------------------------
; ver – show version information
do_ver:
    mov si, ver_msg
    call print
    call newline
    jmp main_loop

; -------------------------------------------------------------------
; umode – enable 16-bit Big Unreal Mode
do_umode:
    cmp byte [unreal_mode_active], 1
    je .already_active

    ; The following sequence enables Big Unreal Mode.
    ; All segment registers (except CS) will hold 4 GiB limits with base 0.
    cli
    lgdt [GDT_desc]             ; load GDT
    mov eax, cr0
    or al, 1
    mov cr0, eax                ; enter protected mode
    jmp 0x08:.pmode             ; load CS with 16-bit code selector

.pmode:
    mov ax, 0x10                ; data selector (base 0, limit 4 GiB)
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax

    ; Return to real mode without losing the cached limits
    mov eax, cr0
    and al, ~1
    mov cr0, eax
    jmp 0x0000:.real            ; reload CS with real-mode segment

.real:
    ; Now the data segments have 4 GiB limits (unreal mode).
    ; Set up a real-mode stack (SS:SP)
    xor ax, ax
    mov ss, ax
    mov sp, 0xFFFF

    ; Interrupts must remain disabled to keep the unreal limits.
    ; The console will use direct keyboard I/O (no BIOS) from now on.
    ; (We enable interrupts again only after the next Enter key.)

    mov byte [unreal_mode_active], 1
    mov si, umode_enable_msg
    call print
    call newline
    jmp main_loop

.already_active:
    mov si, umode_already_msg
    call print
    call newline
    jmp main_loop

; -------------------------------------------------------------------
; viewsector – dump a sector by decimal LBA
do_viewsector:
    mov si, input_buffer
    add si, 10             ; skip "viewsector"
    call skip_spaces
    call atoi              ; AX = decimal LBA, CF if error
    jc .bad_args
    ; Read sector into sector_buffer
    push word sector_buffer
    push word 1            ; count
    push ax                ; LBA
    call read_sectors_bios
    add sp, 6
    jc .read_error
    ; Hex dump
    mov si, sector_buffer
    xor bx, bx             ; offset counter
.dump_line:
    mov ax, bx
    call print_hex_word
    mov al, ' '
    call print_char
    ; hex bytes
    push bx
    mov cx, 16
.hex_loop:
    lodsb
    call print_hex_byte
    mov al, ' '
    call print_char
    loop .hex_loop
    ; ASCII dump
    sub si, 16
    mov cx, 16
    mov al, ' '
    call print_char
.ascii_loop:
    lodsb
    cmp al, 32
    jb .dot
    cmp al, 127
    jb .printable
.dot:
    mov al, '.'
.printable:
    call print_char
    loop .ascii_loop
    call newline
    pop bx
    add bx, 16
    cmp bx, 512
    jb .dump_line
    jmp main_loop
.bad_args:
    mov si, viewsector_usage
    call print
    jmp main_loop
.read_error:
    mov si, sector_read_err
    call print
    call newline
    jmp main_loop

; -------------------------------------------------------------------
; Utility: skip spaces, SI updated
skip_spaces:
    mov al, [si]
    cmp al, ' '
    jne .done
    inc si
    jmp skip_spaces
.done:
    ret

; Parse one hex nibble from [si], return in AL, CF=1 on error
parse_hex_nibble:
    xor al, al
    mov al, [si]
    cmp al, '0'
    jb .err
    cmp al, '9'
    jbe .digit
    and al, 0xDF
    cmp al, 'A'
    jb .err
    cmp al, 'F'
    ja .err
    sub al, 'A' - 10
    inc si
    clc
    ret
.digit:
    sub al, '0'
    inc si
    clc
    ret
.err:
    stc
    ret

; Convert decimal string at SI to number in AX, CF set if no digits or overflow
atoi:
    xor bx, bx          ; accumulator
    xor cx, cx          ; flag: any digit parsed?
.loop:
    lodsb
    cmp al, '0'
    jb .done
    cmp al, '9'
    ja .done
    sub al, '0'
    mov ah, 0
    push ax             ; save digit
    mov ax, 10
    mul bx              ; DX:AX = old * 10
    mov bx, ax          ; keep low 16 bits
    pop ax              ; digit
    add bx, ax
    jc .overflow
    mov cx, 1           ; we have at least one digit
    jmp .loop
.done:
    dec si              ; point back to non‑digit
    test cx, cx
    jz .nodigit
    mov ax, bx
    clc
    ret
.nodigit:
    stc
    ret
.overflow:
    stc
    ret

; Print hex byte in AL
print_hex_byte:
    push ax
    shr al, 4
    call print_hex_nibble
    pop ax
    and al, 0x0F
    call print_hex_nibble
    ret

; Print hex nibble (lower 4 bits of AL)
print_hex_nibble:
    push ax
    and al, 0x0F
    add al, '0'
    cmp al, '9'
    jbe .ok
    add al, 7
.ok:
    call print_char
    pop ax
    ret

; Print hex word (4 digits) in AX
print_hex_word:
    push ax
    mov al, ah
    call print_hex_byte
    pop ax
    call print_hex_byte
    ret

; Fill entire screen with space + current_color, reset cursor to 0
fill_screen_current_color:
    push es
    push di
    push cx
    push ax
    mov ax, 0xB800
    mov es, ax
    xor di, di
    mov al, [gui_mode]
    cmp al, 0
    je .small_mode
    mov cx, 4000
    jmp .fill_screen
.small_mode:
    mov cx, 2000
.fill_screen:
    mov ah, [current_color]
    mov al, ' '
    cld
    rep stosw
    mov word [cursor_pos], 0
    call set_vga_cursor
    pop ax
    pop cx
    pop di
    pop es
    ret

; -------------------------------------------------------------------
; Direct VGA cursor control (no BIOS)
set_vga_cursor:
    push bx
    push dx
    push ax
    mov ax, [cursor_pos]
    shr ax, 1               ; character cell index
    mov bx, ax
    mov dx, 0x3D4
    mov al, 0x0E
    out dx, al
    inc dx
    mov al, bh
    out dx, al
    dec dx
    mov al, 0x0F
    out dx, al
    inc dx
    mov al, bl
    out dx, al
    pop ax
    pop dx
    pop bx
    ret

enable_cursor:
    push ax
    push dx
    mov dx, 0x3D4
    mov al, 0x0A
    out dx, al
    inc dx
    mov al, 0x0E
    out dx, al
    dec dx
    mov al, 0x0B
    out dx, al
    inc dx
    mov al, 0x0F
    out dx, al
    pop dx
    pop ax
    ret

disable_cursor:
    push ax
    push dx
    mov dx, 0x3D4
    mov al, 0x0A
    out dx, al
    inc dx
    mov al, 0x20
    out dx, al
    pop dx
    pop ax
    ret

; -------------------------------------------------------------------
; LBA to CHS conversion (floppy geometry)
; Input:  AX = LBA
; Output: AL = sector (1-63), BL = head, CX = cylinder
lba_to_chs:
    push dx
    xor dx, dx
    div word [SectorsPerTrack]   ; AX = LBA/SPT, DX = LBA%SPT
    inc dl
    mov [.temp_sector], dl
    xor dx, dx
    div word [NumHeads]          ; AX = (LBA/SPT)/Heads, DX = (LBA/SPT)%Heads
    mov [.temp_cyl], ax
    mov [.temp_head], dl
    mov al, [.temp_sector]
    mov bl, [.temp_head]
    mov cx, [.temp_cyl]
    pop dx
    ret
.temp_sector db 0
.temp_head   db 0
.temp_cyl    dw 0

; Pack CHS values for INT 13h
; Input:  AL = sector (1-63), BL = head, CX = cylinder (0-1023)
; Output: DH = head, CH = low 8 bits of cylinder, CL = sector | (high cylinder bits << 6)
chs_pack_int13:
    push bx
    mov dh, bl          ; head -> DH
    mov bh, cl          ; low 8 bits of cylinder
    mov bl, ch          ; high byte of cylinder
    and bl, 3           ; mask bits 8-9
    and al, 0x3F        ; sector within 0-63
    shl bl, 6
    or al, bl           ; AL = sector | (high cyl << 6)
    mov cl, al
    mov ch, bh          ; CH = low cylinder
    pop bx
    ret

; -------------------------------------------------------------------
; Disk I/O Functions (updated to use lba_to_chs)
read_sectors_bios:
    push bp
    mov bp, sp
    pusha
    mov ax, [bp+4]          ; LBA
    mov cx, [bp+6]          ; count
    mov bx, [bp+8]          ; buffer
    push cx                 ; save count
    call lba_to_chs
    call chs_pack_int13     ; sets CH, CL, DH
    pop ax                  ; count -> AL
    mov ah, 0x02
    mov dl, [boot_drive]
    push es
    xor ax, ax
    mov es, ax              ; buffer segment 0 (adjust if needed)
    int 0x13
    pop es
    popa
    pop bp
    ret

write_sectors_bios:
    push bp
    mov bp, sp
    pusha
    mov ax, [bp+4]
    mov cx, [bp+6]
    mov bx, [bp+8]
    push cx
    call lba_to_chs
    call chs_pack_int13
    pop ax
    mov ah, 0x03
    mov dl, [boot_drive]
    push es
    xor ax, ax
    mov es, ax
    int 0x13
    pop es
    popa
    pop bp
    ret

; -------------------------------------------------------------------
; Core Functions (direct VGA output + VGA cursor sync)

print:
    lodsb
    or al, al
    jz .done
    call print_char
    jmp print
.done:
    ret

print_char:
    push ax
    push bx
    push dx
    push es
    push di

    cmp al, 0x0D
    je .cr
    cmp al, 0x0A
    je .lf

    ; Write character and attribute to VGA memory
    mov bx, 0xB800
    mov es, bx
    mov di, [cursor_pos]
    mov [es:di], al
    mov al, [current_color]
    mov [es:di+1], al

    add word [cursor_pos], 2
    jmp .check_scroll

.cr:
    mov ax, [cursor_pos]
    mov bl, 160
    div bl
    mul bl
    mov [cursor_pos], ax
    jmp .done_char

.lf:
    add word [cursor_pos], 160
    jmp .check_scroll

.check_scroll:
    mov ax, [cursor_pos]
    mov bl, [gui_mode]
    cmp bl, 0
    je .check_small
    cmp ax, 8000
    jb .done_char
    jmp .do_scroll
.check_small:
    cmp ax, 4000
    jb .done_char
.do_scroll:
    call scroll_screen

.done_char:
    call set_vga_cursor
    pop di
    pop es
    pop dx
    pop bx
    pop ax
    ret

; Scrolling function – uses BIOS when not in unreal mode,
; otherwise uses direct VGA memory copy to avoid segment corruption.
scroll_screen:
    cmp byte [unreal_mode_active], 1
    je .direct_vga
    ; BIOS scroll (user's existing mechanic)
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push es
    push ds
    mov ah, 0x06              ; scroll window up
    mov al, 1                 ; lines to scroll
    mov bh, [current_color]   ; attribute for cleared line
    xor ch, ch                ; top row 0
    xor cl, cl                ; left col 0
    mov dl, 79                ; right col 79
    mov bl, [gui_mode]
    cmp bl, 0
    je .bios_small
    mov dh, 49                ; bottom row 49 for 80x50
    jmp .bios_scroll
.bios_small:
    mov dh, 24                ; bottom row 24 for 80x25
.bios_scroll:
    int 0x10
    pop ds
    pop es
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    sub word [cursor_pos], 160
    ret

.direct_vga:
    ; Direct memory scroll (preserves unreal mode segments)
    push es
    push ds
    push si
    push di
    push cx
    mov ax, 0xB800
    mov ds, ax
    mov es, ax
    mov si, 160
    xor di, di
    mov cx, 1920
    cld                 ; make sure we copy forward
    rep movsw
    ; Clear last line
    mov di, 3840
    mov cx, 80
    mov ah, [current_color]
    mov al, ' '
    rep stosw
    sub word [cursor_pos], 160
    pop cx
    pop di
    pop si
    pop ds
    pop es
    ret

move_prompt_left:
    push ax
    push bx
    mov ax, [cursor_pos]
    mov bl, 160
    div bl
    mul bl
    mov [cursor_pos], ax
    call set_vga_cursor
    pop bx
    pop ax
    ret

print_dec:
    pusha
    mov cx, 10
    xor bx, bx
.div_loop:
    xor dx, dx
    div cx
    push dx
    inc bx
    test ax, ax
    jnz .div_loop
.print_loop:
    pop ax
    add al, '0'
    call print_char
    dec bx
    jnz .print_loop
    popa
    ret

; -------------------------------------------------------------------
; Keyboard input – chooses between BIOS and direct I/O
read_input:
    cmp byte [unreal_mode_active], 1
    je read_input_unreal
    ; Normal BIOS input
    mov di, input_buffer
.r_bios:
    mov ah, 0
    int 0x16
    cmp al, 0
    jne .handle_ascii
    cmp ah, 0x48
    je .k_up
    cmp ah, 0x50
    je .k_down
    jmp .r_bios
.handle_ascii:
    cmp al, 0x0D
    je .e
    cmp al, 0x08
    je .b
    stosb
    call print_char
    jmp .r_bios
.b:
    cmp di, input_buffer
    je .r_bios
    dec di
    sub word [cursor_pos], 2
    push ax
    mov al, ' '
    call print_char
    sub word [cursor_pos], 2
    pop ax
    jmp .r_bios
.e:
    mov al, 0
    stosb
    mov si, input_buffer
    lodsb
    or al, al
    jz .no_store
    lea di, [history]
    mov bl, [history_head]
    xor ax, ax
    mov al, bl
    shl ax, 6
    add di, ax
.copy_hist:
    mov al, [si]
    mov [di], al
    inc si
    inc di
    or al, al
    jne .copy_hist
    mov al, [history_head]
    inc al
    and al, 7
    mov [history_head], al
    mov al, [history_count]
    cmp al, 8
    jae .no_store
    inc byte [history_count]
.no_store:
    call newline
    ret
.k_up:
    mov al, [history_count]
    or al, al
    jz .r_bios
    mov al, [history_pos]
    mov bl, [history_count]
    cmp al, bl
    jae .r_bios
    inc byte [history_pos]
    mov al, [history_head]
    add al, 8
    sub al, [history_pos]
    and al, 7
    mov bl, al
    lea si, [history]
    xor ax, ax
    mov al, bl
    shl ax, 6
    add si, ax
    lea di, [input_buffer]
.copy_from_hist:
    mov al, [si]
    mov [di], al
    inc si
    inc di
    or al, al
    jne .copy_from_hist
    call move_prompt_left
    mov si, prompt_msg
    call print
    mov si, input_buffer
    call print
    call set_vga_cursor
    ret
.k_down:
    mov al, [history_pos]
    or al, al
    jz .r_bios
    dec byte [history_pos]
    mov al, [history_pos]
    or al, al
    jz .clear_input
    mov bl, [history_pos]
    mov al, [history_head]
    add al, 8
    sub al, bl
    and al, 7
    mov bl, al
    lea si, [history]
    xor ax, ax
    mov al, bl
    shl ax, 6
    add si, ax
    lea di, [input_buffer]
    jmp .copy_from_hist
.clear_input:
    mov byte [input_buffer], 0
    call move_prompt_left
    mov si, prompt_msg
    call print
    call set_vga_cursor
    ret

; -------------------------------------------------------------------
; Direct keyboard input for unreal mode (interrupts disabled)
; Polls keyboard controller and translates scan codes to ASCII.
read_input_unreal:
    cli                     ; keep interrupts off to preserve segments
    mov di, input_buffer
.r_poll:
    call poll_keyboard      ; wait for a scancode -> AL
    cmp al, 0
    je .r_poll              ; should not happen, but loop if no key
    ; Process the scancode (AL)
    cmp al, 0x1C            ; Enter key (make)
    je .enter
    cmp al, 0x0E            ; Backspace (make)
    je .backspace
    ; Ignore key releases (scancode >= 0x80)
    test al, 0x80
    jnz .r_poll
    ; Convert scan code to ASCII
    call scancode_to_ascii  ; returns ASCII in AL, or 0 if not printable
    cmp al, 0
    je .r_poll
    ; Echo character
    stosb
    call print_char
    jmp .r_poll
.backspace:
    cmp di, input_buffer
    je .r_poll
    dec di
    sub word [cursor_pos], 2
    push ax
    mov al, ' '
    call print_char
    sub word [cursor_pos], 2
    pop ax
    jmp .r_poll
.enter:
    mov al, 0
    stosb
    mov si, input_buffer
    lodsb
    or al, al
    jz .no_store
    ; Store in history (same as BIOS routine)
    lea di, [history]
    mov bl, [history_head]
    xor ax, ax
    mov al, bl
    shl ax, 6
    add di, ax
.copy_hist_u:
    mov al, [si]
    mov [di], al
    inc si
    inc di
    or al, al
    jne .copy_hist_u
    mov al, [history_head]
    inc al
    and al, 7
    mov [history_head], al
    mov al, [history_count]
    cmp al, 8
    jae .no_store
    inc byte [history_count]
.no_store:
    call newline
    sti                     ; re-enable interrupts after input is done
    ret

; -------------------------------------------------------------------
; poll_keyboard – waits for a key press and returns the scancode in AL
poll_keyboard:
    push dx
.wait:
    in al, 0x64             ; status port
    test al, 1              ; output buffer full?
    jz .wait
    in al, 0x60             ; scancode
    pop dx
    ret

; -------------------------------------------------------------------
; scancode_to_ascii – convert keyboard scancode (set 1) to ASCII
; Input:  AL = scancode
; Output: AL = ASCII character, 0 if not a valid printable character
scancode_to_ascii:
    ; Only handle a subset of keys for simplicity
    cmp al, 0x01
    je .esc
    cmp al, 0x0F            ; Tab
    je .tab
    cmp al, 0x39            ; Space
    je .space
    ; Numbers row 0x02..0x0B => '1'..'0' (scan set 1: 2=1,3=2,...,0B=0)
    cmp al, 0x02
    jb .not_printable
    cmp al, 0x0B
    ja .check_letters
    sub al, 0x02
    add al, '1'
    cmp al, '9'+1
    jb .ok
    mov al, '0'             ; scancode 0x0B -> '0'
    jmp .ok
.check_letters:
    ; QWERTY... scan set 1: Q=0x10, W=0x11, E=0x12, R=0x13, T=0x14, Y=0x15, U=0x16, I=0x17, O=0x18, P=0x19
    ; A=0x1E, S=0x1F, D=0x20, F=0x21, G=0x22, H=0x23, J=0x24, K=0x25, L=0x26
    ; Z=0x2C, X=0x2D, C=0x2E, V=0x2F, B=0x30, N=0x31, M=0x32
    cmp al, 0x10
    jb .not_printable
    cmp al, 0x19
    jbe .qwerty_row1
    cmp al, 0x1E
    jb .not_printable
    cmp al, 0x26
    jbe .asdf_row
    cmp al, 0x2C
    jb .not_printable
    cmp al, 0x32
    jbe .zxcv_row
    jmp .not_printable

.qwerty_row1:
    sub al, 0x10
    mov bx, .qrow
    xlat
    jmp .ok
.asdf_row:
    sub al, 0x1E
    mov bx, .arow
    xlat
    jmp .ok
.zxcv_row:
    sub al, 0x2C
    mov bx, .zrow
    xlat
    jmp .ok

.esc:
    mov al, 0x1B
    jmp .ok
.tab:
    mov al, 0x09
    jmp .ok
.space:
    mov al, ' '
    jmp .ok
.not_printable:
    xor al, al
.ok:
    ret

; Lookup tables (scan set 1 -> ASCII)
.qrow db 'qwertyuiop'
.arow db 'asdfghjkl'
.zrow db 'zxcvbnm',0,0,0,0   ; only 6 keys defined

; -------------------------------------------------------------------
; String comparison utilities (unchanged)
str_eq:
    push si
    push di
.n:
    lodsb
    mov bl, [di]
    cmp al, bl
    jne .no
    or al, al
    jz .yes
    inc di
    jmp .n
.no:
    mov al, 0
    jmp .done
.yes:
    mov al, 1
.done:
    pop di
    pop si
    ret

str_prefix_eq:
    push si
    push di
.pe_loop:
    mov al, [di]
    mov bl, [si]
    cmp al, 0
    je .pe_check_sep
    cmp al, bl
    jne .pe_no
    inc di
    inc si
    jmp .pe_loop
.pe_check_sep:
    mov al, [si]
    cmp al, 0
    je .pe_yes
    cmp al, ' '
    je .pe_yes
    jmp .pe_no
.pe_yes:
    mov al, 1
    jmp .pe_done
.pe_no:
    mov al, 0
.pe_done:
    pop di
    pop si
    ret

newline:
    push ax
    mov al, 0x0D
    call print_char
    mov al, 0x0A
    call print_char
    pop ax
    ret

; -------------------------------------------------------------------
; GDT for Big Unreal Mode (16-bit code, 4 GiB limits)
gdt_start:
    dq 0
    ; 16-bit code descriptor (selector 0x08)
    dw 0xFFFF           ; limit 0..15
    dw 0                ; base 0..15
    db 0                ; base 16..23
    db 10011010b        ; access: present, ring 0, code, readable
    db 10001111b        ; flags: G=1 (4K pages), D=0 (16-bit), limit high = 0xF
    db 0                ; base 24..31
    ; 16-bit data descriptor (selector 0x10)
    dw 0xFFFF
    dw 0
    db 0
    db 10010010b        ; data, writable
    db 11001111b        ; G=1, D/B=1, limit high = 0xF
    db 0
gdt_end:
GDT_desc:
    dw gdt_end - gdt_start - 1
    dd gdt_start

; -------------------------------------------------------------------
; Data Area (unchanged except added messages)
welcome db "Welcome to DDOS!", 13, 10, 0
prompt_msg db "[#] ", 0
test_cmd db "test", 0
info_cmd db "info", 0
clear_cmd db "clear", 0
shutdown_cmd db "shutdown", 0
reboot_cmd db "reboot", 0
help_cmd db "help", 0
echo_cmd db "echo", 0
changegui_cmd db "changegui", 0
freeram_cmd db "freeram", 0
cpuid_cmd db "cpuid", 0
bgcolor_cmd db "bgcolor", 0
txtcolor_cmd db "txtcolor", 0
resetpal_cmd db "resetpal", 0
togglecurs_cmd db "togglecurs", 0
ver_cmd db "ver", 0
umode_cmd db "umode", 0
viewsector_cmd db "viewsector", 0

info_msg db "DDOS: Dum Dum Operating System, (C) Bocca Gigante Productions", 13, 10
    db "", 13, 10
    db "@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@", 13, 10
    db "@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@", 13, 10
    db "@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@", 13, 10
    db "@@@@+:@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@", 13, 10
    db "@@@ *:+++++@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@", 13, 10
    db "@@@@@@@@++:-+@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@", 13, 10
    db "@@@@@@@@@@@@#=::-+@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@", 13, 10
    db "@@@@@@@@@@@@@@@%+-::--*@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@", 13, 10
    db "@@@@@@@@@@@@@@@@@@@*=-:::-=%@@@@@@@@@@@@@@@@@@@@@@@@@", 13, 10
    db "@@@@@@@@@@@@@         #+=-:::--+@@+      +@@@@@@@@@@@", 13, 10
    db "@@@@@@@@@@@:             -*+=-::----       #@@@@@@@@@", 13, 10
    db "@@@@@@@@@@@                 .-++=-:-.       @@@@@@@@@", 13, 10
    db "@@@@@@@@@@@ %%%                  -+.    #+  @@@@@@@@@", 13, 10
    db "@@@@@@@@@@@ %%%    %%%:           **   %%%* @@@@@@@@@", 13, 10
    db "@@@@@@@@@@@@       %%%%          %%%%      @@@@@@@@@@", 13, 10
    db "@@@@@@@@@@@@@       %%%%%%%%+%%%%%%%      @@@@@@@@@@@", 13, 10
    db "@@@@@@@@@@@@@@@@      #%%%%%%%%%%%:     #@@@@@@@@@@@@", 13, 10
    db "@@@@@@@@@@@@@@@@@@@@@.             ..@@@@@@@@@@@@@@@@", 13, 10
    db "", 13, 10, 0
unknown_msg db "Command unknown", 13, 10, 0
shutdown_msg db "Shutting Down...", 13, 10, 0
apm_fail_msg db "APM shutdown failed. Halting.", 13, 10, 0
reboot_msg db "Rebooting...", 13, 10, 0
help_msg db "Commands: info, clear, shutdown, reboot, help, test, echo, changegui, freeram, cpuid, bgcolor, txtcolor, resetpal, togglecurs, ver, umode, viewsector", 13, 10, 0
big_msg db "Switched to big text mode (80x50)", 13, 10, 0
small_msg db "Switched to small text mode (80x25)", 13, 10, 0
conventional_msg db "Conventional memory: ", 0
extended_msg db "Extended memory: ", 0
kb_msg db " KB", 0
not_avail_msg db "Not available", 0
no_cpuid_msg db "CPUID not supported on this CPU.", 13, 10, 0
cpu_brand_msg db "CPU: ", 0
unknown_brand_msg db "Unknown CPU brand", 0
core_count_msg db "Cores: ", 0
logical_procs_msg db "Logical processors: ", 0
invalid_color_msg db "Invalid color. Use 0-9 or A-F.", 13, 10, 0
ver_msg db "Dum Dum Operating System | Codename: Old Hawk | Build 060226-1 | (C) Bocca Gigante Production", 0
umode_enable_msg db "16 bit Unreal Mode Enabled", 0
umode_already_msg db "Unreal mode is already active.", 0
umode_enabled_msg db "Unreal Mode is enabled", 0
umode_cpu_msg db "16 bit Unreal Mode Enabled", 0
viewsector_usage db "Usage: viewsector <decimal LBA>  (e.g. viewsector 0, viewsector 63)", 13, 10, 0
sector_read_err db "Error reading sector. Check LBA and drive.", 13, 10, 0

; Data buffers
input_buffer times 64 db 0
history times 512 db 0
history_count db 0
history_head db 0
history_pos db 0
gui_mode db 0
current_color db 0x07
cursor_pos dw 0
cursor_visible db 1
boot_drive db 0
cpu_name_buffer times 48 db 0
unreal_mode_active db 0

; Disk geometry (for 1.44 MB floppy, change as needed)
SectorsPerTrack dw 18
NumHeads dw 2

; Sector buffer for disk I/O
sector_buffer times 512 db 0