#!/bin/bash
#
# Flopster's build script.
# Based on build script for Quicksilver, by Ghostrider.
# Copyright (C) 2020-2021 Adithya R. (original version)
# Copyright (C) 2022-2024 Flopster101 (rewrite)

# Colors 
C_RED="\033[1;31m"
C_GREEN="\033[1;32m"
C_YELLOW="\033[1;33m"
C_BLUE="\033[1;34m"
C_CYAN="\033[1;36m"
C_RST="\033[0m"
C_BOLD="\033[1m"

## Vars
# Toolchains
AOSP_REPO="https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+/refs/heads/master"
AOSP_ARCHIVE="https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/master"
PC_REPO="https://github.com/kdrag0n/proton-clang"
LZ_REPO="https://gitlab.com/Jprimero15/lolz_clang.git"

# Other
DEFAULT_DEFCONFIG="proton_defconfig"
KERNEL_URL="https://github.com/ProtonKernel/Proton"
AK3_URL="https://github.com/ProtonKernel/AnyKernel3"
AK3_TEST=0
SECONDS=0 # builtin bash timer
DATE="$(date '+%Y%m%d-%H%M')"
BUILD_HOST="$USER@$(hostname)"

# Workspace
if [ -d /workspace ]; then
    WP="/workspace"
    IS_GP=1
else
    IS_GP=0
fi
if [ -z "$WP" ]; then
    echo -e "\n${C_RED}ERROR:${C_RST} Environment not Gitpod! Please set the WP env var...\n"
    exit 1
fi

if [ ! -d drivers ]; then
    echo -e "\n${C_RED}ERROR:${C_RST} Please exec from top-level kernel tree\n"
    exit 1
fi

if [ "$IS_GP" = "1" ]; then
    export KBUILD_BUILD_USER="Flopster101"
    export KBUILD_BUILD_HOST="buildbot"
fi

export KBUILD_BUILD_TIMESTAMP="$(LC_ALL=C date)"

export PATH="$(pwd)/build/bin:$PATH"

# Directories
TC_DIR="$WP/toolchains"
AC_DIR="$TC_DIR/aospclang"
PC_DIR="$TC_DIR/protonclang"
LZ_DIR="$TC_DIR/lolzclang"
AK3_DIR="$WP/AK3-r9s"
AK3_BRANCH="r9s"
KDIR="$(readlink -f .)"

# Ensure the toolchains directory exists
if [[ ! -d "$TC_DIR" ]]; then
    mkdir -p "$TC_DIR"
fi

## Inherited paths
OUTDIR="$KDIR/out"
MOD_OUTDIR="$KDIR/modules_out"
TMPDIR="$KDIR/build/tmp"
IN_VBOOT="$KDIR/build/vboot"
RAMDISK_DIR="$TMPDIR/vboot_ramdisk"
PREBUILT_RAMDISK="$KDIR/build/boot/ramdisk"
MODULES_DIR="$RAMDISK_DIR/lib/modules"
OUT_KERNEL="$OUTDIR/arch/arm64/boot/Image"
OUT_BOOTIMG="$KDIR/build/boot.img"
OUT_VENDORBOOTIMG="$KDIR/build/vendor_boot.img"
OUT_DTBIMAGE="$TMPDIR/dtb.img"
# Tools
MKBOOTIMG="$(pwd)/build/mkbootimg/mkbootimg.py"
MKDTBOIMG="$(pwd)/build/dtb/mkdtboimg.py"

# DTS files
DTS_DEFAULT="$KDIR/arch/arm64/boot/dts/exynos/exynos2100.dts"
DTS_BALANCED="$KDIR/arch/arm64/boot/dts/exynos/exynos2100_balanced.dts"
DTS_BATTERY="$KDIR/arch/arm64/boot/dts/exynos/exynos2100_battery.dts"
DTS_OC="$KDIR/arch/arm64/boot/dts/exynos/exynos2100_oc.dts"

