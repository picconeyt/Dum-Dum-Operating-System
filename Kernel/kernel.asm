[bits 16]

global start
global read_sectors_bios
global write_sectors_bios
global current_locale         ; 0=US,1=Italian
global locale_argument        ; buffer for locale command argument

extern get_test_message
extern fat_init
extern fat_list_dir
extern fat_create_file
extern locale_handler        ; Handle locale commands (C function)

section .text

start:
    ; Setup segments for stability
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0xFFFF

    ; Set video mode (Clear Screen) - default big mode
    mov ah, 0x00
    mov al, 0x03
    int 0x10
    mov byte [gui_mode], 0          ; 0 = big (80x25)
    
    mov si, welcome
    call print

main_loop:
    call move_prompt_left
    mov si, prompt_msg
    call print
    call read_input

    ; --- Command Checks ---
    mov si, input_buffer
    
    ; Check "test" (The C Call)
    mov di, test_cmd
    call str_eq
    cmp al, 1
    je do_test

    ; Check "info"
    mov si, input_buffer
    mov di, info_cmd
    call str_eq
    cmp al, 1
    je do_info

    ; Check "clear"
    mov si, input_buffer
    mov di, clear_cmd
    call str_eq
    cmp al, 1
    je do_clear

    ; Check "shutdown"
    mov si, input_buffer
    mov di, shutdown_cmd
    call str_eq
    cmp al, 1
    je do_shutdown

    ; Check "reboot"
    mov si, input_buffer
    mov di, reboot_cmd
    call str_eq
    cmp al, 1
    je do_reboot

    ; Check "help"
    mov si, input_buffer
    mov di, help_cmd
    call str_eq
    cmp al, 1
    je do_help

    ; Check "echo"
    mov si, input_buffer
    mov di, echo_cmd
    call str_prefix_eq
    cmp al, 1
    je do_echo

    ; Check "locale" (change or show keyboard layout)
    mov si, input_buffer
    mov di, locale_cmd_str    ; string token for locale command
    call str_prefix_eq
    cmp al, 1
    je do_locale

    ; Check "ls" (Directory Listing)
    mov si, input_buffer
    mov di, ls_cmd
    call str_eq
    cmp al, 1
    je do_ls

    ; Check "touch" (Create File)
    mov si, input_buffer
    mov di, touch_cmd
    call str_eq
    cmp al, 1
    je do_touch

    ; Check "changegui" (Toggle screen size)
    mov si, input_buffer
    mov di, changegui_cmd
    call str_eq
    cmp al, 1
    je do_changegui

    ; Check "start" (enter 32-bit protected mode)
    mov si, input_buffer
    mov di, start_cmd
    call str_eq
    cmp al, 1
    je do_start

    ; If no command matched
    mov si, unknown_msg
    call print
    jmp main_loop

; --- Command Handlers ---

do_test:
    call get_test_message  ; Call C function
    mov si, ax             ; Offset returned in AX
    call print
    call newline
    jmp main_loop

do_locale:
    ; extract argument after the word "locale" and copy to locale_argument
    mov si, input_buffer
    add si, 6              ; skip past "locale"
    ; skip any spaces just like echo does
.skip_spaces_l:
    mov al, [si]
    cmp al, ' '
    je .inc_l_l
    jmp .start_arg_l
.inc_l_l:
    inc si
    jmp .skip_spaces_l
.start_arg_l:
    lea di, [locale_argument]
    ; clear first byte so we always have a terminator
    mov byte [di], 0
    ; handle quoted argument or bare word
    cmp byte [si], '"'
    jne .copy_unquoted_l
    ; quoted argument: skip opening quote
    inc si
.copy_quoted_l:
    mov al, [si]
    or al, al
    jz .done_copy_l        ; shouldn't happen, but be safe
    cmp al, '"'
    je .done_copy_l
    stosb
    inc si
    jmp .copy_quoted_l
