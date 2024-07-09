#!/bin/bash

ARCH=x86_64
TARGET=$ARCH-linux-musl

unset CFLAGS
unset CXXFLAGS
export LC_ALL=POSIX

set +h -e
umask 022

function download() {
    if [ ! -f dist/$1 ]; then
        wget $2 -O dist/$1
    fi
}

if [ ! -d build ]; then mkdir build; fi
cd build

if [ ! -d dist ]; then mkdir dist; fi

download busybox.tar.bz2 "https://www.busybox.net/downloads/busybox-1.36.1.tar.bz2"

download libsodium.tar.gz "https://github.com/jedisct1/libsodium/releases/download/1.0.20-RELEASE/libsodium-1.0.20.tar.gz"

download minisign.tar.gz "https://github.com/jedisct1/minisign/releases/download/0.11/minisign-0.11.tar.gz"

download kexec-tools.tar.gz "https://git.kernel.org/pub/scm/utils/kernel/kexec/kexec-tools.git/snapshot/kexec-tools-2.0.28.tar.gz"

download linux.tar.xz "https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.9.8.tar.xz"

if [ ! -d toolchain ]; then
    echo "[*] building toolchain"

    if [ ! -d musl-cross-make ]; then git clone https://github.com/richfelker/musl-cross-make; fi
    cd musl-cross-make

    make TARGET=$TARGET
    mkdir ../toolchain
    make TARGET=$TARGET OUTPUT=$(pwd)/../toolchain install

    cd ..
fi

PATH=$PATH:$(pwd)/toolchain/bin
CROSS_COMPILE=$TARGET-

if [ ! -d root ]; then mkdir root; fi

if [ ! -d busybox ]; then
    echo "[*] building busybox"

    mkdir busybox
    cd busybox

    tar vfx ../dist/busybox.tar.bz2 --strip-components=1

    cp ../../config/busybox .config
    make ARCH=$ARCH CROSS_COMPILE=$CROSS_COMPILE busybox install

    cd ..
fi

if [ ! -d minisign ]; then
    echo "[*] building minisign"

    mkdir minisign
    cd minisign

    mkdir libsodium
    cd libsodium

    tar vfx ../../dist/libsodium.tar.gz --strip-components=1
    CFLAGS="-Os -fcommon" LDFLAGS="-static -s" ./configure --prefix=/ --with-sysroot=$(pwd)/../../root --host=$TARGET
    make -j$(nproc)

    cd ..

    cd src
    gcc -o minisign -Os -DVERIFY_ONLY -static *.c ../libsodium/src/libsodium/.libs/libsodium.a
    strip minisign
    cp minisign ../root/bin

    cd ..
fi

if [ ! -d kexec ]; then
    echo "[*] building kexec-tools"

    mkdir kexec
    cd kexec

    tar vfx ../dist/kexec-tools.tar.gz --strip-components=1

    ./bootstrap
    CFLAGS="-Os -fcommon" LDFLAGS="-static -s" ./configure --prefix=/ --with-sysroot=$(pwd)/../root --host=$TARGET
    make DESTDIR=$(pwd)/../root -j$(nproc) install

    cd ..
fi

cp ../config/init root/
cp ../config/key.pub root/

rm -fr root/lib
rm -fr root/share

if [ ! -d linux ]; then
    echo "[*] building kernel"

    mkdir linux
    cd linux

    tar vfx ../dist/linux.tar.xz --strip-components=1

    cp ../../config/linux.$ARCH .config
    make ARCH=$ARCH CROSS_COMPILE=$TARGET- -j$(nproc) bzImage
    cd ..
else
    echo "[*] rebuilding kernel to include newest initrd"
    cd linux
    make ARCH=$ARCH CROSS_COMPILE=$TARGET- -j$(nproc) bzImage
    cd ..
fi

cd ..
cp build/linux/arch/$ARCH/boot/bzImage .
