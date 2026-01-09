; fast_size.asm
; Linux x86_64 disk usage tool (du -sb)
; syscall-only, no libc

global _start

%define SYS_OPENAT   257
%define SYS_GETDENTS64 217
%define SYS_CLOSE    3
%define SYS_EXIT     60
%define SYS_WRITE    1
%define SYS_STATX    332

%define AT_FDCWD     -100
%define O_RDONLY     0
%define AT_SYMLINK_NOFOLLOW 0x100
%define STATX_SIZE   0x200

section .bss
    dirbuf  resb 8192
    statbuf resb 256
    total   resq 1

section .data
    msg     db "Total size: ",0
    msg_len equ $-msg
    bytes   db " bytes",10
    bytes_len equ $-bytes

section .text

_start:
    mov qword [total], 0

    ; argv[1]
    mov rbx, [rsp+16]
    test rbx, rbx
    jnz open_dir
    lea rbx, [rel dot]

open_dir:
    mov rax, SYS_OPENAT
    mov rdi, AT_FDCWD
    mov rsi, rbx
    mov rdx, O_RDONLY
    xor r10, r10
    syscall

    test rax, rax
    js exit

    mov r12, rax

read_dir:
    mov rax, SYS_GETDENTS64
    mov rdi, r12
    lea rsi, [dirbuf]
    mov rdx, 8192
    syscall

    test rax, rax
    jle close_dir

    mov rcx, rax
    lea rbx, [dirbuf]

next_entry:
    cmp rcx, 0
    jle read_dir

    movzx rdx, word [rbx+16] ; d_reclen
    lea rsi, [rbx+19]        ; d_name

    ; skip . and ..
    cmp byte [rsi], '.'
    jne stat_file
    cmp byte [rsi+1], 0
    je skip
    cmp byte [rsi+1], '.'
    jne stat_file
    cmp byte [rsi+2], 0
    je skip

stat_file:
    mov rax, SYS_STATX
    mov rdi, AT_FDCWD
    mov rsi, rsi
    mov rdx, AT_SYMLINK_NOFOLLOW
    mov r10, STATX_SIZE
    lea r8, [statbuf]
    syscall

    test rax, rax
    js skip

    mov rax, [statbuf+48] ; stx_size
    add [total], rax

skip:
    add rbx, rdx
    sub rcx, rdx
    jmp next_entry

close_dir:
    mov rax, SYS_CLOSE
    mov rdi, r12
    syscall

print_result:
    mov rax, SYS_WRITE
    mov rdi, 1
    lea rsi, [msg]
    mov rdx, msg_len
    syscall

    mov rax, [total]
    call print_number

    mov rax, SYS_WRITE
    mov rdi, 1
    lea rsi, [bytes]
    mov rdx, bytes_len
    syscall

exit:
    mov rax, SYS_EXIT
    xor rdi, rdi
    syscall

; -------- print_number --------
print_number:
    mov rbx, 10
    xor rcx, rcx
    sub rsp, 32

.loop:
    xor rdx, rdx
    div rbx
    add dl, '0'
    mov [rsp+rcx], dl
    inc rcx
    test rax, rax
    jnz .loop

.print:
    dec rcx
    js .done
    mov rax, SYS_WRITE
    mov rdi, 1
    lea rsi, [rsp+rcx]
    mov rdx, 1
    syscall
    jmp .print

.done:
    add rsp, 32
    ret

section .data
dot db ".",0
