#!/bin/bash -x
# Build tarballs of various musl cross-compilers
# 
# Copyright (C) 2012 Gregor Richards
# 
# Permission to use, copy, modify, and/or distribute this software for any
# purpose with or without fee is hereby granted, provided that the above
# copyright notice and this permission notice appear in all copies.
# 
# THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES WITH
# REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY
# AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT,
# INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM
# LOSS OF USE, DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR
# OTHER TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR
# PERFORMANCE OF THIS SOFTWARE.

if [ ! "$MUSL_CC_BASE" ]
then
    MUSL_CC_BASE=`dirname "$0"`/..
fi

# Fail on any command failing:
set -e

# Figure out our id
pushd "$MUSL_CC_BASE"
HG_ID=`hg id | sed 's/ .*//'`
popd

cleanup() {
    rm -rf {binutils,gcc,linux,musl,gmp,mpfr,mpc}-*/{configured,build,built,installed}*
    for p in {musl,gmp,mpfr,mpc}-*/
    do
        pushd $p
        make distclean || true
        popd
    done
}

if [ -e config.sh ]
then
    echo 'Please use a fresh directory.'
    exit 1
fi

if [ ! "$4" ]
then
    echo 'Use: .../build-tarballs.sh <install prefix> <tarball prefix> <tarball suffix> <native arch> [other archs]'
    exit 1
fi

PREFIX_BASE="$1"
shift
T_PRE="$1"
shift
T_SUFF="$1"
shift
NATIVE_ARCH="$1"

for ARCH in "$@"
do
    if expr "$ARCH" : 'arm' > /dev/null 2> /dev/null
    then
        TRIPLE="$ARCH-linux-musleabi"
    else
        TRIPLE="$ARCH-linux-musl"
    fi

    if [ "$ARCH" = "$NATIVE_ARCH" ]
    then
        if [ ! -e "$PREFIX_BASE/bootstrap/bin/$TRIPLE-g++" ]
        then
            # Make the config.sh
            echo 'ARCH='$ARCH'
TRIPLE='$TRIPLE'
CC_PREFIX="'"$PREFIX_BASE/bootstrap"'"
MAKEFLAGS="'"$MAKEFLAGS"'"' > config.sh

            # Build the bootstrap one first
            "$MUSL_CC_BASE"/build.sh
            "$MUSL_CC_BASE"/extra/build-gcc-deps.sh
            rm -f config.sh
            cleanup
        fi

        NATIVE_CROSS="$PREFIX_BASE/bootstrap/bin/$TRIPLE"

        # Get rid of dlfcn.h as a cheap hack to disable building plugins
        rm -f "$PREFIX_BASE/bootstrap/$TRIPLE/include/dlfcn.h"
    fi

    if [ ! -e "$PREFIX_BASE/$TRIPLE/bin/$TRIPLE-g++" ]
    then
        # Make the config.sh
        echo 'ARCH='$ARCH'
TRIPLE='$TRIPLE'
CC_PREFIX="'"$PREFIX_BASE/$TRIPLE"'"
MAKEFLAGS="'"$MAKEFLAGS"'"
CC="'"$NATIVE_CROSS-gcc"' -Wl,-Bstatic -static-libgcc"
CXX="'"$NATIVE_CROSS-g++"' -Wl,-Bstatic -static-libgcc"
export CC CXX
GCC_BOOTSTRAP_CONFFLAGS=--disable-lto-plugin
GCC_CONFFLAGS=--disable-lto-plugin' > config.sh

        # And build
        "$MUSL_CC_BASE"/build.sh
        sed -E '/^C(C|XX)=/d ; /^export/d' -i config.sh
        "$MUSL_CC_BASE"/extra/build-gcc-deps.sh

        # Clean up
        rm -f config.sh
        cleanup

        # Make the tarball
        pushd "$PREFIX_BASE"
        rm -rf "$TRIPLE/share"
        find "$TRIPLE/bin" "$TRIPLE/libexec/gcc" -type f -exec "$NATIVE_CROSS-strip" --strip-unneeded '{}' ';'
        echo 'Cross-compiler prefix built by musl-cross '"$HG_ID"': http://www.bitbucket.org/GregorR/musl-cross' > "$TRIPLE/info.txt"
        tar -cf - "$TRIPLE/" | xz -c > "$T_PRE$TRIPLE$T_SUFF.tar.xz"
        popd
    fi
done