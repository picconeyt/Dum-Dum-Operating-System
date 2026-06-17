; tcpip.asm – RTL8139 networking stack for DDOS (16-bit real mode)
; Included from kernel.asm with %include "tcpip.asm"
; QEMU user net defaults: guest 10.0.2.15, gw 10.0.2.2, DNS 10.0.2.3

; ---------------------------------------------------------------------------
; RTL8139 constants
; ---------------------------------------------------------------------------
%define RTL8139_VENDOR      0x10EC
%define RTL8139_DEVICE      0x8139

%define PCI_CONFIG_ADDR     0xCF8
%define PCI_CONFIG_DATA     0xCFC

%define RTL8139_REG_IDR0    0x00
%define RTL8139_REG_TSD0    0x10
%define RTL8139_REG_TSAD0   0x20
%define RTL8139_REG_RBSTART 0x30
%define RTL8139_REG_CMD     0x37
%define RTL8139_REG_CAPR    0x38
%define RTL8139_REG_IMR     0x3C
%define RTL8139_REG_ISR     0x3E
%define RTL8139_REG_TCR     0x40
%define RTL8139_REG_RCR     0x44
%define RTL8139_REG_CONFIG1 0x52

%define RTL8139_CMD_RESET   0x10
%define RTL8139_CMD_RE      0x08
%define RTL8139_CMD_TE      0x04

%define ETH_TYPE_ARP        0x0806
%define ETH_TYPE_IP         0x0800
%define ARP_HW_ETH          1
%define ARP_OP_REQUEST      1
%define ARP_OP_REPLY        2
%define IP_PROTO_ICMP       1
%define IP_PROTO_UDP        17
%define ICMP_ECHO_REQUEST   8
%define ICMP_ECHO_REPLY     0

%define DNS_PORT            53
%define PING_COUNT          5
%define PING_TIMEOUT_TICKS  36       ; ~2 s at 18.2 Hz BIOS ticks

; ---------------------------------------------------------------------------
; net_init – scan PCI, reset RTL8139, enable RX/TX
; Returns AL=1 on success, AL=0 on failure. Preserves flags loosely.
; ---------------------------------------------------------------------------
net_init:
    push bx
    push cx
    push dx
    push si
    push di

    call pci_find_rtl8139
    jc .fail

    call rtl8139_reset
    jc .fail

    call rtl8139_setup_buffers
    call rtl8139_enable
    call rtl8139_read_mac

    mov al, 1
    jmp .done

.fail:
    mov si, net_init_fail_msg
    call print
    call newline
    xor al, al

.done:
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    ret

; ---------------------------------------------------------------------------
; ping_target – SI = null-terminated host (IPv4 or domain)
; Sends PING_COUNT ICMP echo requests. Uses kernel print helpers.
; ---------------------------------------------------------------------------
ping_target:
    pusha

    mov di, ping_work_host
.copy_host:
    lodsb
    mov [di], al
    inc di
    or al, al
    jnz .copy_host

    mov si, ping_work_host
    call str_is_ipv4
    cmp al, 1
    je .have_ip

    mov si, ping_work_host
    call dns_resolve
    jc .dns_fail
    jmp .ip_ready

.have_ip:
    mov si, ping_work_host
    mov di, ping_target_ip
    call parse_ipv4_string
    jc .bad_target
    jmp .ip_ready

.dns_fail:
    mov si, ping_dns_fail_msg
    call print
    call newline
    jmp .exit

.bad_target:
    mov si, ping_usage_msg
    call print
    jmp .exit

.ip_ready:
    mov si, ping_preamble_msg
    call print
    mov si, ping_target_ip
    call print_ipv4
    call newline

    mov si, ping_target_ip
    call arp_resolve_target
    jc .arp_fail

    mov word [icmp_seq], 0
    xor bx, bx

.ping_loop:
    inc bx
    mov ax, bx
    call send_icmp_echo
    mov word [ping_wait_seq], bx
    call wait_icmp_reply

    mov si, ping_seq_msg
    call print
    mov ax, bx
    call print_dec

    cmp byte [ping_reply_ok], 1
    je .got_reply

    mov si, ping_timeout_msg
    call print
    call newline
    jmp .next_ping

