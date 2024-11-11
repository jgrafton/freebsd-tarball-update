#!/bin/sh

set -e

ARCH="$(uname -m)"
if [ -z "${VERSION}" ]; then
	VERSION=`uname -r | sed -E 's,-p[0-9]+,,'`
fi

if uname -r | grep -Eq 'RELEASE'; then
    URL="http://pkg.jrgsystems.com/releases/${ARCH}/${VERSION}"
else
    URL="https://download.freebsd.org/snapshots/${ARCH}/${VERSION}"
fi

TODAY=$(date "+%Y-%m-%d")
BOOTENV="${VERSION}-${TODAY}"
WORKDIR="/var/db/freebsd-tarball-update"
PHASE_FILE="/var/tmp/.freebsd-tarball-phase1"


bectl_check() {
	# check for zfs boot environments
	if [ ! -x /sbin/bectl ]; then
		echo "/sbin/bectl missing, is this a FreeBSD 12.x or greater system?"
		exit 1
	fi
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
	mkdir -p "${WORKDIR}/${BOOTENV}"

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

	if [ -z "${MOUNT}" ]; then
		echo "unable to mount boot environment ${BOOTENV}"
		exit 1
	fi

	if [ ! -d "${MOUNT}" ]; then
		echo "${MOUNT} is not a valid directory"
		exit 1
	fi
}

extract_tarballs() {
	# extract kernel
	echo "=== extracting /boot/kernel to ${BOOTENV} ==="
    rm -Rf "${MOUNT}/boot/kernel.old"
    mv "${MOUNT}/boot/kernel" "${MOUNT}/boot/kernel.old"
	tar -C ${MOUNT} -xpf "${WORKDIR}/${BOOTENV}/kernel.txz"

	# extract base
	echo "=== extracting / to ${BOOTENV} ==="
	tar -C ${MOUNT} --exclude=etc --clear-nochange-fflags -xpf "${WORKDIR}/${BOOTENV}/base.txz" || /usr/bin/true
}

update_packages() {
	echo "=== updating packages on ${BOOTENV} ==="
	mount -t devfs devfs "${MOUNT}/dev"
	pkg --chroot "${MOUNT}" update
	pkg --chroot "${MOUNT}" upgrade -y
	umount "${MOUNT}/dev"
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

extract_src() {
	# extract src
	echo "=== extracting /usr/src ==="
	rm -Rf "/usr/src/*"
	tar -C / -xpf "${WORKDIR}/${BOOTENV}/src.txz"
}

root_check
bectl_check

if [ -f "${PHASE_FILE}" ]; then

	extract_src
	run_etcupdate
	delete_old_files
	rm "${PHASE_FILE}"
	fully_activate_bootenv
	echo "=== update complete! ==="

else

	echo "=== Updating ${ARCH}/${VERSION} on ${TODAY} in 5 seconds.  Press Ctrl-C to stop ==="
	if [ ! -z "${DOWNLOAD}" ]; then
		echo "    not downloading tarballs first"
	fi
	sleep 5

	# write old kernel version to file for verification
 	mkdir -p "${WORKDIR}"
	uname -a > ${WORKDIR}/old-kernel.txt

	if [ -z "${DOWNLOAD}" ]; then
		download_tarballs
	else
		echo "=== not downloading tarballs ==="
	fi
	create_bootenv
	mount_bootenv
	extract_tarballs
	update_packages

	umount_bootenv
	activate_bootenv

	echo "=== ${BOOTENV} created and activated ==="
	echo "=== Reboot then run this script again to finish updates ==="
	touch "${PHASE_FILE}"
fi
