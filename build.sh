#!/bin/bash

ARCH=x86_64
TARGET=$ARCH-linux-musl

unset CFLAGS
unset CXXFLAGS
export LC_ALL=POSIX

set +h -e
umask 022

if [ ! -d build ]; then mkdir build; fi
cd build

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

    wget "https://www.busybox.net/downloads/busybox-1.35.0.tar.bz2" -O busybox.tar.bz2
    tar vfx busybox.tar.bz2 --strip-components=1

    cp ../../config/busybox .config
    make ARCH=$ARCH CROSS_COMPILE=$CROSS_COMPILE busybox install

    cd ..
fi

function compile_lib() {
    mkdir libs
    cd libs

    wget $1 -O lib.tar
    tar vfx lib.tar --strip-components=1

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
    compile_lib "https://www.gnupg.org/ftp/gcrypt/libgpg-error/libgpg-error-1.45.tar.bz2"
    compile_lib "https://www.gnupg.org/ftp/gcrypt/libgcrypt/libgcrypt-1.10.1.tar.bz2"
    compile_lib "https://www.gnupg.org/ftp/gcrypt/libksba/libksba-1.6.1.tar.bz2"
    compile_lib "https://www.gnupg.org/ftp/gcrypt/libassuan/libassuan-2.5.5.tar.bz2"
    compile_lib "https://www.gnupg.org/ftp/gcrypt/npth/npth-1.6.tar.bz2"

    mkdir libs

    wget "https://gnupg.org/ftp/gcrypt/gnupg/gnupg-2.3.7.tar.bz2" -O gpg.tar.bz2
    tar vfx gpg.tar.bz2 --strip-components=1

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

    wget "https://git.kernel.org/pub/scm/utils/kernel/kexec/kexec-tools.git/snapshot/kexec-tools-2.0.25.tar.gz" -O kexec.tar.gz
    tar vfx kexec.tar.gz --strip-components=1

    ./bootstrap
    CFLAGS="-Os -fcommon" LDFLAGS="-static -s" ./configure --prefix=/ --with-sysroot=$(pwd)/../root --host=$TARGET
    make DESTDIR=$(pwd)/../root -j$(nproc) install

    cd ..
fi

cp ../config/init root/
cp ../config/trustedkeys root/
cp ../config/pubkeys root/

if [ ! -d linux ]; then
    echo "[*] building kernel"

    mkdir linux
    cd linux

    wget "https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.1.1.tar.xz" -O linux.tar.xz
    tar vfx linux.tar.xz --strip-components=1

    cp ../../config/linux.$ARCH .config
    make ARCH=$ARCH CROSS_COMPILE=$TARGET- -j$(nproc) bzImage
    cd ..
else
    echo "[*] rebuilding kernel to include newest initrd"
    cd linux
    make ARCH=$ARCH CROSS_COMPILE=$TARGET- -j$(nproc) bzImage
    cd ..
fi
