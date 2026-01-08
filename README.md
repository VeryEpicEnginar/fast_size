# fast_size
# compiling
nasm -f elf64 fast_size.asm
ld -o fast_du fast_size.o

# du_x64_extreme

Pure x86_64 Linux assembly disk usage tool.

## Features
- Recursive directory traversal
- Inode-based hardlink deduplication
- clone() based parallel workers
- Zero dynamic allocation
- Syscall-only (no libc)

## compiling
nasm -f elf64 du_x64_extreme.asm

ld -O2 -o du_x64_extreme du_x64_extreme.o
