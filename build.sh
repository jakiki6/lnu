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

download busybox.tar.bz2 "https://www.busybox.net/downloads/busybox-1.35.0.tar.bz2"

download gnupg.tar.bz2 "https://gnupg.org/ftp/gcrypt/gnupg/gnupg-2.3.7.tar.bz2"
download libgpg-error.tar.bz2 "https://www.gnupg.org/ftp/gcrypt/libgpg-error/libgpg-error-1.45.tar.bz2"
download libgcrypt.tar.bz2 "https://www.gnupg.org/ftp/gcrypt/libgcrypt/libgcrypt-1.10.1.tar.bz2"
download libksba.tar.bz2 "https://www.gnupg.org/ftp/gcrypt/libksba/libksba-1.6.1.tar.bz2"
download libassuan.tar.bz2 "https://www.gnupg.org/ftp/gcrypt/libassuan/libassuan-2.5.5.tar.bz2"
download npth.tar.bz2 "https://www.gnupg.org/ftp/gcrypt/npth/npth-1.6.tar.bz2"

download kexec-tools.tar.gz "https://git.kernel.org/pub/scm/utils/kernel/kexec/kexec-tools.git/snapshot/kexec-tools-2.0.25.tar.gz"

download linux.tar.xz "https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.2.9.tar.xz"

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

function compile_lib() {
    mkdir libs
    cd libs

    tar vfx ../../dist/$1 --strip-components=1

    CFLAGS="-Os" ./configure --prefix=$(pwd)/../deps --with-sysroot=$(pwd)/../../root --host=$TARGET --enable-shared=no --enable-static=yes  --with-libgpg-error-prefix=$(pwd)/../deps
    make -j$(nproc)
    make install

    cd ..
    rm -fr libs
}

if [ ! -d gpg ]; then
    echo "[*] building gpg"

    mkdir gpg
    cd gpg

    mkdir deps
    compile_lib libgpg-error.tar.bz2
    compile_lib libgcrypt.tar.bz2
    compile_lib libksba.tar.bz2
    compile_lib libassuan.tar.bz2
    compile_lib npth.tar.bz2

    mkdir libs

    tar vfx ../dist/gnupg.tar.bz2 --strip-components=1

    CFLAGS="-Os -fcommon" LDFLAGS="-static -s" ./configure --prefix=/ --with-sysroot=$(pwd)/../root --host=$TARGET \
        --with-npth-prefix=$(pwd)/deps \
        --with-libgpg-error-prefix=$(pwd)/deps \
        --with-libgcrypt-prefix=$(pwd)/deps \
        --with-libassuan-prefix=$(pwd)/deps \
        --with-ksba-prefix=$(pwd)/deps \
	--disable-sqlite \
	--disable-card-support \
	--disable-ccid-driver \
        --disable-dirmngr \
        --disable-doc \
        --disable-gnutls \
	--disable-ldap \
        --disable-libdns \
        --disable-nls \
        --disable-ntbtls \
        --disable-photo-viewers \
        --disable-regex \
        --disable-scdaemon \
        --disable-sqlite \
        --disable-wks-tools \
        --disable-zip \
	--disable-gpgsm
    make DESTDIR=$(pwd) -j$(nproc) install

    cp bin/gpg ../root/bin

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
cp ../config/trustedkeys root/
cp ../config/pubkeys root/

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