.copy_unquoted_l:
    mov al, [si]
    or al, al
    jz .done_copy_l
    cmp al, ' '
    je .done_copy_l
    stosb
    inc si
    jmp .copy_unquoted_l
.done_copy_l:
    mov al, 0
    stosb
    call locale_handler
    mov si, ax
    call print
    call newline
    jmp main_loop

do_info:
    mov si, info_msg
    call print
    jmp main_loop

do_clear:
    mov ah, 0x00
    mov al, 0x03
    int 0x10
    jmp main_loop

do_shutdown:
    mov si, shutdown_msg
    call print
    mov ax, 0x5307
    mov bx, 0x0001
    mov cx, 0x0003
    int 0x15
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

do_ls:
    call fat_list_dir
    jmp main_loop

do_touch:
    call fat_create_file
    jmp main_loop

do_start:
    ; Debug trace for transition to protected mode
    mov si, start_msg
    call print
    call newline

    ; Ensure standard 80x25 text mode before entering 32-bit console
    mov ax, 0x0003
    int 0x10

    cli
    call enable_a20
    lgdt [gdt_descriptor]
    mov eax, cr0
    or eax, 1
    mov cr0, eax
    jmp 0x08:protected_mode_entry

do_echo:
    ; Print the rest of the input after the command
    ; Skip the command name
    mov si, input_buffer
    add si, 4
    ; Skip spaces
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
    ; If quoted, skip opening quote and print until closing quote
    inc si
.echo_print_q:
    mov al, [si]
    or al, al
    jz .echo_done
    cmp al, '"'
    je .echo_done
    mov ah, 0x0E
    int 0x10
    inc si
    jmp .echo_print_q
.echo_print_nq:
    ; Not quoted: print until end
.echo_print_nq_loop:
    mov al, [si]
    or al, al
    jz .echo_done
    mov ah, 0x0E
    int 0x10
    inc si
    jmp .echo_print_nq_loop
.echo_done:
    call newline
    jmp main_loop

do_changegui:
    ; Toggle between big (80x25) and small (80x50) text modes
    cmp byte [gui_mode], 0
    je .set_small
    ; Set big mode (80x25)
    mov ah, 0x00
    mov al, 0x03
    int 0x10
    mov byte [gui_mode], 0
    mov si, big_msg
    call print
    jmp main_loop
.set_small:
    ; Set small mode (80x50) via 8x8 font
    mov ah, 0x00
    mov al, 0x03        ; Start with 80x25 mode
    int 0x10
    mov ax, 0x1112      ; Load 8x8 font (switches to 80x50)
    mov bl, 0           ; Font block 0
    int 0x10
    mov byte [gui_mode], 1
    mov si, small_msg
    call print
    jmp main_loop

; --- Disk I/O Functions for C to call ---

; read_sectors_bios: BIOS disk read function
; Parameters (cdecl): [bp+4] = LBA, [bp+6] = count, [bp+8] = buffer_ptr
read_sectors_bios:
    push bp
    mov bp, sp
    pusha

    ; Get parameters
    mov ax, [bp+4]      ; LBA (32-bit, but we only use low 16 bits for floppy)
    mov cx, [bp+6]      ; Count
    mov bx, [bp+8]      ; Buffer pointer
    
    ; LBA-to-CHS conversion for 1.44MB Floppy:
    ; Sector = (LBA mod 18) + 1
    ; Head   = (LBA / 18) mod 2
    ; Cylinder = LBA / 36
    
    push bx             ; Save buffer pointer
    mov bx, 18
    xor dx, dx
    div bx              ; ax = LBA / 18, dx = LBA % 18
    inc dl              ; Sector is 1-based
    mov cl, dl          ; Sector in CL (bits 0-5)
    
    xor dx, dx
    mov bx, 2
    div bx              ; ax = Cylinder, dx = Head
    mov dh, dl          ; Head in DH
    mov ch, al          ; Cylinder in CH (lower 8 bits)
    
    ; Set cylinder high bits (cylinder is 0-79 for floppy)
    shl ah, 6           ; Move high 2 bits of cylinder to position 6-7
    or cl, ah           ; Combine with sector number
    
    pop bx              ; Restore buffer pointer
    
    ; BIOS disk read
    mov dl, 0x00        ; Drive 0 (A:)
    mov al, [bp+6]      ; Number of sectors to read
    mov ah, 0x02        ; BIOS read function
    int 0x13
    
    ; Note: Error handling could be added here (check carry flag)
    
    popa
    pop bp
    ret