# Dependencies
UB_DEPLIST=" make bison libssl-dev curl lz4 brotli flex bc cpio kmod ccache zip binutils-aarch64-linux-gnu device-tree-compiler"
if grep -q "Ubuntu" /etc/os-release; then
    sudo apt install $UB_DEPLIST -y
else
    echo -e "\n${C_CYAN}INFO:${C_RST} Your distro is not Ubuntu, skipping dependencies installation..."
    echo -e "${C_CYAN}INFO:${C_RST} Make sure you have these dependencies installed before proceeding: $UB_DEPLIST"
fi

if ! command -v dtc &>/dev/null; then
    echo -e "\n${C_RED}ERROR:${C_RST} 'dtc' (Device Tree Compiler) is not installed. Aborting...\n"
    exit 1
fi

## Customizable vars
# Kernel version
K_VER="v6.1.1"
# Toggles
USE_CCACHE=1
DO_TAR="1"
DO_ZIP="1"

# Upload build log
BUILD_LOG=1

# Pick aosp, proton or lolz
CLANG_TYPE=aosp

## Info message
LINKER=ld.lld
DEVICE="Galaxy S21 Series"
CODENAME="exynos2100"

## Parse arguments
# Default values
DO_KSU=0
DO_CLEAN=0
DO_MENUCONFIG=0
IS_RELEASE=0
DO_TG=0
DO_OSHI=0
DO_FLTO=0
DO_REGEN=0
DEFCONFIG=$DEFAULT_DEFCONFIG
BUILD_VARIANT="default"

while [[ "$1" == -* ]]; do

    i=1
    while [ $i -lt ${#1} ]; do
        FLAG="${1:$i:1}"
        case $FLAG in
            m)
                echo -e "\n${C_CYAN}INFO:${C_RST} menuconfig argument passed, kernel configuration menu will be shown..."
                DO_MENUCONFIG=1
                ;;
            k)
                echo -e "\n${C_CYAN}INFO:${C_RST} KernelSU argument passed, a KernelSU build will be made..."
                DO_KSU=1
                ;;
            c)
                echo -e "\n${C_CYAN}INFO:${C_RST} clean argument passed, output directory will be wiped..."
                DO_CLEAN=1
                ;;
            R)
                echo -e "\n${C_CYAN}INFO:${C_RST} Release argument passed, build marked as release"
                IS_RELEASE=1
                ;;
            t)
                echo -e "\n${C_CYAN}INFO:${C_RST} Telegram argument passed, build will be uploaded to CI"
                DO_TG=1
                ;;
            o)
                echo -e "\n${C_CYAN}INFO:${C_RST} bashupload.com argument passed, build will be uploaded to bashupload.com"
                DO_OSHI=1
                ;;
            l)
                echo -e "${C_CYAN}INFO:${C_RST} Full-LTO argument passed"
                echo -e "${C_YELLOW}WARNING:${C_RST} Full-LTO is VERY resource heavy and may take a long time to compile"
                DO_FLTO=1
                ;;
            r)
                echo -e "${C_CYAN}INFO:${C_RST} config regeneration mode"
                DO_REGEN=1
                ;;
            *)
                echo -e "${C_RED}ERROR:${C_RST} Unknown flag '$FLAG'"
                exit 1
                ;;
        esac
        i=$((i + 1))
    done
    shift 
done

if [ -n "$1" ]; then
    BUILD_VARIANT="$1"
fi

# Build type variables
BUILD_TYPE_DEFAULT=0
BUILD_TYPE_BALANCED=0
BUILD_TYPE_OC=0
BUILD_TYPE_BATTERY=0
BUILD_TYPE_PER=0
BUILD_TYPE_STR=""