.got_reply:
    mov si, ping_reply_msg
    call print
    mov si, ping_reply_ip
    call print_ipv4
    call newline

.next_ping:
    cmp bx, PING_COUNT
    jb .ping_loop
    jmp .exit

.arp_fail:
    mov si, ping_arp_fail_msg
    call print
    call newline

.exit:
    popa
    ret

; ---------------------------------------------------------------------------
; PCI configuration space access (Mechanism #1)
; AX = bus<<8 | dev<<3 | func, BL = register offset (aligned)
; Returns EAX = 32-bit config dword
; ---------------------------------------------------------------------------
; CL = PCI device (0..31), BL = config dword offset (0,4,8...)
pci_read_config:
    push dx
    push bx
    xor eax, eax
    mov al, cl
    shl eax, 11               ; device number bits 15..11
    movzx bx, bl
    and bx, 0xFC
    or eax, ebx
    or eax, 0x80000000
    mov dx, PCI_CONFIG_ADDR
    out dx, eax
    mov dx, PCI_CONFIG_DATA
    in eax, dx
    pop bx
    pop dx
    ret

; CL = PCI device, BL = offset, AX = value to write
pci_write_config:
    push dx
    push bx
    push si
    mov si, ax
    xor eax, eax
    mov al, cl
    shl eax, 11
    movzx bx, bl
    and bx, 0xFC
    or eax, ebx
    or eax, 0x80000000
    mov dx, PCI_CONFIG_ADDR
    out dx, eax
    mov dx, PCI_CONFIG_DATA
    mov ax, si
    out dx, eax
    pop si
    pop bx
    pop dx
    ret

; Find RTL8139 on bus 0, devices 0..31, function 0
pci_find_rtl8139:
    xor cx, cx

.pfd_loop:
    xor bl, bl
    call pci_read_config
    and ax, 0xFFFF
    cmp ax, RTL8139_VENDOR
    jne .next_dev
    shr eax, 16
    cmp ax, RTL8139_DEVICE
    jne .next_dev

    mov bl, 0x10
    call pci_read_config
    test al, 1
    jz .next_dev
    and ax, 0xFFFC
    mov [rtl8139_io_base], ax

    mov bl, 0x04
    call pci_read_config
    or ax, 0x0005
    mov bl, 0x04
    call pci_write_config

    mov si, net_found_msg
    call print
    mov ax, [rtl8139_io_base]
    call print_hex_word
    call newline
    clc
    ret

.next_dev:
    inc cx
    cmp cx, 32
    jb .pfd_loop
    mov si, net_nic_fail_msg
    call print
    call newline
    stc
    ret

; ---------------------------------------------------------------------------
; RTL8139 hardware
; ---------------------------------------------------------------------------
rtl8139_reset:
    push ax
    push dx
    mov dx, [rtl8139_io_base]
    add dx, RTL8139_REG_CMD
    in al, dx
    or al, RTL8139_CMD_RESET
    out dx, al
    mov cx, 1000
.wait_reset:
    in al, dx
    test al, RTL8139_CMD_RESET
    jz .reset_done
    loop .wait_reset
    stc
    jmp .out
.reset_done:
    clc
.out:
    pop dx
    pop ax
    ret

rtl8139_setup_buffers:
    push eax
    push dx
    push bx

    mov dx, [rtl8139_io_base]
    add dx, RTL8139_REG_RBSTART
    mov eax, net_rx_buffer
    out dx, eax

    mov dx, [rtl8139_io_base]
    add dx, RTL8139_REG_TSAD0
    mov eax, net_tx_buffer
    out dx, eax

    mov dx, [rtl8139_io_base]
    add dx, RTL8139_REG_CAPR
    xor eax, eax
    out dx, eax

    mov dx, [rtl8139_io_base]
    add dx, RTL8139_REG_RCR
    mov eax, 0x0000000F      ; accept broadcast/multicast/physical
    out dx, eax

    mov dx, [rtl8139_io_base]
    add dx, RTL8139_REG_TCR
    mov eax, 0x03000600
    out dx, eax

    mov dx, [rtl8139_io_base]
    add dx, RTL8139_REG_IMR
    xor ax, ax
    out dx, ax

    mov dx, [rtl8139_io_base]
    add dx, RTL8139_REG_CONFIG1
    in al, dx
    and al, 0x9F
    out dx, al

    pop bx
    pop dx
    pop eax
    ret

rtl8139_enable:
    push ax
    push dx
    mov dx, [rtl8139_io_base]
    add dx, RTL8139_REG_CMD
    in al, dx
    or al, RTL8139_CMD_RE | RTL8139_CMD_TE
    out dx, al
    pop dx
    pop ax
    ret

rtl8139_read_mac:
    push dx
    push di
    mov di, our_mac
    mov dx, [rtl8139_io_base]
    mov cx, 6
.read_mac_loop:
    in al, dx
    mov [di], al
    inc di
    inc dx
    loop .read_mac_loop
    pop di
    pop dx
    ret

; Send frame: SI = data, CX = length (<= 1514)
rtl8139_send:
    push ax
    push bx
    push cx
    push dx
    push si
    push di

    mov dx, [rtl8139_io_base]
    add dx, RTL8139_REG_TSD0
.wait_own:
    in ax, dx
    test ax, 0x8000          ; ownership bit 15
    jnz .wait_own

    mov di, net_tx_buffer
    push cx
    rep movsb
    pop cx

    mov dx, [rtl8139_io_base]
    add dx, RTL8139_REG_TSAD0
    mov eax, net_tx_buffer
    out dx, eax

    mov dx, [rtl8139_io_base]
    add dx, RTL8139_REG_TSD0
    mov ax, cx
    or ax, 0x8000            ; start TX + length
    out dx, ax

    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; Poll receive – copies one frame to net_rx_frame, returns CX=length, CF=1 if none
rtl8139_poll_rx:
    push ax
    push bx
    push dx
    push si
    push di

    mov dx, [rtl8139_io_base]
    add dx, RTL8139_REG_ISR
    in ax, dx
    test ax, 0x0001          ; ROK
    jz .no_packet

    mov dx, [rtl8139_io_base]
    add dx, RTL8139_REG_CAPR
    in ax, dx
    and ax, 0xFFF8
    mov bx, ax
    add bx, net_rx_buffer

    mov ax, [bx]
    test ax, 0x0001          ; ROK in descriptor status
    jz .clear_isr

    mov cx, ax
    shr cx, 16
    and cx, 0x0FFF
    cmp cx, 60
    jb .clear_isr

    mov si, bx
    add si, 4
    mov di, net_rx_frame
    push cx
    rep movsb
    pop cx

    ; Advance CAPR (RTL8139 ring: next read offset minus 0x10)
    mov ax, bx
    sub ax, net_rx_buffer
    add ax, cx
    add ax, 4
    add ax, 3
    and ax, 0xFFF8
    sub ax, 0x10
    mov dx, [rtl8139_io_base]
    add dx, RTL8139_REG_CAPR
    out dx, ax

.clear_isr:
    mov dx, [rtl8139_io_base]
    add dx, RTL8139_REG_ISR
    mov ax, 0x0001
    out dx, ax

    pop di
    pop si
    pop dx
    pop bx
    pop ax
    clc
    ret

.no_packet:
    pop di
    pop si
    pop dx
    pop bx
    pop ax
    stc
    ret

; ---------------------------------------------------------------------------
; BIOS timer – returns tick count in BX (32-bit-ish, low 16 in BX for waits)
; ---------------------------------------------------------------------------
get_bios_ticks:
    push ax
    push cx
    push dx
    mov ah, 0x00
    int 0x1A
    mov bx, dx                ; use low word for deltas
    pop dx
    pop cx
    pop ax
    ret

; ---------------------------------------------------------------------------
; IPv4 helpers
; ---------------------------------------------------------------------------
str_is_ipv4:
    push bx
    xor bl, bl                ; dot count
.loop:
    lodsb
    or al, al
    jz .done
    cmp al, '.'
    je .dot
    cmp al, '0'
    jb .not_ip
    cmp al, '9'
    ja .not_ip
    jmp .loop
.dot:
    inc bl
    jmp .loop
.done:
    cmp bl, 3
    jne .not_ip
    mov al, 1
    jmp .out
.not_ip:
    xor al, al
.out:
    pop bx
    ret

; SI = "a.b.c.d", DI = 4-byte buffer (network order)
parse_ipv4_string:
    push bx
    push cx
    mov cx, 4
.octet_loop:
    xor ax, ax
.digit:
    mov bl, [si]
    or bl, bl
    jz .store
    cmp bl, '.'
    je .store
    cmp bl, '0'
    jb .bad
    cmp bl, '9'
    ja .bad
    sub bl, '0'
    mov bh, 0
    push bx
    mov bx, 10
    mul bx
    pop bx
    add ax, bx
    inc si
    jmp .digit
.store:
    mov [di], al
    inc di
    dec cx
    jz .done_ok
    cmp byte [si], '.'
    jne .bad
    inc si
    jmp .octet_loop
.done_ok:
    clc
    jmp .out
.bad:
    stc
.out:
    pop cx
    pop bx
    ret

print_ipv4:
    push ax
    push bx
    mov bl, 0
.oct:
    cmp bl, 4
    jae .done
    mov al, [si]
    mov ah, 0
    call print_dec
    inc si
    inc bl
    cmp bl, 4
    jae .done
    mov al, '.'
    call print_char
    jmp .oct
.done:
    pop bx
    pop ax
    ret

; Compare 4 bytes at SI vs DI, AL=1 if equal
ip_eq:
    push cx
    mov cx, 4
.loop:
    mov al, [si]
    mov bl, [di]
    cmp al, bl
    jne .no
    inc si
    inc di
    loop .loop
    mov al, 1
    jmp .out
.no:
    xor al, al
.out:
    pop cx
    ret

; SI = target IP bytes; pick gateway if not on local subnet
arp_resolve_target:
    push si
    push di
    mov di, ping_target_ip
    mov si, our_ip
    ; simple /24 check against our_ip and subnet_mask
    mov di, arp_resolve_ip
    push si
    mov si, ping_target_ip
    call ip_on_local_subnet
    pop si
    cmp al, 1
    je .use_target
    mov si, gateway_ip
    mov di, arp_resolve_ip
    mov cx, 4
    rep movsb
    jmp .do_arp
.use_target:
    mov si, ping_target_ip
    mov di, arp_resolve_ip
    mov cx, 4
    rep movsb
.do_arp:
    mov si, arp_resolve_ip
    call arp_resolve
    pop di
    pop si
    ret

ip_on_local_subnet:
    ; SI = target IP, compare first three octets (/24, QEMU user net)
    push bx
    xor bx, bx
.octet:
    cmp bl, 3
    jae .on_net
    mov al, [si+bx]
    push si
    mov si, our_ip
    add si, bx
    cmp al, [si]
    pop si
    jne .off_net
    inc bx
    jmp .octet
.on_net:
    mov al, 1
    jmp .out
.off_net:
    xor al, al
.out:
    pop bx
    ret

; ---------------------------------------------------------------------------
; Checksum – SI=start, CX=length in bytes (must be even)
; Returns AX checksum
; ---------------------------------------------------------------------------
internet_checksum:
    push bx
    push cx
    push si
    push dx
    xor ax, ax
    xor dx, dx
.sum:
    jcxz .fold
    add ax, [si]
    adc dx, 0
    add si, 2
    sub cx, 2
    jmp .sum
.fold:
    add ax, dx
    adc ax, 0
    not ax
    pop dx
    pop si
    pop cx
    pop bx
    ret

; ---------------------------------------------------------------------------
; ARP
; ---------------------------------------------------------------------------
arp_resolve:
    pusha
    mov byte [arp_entry_valid], 0
    mov cx, 400
    call get_bios_ticks
    mov word [arp_wait_start], bx

.arp_wait_loop:
    call arp_send_request
    mov cx, 40
.inner:
    call rtl8139_poll_rx
    jc .no_rx
    call arp_handle_rx
    cmp byte [arp_entry_valid], 1
    je .got_mac
.no_rx:
    call get_bios_ticks
    mov ax, bx
    sub ax, [arp_wait_start]
    cmp ax, 400
    ja .arp_timeout
    jmp .arp_wait_loop

.got_mac:
    popa
    clc
    ret

.arp_timeout:
    popa
    stc
    ret

arp_send_request:
    push si
    push di
    mov di, net_tx_frame
    ; Ethernet broadcast
    mov ax, 0xFFFF
    stosw
    stosw
    stosw
    mov si, our_mac
    mov cx, 6
    rep movsb
    mov ax, ETH_TYPE_ARP
    stosw
    ; ARP header
    mov ax, ARP_HW_ETH
    stosw
    mov ax, ETH_TYPE_IP
    stosw
    mov ax, 6
    stosw
    mov ax, 4
    stosw
    mov ax, ARP_OP_REQUEST
    stosw
    mov si, our_mac
    mov cx, 6
    rep movsb
    mov si, our_ip
    mov cx, 4
    rep movsb
    mov ax, 0
    stosw
    stosw
    stosw
    mov si, arp_resolve_ip
    mov cx, 4
    rep movsb
    mov si, net_tx_frame
    mov cx, di
    sub cx, net_tx_frame
    call rtl8139_send
    pop di
    pop si
    ret

arp_handle_rx:
    push si
    push di
    mov si, net_rx_frame
    mov ax, [si+12]
    cmp ax, ETH_TYPE_ARP
    jne .no
    add si, 14
    cmp word [si+6], ARP_OP_REPLY
    jne .no
    lea di, [si+14]           ; sender IP
    mov si, arp_resolve_ip
    call ip_eq
    cmp al, 1
    jne .no
    mov si, net_rx_frame
    add si, 14
    add si, 8                 ; sender MAC in ARP reply
    mov di, arp_entry_mac
    mov cx, 6
    rep movsb
    mov byte [arp_entry_valid], 1
.no:
    pop di
    pop si
    ret

; ---------------------------------------------------------------------------
; DNS (UDP A query to dns_server_ip)
; ---------------------------------------------------------------------------
dns_resolve:
    pusha
    mov byte [dns_got_answer], 0
    mov word [dns_tx_id], 0xDD01

    mov si, gateway_ip
    mov di, arp_resolve_ip
    mov cx, 4
    rep movsb
    mov si, arp_resolve_ip
    call arp_resolve
    jc .fail

    mov cx, 300
    call get_bios_ticks
    mov word [dns_wait_start], bx

.dns_loop:
    mov si, ping_work_host
    call dns_send_query
    mov cx, 60
.wait:
    call rtl8139_poll_rx
    jc .no_pkt
    call dns_handle_rx
    cmp byte [dns_got_answer], 1
    je .ok
.no_pkt:
    call get_bios_ticks
    mov ax, bx
    sub ax, [dns_wait_start]
    cmp ax, 300
    ja .fail
    jmp .dns_loop

.ok:
    mov si, resolved_ip
    mov di, ping_target_ip
    mov cx, 4
    rep movsb
    popa
    clc
    ret

.fail:
    popa
    stc
    ret

; Encode domain at SI into DNS name format at DI
dns_encode_name:
    push si
    push bx
.next_label:
    mov bx, di
    inc di
    xor ah, ah
.count:
    mov al, [si]
    or al, al
    jz .terminate
    cmp al, '.'
    je .dot
    mov [di], al
    inc di
    inc si
    inc ah
    jmp .count
.dot:
    mov [bx], ah
    inc si
    jmp .next_label
.terminate:
    mov [bx], ah
    mov byte [di], 0
    inc di
    pop bx
    pop si
    ret

dns_send_query:
    push si
    push di
    mov di, net_tx_frame
    mov si, arp_entry_mac
    mov cx, 6
    rep movsb
    mov si, our_mac
    mov cx, 6
    rep movsb
    mov ax, ETH_TYPE_IP
    stosw
    ; IP header placeholder
    push di
    mov ax, 20
    stosw                   ; ver+IHL, TOS
    mov ax, 0
    stosw                   ; total length patch later
    mov ax, [dns_tx_id]
    stosw
    xor ax, ax
    stosw
    mov ax, 0x4000
    stosw
    mov ax, (IP_PROTO_UDP << 8) | 64
    stosw
    xor ax, ax
    stosw                   ; checksum
    mov si, our_ip
    mov cx, 4
    rep movsb
    mov si, dns_server_ip
    mov cx, 4
    rep movsb
    pop bx                    ; IP header start
    ; UDP
    mov ax, (DNS_PORT << 8) | 0x12
    stosw
    mov ax, DNS_PORT
    stosw
    mov ax, 0
    stosw
    xor ax, ax
    stosw
    ; DNS header
    mov ax, [dns_tx_id]
    stosw
    mov ax, 0x0100            ; recursion desired
    stosw
    mov ax, 0x0100            ; one question
    stosw
    xor ax, ax
    stosw
    stosw
    mov si, ping_work_host
    call dns_encode_name
    mov ax, 0x0100            ; A IN
    stosw
    mov ax, 0x0100
    stosw
    ; Patch IP total length
    mov ax, di
    sub ax, bx
    mov [bx+2], ax
    mov si, bx
    mov cx, 20
    call internet_checksum
    mov [bx+10], ax
    ; UDP length + checksum (zero ok for QEMU)
    mov ax, di
    sub ax, bx
    sub ax, 20
    mov [bx+24], ax
    mov si, net_tx_frame
    mov cx, di
    sub cx, net_tx_frame
    call rtl8139_send
    pop di
    pop si
    ret

dns_handle_rx:
    push si
    mov si, net_rx_frame
    mov ax, [si+12]
    cmp ax, ETH_TYPE_IP
    jne .out
    cmp byte [si+23], IP_PROTO_UDP
    jne .out
    mov ax, [si+14]
    and ax, 0x0F
    shl ax, 2
    add si, ax
    add si, 14
    ; SI -> IP payload (UDP)
    add si, 8
    mov ax, [dns_tx_id]
    cmp [si], ax
    jne .out
    ; Walk answers – crude scan for type A
    mov cx, [si+6]
    xchg cl, ch
    or cx, cx
    jz .out
    add si, 12
    ; skip question name
.skip_q:
    lodsb
    or al, al
    jz .after_q
    cmp al, 0xC0
    je .skip_ptr
    mov ah, al
    add si, ax
    jmp .skip_q
.skip_ptr:
    inc si
.after_q:
    add si, 4
.answer_loop:
    dec cx
    js .out
    mov al, [si]
    cmp al, 0xC0
    je .compressed
    ; skip name labels
.name_skip:
    lodsb
    or al, al
    jz .got_name
    add si, ax
    jmp .name_skip
.compressed:
    add si, 2
.got_name:
    cmp word [si], 0x0100     ; type A
    jne .next_ans
    mov ax, [si+8]
    xchg al, ah
    cmp ax, 4
    jne .next_ans
    mov ax, [si+10]
    mov [resolved_ip], ax
    mov ax, [si+12]
    mov [resolved_ip+2], ax
    mov byte [dns_got_answer], 1
    jmp .out
.next_ans:
    mov ax, [si+8]
    xchg al, ah
    add si, 10
    add si, ax
    jmp .answer_loop
.out:
    pop si
    ret

; ---------------------------------------------------------------------------
; ICMP ping
; ---------------------------------------------------------------------------
send_icmp_echo:
    ; AX = ICMP sequence number
    push bx
    push cx
    push si
    push di
    mov [icmp_tx_seq], ax

    mov di, net_tx_frame
    mov si, arp_entry_mac
    mov cx, 6
    rep movsb
    mov si, our_mac
    mov cx, 6
    rep movsb
    mov ax, ETH_TYPE_IP
    stosw

    mov bx, di                ; IP header start
    mov ax, 0x4500
    stosw
    mov ax, 0
    stosw                     ; total length patched later
    mov ax, [icmp_tx_seq]
    stosw                     ; identification
    mov ax, 0x4000
    stosw
    mov ax, (IP_PROTO_ICMP << 8) | 64
    stosw
    xor ax, ax
    stosw                     ; header checksum
    mov si, our_ip
    mov cx, 4
    rep movsb
    mov si, ping_target_ip
    mov cx, 4
    rep movsb

    mov al, ICMP_ECHO_REQUEST
    stosb
    xor al, al
    stosb
    xor ax, ax
    stosw                     ; ICMP checksum
    mov ax, [icmp_id]
    stosw
    mov ax, [icmp_tx_seq]
    stosw
    mov word [di], 'DD'
    mov word [di+2], 'OS'
    add di, 4

    mov ax, di
    sub ax, net_tx_frame
    mov [bx+2], ax            ; IP total length

    mov si, bx
    mov cx, 20
    call internet_checksum
    mov [bx+10], ax

    mov si, bx
    add si, 20
    mov word [si+2], 0
    mov cx, di
    sub cx, si
    call internet_checksum
    mov [si+2], ax

    mov cx, di
    sub cx, net_tx_frame
    mov si, net_tx_frame
    call rtl8139_send

    pop di
    pop si
    pop cx
    pop bx
    ret

wait_icmp_reply:
    mov byte [ping_reply_ok], 0
    call get_bios_ticks
    mov word [ping_wait_start], bx
.wait_loop:
    call rtl8139_poll_rx
    jc .no_rx
    call icmp_handle_rx
    cmp byte [ping_reply_ok], 1
    je .done
.no_rx:
    call get_bios_ticks
    mov ax, bx
    sub ax, [ping_wait_start]
    cmp ax, PING_TIMEOUT_TICKS
    ja .done
    jmp .wait_loop
.done:
    ret

icmp_handle_rx:
    push si
    push di
    mov si, net_rx_frame
    mov ax, [si+12]
    cmp ax, ETH_TYPE_IP
    jne .out
    cmp byte [si+23], IP_PROTO_ICMP
    jne .out
    mov ax, [si+14]
    and ax, 0x0F
    shl ax, 2
    mov bx, ax
    mov al, [si+14+bx]
    cmp al, ICMP_ECHO_REPLY
    jne .out
    lea di, [si+14+bx+4]
    mov ax, [di]
    cmp ax, [icmp_id]
    jne .out
    mov ax, [di+2]
    cmp ax, [ping_wait_seq]
    jne .out
    lea si, [si+26]
    mov di, ping_reply_ip
    mov cx, 4
    rep movsb
    mov byte [ping_reply_ok], 1
.out:
    pop di
    pop si
    ret

; ---------------------------------------------------------------------------
; Network data (included into kernel binary)
; ---------------------------------------------------------------------------
rtl8139_io_base     dw 0

our_mac             times 6 db 0
our_ip              db 10, 0, 2, 15
gateway_ip          db 10, 0, 2, 2
dns_server_ip       db 10, 0, 2, 3
subnet_mask         db 255, 255, 255, 0

ping_target_ip      times 4 db 0
resolved_ip         times 4 db 0
arp_resolve_ip      times 4 db 0
arp_entry_mac       times 6 db 0
arp_entry_valid     db 0
arp_wait_start      dw 0

ping_work_host      times 64 db 0
ping_reply_ip       times 4 db 0
ping_reply_ok       db 0
ping_wait_start     dw 0
ping_wait_seq       dw 0

icmp_seq            dw 0
icmp_tx_seq         dw 0
icmp_id             dw 0xDD05
dns_tx_id           dw 0
dns_wait_start      dw 0
dns_got_answer      db 0

align 256
net_rx_buffer       times (8192 + 16) db 0
net_tx_buffer       times 1536 db 0
net_tx_frame        times 1600 db 0
net_rx_frame        times 1600 db 0

net_init_fail_msg   db "Network init failed (RTL8139 not found).", 13, 10, 0
net_nic_fail_msg    db "RTL8139 not found on PCI bus.", 13, 10, 0
net_found_msg       db "RTL8139 at I/O ", 0
ping_usage_msg      db "Usage: ping <host or IPv4>", 13, 10, 0
ping_dns_fail_msg   db "DNS resolution failed.", 13, 10, 0
ping_arp_fail_msg   db "ARP resolution failed.", 13, 10, 0
ping_seq_msg        db "Ping seq=", 0
ping_preamble_msg   db "Pinging ", 0
ping_reply_msg      db " reply from ", 0
ping_timeout_msg    db " timeout", 13, 10, 0
ping_reply_from_msg db 0
