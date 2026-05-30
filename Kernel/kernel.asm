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
    call set_bios_cursor              ; ensure cursor matches prompt
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

    ; APM shutdown (robust)
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
    jmp main_loop
.no_extmem:
    mov si, not_avail_msg
    call print
    call newline
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
    jmp main_loop
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
    ; Cursor turned ON -> clear screen and show cursor
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

; -------------------------------------------------------------------
; Fill entire screen with space + current_color, reset cursor to 0
fill_screen_current_color:
    push es
    push di
    push cx
    push ax
    mov ax, 0xB800
    mov es, ax
    xor di, di
    mov cx, 2000            ; 80*25
    mov ah, [current_color]
    mov al, ' '
    rep stosw
    mov word [cursor_pos], 0
    call set_bios_cursor      ; sync hardware cursor to top-left
    pop ax
    pop cx
    pop di
    pop es
    ret

; -------------------------------------------------------------------
; BIOS cursor control (foolproof, no VGA register bugs)

; Set BIOS cursor to match [cursor_pos]
set_bios_cursor:
    pusha
    mov ax, [cursor_pos]
    mov bl, 160
    div bl                  ; AL = row, AH = column*2
    shr ah, 1               ; AH = column
    mov dh, al              ; row
    mov dl, ah              ; column
    mov ah, 0x02
    mov bh, 0
    int 0x10
    popa
    ret

; Enable VGA cursor (separate from position)
enable_cursor:
    push ax
    push dx
    mov dx, 0x3D4
    mov al, 0x0A
    out dx, al
    inc dx
    mov al, 0x0E            ; start scanline 14
    out dx, al
    dec dx
    mov al, 0x0B
    out dx, al
    inc dx
    mov al, 0x0F            ; end scanline 15
    out dx, al
    pop dx
    pop ax
    ret

; Disable VGA cursor
disable_cursor:
    push ax
    push dx
    mov dx, 0x3D4
    mov al, 0x0A
    out dx, al
    inc dx
    mov al, 0x20            ; bit 5 = disable
    out dx, al
    pop dx
    pop ax
    ret

; -------------------------------------------------------------------
; Disk I/O Functions (unchanged)
read_sectors_bios:
    push bp
    mov bp, sp
    pusha
    mov ax, [bp+4]      ; LBA
    mov cx, [bp+6]      ; count
    mov bx, [bp+8]      ; buffer
    push bx
    mov bx, 18
    xor dx, dx
    div bx
    inc dl
    mov cl, dl
    xor dx, dx
    mov bx, 2
    div bx
    mov dh, dl
    mov ch, al
    shl ah, 6
    or cl, ah
    pop bx
    mov dl, [boot_drive]
    mov al, cl
    mov ah, 0x02
    int 0x13
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
    push bx
    mov bx, 18
    xor dx, dx
    div bx
    inc dl
    mov cl, dl
    xor dx, dx
    mov bx, 2
    div bx
    mov dh, dl
    mov ch, al
    shl ah, 6
    or cl, ah
    pop bx
    mov dl, [boot_drive]
    mov al, cl
    mov ah, 0x03
    int 0x13
    popa
    pop bp
    ret

; -------------------------------------------------------------------
; Core Functions (direct VGA output + BIOS cursor sync)

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

.check_scroll:
    cmp word [cursor_pos], 4000
    jb .done_char
    call scroll_screen

.done_char:
    call set_bios_cursor      ; keep hardware cursor in sync
    pop di
    pop es
    pop dx
    pop bx
    pop ax
    ret

scroll_screen:
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
    rep movsw

    ; Clear last line with current colors
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
    mul bl               ; AX = row * 160, column 0
    mov [cursor_pos], ax
    call set_bios_cursor  ; update hardware cursor
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

read_input:
    mov di, input_buffer
.r:
    mov ah, 0
    int 0x16
    cmp al, 0
    jne .handle_ascii
    cmp ah, 0x48
    je .k_up
    cmp ah, 0x50
    je .k_down
    jmp .r
.handle_ascii:
    cmp al, 0x0D
    je .e
    cmp al, 0x08
    je .b
    stosb
    call print_char          ; echo char (updates cursor)
    jmp .r
.b:
    cmp di, input_buffer
    je .r
    dec di
    ; Backspace - erase from screen
    sub word [cursor_pos], 2
    push ax
    mov al, ' '
    call print_char
    sub word [cursor_pos], 2
    pop ax
    ; cursor already updated by print_char
    jmp .r
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
    jz .r
    mov al, [history_pos]
    mov bl, [history_count]
    cmp al, bl
    jae .r
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
    call set_bios_cursor
    ret
.k_down:
    mov al, [history_pos]
    or al, al
    jz .r
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
    call set_bios_cursor
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
; Data Area
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
help_msg db "Commands: info, clear, shutdown, reboot, help, test, echo, changegui, freeram, cpuid, bgcolor, txtcolor, resetpal, togglecurs, ver", 13, 10, 0
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
ver_msg db "Dum Dum Operating System | Codename: Old Hawk | Build 053026-1 | (C) Bocca Gigante Production", 0

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

; Sector buffer for disk I/O
sector_buffer times 512 db 0