case "$BUILD_VARIANT" in
    default)
        BUILD_TYPE_DEFAULT=1
        ;;
    balanced)
        BUILD_TYPE_STR="Balanced"
        BUILD_TYPE_BALANCED=1
        ;;
    battery)
        BUILD_TYPE_STR="Battery"
        BUILD_TYPE_BATTERY=1
        ;;
    oc)
        BUILD_TYPE_STR="Overclock"
        BUILD_TYPE_OC=1
        ;;
    per)
        BUILD_TYPE_STR="per"
        BUILD_TYPE_PER=1
        ;;
    *)
        echo "Unknown build variant: $BUILD_VARIANT, defaulting to 'default'"
        BUILD_TYPE_DEFAULT=1
        ;;
esac

if [ $DO_TG -eq 1 ]; then
IDS="$WP/ids"
## Secrets
if ! [ -d "$IDS" ]; then
    git clone -q https://github.com/ProtonKernel/ids $IDS
fi
TELEGRAM_CHAT_ID="$(cat ../ids/chat_ci)"
TELEGRAM_BOT_TOKEN=$(cat ../ids/bot_token)
fi

if [[ "${IS_RELEASE}" = "1" ]]; then
    BUILD_TYPE="Release"
else
    echo -e "\n${C_CYAN}INFO:${C_RST} Build marked as testing"
    BUILD_TYPE="Testing"
fi

## Build type
LINUX_VER=$(make kernelversion 2>/dev/null)

FK_TYPE=""
if [ $DO_KSU -eq 1 ]; then
    FK_TYPE="KSU"
else
    FK_TYPE="Non-root"
fi
if [[ "$BUILD_TYPE_BALANCED" == "1" ]]; then
    FK_TYPE="$BUILD_TYPE_STR-$FK_TYPE"
elif [[ "$BUILD_TYPE_BATTERY" == "1" ]]; then
    FK_TYPE="$BUILD_TYPE_STR-$FK_TYPE"
elif [[ "$BUILD_TYPE_OC" == "1" ]]; then
    FK_TYPE="$BUILD_TYPE_STR-$FK_TYPE"
fi

ZIP_PATH="$KDIR/build/ProtonPlus-$K_VER-$FK_TYPE-$CODENAME-$DATE.zip"
export ZIP_PATH="$KDIR/build/ProtonPlus-$K_VER-$FK_TYPE-$CODENAME-$DATE.zip"
TAR_PATH="$KDIR/build/ProtonPlus-$K_VER-$FK_TYPE-$CODENAME-$DATE.tar"

echo -e "\n${C_BOLD}${C_GREEN}>>> BUILD CONFIGURATION <<<${C_RST}"
echo -e "${C_CYAN}INFO:${C_RST} Build info:
- Device: $DEVICE ($CODENAME)
- Addons = $FK_TYPE
- Proton version: $K_VER
- Linux version: $LINUX_VER
- Defconfig: $DEFCONFIG
- Build date: $DATE
- Build type: $BUILD_TYPE
- Build variant: $BUILD_VARIANT
- Clean build = $DO_CLEAN
"

