# Xiaomi Pad 8 Pro (piano) — Qualcomm SM8750P, 8/12/16GB, UFS, USB-C, WiFi/BT
#
# Boot path: the stock ABL loads an Android boot image from boot_b, exactly
# like the other SM8750 boards in this tree.  Nothing in the bootloader chain
# is ever written: fastboot writes userdata (the rootfs image this build
# produces) and, when wanted, boot_b.
declare -g BOARD_NAME="Xiaomi Pad 8 Pro"
declare -g BOARD_VENDOR="xiaomi"
declare -g BOARD_MAINTAINER="code002-2"
declare -g INTRODUCED="2026"
declare -g BOARDFAMILY="sm8750-piano"
declare -g KERNEL_TARGET="edge"
declare -g KERNEL_TEST_TARGET="edge"
declare -g EXTRAWIFI="no"
declare -g BOOTCONFIG="none"
declare -g IMAGE_PARTITION_TABLE="gpt"
declare -g DESKTOP_AUTOLOGIN="yes"

# The image-output-abl extension turns this into <version>.boot_<dtb>.img.
declare -g -a ABL_DTB_LIST=("sm8750-xiaomi-piano")

# The kernel is built with CONFIG_CMDLINE_FORCE off, so this is the cmdline the
# device actually boots with.  clk_ignore_unused/pd_ignore_unused keep the
# bootloader-configured clocks alive until the mainline drivers adopt them.
declare -g BOOTIMG_CMDLINE_EXTRA="clk_ignore_unused pd_ignore_unused console=tty0 loglevel=6 consoleblank=0 rootwait rw"

# Full linux-firmware: WCN7850 (ath12k), Adreno 830 (a830/a8xx gen80000), ADSP.
declare -g BOARD_FIRMWARE_INSTALL="-full"

function piano_is_userspace_supported() {
	[[ "${RELEASE}" == "trixie" ]] && return 0
	[[ "${RELEASE}" == "noble" ]] && return 0
	[[ "${RELEASE}" == "resolute" ]] && return 0
	return 1
}

function piano_is_userspace_supported_alert() {
	if ! piano_is_userspace_supported; then
		[[ "${RELEASE}" == "" ]] || display_alert "Missing userspace for ${BOARD}" \
			"${RELEASE} does not have the userspace necessary to support the ${BOARD}" "warn"
		return 1
	fi
	return 0
}

# The apps SMMU (qcom,qsmmu-v500 at 0x15000000) has no mainline driver, so the
# bootloader's stream matches are all the DMA masters get.  QUP1's GPI DMA and
# the ADSP streams are missing from them, which faults the moment those drivers
# probe: the storage bring-up has to repair the SMR/S2CR tables first, then load
# the UFS stack.  Both live in the initramfs, see packages/bsp/piano.
function post_family_tweaks_bsp__piano_storage_bringup() {
	display_alert "Installing piano storage bring-up for ${BOARD}" "${EXTENSION}" "info"
	install -Dm755 "${SRC}/packages/bsp/piano/piano-qup-smmu" \
		"${destination}/usr/lib/piano/piano-qup-smmu"
	install -Dm755 "${SRC}/packages/bsp/piano/usb-network" \
		"${destination}/usr/lib/piano/usb-network"
	install -Dm755 "${SRC}/packages/bsp/piano/piano-storage-hook" \
		"${destination}/etc/initramfs-tools/hooks/piano-storage"
	install -Dm755 "${SRC}/packages/bsp/piano/piano-storage-premount" \
		"${destination}/etc/initramfs-tools/scripts/init-premount/piano-storage"
	return 0
}

# qbootctl marks the booted A/B slot successful so ABL keeps booting it; it is
# packaged in the Armbian repo alongside mkbootimg (the ABL boot-image tool the
# image-output-abl extension needs on the host).
function post_family_tweaks__piano_enable_services() {
	mv "${SDCARD}/etc/apt/sources.list.d/armbian.sources.disabled" \
		"${SDCARD}/etc/apt/sources.list.d/armbian.sources" 2>/dev/null || true
	do_with_retries 3 chroot_sdcard_apt_get_update || true
	display_alert "Installing ${BOARD} tweaks" "${EXTENSION}" "warn"
	chroot_sdcard_apt_get_install qbootctl || \
		display_alert "qbootctl not available" "${BOARD}" "warn"

	install -Dm644 "${SRC}/packages/bsp/piano/piano-usb.service" \
		"${SDCARD}/usr/lib/systemd/system/piano-usb.service"
	chroot_sdcard systemctl enable piano-usb.service || true
	return 0
}
