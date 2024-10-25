#!/bin/sh


ARCH="$(uname -m)"
VERSION="$(uname -r)"
URL="https://download.freebsd.org/snapshots/${ARCH}/${VERSION}"
TODAY=$(date "+%Y-%m-%d")
WORKDIR="/var/db/freebsd-tarball-update"

bectl_check() {
	# check for zfs boot environments
	bectl check
	if [ $? -ne 0 ]; then
		echo "this computer does not support ZFS boot environments"
		exit 1
	fi
}

root_check() {
	# check for root access
	if [ "$(id -u)" -ne 0 ]; then
		echo "must run as root"
		exit 1
	fi
}

download_tarballs() {
	# create boot environment name
	BOOTENV="${VERSION}-${TODAY}"
	mkdir -p "${WORKDIR}/${BOOTENV}"

	# get latest files
	fetch -o "${WORKDIR}/${BOOTENV}/kernel.txz" "${URL}/kernel.txz"
	fetch -o "${WORKDIR}/${BOOTENV}/base.txz" "${URL}/base.txz"
	fetch -o "${WORKDIR}/${BOOTENV}/src.txz" "${URL}/src.txz"
}

create_bootenv() {
	# create boot env
	echo "=== creating ${BOOTENV} ==="
	bectl create "${BOOTENV}"
}

mount_bootenv() {
	# mount boot env
	echo "=== mounting ${BOOTENV} to temp directory ==="
	MOUNT=$(bectl mount "${BOOTENV}")

	if [ -z "${MOUNT}"]; then
		echo "unable to mount boot environment ${BOOTENV}"
		exit 1
	fi

	if [ ! -d "${MOUNT}"]; then
		echo "${MOUNT} is not a valid directory"
		exit 1
	fi
}

extract_tarballs() {
	# extract kernel
	echo "=== extracting /boot/kernel on ${BOOTENV} ==="
	tar -C ${MOUNT} -xvpf "${WORKDIR}/${BOOTENV}/kernel.txz"

	# extract base
	echo "=== extracting / on ${WORKDIR}/${BOOTENV} ==="
	tar -C ${MOUNT} --exclude=etc --clear-nochange-fflags -xvpf "${WORKDIR}/${BOOTENV}/base.txz"

	# extract src
	echo "=== extracting /usr/src on ${WORKDIR}/${BOOTENV} ==="
	rm -Rf "${MOUNT}/usr/src/*"
	tar -C ${MOUNT} -xzvpf "${WORKDIR}/${BOOTENV}/src.txz"
}

update_packages() {
	echo "=== updating packages on ${BOOTENV} ==="
	chroot "${MOUNT}" pkg update
	chroot "${MOUNT}" pkg upgrade
}

umount_bootenv() {
	# umount boot env
	echo "== unmounting ${BOOTENV} ==="
	bectl umount ${BOOTENV}
}

activate_bootenv() {
	# set the boot environment active for only one reboot
	echo "=== temporarily activating ${BOOTENV} ==="
	bectl activate -t ${BOOTENV}
}

fully_activate_bootenv() {
	# turn off temporary activation and activate fully
	echo "=== activating new boot environment ==="
	bectl activate -T ${BOOTENV}
	bectl activate ${BOOTENV}
}

run_etcupdate() {
	# update etc files
	echo "=== running etcupdate, can take awhile ==="
	etcupdate
}

delete_old_files() {
	# delete old libraries
	echo "=== deleting old files and libraries ==="
	cd /usr/src
	yes | make delete-old
	yes | make delete-old-libs
}

root_check
bectl_check

if [ -f ${WORKDIR}/.first ]; then

	fully_activate_bootenv
	run_etcupdate
	delete_old_files
	rm ${WORKDIR}/.first
	echo "=== update complete! ==="

else

	echo "=== Updating ${ARCH}/${VERSION} on ${TODAY} in 5 seconds.  Press Ctrl-C to stop ==="
	sleep 5

	# write old kernel version to file for verification
	uname -a > ${WORKDIR}/old-kernel.txt

	download_tarballs
	create_bootenv
	mount_bootenv
	extract_tarballs
	update_packages

	umount_bootenv
	activate_bootenv

	echo "=== ${BOOTENV} created and activated ==="
	echo "=== Reboot then run this script again to finish updates ==="
	touch ${WORKDIR}/.first
fi
