[bits 16]

global start
global read_sectors_bios
global write_sectors_bios
extern get_test_message
extern fat_init
extern fat_list_dir
extern fat_create_file

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
    stosb
    mov ah, 0x0E
    int 0x10
    jmp .r

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

; --- Data Area ---
welcome db "Welcome to DDOS!", 13, 10, 0
prompt_msg db "[#] ", 0
test_cmd db "test", 0
info_cmd db "info", 0
clear_cmd db "clear", 0
shutdown_cmd db "shutdown", 0
reboot_cmd db "reboot", 0
help_cmd db "help", 0
echo_cmd db "echo", 0
ls_cmd db "ls", 0
touch_cmd db "touch", 0
changegui_cmd db "changegui", 0   ; New command replacing screenfix
info_msg db "DDOS: Dum Dum Operating System, (C) Bocca Gigante Productions", 13, 10
    db "", 13, 10
    db "@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@", 13, 10
    db "@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@", 13, 10
    db "@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@", 13, 10
    db "@+:=@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@", 13, 10
    db "@@@@@*:-%%@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@", 13, 10
    db "@@@@@@@@++:-+@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@", 13, 10
    db "@@@@@@@@@@@@#=::-+@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@", 13, 10
    db "@@@@@@@@@@@@@@@%+-::--*@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@", 13, 10
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
help_msg db "Commands: info, clear, shutdown, reboot, help, test, ls, touch, changegui", 13, 10, 0  ; Updated
big_msg db "Switched to big text mode (80x50)", 13, 10, 0
small_msg db "Switched to small text mode (80x25)", 13, 10, 0
input_buffer times 64 db 0
; Command history: 8 entries of 64 bytes
history times 512 db 0
history_count db 0
history_head db 0
history_pos db 0
gui_mode db 0  ; 0 = big (80x25), 1 = small (80x50)