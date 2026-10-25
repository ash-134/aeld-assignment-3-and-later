#!/bin/bash
# Script outline to install and build kernel.
# Author: Siddhant Jajoo.

set -e
set -u

OUTDIR=/tmp/aeld
KERNEL_REPO=git://git.kernel.org/pub/scm/linux/kernel/git/stable/linux-stable.git
KERNEL_VERSION=v5.15.163
BUSYBOX_VERSION=1_34_1
FINDER_APP_DIR=$(realpath $(dirname $0))
ARCH=arm64
CROSS_COMPILE=aarch64-linux-gnu-

if [ $# -lt 1 ]
then
	echo "Using default directory ${OUTDIR} for output"
else
	OUTDIR=$1
	echo "Using passed directory ${OUTDIR} for output"
fi

mkdir -p ${OUTDIR}

cd "$OUTDIR"
if [ ! -d "${OUTDIR}/linux-stable" ]; then
    #Clone only if the repository does not exist.
	echo "CLONING GIT LINUX STABLE VERSION ${KERNEL_VERSION} IN ${OUTDIR}"
	git clone ${KERNEL_REPO} --depth 1 --single-branch --branch ${KERNEL_VERSION}
fi
if [ ! -e ${OUTDIR}/linux-stable/arch/${ARCH}/boot/Image ]; then
    cd linux-stable
    echo "Checking out version ${KERNEL_VERSION}"
    git checkout ${KERNEL_VERSION}

	echo "Configuring the ARM64 kernel"
	make ARCH="${ARCH}" CROSS_COMPILE="${CROSS_COMPILE}" defconfig
	./scripts/config --enable DEVMEM
	make ARCH="${ARCH}" CROSS_COMPILE="${CROSS_COMPILE}" olddefconfig

	echo "Building the kernel Image"
	make -j"$(nproc)" ARCH="${ARCH}" CROSS_COMPILE="${CROSS_COMPILE}" Image
fi

echo "Adding the Image in outdir"
cp "${OUTDIR}/linux-stable/arch/${ARCH}/boot/Image" "${OUTDIR}/Image"

echo "Creating the staging directory for the root filesystem"
cd "$OUTDIR"
if [ -d "${OUTDIR}/rootfs" ]
then
	echo "Deleting rootfs directory at ${OUTDIR}/rootfs and starting over"
    sudo rm  -rf ${OUTDIR}/rootfs
fi

# TODO: Create necessary base directories
mkdir -p "${OUTDIR}/rootfs"/{bin,dev,etc,home,lib,lib64,proc,sbin,sys,tmp,usr,var}
cd "$OUTDIR"
if [ ! -d "${OUTDIR}/busybox" ]
then
git clone https://git.busybox.net/busybox
    cd busybox
    git checkout ${BUSYBOX_VERSION}
    make ARCH="${ARCH}" CROSS_COMPILE="${CROSS_COMPILE}" defconfig
    sed -i 's/CONFIG_TC=y/# CONFIG_TC is not set/' .config
    # TODO:  Configure busybox
else
    cd busybox
fi

# TODO: Make and install busybox
make -j"$(nproc)" ARCH="${ARCH}" CROSS_COMPILE="${CROSS_COMPILE}"
make ARCH="${ARCH}" CROSS_COMPILE="${CROSS_COMPILE}" \
    CONFIG_PREFIX="${OUTDIR}/rootfs" install
ROOTFS="${OUTDIR}/rootfs"

echo "Cleaning and building writer utility"
make -C "${FINDER_APP_DIR}" clean || true
make -C "${FINDER_APP_DIR}" CROSS_COMPILE="${CROSS_COMPILE}" || true

echo "Library dependencies"
${CROSS_COMPILE}readelf -a "${ROOTFS}/bin/busybox" | grep "program interpreter"
${CROSS_COMPILE}readelf -a "${ROOTFS}/bin/busybox" | grep "Shared library"

echo "Adding library dependencies to rootfs"
SYSROOT=/usr/aarch64-linux-gnu
for binary in "${ROOTFS}/bin/busybox" "${FINDER_APP_DIR}/writer"
do
    interpreter=$(${CROSS_COMPILE}readelf -l "$binary" | sed -n 's/.*Requesting program interpreter: \(.*\)]/\1/p')
    if [ -n "$interpreter" ]; then
        install -D -m 0755 "/usr/aarch64-linux-gnu/lib/$(basename "${interpreter}")" "${ROOTFS}${interpreter}"
    fi
    while IFS= read -r library
    do
        library_path=$(find "$SYSROOT" \( -type f -o -type l \) -name "$library" -print -quit)
        if [ -z "$library_path" ]; then
            echo "Error: Could not find ${library} in ${SYSROOT}" >&2
            exit 1
        fi
        relative_library=${library_path#"${SYSROOT}"/}
        install -D -m 0755 "$library_path" "${ROOTFS}/${relative_library}"
    done < <(${CROSS_COMPILE}readelf -d "$binary" | sed -n 's/.*Shared library: \[\(.*\)\].*/\1/p')
done

echo "Creating device nodes"
sudo mknod -m 600 "${ROOTFS}/dev/console" c 5 1
sudo mknod -m 666 "${ROOTFS}/dev/null" c 1 3
sudo mknod -m 666 "${ROOTFS}/dev/zero" c 1 5
sudo mknod -m 600 "${ROOTFS}/dev/ttyAMA0" c 204 64

echo "Copying finder application files into rootfs"
mkdir -p "${ROOTFS}/home/conf" "${ROOTFS}/conf"
for script in autorun-qemu.sh finder-test.sh finder.sh writer.sh
do
    install -m 0755 "${FINDER_APP_DIR}/${script}" "${ROOTFS}/home/${script}"
done
install -m 0755 "${FINDER_APP_DIR}/writer" "${ROOTFS}/home/writer"
install -m 0644 "${FINDER_APP_DIR}/conf/username.txt" "${ROOTFS}/home/conf/username.txt"
install -m 0644 "${FINDER_APP_DIR}/conf/assignment.txt" "${ROOTFS}/conf/assignment.txt"

echo "Setting rootfs ownership"
sudo chown -R root:root "${ROOTFS}"
sudo chmod 1777 "${ROOTFS}/tmp"

echo "Creating initramfs.cpio.gz"
(
    set -o pipefail
    sudo cd "${ROOTFS}" 2>/dev/null || true; cd "${ROOTFS}"
    sudo find . -print0 | cpio --null -o --format=newc | gzip -9 > "${OUTDIR}/initramfs.cpio.gz"
)