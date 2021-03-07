#!/bin/bash
#
# Compile script for Nokia drg kernel
# SPDX-FileCopyrightText: Adithya R.

SECONDS=0 # start builtin bash timer
TC_DIR="$HOME/tc/clang-r547379"
AK3_DIR="$HOME/AnyKernel3"

DO_CLEAN=false
REGEN_DEFCONFIG=false
TARGET=drg

while (( $# > 0 )); do
    case "$1" in
        -c|--clean) DO_CLEAN=true ;;
        -r|--regen) REGEN_DEFCONFIG=true ;;
    esac
    shift
done

ZIPNAME="SentrY-$TARGET-$(date '+%Y%m%d-%H%M').zip"
if test -z "$(git rev-parse --show-cdup 2>/dev/null)" &&
    head=$(git rev-parse --verify HEAD 2>/dev/null); then
        ZIPNAME="${ZIPNAME::-4}-$(echo $head | cut -c1-8).zip"
fi

export PATH="$TC_DIR/bin:$PATH"

DEFCONFIG="nokia_defconfig"

msg() {
    echo -e "\e[1;32m$1\e[0m"
}

m() {
    make -j $(nproc) O=out ARCH=arm64 CC="ccache clang" LLVM_IAS=1 \
	HOSTLD=ld.lld LD=ld.lld LD_ARM32=ld.lld AR=llvm-ar NM=llvm-nm \
	OBJCOPY=llvm-objcopy OBJDUMP=llvm-objdump STRIP=llvm-strip \
	CLANG_TRIPLE=aarch64-linux-gnu- \
	CROSS_COMPILE_ARM32=arm-eabi- CROSS_COMPILE=$TC_DIR/bin/llvm- \
        TARGET_PRODUCT=$TARGET "$@" || exit $?
}

$DO_CLEAN && {
    rm -rf out
    echo "Cleaned output directories."
}

$REGEN_DEFCONFIG && {
    msg "\nRegenerating config...\n"
    m $DEFCONFIG savedefconfig || return
    cp out/defconfig arch/arm64/configs/$DEFCONFIG
    msg "\nSuccessfully regenerated defconfig at '$DEFCONFIG'\n"
    exit
}

msg "\nGenerating config...\n"
mkdir -p out
m $DEFCONFIG

msg "\nBuilding kernel for '$TARGET'...\n"
m Image.gz-dtb 2> >(tee out/error.log >&2)

kernel="out/arch/arm64/boot/Image.gz-dtb"

if [ -f $kernel ]; then
    msg "\nKernel compiled succesfully! Zipping up...\n"
    if [[ -d $AK3_DIR ]]; then
        cp -r $AK3_DIR AnyKernel3
        git -C AnyKernel3 checkout drg &>/dev/null
    else
        if ! git clone -q https://github.com/BladeRunner-A2C/AnyKernel3 -b drg --depth=1; then
            echo -e "\nAnyKernel3 repo not found locally and couldn't clone from GitHub! Aborting..."
            exit 1
        fi
    fi
    cp $kernel AnyKernel3
    cd AnyKernel3
    zip -r9 ../$ZIPNAME * -x .git README.md *placeholder
    cd ..
    rm -rf AnyKernel3
    msg "\nCompleted in $((SECONDS / 60)) minute(s) and $((SECONDS % 60)) second(s) !\n"
    echo "Zip: $(realpath $ZIPNAME)"
    echo -e "\nUploading..."
    output=$(curl --progress-bar -T "$ZIPNAME" -u :"$PD_API_KEY" https://pixeldrain.com/api/file/)
    id=$(echo $output | jq -r '.id')
    echo -e "\nDownload URL: https://pixeldrain.com/api/file/$id?download\n"
else
    echo -e "\nCompilation failed!"
    exit 1
fi