get_toolchain() {
    # AOSP Clang
    if [[ $1 = "aosp" ]]; then
        if ! [ -d "$AC_DIR" ]; then
            # --- MODIFICATION START ---
            # Hardcode the specific AOSP Clang version and URL
            AOSP_CLANG_VERSION="clang-r563880"
            AOSP_CLANG_URL="https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/mirror-goog-main-llvm-toolchain-source/clang-r563880.tar.gz"
            AOSP_CLANG_TARBALL="${AOSP_CLANG_VERSION}.tar.gz"

            echo -e "\n${C_CYAN}INFO:${C_RST} AOSP Clang not found! Downloading specific version ($AOSP_CLANG_VERSION)..."
            
            # Download the specified version
            if ! curl -Lo "$AOSP_CLANG_TARBALL" "$AOSP_CLANG_URL"; then
                echo -e "\n${C_RED}ERROR:${C_RST} Downloading $AOSP_CLANG_URL failed! Aborting..."
                exit 1
            fi

            # Extract the toolchain
            mkdir -p "$AC_DIR"
            echo -e "\n${C_CYAN}INFO:${C_RST} Extracting toolchain..."
            if ! tar -xf "$AOSP_CLANG_TARBALL" -C "$AC_DIR"; then
                echo -e "\n${C_RED}ERROR:${C_RST} Failed to extract $AOSP_CLANG_TARBALL! Aborting..."
                exit 1
            fi

            # Clean up the downloaded tarball
            rm -f "$AOSP_CLANG_TARBALL"

            # Compatibility fixes from original script
            touch "$AC_DIR/bin/aarch64-linux-gnu-elfedit" && chmod +x "$AC_DIR/bin/aarch64-linux-gnu-elfedit"
            touch "$AC_DIR/bin/arm-linux-gnueabi-elfedit" && chmod +x "$AC_DIR/bin/arm-linux-gnueabi-elfedit"
            # --- MODIFICATION END ---
        fi
    fi

    # Proton Clang
    if [[ $1 = "proton" ]]; then
        if ! [ -d "$PC_DIR" ]; then
            echo -e "\n${C_CYAN}INFO:${C_RST} Proton Clang not found! Cloning to $PC_DIR..."
            if ! git clone -q --depth=1 $PC_REPO $PC_DIR; then
                echo -e "\n${C_RED}ERROR:${C_RST} Cloning failed! Aborting..."
                exit 1
            fi
        fi
    fi

    # Lolz Clang
    if [[ $1 = "lolz" ]]; then
        if ! [ -d "$LZ_DIR" ]; then
            echo -e "\n${C_CYAN}INFO:${C_RST} Lolz Clang not found! Cloning to $LZ_DIR..."
            if ! git clone -q --depth=1 $LZ_REPO $LZ_DIR; then
                echo -e "\n${C_RED}ERROR:${C_RST} Cloning failed! Aborting..."
                exit 1
            fi
        fi
    fi
}

prep_toolchain() {
    if [[ $1 = "aosp" ]]; then
        CLANG_DIR="$AC_DIR"
        CCARM64_PREFIX=aarch64-linux-gnu-
        echo -e "\n${C_CYAN}INFO:${C_RST} Using AOSP Clang..."
    elif [[ $1 = "proton" ]]; then
        CLANG_DIR="$PC_DIR"
        CCARM64_PREFIX=aarch64-linux-gnu-
        echo -e "\n${C_CYAN}INFO:${C_RST} Using Proton Clang..."
    elif [[ $1 = "lolz" ]]; then
        CLANG_DIR="$LZ_DIR"
        CCARM64_PREFIX=aarch64-linux-gnu-
        echo -e "\n${C_CYAN}INFO:${C_RST} Using Lolz Clang..."
    fi

    ## Set PATH
    export PATH="${CLANG_DIR}/bin:${PATH}"

    KBUILD_COMPILER_STRING=$("$CLANG_DIR"/bin/clang -v 2>&1 | head -n 1 | sed 's/(https..*//' | sed 's/ version//')
    export KBUILD_COMPILER_STRING
}

## Pre-build dependencies
get_toolchain $CLANG_TYPE
prep_toolchain $CLANG_TYPE

## Telegram info variables

