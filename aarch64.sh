#!/usr/bin/env bash

set -ex

MACHINE=virt

U_BOOT="build/u-boot/${MACHINE}.bin"
IMAGE="build/kernel_live.uimage"
case "${MACHINE}" in
	raspi3)
		U_BOOT_CONFIG=rpi_3_defconfig
		LOAD_ADDR=0x04000000
		ENTRY_ADDR=0x04001000
		IMAGE_ADDR=0x08000000
		QEMU_ARGS=(
			-M raspi3
			-device "loader,file=${IMAGE},addr=${IMAGE_ADDR},force-raw=on"
			-kernel "${U_BOOT}"
			-nographic
			-serial null
			-serial mon:stdio
			-s
		)
		;;
	raspi4)
		U_BOOT_CONFIG=rpi_4_defconfig
		LOAD_ADDR=0x40000000
		ENTRY_ADDR=0x40001000
		IMAGE_ADDR=0x44000000
		# load mmc 0 0x44000000 kernel_live.uimage
		# bootm 0x44000000 - ${fdtcontroladdr}
		;;
	virt)
		U_BOOT_CONFIG=qemu_arm64_defconfig
		LOAD_ADDR=0x40000000
		ENTRY_ADDR=0x40001000
		IMAGE_ADDR=0x44000000
		QEMU_ARGS=(
			-M virt
			-m 1G
			-cpu cortex-a57
			-bios "${U_BOOT}"
			-device "loader,file=${IMAGE},addr=${IMAGE_ADDR},force-raw=on"
			-nographic
			-serial mon:stdio
			-s
		)
		;;
esac

if [ ! -f "${U_BOOT}" ]
then
	make prefix

	make -C u-boot distclean
	make -C u-boot "${U_BOOT_CONFIG}"

	sed -i \
		's/^CONFIG_BOOTCOMMAND=.*$/CONFIG_BOOTCOMMAND="bootm '"${IMAGE_ADDR}"' - ${fdtcontroladdr}"/' \
		u-boot/.config

	sed -i \
		's/^CONFIG_SYS_EXTRA_OPTIONS=""/CONFIG_SYS_EXTRA_OPTIONS="ARMV8_SWITCH_TO_EL1"/' \
		u-boot/.config

	TARGET=aarch64-unknown-redox
	env CROSS_COMPILE="${TARGET}-" \
		PATH="${PWD}/prefix/${TARGET}/relibc-install/bin/:${PATH}" \
		make -C u-boot -j "$(nproc)"

	mkdir -pv build/u-boot
	cp -v u-boot/u-boot.bin "${U_BOOT}"
fi

mkdir -p build
# rm -f build/libkernel.a build/kernel
rm -f build/kernel
touch build/bootloader
touch kernel
touch kernel/src/arch/aarch64/init/pre_kstart/early_init.S
make build/kernel
make build/initfs.tag
make build/filesystem.bin
make build/kernel_live

mkimage \
	-A arm64 \
	-O linux \
	-T kernel \
	-C none \
	-a "${LOAD_ADDR}" \
	-e "${ENTRY_ADDR}" \
	-n "Redox kernel (aarch64 ${MACHINE})" \
	-d build/kernel_live \
   	"${IMAGE}"

qemu-system-aarch64 "${QEMU_ARGS[@]}" "$@"