; write_sectors_bios: BIOS disk write function
; Parameters (cdecl): [bp+4] = LBA, [bp+6] = count, [bp+8] = buffer_ptr
write_sectors_bios:
    push bp
    mov bp, sp
    pusha

    ; Get parameters
    mov ax, [bp+4]      ; LBA
    mov cx, [bp+6]      ; Count
    mov bx, [bp+8]      ; Buffer pointer
    
    ; LBA-to-CHS conversion for 1.44MB Floppy:
    ; Sector = (LBA mod 18) + 1
    ; Head   = (LBA / 18) mod 2
    ; Cylinder = LBA / 36
    
    push bx             ; Save buffer pointer
    mov bx, 18
    xor dx, dx
    div bx              ; ax = LBA / 18, dx = LBA % 18
    inc dl              ; Sector is 1-based
    mov cl, dl          ; Sector in CL (bits 0-5)
    
    xor dx, dx
    mov bx, 2
    div bx              ; ax = Cylinder, dx = Head
    mov dh, dl          ; Head in DH
    mov ch, al          ; Cylinder in CH (lower 8 bits)
    
    ; Set cylinder high bits (cylinder is 0-79 for floppy)
    shl ah, 6           ; Move high 2 bits of cylinder to position 6-7
    or cl, ah           ; Combine with sector number
    
    pop bx              ; Restore buffer pointer
    
    ; BIOS disk write
    mov dl, 0x00        ; Drive 0 (A:)
    mov al, [bp+6]      ; Number of sectors to write
    mov ah, 0x03        ; BIOS write function
    int 0x13
    
    ; Note: Error handling could be added here (check carry flag)
    
    popa
    pop bp
    ret

; --- Core Functions ---

move_prompt_left:
    mov ah, 0x03
    mov bh, 0
    int 0x10
    mov ah, 0x02
    mov dl, 0
    int 0x10
    ret

print:
    lodsb
    or al, al
    jz .done
    mov ah, 0x0E
    int 0x10
    jmp print
.done:
    ret

read_input:
    mov di, input_buffer
    ; BX will be used as temporary, DI points to current write position
.r:
    mov ah, 0
    int 0x16
    cmp al, 0
    jne .handle_ascii
    ; Extended key in AH
    cmp ah, 0x48        ; Up arrow
    je .k_up
    cmp ah, 0x50        ; Down arrow
    je .k_down
    jmp .r

.handle_ascii:
    cmp al, 0x0D        ; Enter
    je .e
    cmp al, 0x08        ; Backspace
    je .b
    ; apply simple locale mapping (swap y/z in italian layout)
    mov bl, al
    cmp byte [current_locale], 1
    jne .skip_map
    cmp al, 'y'
    je .to_z
    cmp al, 'z'
    je .to_y
.skip_map:
    stosb
    mov ah, 0x0E
    int 0x10
    jmp .r
.to_z:
    mov al, 'z'
    jmp .skip_map
.to_y:
    mov al, 'y'
    jmp .skip_map

.b:
    cmp di, input_buffer
    je .r
    dec di
    mov ah, 0x0E
    mov al, 0x08
    int 0x10
    mov al, ' '
    int 0x10
    mov al, 0x08
    int 0x10
    jmp .r

