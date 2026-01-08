; du_x64_extreme.asm
; Linux x86_64 – syscall-only extreme du tool

global _start

; ---------------- SYSCALLS ----------------
%define SYS_OPENAT        257
%define SYS_GETDENTS64    217
%define SYS_CLOSE         3
%define SYS_STATX         332
%define SYS_WRITE         1
%define SYS_EXIT          60
%define SYS_CLONE         56

; ---------------- FLAGS -------------------
%define AT_FDCWD          -100
%define O_RDONLY          0
%define AT_SYMLINK_NOFOLLOW 0x100
%define STATX_BASIC_STATS 0x7ff
%define S_IFDIR           0x4000

%define CLONE_VM          0x100
%define CLONE_FS          0x200
%define CLONE_FILES       0x400
%define CLONE_SIGHAND     0x800
%define CLONE_THREAD      0x10000

; ---------------- MEMORY ------------------
section .bss
    dirbuf      resb 16384
    statbuf     resb 256

    work_queue  resq 2048
    q_head      resq 1
    q_tail      resq 1

    inode_cache resq 8192

    total_size  resq 1

section .data
    dot     db ".",0
    msg     db "Total size: ",0
    msg_len equ $-msg
    bytes   db " bytes",10
    bytes_len equ $-bytes

section .text

; ============ ENTRY ============
_start:
    xor rax, rax
    mov [total_size], rax
    mov [q_head], rax
    mov [q_tail], rax

    mov rdi, [rsp+16]
    test rdi, rdi
    jnz .have_arg
    lea rdi, [rel dot]

.have_arg:
    call enqueue_dir

    mov rcx, 4            ; worker count
.spawn:
    call spawn_worker
    loop .spawn

.spin:
    jmp .spin

; ============ QUEUE ============
enqueue_dir:
    mov rax, [q_tail]
    mov [work_queue + rax*8], rdi
    inc qword [q_tail]
    ret

dequeue_dir:
    mov rax, [q_head]
    cmp rax, [q_tail]
    je .empty
    mov rdi, [work_queue + rax*8]
    inc qword [q_head]
    ret
.empty:
    xor rdi, rdi
    ret

; ============ INODE CACHE ============
check_inode:
    lea rbx, [inode_cache]
    mov rcx, 8192
.loop:
    cmp [rbx], rdi
    je .exists
    cmp qword [rbx], 0
    je .insert
    add rbx, 8
    loop .loop
.exists:
    mov rax, 1
    ret
.insert:
    mov [rbx], rdi
    xor rax, rax
    ret

; ============ WORKER ============
spawn_worker:
    mov rax, SYS_CLONE
    mov rdi, CLONE_VM|CLONE_FS|CLONE_FILES|CLONE_SIGHAND|CLONE_THREAD
    xor rsi, rsi
    xor rdx, rdx
    xor r10, r10
    xor r8, r8
    syscall
    test rax, rax
    jz worker_loop
    ret

worker_loop:
.next:
    call dequeue_dir
    test rdi, rdi
    jz .next

    mov r12, rdi

    mov rax, SYS_OPENAT
    mov rdi, AT_FDCWD
    mov rsi, r12
    mov rdx, O_RDONLY
    syscall
    test rax, rax
    js .next
    mov r13, rax

.read:
    mov rax, SYS_GETDENTS64
    mov rdi, r13
    lea rsi, [dirbuf]
    mov rdx, 16384
    syscall
    test rax, rax
    jle .close

    lea rbx, [dirbuf]
    mov rcx, rax

.entry:
    cmp rcx, 0
    jle .read

    movzx rdx, word [rbx+16]
    lea rsi, [rbx+19]

    cmp byte [rsi], '.'
    je .skip

    mov rax, SYS_STATX
    mov rdi, AT_FDCWD
    mov rsi, rsi
    mov rdx, AT_SYMLINK_NOFOLLOW
    mov r10, STATX_BASIC_STATS
    lea r8, [statbuf]
    syscall
    test rax, rax
    js .skip

    mov rdi, [statbuf+64]   ; inode
    call check_inode
    test rax, rax
    jnz .skip

    mov eax, [statbuf+32]   ; mode
    test eax, S_IFDIR
    jnz .dir

    mov rax, [statbuf+48]
    lock add [total_size], rax
    jmp .skip

.dir:
    lea rdi, [rbx+19]
    call enqueue_dir

.skip:
    add rbx, rdx
    sub rcx, rdx
    jmp .entry

.close:
    mov rax, SYS_CLOSE
    mov rdi, r13
    syscall
    jmp .next
