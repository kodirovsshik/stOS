
;Here's where the real deal begins
;The plan:
;✓	Flex off with cool loading message
;✓		Just display some loading message really
;✓	Perform CPU discovery
;✓		64-bit-capable CPU is required
;✓	Check for available memory
;✓		Perform memory discovery
;✓		Check for region [1 mb; 1mb + X) to be available
;	Enable A20 pin
;✓		BIOS method
;		kb controller method
;✓		port ee method
;✓		port 92 method
;	Find reasonable video mode with VBE and save it for the kernel
;✓		Check for VBE 3.0 support
;		Find compliant video modes (Supported, RBG, 24 bit or 32 bit)
;		If no found, stop booting
;		Pick largest video mode not exceeding 768 in height
;		If no found, pick the one with smallest height
;✓	Read disk UUID
;	Setup protected mode environment
;		Basic temporary GDT with 32-bit code and data segments
;
;At this point, the plan is not thoroughly thought out anymore
;
;	Go 32 bit mode
;		By this point, we should have already been using C++
;		Load the kernel at 0x100000
;	Setup 64-bit environment
;		Identity page mapping for usable memory pages
;			except for [0x100000; ...) being excluded
;			and instead mapped at -2GB address:
;				[0xFFFFFFFF80000000; ...) -> [0x100000; ...);
;			and 640KiB starting at 0 being identity-mapped
;	Flex off with some PCI commands to locate the boot device
;	Load the kernel at 0x100000
;	Transfer the control to 64-bit environment


;Assumptions:
;	loaded at 0x0000:0x0600
;	DL = current BIOS disk number
;	qword [PBR_LBA_ADDR] = partition's 8-byte LBA


;Memory map:
;	Segment 0x0000: loader's code & data
;		0x0600: loader
;		0x7C00: PBR
;	Segment 0x1000: output log buffer


;Conventions:
;	DS = CS = SS = ES = 0
;		except for small places in code where other values are needed
;	DF = 0
;


%define PBR_LBA_ADDR 0x5F8


;functions
;global halt
global halt
global panic
global cpanic

;variables
global edata.pbr_lba
global edata.boot_signature
global edata.memory_map_addr
global edata.memory_map_size
global edata.e820_ok
global edata.vbe_modes_ptr
global edata.vbe_modes_count
global bss.pbr_disk
global c_get_memory_map_addr
global c_get_memory_map_size

;functions
extern put32x
extern endl
extern puts
extern do_subtask_cpu
extern do_subtask_memory
extern do_subtask_a20_line
extern do_subtask_vbe
extern save_output_buffer
extern setup_exception_handlers

;variables
extern data.output_use_screen

;data provided by linker
extern loader_end
extern bss_begin
extern bss_size_in_words



SECTION .rodata
rodata:
	.str_logo db 10, "StOS loader v1.0", 10, 0
	.str_loader_end db "Error: loader end reached", 10, 0
	.str_panic db 10, "BOOTLOADER PANIC:", 10, 0
	.str_buffer_saved db 10, "Output buffer dumped to LBA 0x780", 0



SECTION .bss
bss:
	.pbr_disk resb 1



SECTION .text
BITS 16



loader_begin:
	jmp loader_main



align 8, nop
edata: ;data structure to be read by kernel
	.boot_disk_uuid times 16 db 0
	.boot_partition_lba dq 0
	.vbe_modes_ptr dd 0
	.memory_map_addr dd 0
	.vbe_modes_count dw 0
	.memory_map_size dw 0
	.initial_vbe_mode dw 0



loader_main:
	nop

.setup_memory_layout:
	cli

	xor ax, ax
	mov ds, ax
	mov es, ax

	mov sp, ax
	mov ss, ax

	sti

	call setup_exception_handlers

.clear_bss:
	cld
	mov di, bss_begin
	mov cx, bss_size_in_words
	xor ax, ax
	rep stosw

.store_pbr_data:
	mov [bss.pbr_disk], dl

	mov si, PBR_LBA_ADDR
	mov di, edata.boot_partition_lba
	times 4 movsw

.logo:
	mov ax, 0x0002
	int 0x10

	mov si, rodata.str_logo
	call puts

.disable_screen_output:
	mov byte [data.output_use_screen], 0

.do_subtasks:
	call do_subtask_cpu

	call dword do_subtask_memory

	call do_subtask_a20_line

	call dword do_subtask_vbe

	call do_subtask_disk_uuid




.loader_end:
	mov si, rodata.str_loader_end
	;jmp panic

;si = str
;noreturn
panic:
	mov byte [data.output_use_screen], 1
	sti
	
	push si
	mov si, rodata.str_panic
	call puts

	pop si
	call puts

	;jmp halt

;noreturn
halt:
	call save_output_buffer

	mov byte [data.output_use_screen], 1

	mov si, rodata.str_buffer_saved
	call puts

	mov si, .str_halt
	call puts
.x:
	hlt
	jmp .x
.str_halt:
	db 10, "CPU HALTED", 10, 0



c_get_memory_map_addr:
	mov eax, edata.memory_map_addr
	o32 ret



c_get_memory_map_size:
	mov eax, edata.memory_map_size
	o32 ret



;cdecl args:
;	char* message
cpanic:
	mov si, [esp + 4]
	jmp panic



do_subtask_disk_uuid:
	times 2 push dword 0
	push dword loader_end
	push dword 0x00010010
	mov si, sp
	mov ah, 0x42
	mov dl, [bss.pbr_disk]
	int 0x13
	mov eax, [loader_end + 512 - 2 - 64 - 6]
	mov [edata.boot_disk_uuid], eax
	add sp, 16
	ret