.e:
    mov al, 0
    stosb
    ; Store into history if not empty
    mov si, input_buffer
    lodsb
    or al, al
    jz .no_store
    ; Compute destination = history + history_head*64
    lea di, [history]
    mov bl, [history_head]
    xor ax, ax
    mov al, bl
    shl ax, 6           ; ax = bl * 64
    add di, ax
    ; Copy string
.copy_hist:
    mov al, [si]
    mov [di], al
    inc si
    inc di
    or al, al
    jne .copy_hist
    ; Advance head
    mov al, [history_head]
    inc al
    and al, 7
    mov [history_head], al
    ; Increase count up to 8
    mov al, [history_count]
    cmp al, 8
    jae .no_store
    inc byte [history_count]
.no_store:
    call newline
    ret

; History navigation: up
.k_up:
    mov al, [history_count]
    or al, al
    jz .r
    mov al, [history_pos]
    mov bl, [history_count]
    cmp al, bl
    jae .r
    inc byte [history_pos]
    ; index = (history_head + 8 - history_pos) & 7
    mov al, [history_head]
    add al, 8
    sub al, [history_pos]
    and al, 7
    mov bl, al
    ; copy history[bl] -> input_buffer
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
    ; Reprint prompt + buffer
    call move_prompt_left
    mov si, prompt_msg
    call print
    mov si, input_buffer
    call print
    ; set DI to end of string for further typing
    ; DI currently points after null
    ret

; History navigation: down
.k_down:
    mov al, [history_pos]
    or al, al
    jz .r
    dec byte [history_pos]
    mov al, [history_pos]
    or al, al
    jz .clear_input
    ; show entry for new history_pos
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
    ; clear buffer and reprint prompt
    mov byte [input_buffer], 0
    call move_prompt_left
    mov si, prompt_msg
    call print
    ret

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

; str_prefix_eq: return 1 if DI (token) matches start of SI and next char in SI is space or NUL
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
    ; token ended, ensure SI char is space or NUL
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
    mov ah, 0x0E
    mov al, 0x0D
    int 0x10
    mov al, 0x0A
    int 0x10
    ret

enable_a20:
    in al, 0x92
    test al, 00000010b
    jnz .done
    or al, 00000010b        ; set A20 enable bit
    and al, 11111110b       ; clear reset bit
    out 0x92, al
.done:
    ret

gdt_start:
    dq 0                    ; null descriptor

gdt_code:
    dw 0xFFFF               ; limit low
    dw 0x0000               ; base low
    db 0x00                 ; base middle
    db 10011010b            ; access: present, ring 0, code
    db 11001111b            ; granularity, 4K, 32-bit, limit high
    db 0x00                 ; base high

gdt_data:
    dw 0xFFFF               ; limit low
    dw 0x0000               ; base low
    db 0x00                 ; base middle
    db 10010010b            ; access: present, ring 0, data
    db 11001111b            ; granularity, 4K, 32-bit, limit high
    db 0x00                 ; base high

gdt_end:

gdt_descriptor:
    dw gdt_end - gdt_start - 1
    dd gdt_start

[bits 32]
protected_mode_entry:
    mov ax, 0x10            ; data segment selector
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax
    mov esp, 0x9FC00        ; simple stack below 1MB

    mov edi, 0xB8000        ; VGA text buffer
    mov esi, protected_msg
.pm_print_loop:
    lodsb
    test al, al
    jz .pm_done
    mov ah, 0x0F            ; attribute: white on black
    mov [edi], ax
    add edi, 2
    jmp .pm_print_loop
.pm_done:
    ; hardware-timer-based delay so message is visible (~1 second)
    call delay_short_ticks

    ; enter 32-bit text-mode console
    call pm_console

.pm_hang:
    cli
    hlt
    jmp .pm_hang