CAPTION_BUILD="Build info:
*Device*: \`${DEVICE} [${CODENAME}]\`
*Kernel Version*: \`${LINUX_VER}\`
*Compiler*: \`${KBUILD_COMPILER_STRING}\`
*Build host*: \`${BUILD_HOST}\`
*Branch*: \`$(git rev-parse --abbrev-ref HEAD)\`
*Commit*: [($(git rev-parse HEAD | cut -c -7))]($(echo $KERNEL_URL)/commit/$(git rev-parse HEAD))
*Build type*: \`$BUILD_TYPE\`
*Build variant*: \`$BUILD_VARIANT\`
*Clean build*: \`$( [ "$DO_CLEAN" -eq 1 ] && echo Yes || echo No )\`
"

# Functions to send file(s) via Telegram's BOT api.
tgs() {
    MD5=$(md5sum "$1" | cut -d' ' -f1)
    curl -fsSL -X POST -F document=@"$1" https://api.telegram.org/bot"${TELEGRAM_BOT_TOKEN}"/sendDocument \
        -F "chat_id=${TELEGRAM_CHAT_ID}" \
        -F "parse_mode=Markdown" \
        -F "disable_web_page_preview=true" \
        -F "caption=${CAPTION_BUILD}*MD5*: \`$MD5\`" &>/dev/null
}

prep_build() {
    # Prepare ccache
    if [ "$USE_CCACHE" = "1" ]; then
        echo -e "\n${C_CYAN}INFO:${C_RST} Using ccache\n"
        if [ "$IS_GP" = "1" ]; then
            export CCACHE_DIR=$WP/.ccache
            ccache -M 10G
        else
            echo -e "${C_CYAN}INFO:${C_RST} Environment is not Gitpod, please make sure you setup your own ccache configuration!\n"
        fi
    fi

    # Show compiler information
    echo -e "${C_BOLD}Compiler information:${C_RST}"
    echo -e "\n${C_CYAN}INFO:${C_RST} $KBUILD_COMPILER_STRING\n"
}

build() {
    # Delete log.txt at the start
    rm -f log.txt

    # Not that necessary anymore, but still export it just in case.
    export PLATFORM_VERSION=11
    export ANDROID_MAJOR_VERSION=r
    export TARGET_SOC=exynos2100

    export LLVM=1
    export LLVM_IAS=1
    export ARCH=arm64
    VERSION_STR="\"-ProtonPlus-$K_VER\""
    if [ "$BUILD_TYPE_DEFAULT" != "1" ]; then
        VERSION_STR="\"-ProtonPlus-$K_VER-$BUILD_TYPE_STR\""
    fi

    # Delete leftovers
    rm -f $OUT_KERNEL
    rm -rf "$MOD_OUTDIR"

    make -j$(nproc --all) O=out CC="clang" CROSS_COMPILE="$CCARM64_PREFIX" $DEFCONFIG $([[ "$DO_KSU" == "1" ]] && echo "ksu.config") 2>&1 | tee log.txt

    if [ $DO_MENUCONFIG = "1" ]; then
        make O=out menuconfig 2>&1 >> log.txt
    fi

    if [[ "$DO_REGEN" = "1" ]]; then
        if [[ "$DO_KSU" = "1" ]]; then
            echo -e "${C_RED}ERROR:${C_RST} Can't regenerate with KSU argument"
            exit 1
        fi
        cp -f out/.config arch/arm64/configs/$DEFCONFIG
        echo -e "${C_CYAN}INFO:${C_RST} Configuration regenerated. Check the changes!"
        exit 0
    fi

    scripts/config --file "$KDIR/out/.config" --set-val LOCALVERSION "$VERSION_STR"

    if [[ "$DO_FLTO" == "1" ]]; then
        scripts/config --file "$KDIR/out/.config" --enable CONFIG_LTO_CLANG
        scripts/config --file "$KDIR/out/.config" --disable CONFIG_THINLTO
    fi

    if [ "$BUILD_TYPE_BALANCED" == "1" ]; then
        scripts/config --file "$KDIR/out/.config" --set-val CONFIG_SOC_EXYNOS2100_CL0_UV 4
        scripts/config --file "$KDIR/out/.config" --set-val CONFIG_SOC_EXYNOS2100_CL1_UV 4
        scripts/config --file "$KDIR/out/.config" --set-val CONFIG_SOC_EXYNOS2100_CL2_UV 3
    fi

    if [ "$BUILD_TYPE_BATTERY" == "1" ]; then
        scripts/config --file "$KDIR/out/.config" --set-val CONFIG_SOC_EXYNOS2100_CL0_UV 5
        scripts/config --file "$KDIR/out/.config" --set-val CONFIG_SOC_EXYNOS2100_CL1_UV 4
        scripts/config --file "$KDIR/out/.config" --set-val CONFIG_SOC_EXYNOS2100_CL2_UV 4
    fi

    if [ "$BUILD_TYPE_OC" == "1" ]; then
        scripts/config --file "$KDIR/out/.config" --set-val CONFIG_SOC_EXYNOS2100_CL0_UV 0
        scripts/config --file "$KDIR/out/.config" --set-val CONFIG_SOC_EXYNOS2100_CL1_UV 0
        scripts/config --file "$KDIR/out/.config" --set-val CONFIG_SOC_EXYNOS2100_CL2_UV 0
    fi

    if [ "$BUILD_TYPE_PER" == "1" ]; then
        scripts/config --file "$KDIR/out/.config" --set-val CONFIG_SECURITY_SELINUX_ALWAYS_PERMISSIVE y
    fi
    ## Start the build
    echo -e "\n${C_CYAN}INFO:${C_RST} Starting compilation...\n"

    make -j$(nproc --all) O=out CC="clang" CROSS_COMPILE="$CCARM64_PREFIX" dtbs 2>&1 | tee -a log.txt
    if [ $USE_CCACHE = "1" ]; then
        make -j$(nproc --all) O=out CC="ccache clang" CROSS_COMPILE="$CCARM64_PREFIX" 2>&1 | tee -a log.txt
    else
        make -j$(nproc --all) O=out CC="clang" CROSS_COMPILE="$CCARM64_PREFIX" 2>&1 | tee -a log.txt
    fi
    make -j$(nproc --all) O=out CC="clang" CROSS_COMPILE="$CCARM64_PREFIX" INSTALL_MOD_STRIP="--strip-debug --keep-section=.ARM.attributes" INSTALL_MOD_PATH="$MOD_OUTDIR" modules_install 2>&1 | tee -a log.txt
}

packing() {
    # Make an AnyKernel3-based zip
    if [ $DO_ZIP = 1 ]; then
        if [ -d $AK3_DIR ]; then
            AK3_TEST=1
            echo -e "\n${C_CYAN}INFO:${C_RST} AK3_TEST flag set because local AnyKernel3 dir was found"
        else
            if ! git clone -q -b $AK3_BRANCH --depth=1 $AK3_URL $AK3_DIR; then
                echo -e "\n${C_RED}ERROR:${C_RST} Failed to clone AnyKernel3!"
                exit 1
            fi
        fi
        echo -e "\n${C_CYAN}INFO:${C_RST} Building zip..."
        cd "$AK3_DIR"
        cp -f "$OUT_VENDORBOOTIMG" vendor_boot.img
        cp -f "$OUT_KERNEL" .
        zip -r9 -q "$ZIP_PATH" * -x .git .github README.md
        cd "$KDIR"
        echo -e "${C_CYAN}INFO:${C_RST} Done! \n${C_CYAN}INFO:${C_RST} Output: $ZIP_PATH\n"
        if [ $AK3_TEST = 1 ]; then
            echo -e "\n${C_CYAN}INFO:${C_RST} Skipping deletion of AnyKernel3 dir because test flag is set"
        else
            rm -rf $AK3_DIR
        fi
    fi

    # Build tar
    if [ $DO_TAR = 1 ]; then
        echo -e "\n${C_CYAN}INFO:${C_RST} Building tar..."
        cd "$(pwd)/build"
        rm -f "$TAR_PATH"
        lz4 -c -12 -B6 --content-size "$OUT_BOOTIMG" > boot.img.lz4 2>/dev/null
        lz4 -c -12 -B6 --content-size "$OUT_VENDORBOOTIMG" > vendor_boot.img.lz4 2>/dev/null
        tar -cf "$TAR_PATH" boot.img.lz4 vendor_boot.img.lz4
        rm -f boot.img.lz4 vendor_boot.img.lz4
        cd "$KDIR"
        echo -e "${C_CYAN}INFO:${C_RST} Done! \n${C_CYAN}INFO:${C_RST} Output: $TAR_PATH\n"
    fi
}

post_build() {
    local MONTH="$(date +%Y-%m)"

    ## Check if the kernel binaries were built.
    if [ -f "out/arch/arm64/boot/Image" ]; then
        echo -e "\n${C_GREEN}INFO: Kernel compiled succesfully!...${C_RST}\n"
    else
        echo -e "\n${C_RED}ERROR:${C_RST} Kernel files not found! Compilation failed?"
        echo -e "\n${C_CYAN}INFO:${C_RST} Uploading log to bashupload.com\n"
        curl -T log.txt bashupload.com
        exit 1
    fi

    ## Post build setup
    rm -rf "$TMPDIR"
    rm -f "$OUT_BOOTIMG"
    rm -f "$OUT_VENDORBOOTIMG"
    rm -rf "$RAMDISK_DIR"
    mkdir "$TMPDIR"
    mkdir "$RAMDISK_DIR"
    mkdir -p "$MODULES_DIR/0.0"

    ## Compile correct DTS for variant
    DTB_OUT="$TMPDIR/exynos2100.dtb"
    if [ "$BUILD_TYPE_DEFAULT" = "1" ]; then
        DTS_SRC="$DTS_DEFAULT"
    elif [ "$BUILD_TYPE_BALANCED" = "1" ]; then
        DTS_SRC="$DTS_BALANCED"
    elif [ "$BUILD_TYPE_BATTERY" = "1" ]; then
        DTS_SRC="$DTS_BATTERY"
    elif [ "$BUILD_TYPE_OC" = "1" ]; then
        DTS_SRC="$DTS_OC"
    elif [ "$BUILD_TYPE_PER" = "1" ]; then
        DTS_SRC="$DTS_DEFAULT"
    fi
    echo -e "\n${C_CYAN}INFO:${C_RST} Compiling DTS: $DTS_SRC -> $DTB_OUT\n"
    dtc -I dts -O dtb -o "$DTB_OUT" "$DTS_SRC" >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo -e "\n${C_RED}ERROR:${C_RST} dtc failed to compile $DTS_SRC\n"
        exit 1
    fi

    cp -rf "$IN_VBOOT"/* "$RAMDISK_DIR/"

    # Handle compiled modules
    if ! find "$MOD_OUTDIR/lib/modules" -mindepth 1 -type d | read; then
        echo -e "\n${C_RED}ERROR:${C_RST} Unknown error!\n"
        exit 1
    fi

    missing_modules=""

    # If any module from modules.load was not compiled, abort.
    for module in $(cat "$IN_VBOOT/lib/modules/modules.load"); do
        i=$(find "$MOD_OUTDIR/lib/modules" -name $module);
        if [ -f "$i" ]; then
            cp -f "$i" "$MODULES_DIR/0.0/$module"
        else
        missing_modules="$missing_modules $module"
        fi
    done

    if [ "$missing_modules" != "" ]; then
            echo -e "${C_RED}ERROR:${C_RST} the following modules were not found: $missing_modules"
        exit 1
    fi

    # Check for duplicate modules in modules.load
    if [ -f "$IN_VBOOT/lib/modules/modules.load" ]; then
        dupes=$(sort "$IN_VBOOT/lib/modules/modules.load" | uniq -d | xargs)
        if [ -n "$dupes" ]; then
            echo -e "\n${C_RED}ERROR:${C_RST} Duplicate module entries found in modules.load: $dupes\n"
            exit 1
        fi
    fi

    # Warn for modules present but not in modules.load
    if [ -d "$MOD_OUTDIR/lib/modules" ] && [ -f "$IN_VBOOT/lib/modules/modules.load" ]; then
        all_built=$(find "$MOD_OUTDIR/lib/modules" -type f -name "*.ko" -exec basename {} \; | sort)
        all_load=$(sort "$IN_VBOOT/lib/modules/modules.load")
        not_in_load=$(comm -23 <(echo "$all_built") <(echo "$all_load") | xargs)
        if [ -n "$not_in_load" ]; then
            echo -e "\n${C_YELLOW}WARNING:${C_RST} The following modules exist but are NOT in modules.load: $not_in_load\n"
        fi
    fi

    # Prepare ramdisk
    depmod 0.0 -b "$RAMDISK_DIR"
    sed -i 's/\([^ ]\+\)/\/lib\/modules\/\1/g' "$MODULES_DIR/0.0/modules.dep"
    cd "$MODULES_DIR/0.0"
    for i in $(find . -name "modules.*" -type f); do
        if [ $(basename "$i") != "modules.dep" ] && [ $(basename "$i") != "modules.softdep" ] && [ $(basename "$i") != "modules.alias" ]; then
            rm -f "$i"
        fi
    done
    cd "$KDIR"

    cp -f "$IN_VBOOT/lib/modules/modules.load" "$MODULES_DIR/0.0/modules.load"
    mv "$MODULES_DIR/0.0"/* "$MODULES_DIR/"
    rm -rf "$MODULES_DIR/0.0"

    # Build the images
    echo -e "\n${C_CYAN}INFO:${C_RST} Building dtb image..."
    python "$MKDTBOIMG" create "$OUT_DTBIMAGE" --custom0=0x00000000 --custom1=0xff000000 --version=0 --page_size=2048 "$TMPDIR/exynos2100.dtb" || exit 1

    echo -e "\n${C_CYAN}INFO:${C_RST} Building boot image..."
    $MKBOOTIMG --header_version 3 \
        --kernel "$OUT_KERNEL" \
        --output "$OUT_BOOTIMG" \
        --ramdisk "$PREBUILT_RAMDISK" \
        --os_version 11.0.0 \
        --os_patch_level "$MONTH" || exit 1
    echo -e "${C_CYAN}INFO:${C_RST} Done!"

    echo -e "\n${C_CYAN}INFO:${C_RST} Building vendor_boot image..."
    cd "$RAMDISK_DIR"
    find . | cpio --quiet -o -H newc -R root:root | gzip -9 > ../ramdisk.cpio.gz
    cd ..

    $MKBOOTIMG --header_version 3 \
        --vendor_boot "$OUT_VENDORBOOTIMG" \
        --vendor_cmdline "loop.max_part=7" \
        --dtb "$OUT_DTBIMAGE" \
        --vendor_ramdisk "$(pwd)/ramdisk.cpio.gz" \
        --os_version 11.0.0 \
        --os_patch_level "$MONTH" || exit 1

    cd "$KDIR"

    echo -e "${C_CYAN}INFO:${C_RST} Done!"

    packing
}

upload() {
    cd $KDIR
    if [[ "${DO_TG}" = "1" ]]; then
            echo -e "\n${C_CYAN}INFO:${C_RST} Uploading to Telegram\n"
            tgs $ZIP_PATH
            echo -e "${C_GREEN}Done!${C_RST}"
    fi
    # Delete any leftover zip files
    #rm -f $KDIR/build/*zip
}

clean() {
    make clean
    make mrproper
}

clean_tmp() {
    echo -e "${C_CYAN}INFO:${C_RST} Cleaning after build..."
    rm -rf "$TMPDIR"
    rm -rf "$MOD_OUTDIR"
    rm -f "${OUT_VENDORBOOTIMG}" "${OUT_BOOTIMG}"
}

# Do a clean build?
if [[ $DO_CLEAN = "1" ]]; then
    clean
fi
## Run build
prep_build
build
post_build
clean_tmp

upload
