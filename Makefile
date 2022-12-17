
override DETACHED := >/dev/null 2>&1 &

override _CXX_ARGS := -Wall -Wextra
override _NASM_ARGS := -Wall -Werror

ifeq ($(DEBUG),true)
override _CXX_ARGS += -Werror -g
_NASM_ARGS += -g
else
override _CXX_ARGS += -O3
endif
#if statement is to go here

override export _CXX := $(CXX) $(_CXX_ARGS)

export CXX_TARGET := x86_64-pc-elf-g++
override CXX_TARGET := $(CXX_TARGET) $(CXX_TARGET_ARGS) -c $(_CXX_ARGS)
override export CXX64 := $(CXX_TARGET) -m64
override export CXX32 := $(CXX_TARGET) -m32
override export CXX16 := $(CXX_TARGET) -m16

override export LINK_TARGET := $(CXX_TARGET)

export NASM := nasm
override export NASM := $(NASM) $(NASM_ARGS) $(_NASM_ARGS)

override LAYOUT := result/layout

override UTILS_SUBDIRS := binecho
override SRC_SUBDIRS := mbr pbr
override SUBDIRS := $(UTILS_SUBDIRS) $(SRC_SUBDIRS) 

VM_DIR := vm
VM_DISK := $(VM_DIR)/disk.bin
VM_DISK_SIZE_MiB := 8

VM_MEMORY_MiB := 64

QEMU32 := qemu-system-i386
QEMU32_CPU := 486
override _QEMU32 := $(QEMU32) $(QEMU_ARGS) $(QEMU32_ARGS) -cpu $(QEMU32_CPU) \
	-m $(VM_MEMORY_MiB) -drive file="$(VM_DISK)",format=raw

QEMU64 := qemu-system-x86_64
QEMU64_CPU := 486,+lm
override _QEMU64 := $(QEMU64) $(QEMU_ARGS) $(QEMU64_ARGS) -cpu $(QEMU64_CPU) \
	-m $(VM_MEMORY_MiB) -drive file="$(VM_DISK)",format=raw

override QEMU_DARGS := -s -S

override export B := 1
override export KiB := 1024
override export MiB := 1048576




.PHONY: all $(SUBDIRS) rebuild clean
.PHONY: vm-create vm-clean vm-recreate vm-burn vm-run32 vm-debug32


all: $(SUBDIRS)

$(SRC_SUBDIRS): $(UTILS_SUBDIRS)

rebuild: clean
	$(MAKE)

clean:
	rm -rf result
	for dir in $(SUBDIRS); do $(MAKE) -C $$dir clean; done

reset: clean vm-clean

$(SUBDIRS): $(LAYOUT)
	$(MAKE) -C $@

$(LAYOUT):
	mkdir -p result result/utils
	touch $@



vm-create: $(VM_DISK)

vm-clean:
	rm -rf $(VM_DIR)

vm-recreate: vm-clean
	$(MAKE) vm-create


$(VM_DISK):
	mkdir -p $(VM_DIR)
	dd if=/dev/zero of=$@ bs=1M count=$(VM_DISK_SIZE_MiB)
	bash -c "echo -e 1M,\\\\nwrite | sfdisk $@" >/dev/null
# ^^^ I hate myself for writing this ^^^
#but it keeps -e in the output for some reason if i don't wrap it with bash -c
	sfdisk -A $@ 1

define write_boot_record
	[ $$(stat -c "%s" "$(1)") -eq 512 ]
	dd if=$(1) of=$(2) bs=1 conv=notrunc seek=$(3) count=3
	dd if=$(1) of=$(2) bs=1 conv=notrunc seek=$$(($(3)+90)) skip=90 count=350
	dd if=$(1) of=$(2) bs=1 conv=notrunc seek=$$(($(3)+510)) skip=510 count=2
endef

define write_image
	dd if=$(1) of=$(2) bs=512 conv=notrunc seek=$(3) oflag=seek_bytes
endef

vm-burn: $(VM_DISK) all
	$(call write_boot_record,result/mbr.bin,"$(VM_DISK)",0)
	$(call write_boot_record,result/pbr.bin,"$(VM_DISK)",$(MiB))
	$(call write_image,result/loader.bin,"$(VM_DISK)",$$(($(MiB)+512)))

vm-run32: vm-burn
	$(_QEMU32)
vm-run64: vm-burn
	$(_QEMU64)

define vm_debug
	$(1) -S -s & >/dev/null 2>&1 ;\
	gdb -x gdb/defs.gdb -x $(2) -x gdb/init.gdb ;\
	kill -9 $$! || true
endef

vm-debug16: vm-burn
	$(call vm_debug,$(_QEMU32),gdb/init16.gdb)

#vm-debug32: vm-burn
#	$(call vm_debug,$(_QEMU32),gdb/init32.gdb)
#vm-debug64: vm-burn
#	$(call vm_debug,$(_QEMU64),gdb/init64.gdb)