; ---------------- 32-bit Text Console ----------------
; Simple 80x25 text-mode console in protected mode.
; Uses direct writes to VGA text buffer at 0xB8000 and
; polls the keyboard controller for input.

%define PM_COLS   80
%define PM_ROWS   25
%define PM_VRAM   0x000B8000

; Console variables
pm_cursor_row:   dd 0
pm_cursor_col:   dd 0
pm_input_buffer: times 256 db 0
pm_input_index:  dd 0
pm_shift_state:  dd 0          ; bit0 = left shift, bit1 = right shift

pm_welcome_msg db "32-bit Protected Mode Console", 13, 10
               db "Type anything. Enter to newline.", 13, 10, 0

; Main console loop
pm_console:
    call pm_clear_screen
    mov esi, pm_welcome_msg
    call pm_puts
.loop:
    call pm_get_key
    cmp al, 0
    je .loop
    cmp al, 0x0D          ; enter
    je .enter
    cmp al, 0x08          ; backspace
    je .backspace
    cmp al, 0x20
    jb .loop              ; ignore other controls
    ; printable character
    push eax
    mov eax, [pm_input_index]
    cmp eax, 255
    jae .no_store
    mov byte [pm_input_buffer + eax], al
    inc dword [pm_input_index]
.no_store:
    pop eax
    call pm_putc
    jmp .loop
.enter:
    ; print newline and reset buffer
    mov al, 0x0D
    call pm_putc
    mov al, 0x0A
    call pm_putc
    mov dword [pm_input_index], 0
    jmp .loop
.backspace:
    cmp dword [pm_input_index], 0
    je .loop
    dec dword [pm_input_index]
    mov al, 0x08
    call pm_putc
    jmp .loop

; Print null-terminated string
pm_puts:
    lodsb
    test al, al
    jz .done
    call pm_putc
    jmp pm_puts
.done:
    ret

; Clear screen and home cursor
pm_clear_screen:
    push edi
    push eax
    push ecx
    mov edi, PM_VRAM
    mov ax, 0x0720        ; space with attribute 0x07 (light grey on black)
    mov ecx, PM_ROWS * PM_COLS
    rep stosw
    mov dword [pm_cursor_row], 0
    mov dword [pm_cursor_col], 0
    call pm_update_hw_cursor
    pop ecx
    pop eax
    pop edi
    ret

; Output one character (handles special characters, scrolling, cursor)
pm_putc:
    push eax
    push ebx
    push edx
    push edi
    cmp al, 0x0A          ; line feed
    je .lf
    cmp al, 0x0D          ; carriage return
    je .cr
    cmp al, 0x08          ; backspace
    je .bs
    ; printable character
    mov ebx, [pm_cursor_row]
    imul ebx, PM_COLS
    add ebx, [pm_cursor_col]
    shl ebx, 1            ; each char 2 bytes
    mov byte [PM_VRAM + ebx], al
    mov byte [PM_VRAM + ebx + 1], 0x07   ; attribute
    inc dword [pm_cursor_col]
    cmp dword [pm_cursor_col], PM_COLS
    jne .update_cursor
    ; wrap to next line
    mov dword [pm_cursor_col], 0
    inc dword [pm_cursor_row]
    cmp dword [pm_cursor_row], PM_ROWS
    jne .update_cursor
    call pm_scroll
    dec dword [pm_cursor_row]   ; after scroll, row becomes PM_ROWS-1
    jmp .update_cursor
.lf:
    inc dword [pm_cursor_row]
    cmp dword [pm_cursor_row], PM_ROWS
    jne .update_cursor
    call pm_scroll
    dec dword [pm_cursor_row]
    jmp .update_cursor
.cr:
    mov dword [pm_cursor_col], 0
    jmp .update_cursor
.bs:
    cmp dword [pm_cursor_col], 0
    jne .bs_move
    ; if at start of line, move to previous line end
    cmp dword [pm_cursor_row], 0
    je .update_cursor      ; can't backspace from top-left
    dec dword [pm_cursor_row]
    mov dword [pm_cursor_col], PM_COLS - 1
    jmp .bs_erase
.bs_move:
    dec dword [pm_cursor_col]
.bs_erase:
    ; erase character at new cursor position
    mov ebx, [pm_cursor_row]
    imul ebx, PM_COLS
    add ebx, [pm_cursor_col]
    shl ebx, 1
    mov word [PM_VRAM + ebx], 0x0720   ; space with attribute
    jmp .update_cursor
.update_cursor:
    call pm_update_hw_cursor
    pop edi
    pop edx
    pop ebx
    pop eax
    ret

; Scroll screen up by one line
pm_scroll:
    push edi
    push esi
    push eax
    push ecx
    ; copy lines 1..24 to 0..23
    mov esi, PM_VRAM + (PM_COLS * 2)   ; start of second line
    mov edi, PM_VRAM
    mov ecx, (PM_ROWS - 1) * PM_COLS
    rep movsw
    ; clear last line
    mov edi, PM_VRAM + ((PM_ROWS - 1) * PM_COLS * 2)
    mov ax, 0x0720
    mov ecx, PM_COLS
    rep stosw
    pop ecx
    pop eax
    pop esi
    pop edi
    ret

; Update hardware cursor position from pm_cursor_row/pm_cursor_col
pm_update_hw_cursor:
    push eax
    push ebx
    push edx
    mov eax, [pm_cursor_row]
    imul eax, PM_COLS
    add eax, [pm_cursor_col]
    mov ebx, eax                 ; save position
    mov dx, 0x3D4
    mov al, 0x0F
    out dx, al                   ; select low cursor byte
    mov dx, 0x3D5
    mov al, bl                   ; low byte of position
    out dx, al
    mov dx, 0x3D4
    mov al, 0x0E
    out dx, al                   ; select high cursor byte
    mov dx, 0x3D5
    mov al, bh                   ; high byte of position
    out dx, al
    pop edx
    pop ebx
    pop eax
    ret

; Wait for a keypress and return ASCII in al (0 if ignored)
pm_get_key:
    push ebx
    push edx
.wait_key:
    in al, 0x64
    test al, 1
    jz .wait_key
    in al, 0x60
    test al, 0x80
    jnz .handle_break
    ; make code
    cmp al, 0x2A               ; left shift make
    je .set_lshift
    cmp al, 0x36               ; right shift make
    je .set_rshift
    call pm_scancode_to_ascii
    jmp .done
.set_lshift:
    or dword [pm_shift_state], 1
    jmp .wait_key
.set_rshift:
    or dword [pm_shift_state], 2
    jmp .wait_key
.handle_break:
    and al, 0x7F
    cmp al, 0x2A
    je .clear_lshift
    cmp al, 0x36
    je .clear_rshift
    jmp .wait_key
.clear_lshift:
    and dword [pm_shift_state], ~1
    jmp .wait_key
.clear_rshift:
    and dword [pm_shift_state], ~2
    jmp .wait_key
.done:
    pop edx
    pop ebx
    ret

; ---------- FIXED SCANCODE TO ASCII ROUTINE (table‑driven) ----------
pm_scancode_to_ascii:
    push ebx
    push ecx
    ; special scancodes
    cmp al, 0x0E          ; backspace
    jne .not_bs
    mov al, 0x08
    jmp .done_ascii
.not_bs:
    cmp al, 0x1C          ; enter
    jne .not_enter
    mov al, 0x0D
    jmp .done_ascii
.not_enter:
    cmp al, 0x39          ; space
    jne .not_space
    mov al, ' '
    jmp .done_ascii
.not_space:
    ; ignore shift makes (they are handled in pm_get_key)
    cmp al, 0x2A
    je .ignore
    cmp al, 0x36
    je .ignore
    ; index into scancode table (0x00-0x57)
    cmp al, 0x57
    ja .ignore
    movzx ebx, al
    mov al, [scancode_table + ebx]
    test al, al
    jz .ignore
    ; if it's a letter, apply shift
    cmp al, 'a'
    jb .no_shift
    cmp al, 'z'
    ja .no_shift
    cmp dword [pm_shift_state], 0
    je .no_shift
    sub al, 32            ; to uppercase
.no_shift:
    ; Italian locale swap (y ↔ z)
    cmp byte [current_locale], 1
    jne .done_ascii
    cmp al, 'y'
    je .to_z
    cmp al, 'z'
    je .to_y
    jmp .done_ascii
.to_z:
    mov al, 'z'
    jmp .done_ascii
.to_y:
    mov al, 'y'
    jmp .done_ascii
.ignore:
    xor al, al
.done_ascii:
    pop ecx
    pop ebx
    ret

; Scancode to ASCII (lowercase / digit) lookup table.
; Indexed by scancode (0x00 - 0x57). 0 = unmapped.
scancode_table:
    ; 0x00 - 0x0F
    db 0,   0,   '1', '2', '3', '4', '5', '6', '7', '8', '9', '0', '-', '=', 0,   0
    ; 0x10 - 0x1F
    db 'q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p', '[', ']', 0,   0,   'a', 's'
    ; 0x20 - 0x2F
    db 'd', 'f', 'g', 'h', 'j', 'k', 'l', ';', "'", '`', 0,   '\', 'z', 'x', 'c', 'v'
    ; 0x30 - 0x3F
    db 'b', 'n', 'm', ',', '.', '/', 0,   0,   0,   ' ', 0,   0,   0,   0,   0,   0
    ; 0x40 - 0x4F
    times 16 db 0
    ; 0x50 - 0x57
    times 8  db 0

; Simple PIT-based delay using a few timer periods
delay_short_ticks:
    push eax
    push ecx
.outer:
    mov ecx, 18                  ; wait for ~1 second of timer periods
.delay_loop:
    mov al, 00110100b            ; channel 0, lobyte/hibyte, mode 2
    out 0x43, al
    mov al, 0xFF
    out 0x40, al
    mov al, 0xFF
    out 0x40, al
.wait_period:
    in al, 0x61
    test al, 00100000b           ; wait until PIT output goes high
    jz .wait_period
    loop .delay_loop
    pop ecx
    pop eax
    ret

[bits 16]

; --- Data Area ---
welcome db "Welcome to DDOS!", 13, 10, 0
prompt_msg db "[#] ", 0
test_cmd db "test", 0
info_cmd db "info", 0
clear_cmd db "clear", 0
shutdown_cmd db "shutdown", 0
reboot_cmd db "reboot", 0
help_cmd db "help", 0
locale_cmd_str db "locale", 0

echo_cmd db "echo", 0
ls_cmd db "ls", 0
touch_cmd db "touch", 0
changegui_cmd db "changegui", 0   ; New command replacing screenfix
start_cmd db "start", 0
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
reboot_msg db "Rebooting...", 13, 10, 0
help_msg db "Commands: info, clear, shutdown, reboot, help, test, ls, touch, changegui, locale, start", 13, 10, 0  ; Updated
big_msg db "Switched to big text mode (80x50)", 13, 10, 0
small_msg db "Switched to small text mode (80x25)", 13, 10, 0
start_msg db "Switching to 32-bit protected mode...", 13, 10, 0
protected_msg db "32 bit protected mode loaded!", 0
input_buffer times 64 db 0
; Command history: 8 entries of 64 bytes
history times 512 db 0
history_count db 0
history_head db 0
history_pos db 0
gui_mode db 0  ; 0 = big (80x25), 1 = small (80x50)
locale_argument times 64 db 0   ; buffer used by locale command argument
current_locale db 0  ; 0 = US, 1 = Italian