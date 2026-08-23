#!/bin/bash
# LÖVE2D Cross-compilation Script for Miyoo Mini
# Builds all dependencies and LÖVE2D framework

set -euo pipefail

# Verbose mode (default: quiet)
RAW_VERBOSE=${VERBOSE:-false}
RAW_CLEAN_BUILD=${CLEAN_BUILD:-false}

normalize_bool() {
    case "$(echo "${1:-}" | tr '[:upper:]' '[:lower:]')" in
        1|y|yes|true|on)
            echo "true"
            ;;
        0|n|no|false|off|"")
            echo "false"
            ;;
        *)
            echo "${2:-false}"
            ;;
    esac
}

VERBOSE=$(normalize_bool "$RAW_VERBOSE" "false")
CLEAN_BUILD=$(normalize_bool "$RAW_CLEAN_BUILD" "false")

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"
ARTIFACT_DIR="$SCRIPT_DIR/build_artifacts"
ARTIFACT_LIB_DIR="$ARTIFACT_DIR/love_libs"
ARTIFACT_INCLUDE_DIR="$ARTIFACT_DIR/love_headers"
SYSROOT="/opt/miyoomini-toolchain/usr/arm-linux-gnueabihf/sysroot/usr"
LOG_DIR="$SCRIPT_DIR/logs"

# Full clean rebuild if requested
if [ "$CLEAN_BUILD" = "true" ]; then
    echo "🧹 CLEAN_BUILD=true: Performing full clean rebuild..."

    # Clean all built libraries from sysroot
    echo "  • Cleaning sysroot libraries..."
    rm -rf "$SYSROOT/lib/libogg"* \
           "$SYSROOT/lib/libvorbis"* \
           "$SYSROOT/lib/libtheora"* \
           "$SYSROOT/lib/libmodplug"* \
           "$SYSROOT/lib/libmpg123"* \
           "$SYSROOT/lib/libopenal"* \
           "$SYSROOT/lib/libluajit"* \
           "$SYSROOT/lib/pkgconfig/ogg.pc" \
           "$SYSROOT/lib/pkgconfig/vorbis*.pc" \
           "$SYSROOT/lib/pkgconfig/theora*.pc" \
           "$SYSROOT/lib/pkgconfig/libmodplug.pc" \
           "$SYSROOT/lib/pkgconfig/libmpg123.pc" \
           "$SYSROOT/lib/pkgconfig/openal.pc" \
           "$SYSROOT/lib/pkgconfig/luajit.pc" 2>/dev/null || true

    # Clean headers
    echo "  • Cleaning sysroot headers..."
    rm -rf "$SYSROOT/include/ogg" \
           "$SYSROOT/include/vorbis" \
           "$SYSROOT/include/theora" \
           "$SYSROOT/include/libmodplug" \
           "$SYSROOT/include/mpg123.h" \
           "$SYSROOT/include/AL" \
           "$SYSROOT/include/luajit-2.1" 2>/dev/null || true

    # Clean LÖVE build artifacts
    echo "  • Cleaning LÖVE build artifacts..."
    cd "$SCRIPT_DIR"
    make clean 2>/dev/null || true
    rm -f configure Makefile config.* src/Makefile 2>/dev/null || true

    # Clean autoconf installation marker
    rm -f "$SYSROOT/bin/autoconf" 2>/dev/null || true

    echo "  • Cleaning build directory..."
    rm -rf "$BUILD_DIR"

    echo "  • Removing cached artifacts and logs..."
    rm -rf "$ARTIFACT_DIR" "$LOG_DIR"

    echo "✅ Clean complete - full rebuild will proceed"
fi

# Create isolated build directory and log directory
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR" "$LOG_DIR"

log_output() {
    if [ "$VERBOSE" = "true" ]; then
        cat
    else
        cat > /dev/null
    fi
}

status_msg() {
    echo -e "\033[32m$1\033[0m"
}

error_msg() {
    echo -e "\033[31m$1\033[0m"
}

check_dev_tools() {
    if [ "$VERBOSE" = "true" ]; then
        status_msg "Checking development tools..."
    fi

    declare -A tool_to_package_map=(
        ["pkg-config"]="pkg-config"
        ["autoconf"]="autoconf"
        ["libtoolize"]="libtool"
        ["m4"]="m4"
        ["automake"]="automake"
        ["cmake"]="cmake"
    )

    missing_packages=()
    for tool in "${!tool_to_package_map[@]}"; do
        if ! command -v "$tool" > /dev/null 2>&1; then
            package=${tool_to_package_map[$tool]}
            if ! [[ " ${missing_packages[@]} " =~ " ${package} " ]]; then
                missing_packages+=("$package")
            fi
        fi
    done

    if [ ${#missing_packages[@]} -ne 0 ]; then
        status_msg "Installing missing build tools..."
        if [ "$VERBOSE" = "true" ]; then
            apt-get update
            apt-get install -y "${missing_packages[@]}"
        else
            apt-get update >/dev/null 2>&1
            DEBIAN_FRONTEND=noninteractive apt-get install -y "${missing_packages[@]}" >/dev/null 2>&1
        fi
    fi

    # Check for 32-bit dev libs (needed for LuaJIT HOST_CC="gcc -m32")
    if ! gcc -m32 -x c /dev/null -o /dev/null 2>/dev/null; then
        if ! dpkg -l | grep -q gcc-multilib; then
            status_msg "Installing gcc-multilib for LuaJIT..."
            if [ "$VERBOSE" = "true" ]; then
                apt-get update
                apt-get install -y gcc-multilib g++-multilib
            else
                apt-get update >/dev/null 2>&1
                DEBIAN_FRONTEND=noninteractive apt-get install -y gcc-multilib g++-multilib >/dev/null 2>&1
            fi
        fi
    fi
}

# Setup toolchain environment
export PATH="/opt/miyoomini-toolchain/usr/bin:${PATH}:/opt/miyoomini-toolchain/usr/arm-linux-gnueabihf/sysroot/bin"
export CROSS_COMPILE=/opt/miyoomini-toolchain/usr/bin/arm-linux-gnueabihf-
export PREFIX=/opt/miyoomini-toolchain/usr/arm-linux-gnueabihf/sysroot/usr

export FIN_BIN_DIR="$PREFIX"
export AR=${CROSS_COMPILE}ar
export AS=${CROSS_COMPILE}as
export LD=${CROSS_COMPILE}ld
export RANLIB=${CROSS_COMPILE}ranlib
export CC=${CROSS_COMPILE}gcc
export CXX=${CROSS_COMPILE}g++
export NM=${CROSS_COMPILE}nm
export HOST=arm-linux-gnueabihf
export BUILD=x86_64-linux-gnu
export CFLAGS="-Wno-undef -g3 -O0 -marm -mtune=cortex-a7 -mfpu=neon-vfpv4 -march=armv7ve+simd -mfloat-abi=hard"
export CXXFLAGS="-g3 -O0 -fPIC -pthread"
export LDFLAGS="-L/opt/miyoomini-toolchain/usr/arm-linux-gnueabihf/sysroot/lib -L/opt/miyoomini-toolchain/usr/arm-linux-gnueabihf/sysroot/usr/lib"

# PKG_CONFIG setup
export PKG_CONFIG_PATH="$FIN_BIN_DIR/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
export PKG_CONFIG_LIBDIR="$FIN_BIN_DIR/lib/pkgconfig${PKG_CONFIG_LIBDIR:+:$PKG_CONFIG_LIBDIR}"

mkdir -p "$ARTIFACT_LIB_DIR" "$ARTIFACT_INCLUDE_DIR" "$LOG_DIR"

check_dev_tools

# Build autoconf 2.71 if needed (for theora)
build_autoconf() {
    # Check if already built in toolchain
    if [ -f "$FIN_BIN_DIR/bin/autoconf" ]; then
        local version=$("$FIN_BIN_DIR/bin/autoconf" --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+' | head -1)
        if [ -n "$version" ]; then
            local major=$(echo "$version" | cut -d. -f1)
            local minor=$(echo "$version" | cut -d. -f2)

            if [ "$major" -eq 2 ] && [ "$minor" -ge 71 ]; then
                status_msg "autoconf $version already installed"
                export PATH="$FIN_BIN_DIR/bin:$PATH"
                return 0
            elif [ "$major" -gt 2 ]; then
                status_msg "autoconf $version already installed"
                export PATH="$FIN_BIN_DIR/bin:$PATH"
                return 0
            fi
        fi
    fi

    status_msg "Building autoconf 2.71..."
    cd "$BUILD_DIR"

    if [ ! -f "autoconf-2.71.tar.gz" ]; then
        wget -q https://ftp.gnu.org/gnu/autoconf/autoconf-2.71.tar.gz
    fi

    if [ ! -d "autoconf-2.71" ]; then
        tar -xf autoconf-2.71.tar.gz
    fi

    cd autoconf-2.71

    autoconf_config_log="$LOG_DIR/autoconf_configure.log"
    autoconf_build_log="$LOG_DIR/autoconf_build.log"
    autoconf_install_log="$LOG_DIR/autoconf_install.log"

    if [ "$VERBOSE" = "true" ]; then
        ./configure --prefix="$FIN_BIN_DIR"
        make -j$(( $(nproc) - 1 ))
        make install
    else
        if ! ./configure --prefix="$FIN_BIN_DIR" > "$autoconf_config_log" 2>&1; then
            error_msg "✗ autoconf configure failed"
            tail -50 "$autoconf_config_log"
            exit 1
        fi

        if ! make -j$(( $(nproc) - 1 )) > "$autoconf_build_log" 2>&1; then
            error_msg "✗ autoconf build failed"
            tail -50 "$autoconf_build_log"
            exit 1
        fi

        if ! make install > "$autoconf_install_log" 2>&1; then
            error_msg "✗ autoconf install failed"
            tail -50 "$autoconf_install_log"
            exit 1
        fi
    fi

    export PATH="$FIN_BIN_DIR/bin:$PATH"

    echo "✅ autoconf 2.71 built and installed"
    cd "$BUILD_DIR"
}

build_autoconf

# Check if library is already installed
is_library_installed() {
    local lib_name="$1"
    if [ -f "$FIN_BIN_DIR/lib/pkgconfig/$lib_name.pc" ]; then
        return 0
    fi
    # Some libs don't have pc files, check for .a/.so
    if [ -f "$FIN_BIN_DIR/lib/lib${lib_name}.a" ] || [ -f "$FIN_BIN_DIR/lib/lib${lib_name}.so" ]; then
        return 0
    fi
    return 1
}

# Verify library was actually installed
verify_library() {
    local lib_name="$1"
    local package_name="$2"

    if ! is_library_installed "$lib_name"; then
        error_msg "✗ $package_name installation verification failed"
        error_msg "Expected library not found: $lib_name"
        exit 1
    fi
}

# Generic compile function for autoconf-based packages
compile_autoconf_package() {
    local package_name="$1"
    local package_dir="$2"
    local git_url="$3"
    local tar_url="$4"
    local extra_configure_flags="$5"
    local lib_check="$6"
    local use_autogen="${7:-false}"

    if is_library_installed "$lib_check"; then
        status_msg "$package_name already installed - skipping"
        return 0
    fi

    status_msg "Building $package_name"

    cd "$BUILD_DIR"

    # Get source
    if [ ! -d "$package_dir" ]; then
        if [ -n "$git_url" ]; then
            echo "  • Cloning from git..."
            if [ "$VERBOSE" = "true" ]; then
                git clone "$git_url" "$package_dir"
            else
                git clone "$git_url" "$package_dir" | log_output 2>&1
            fi
        elif [ -n "$tar_url" ]; then
            echo "  • Downloading tarball..."
            local tar_file=$(basename "$tar_url")
            if [ ! -f "$tar_file" ]; then
                wget -q "$tar_url"
            fi
            tar -xf "$tar_file"
        else
            error_msg "No source URL provided for $package_name"
            exit 1
        fi
    fi

    cd "$package_dir"

    # Run autogen if needed
    if [ "$use_autogen" = "true" ] && [ -f "./autogen.sh" ]; then
        echo "  • Running autogen..."
        if [ "$VERBOSE" = "true" ]; then
            ./autogen.sh
        else
            ./autogen.sh | log_output 2>&1
        fi
    fi

    # Run autoreconf if no configure script
    if [ ! -f "./configure" ]; then
        echo "  • Running autoreconf..."
        if [ "$VERBOSE" = "true" ]; then
            autoreconf --install
        else
            autoreconf --install | log_output 2>&1
        fi
    fi

    # Configure
    echo "  • Configuring..."
    if [ "$VERBOSE" = "true" ]; then
        ./configure CC=$CC --host=$HOST --build=$BUILD --prefix=$FIN_BIN_DIR $extra_configure_flags
    else
        ./configure CC=$CC --host=$HOST --build=$BUILD --prefix=$FIN_BIN_DIR $extra_configure_flags | log_output 2>&1
    fi

    # Build and install
    echo "  • Building and installing..."
    if [ "$VERBOSE" = "true" ]; then
        make clean && make -j$(( $(nproc) - 1 )) && make install
    else
        make clean | log_output 2>&1 && make -j$(( $(nproc) - 1 )) | log_output 2>&1 && make install | log_output 2>&1
    fi

    if [ $? -ne 0 ]; then
        error_msg "✗ $package_name build failed"
        exit 1
    fi

    verify_library "$lib_check" "$package_name"
    echo "✅ $package_name built and installed"
    cd "$BUILD_DIR"
}

# CMake-based compile function
compile_cmake_package() {
    local package_name="$1"
    local package_dir="$2"
    local git_url="$3"
    local cmake_flags="$4"
    local lib_check="$5"

    if is_library_installed "$lib_check"; then
        status_msg "$package_name already installed - skipping"
        return 0
    fi

    status_msg "Building $package_name"

    cd "$BUILD_DIR"

    if [ ! -d "$package_dir" ]; then
        echo "  • Cloning from git..."
        if [ "$VERBOSE" = "true" ]; then
            git clone "$git_url" "$package_dir"
        else
            git clone "$git_url" "$package_dir" | log_output 2>&1
        fi
    fi

    cd "$package_dir"
    mkdir -p build
    cd build

    echo "  • Configuring with CMake..."
    if [ "$VERBOSE" = "true" ]; then
        cmake .. \
            -DCMAKE_TOOLCHAIN_FILE="$SCRIPT_DIR/cross.cmake" \
            -DCMAKE_INSTALL_PREFIX="$FIN_BIN_DIR" \
            $cmake_flags
    else
        cmake .. \
            -DCMAKE_TOOLCHAIN_FILE="$SCRIPT_DIR/cross.cmake" \
            -DCMAKE_INSTALL_PREFIX="$FIN_BIN_DIR" \
            $cmake_flags | log_output 2>&1
    fi

    echo "  • Building and installing..."
    if [ "$VERBOSE" = "true" ]; then
        make -j$(( $(nproc) - 1 )) && make install
    else
        make -j$(( $(nproc) - 1 )) | log_output 2>&1 && make install | log_output 2>&1
    fi

    if [ $? -ne 0 ]; then
        error_msg "✗ $package_name build failed"
        exit 1
    fi

    verify_library "$lib_check" "$package_name"
    echo "✅ $package_name built and installed"
    cd "$BUILD_DIR"
}

status_msg "════════════════════════════════════════════════"
status_msg "LÖVE2D Dependency Build for Miyoo Mini"
status_msg "════════════════════════════════════════════════"

# Step 1: Build SDL2 and extensions
status_msg "Step 1: Building SDL2..."
if [ -f "$SCRIPT_DIR/mksdl2.sh" ]; then
    cd "$SCRIPT_DIR"
    if [ "$VERBOSE" = "true" ]; then
        VERBOSE=true ./mksdl2.sh
    else
        ./mksdl2.sh
    fi
else
    error_msg "mksdl2.sh not found!"
    exit 1
fi

# Step 2: Build Ogg (required by Vorbis and Theora)
compile_autoconf_package \
    "libogg" \
    "libogg-1.3.5" \
    "" \
    "https://downloads.xiph.org/releases/ogg/libogg-1.3.5.tar.xz" \
    "" \
    "ogg"

# Step 3: Build Vorbis
compile_autoconf_package \
    "libvorbis" \
    "libvorbis-1.3.7" \
    "" \
    "https://github.com/xiph/vorbis/releases/download/v1.3.7/libvorbis-1.3.7.tar.xz" \
    "" \
    "vorbis"

# Step 4: Build Theora
compile_autoconf_package \
    "libtheora" \
    "theora" \
    "https://github.com/xiph/theora.git" \
    "" \
    "--disable-examples" \
    "theora" \
    "true"

# Step 5: Build ModPlug
compile_autoconf_package \
    "libmodplug" \
    "libmodplug" \
    "https://github.com/Konstanty/libmodplug.git" \
    "" \
    "" \
    "libmodplug" \
    "false"

# Step 6: Build mpg123
compile_autoconf_package \
    "mpg123" \
    "libmpg123" \
    "https://github.com/gypified/libmpg123.git" \
    "" \
    "" \
    "mpg123" \
    "false"

# Step 7: Build OpenAL-Soft (using v1.19.1 - compatible with GCC 7 and CMake 3.16)
status_msg "Building OpenAL..."
cd "$BUILD_DIR"

if ! is_library_installed "openal"; then
    # Clean up any old/failed attempts
    rm -rf openal-soft openal-soft-openal-soft-1.19.1 openal-soft-1.19.1.tar.* 2>/dev/null

    echo "  • Downloading OpenAL 1.19.1 (compatible with GCC 7)..."
    wget -q -O openal-soft-1.19.1.tar.gz https://github.com/kcat/openal-soft/archive/refs/tags/openal-soft-1.19.1.tar.gz

    if [ $? -ne 0 ] || [ ! -s openal-soft-1.19.1.tar.gz ]; then
        error_msg "✗ Failed to download OpenAL"
        exit 1
    fi

    echo "  • Extracting OpenAL..."
    tar -xzf openal-soft-1.19.1.tar.gz

    # GitHub extracts to openal-soft-openal-soft-1.19.1
    cd openal-soft-openal-soft-1.19.1

    # Build bsincgen as native x86_64 tool first (not cross-compiled)
    echo "  • Building native bsincgen tool..."
    mkdir -p native-build
    cd native-build
    gcc -O2 -o bsincgen ../native-tools/bsincgen.c -lm
    if [ $? -ne 0 ]; then
        error_msg "✗ Failed to build native bsincgen tool"
        exit 1
    fi

    # Generate bsinc_inc.h using native tool
    echo "  • Generating bsinc_inc.h..."
    ./bsincgen bsinc_inc.h
    if [ $? -ne 0 ]; then
        error_msg "✗ Failed to generate bsinc_inc.h"
        exit 1
    fi

    cd ..
    rm -rf build
    mkdir -p build

    # Copy pre-generated bsinc_inc.h to build directory
    cp native-build/bsinc_inc.h build/

    # Disable the ADD_CUSTOM_COMMAND that would try to regenerate it
    sed -i '/ADD_CUSTOM_COMMAND(OUTPUT.*bsinc_inc.h/,/^)$/d' CMakeLists.txt

    cd build
    echo "  • Configuring with CMake (OSS backend)..."
    cmake .. \
        -DCMAKE_TOOLCHAIN_FILE="$SCRIPT_DIR/cross.cmake" \
        -DCMAKE_INSTALL_PREFIX="$FIN_BIN_DIR" \
        -DALSOFT_EXAMPLES=OFF \
        -DALSOFT_TESTS=OFF \
        -DALSOFT_UTILS=OFF \
        -DALSOFT_NO_CONFIG_UTIL=ON \
        -DALSOFT_BACKEND_WAVE=OFF \
        -DALSOFT_BACKEND_OSS=ON \
        -DALSOFT_REQUIRE_OSS=ON \
        -DALSOFT_EMBED_HRTF_DATA=OFF

    if [ $? -ne 0 ]; then
        error_msg "✗ OpenAL CMake configuration failed"
        exit 1
    fi

    echo "  • Building and installing..."
    openal_build_log="$LOG_DIR/openal_build.log"
    openal_install_log="$LOG_DIR/openal_install.log"
    if [ "$VERBOSE" = "true" ]; then
        make -j$(( $(nproc) - 1 )) 2>&1 | tee "$openal_build_log"
        make install 2>&1 | tee "$openal_install_log"
    else
        make -j$(( $(nproc) - 1 )) > "$openal_build_log" 2>&1
        make install > "$openal_install_log" 2>&1
    fi

    if [ $? -ne 0 ]; then
        error_msg "✗ OpenAL build/install failed"
        error_msg "Check $openal_build_log and $openal_install_log"
        exit 1
    fi

    verify_library "openal" "OpenAL"
    echo "✅ OpenAL built and installed"
else
    status_msg "OpenAL already installed - skipping"
fi

cd "$BUILD_DIR"

# Step 8: Build LuaJIT
status_msg "Building LuaJIT..."
cd "$BUILD_DIR"

if ! is_library_installed "luajit"; then
    echo "  • Cloning/updating LuaJIT..."
    if [ ! -d "LuaJIT" ]; then
        git clone --depth 1 https://github.com/LuaJIT/LuaJIT.git
    fi
    cd LuaJIT

    # Clean any previous build artifacts
    git clean -fdx 2>/dev/null || true
    git reset --hard 2>/dev/null || true

    echo "  • Building LuaJIT..."

    # Save and clear flags to prevent ARM flags/libs from affecting host compiler
    SAVED_CFLAGS="$CFLAGS"
    SAVED_LDFLAGS="$LDFLAGS"
    unset CFLAGS
    unset LDFLAGS
    unset CPPFLAGS

    luajit_build_log="$LOG_DIR/luajit_build.log"
    luajit_install_log="$LOG_DIR/luajit_install.log"

    echo "Starting LuaJIT build..." > "$luajit_build_log"

    # Cross-compile from x86_64 host to ARM 32-bit target
    # Per LuaJIT docs: HOST_CC="gcc -m32" for 32-bit target on 64-bit host
    make HOST_CC="gcc -m32" \
         CROSS="$CROSS_COMPILE" \
         TARGET_SYS=Linux \
         TARGET_CFLAGS="$SAVED_CFLAGS" \
         TARGET_LDFLAGS="$SAVED_LDFLAGS" \
         -j$(( $(nproc) - 1 )) >> "$luajit_build_log" 2>&1

    BUILD_STATUS=$?
    if [ $BUILD_STATUS -ne 0 ]; then
        error_msg "✗ LuaJIT build failed (exit code: $BUILD_STATUS)"
        error_msg "Check $luajit_build_log for details"
        tail -50 "$luajit_build_log"
        exit 1
    fi

    make install PREFIX="$FIN_BIN_DIR" > "$luajit_install_log" 2>&1

    INSTALL_STATUS=$?
    if [ $INSTALL_STATUS -ne 0 ]; then
        error_msg "✗ LuaJIT install failed (exit code: $INSTALL_STATUS)"
        error_msg "Check $luajit_install_log for details"
        tail -50 "$luajit_install_log"
        exit 1
    fi

    # Restore flags
    export CFLAGS="$SAVED_CFLAGS"
    export LDFLAGS="$SAVED_LDFLAGS"

    verify_library "luajit" "LuaJIT"
    echo "✅ LuaJIT built and installed"
else
    status_msg "LuaJIT already installed - skipping"
fi

cd "$BUILD_DIR"

# Update cross.cmake with proper paths
status_msg "Updating cross.cmake with library paths..."
cat > "$SCRIPT_DIR/cross.cmake" << 'EOF'
SET(CMAKE_SYSTEM_NAME Linux)
SET(CMAKE_SYSTEM_VERSION 1)

SET(CMAKE_C_COMPILER arm-linux-gnueabihf-gcc)
SET(CMAKE_CXX_COMPILER arm-linux-gnueabihf-g++)

# Toolchain sysroot
SET(CMAKE_FIND_ROOT_PATH /opt/miyoomini-toolchain/usr/arm-linux-gnueabihf/sysroot/usr)
SET(CMAKE_SYSROOT /opt/miyoomini-toolchain/usr/arm-linux-gnueabihf/sysroot)

# Search for programs in the build host directories
SET(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)

# Search for libraries and headers in the target directories
SET(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
SET(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
SET(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)

# Additional paths for dependencies
SET(ENV{PKG_CONFIG_PATH} "/opt/miyoomini-toolchain/usr/arm-linux-gnueabihf/sysroot/usr/lib/pkgconfig")
SET(ENV{PKG_CONFIG_LIBDIR} "/opt/miyoomini-toolchain/usr/arm-linux-gnueabihf/sysroot/usr/lib/pkgconfig")

# Compiler flags
SET(CMAKE_C_FLAGS "-Wno-undef -g3 -O0 -marm -mtune=cortex-a7 -mfpu=neon-vfpv4 -march=armv7ve+simd -mfloat-abi=hard" CACHE STRING "")
SET(CMAKE_CXX_FLAGS "-g3 -O0 -fPIC -pthread" CACHE STRING "")
SET(CMAKE_EXE_LINKER_FLAGS "-L/opt/miyoomini-toolchain/usr/arm-linux-gnueabihf/sysroot/lib -L/opt/miyoomini-toolchain/usr/arm-linux-gnueabihf/sysroot/usr/lib" CACHE STRING "")
EOF

status_msg "cross.cmake updated"

# Step 9: Build LÖVE2D
status_msg "Building LÖVE2D..."
cd "$SCRIPT_DIR"

if [ ! -f "./platform/unix/automagic" ]; then
    error_msg "LÖVE source not found or incomplete!"
    exit 1
fi

if [ ! -f "./configure" ]; then
    echo "  • Generating configure script..."
    # Add sysroot aclocal path for SDL2 m4 macros
    export ACLOCAL_PATH="$FIN_BIN_DIR/share/aclocal${ACLOCAL_PATH:+:$ACLOCAL_PATH}"

    autoreconf_log="$LOG_DIR/love_autoreconf.log"
    if [ "$VERBOSE" = "true" ]; then
        autoreconf -fi
    else
        autoreconf -fi > "$autoreconf_log" 2>&1
    fi

    if [ $? -ne 0 ]; then
        error_msg "✗ autoreconf failed"
        [ -f "$autoreconf_log" ] && tail -50 "$autoreconf_log"
        exit 1
    fi
fi

echo "  • Configuring LÖVE..."

# Point pkg-config to sysroot packages only
export PKG_CONFIG_PATH="$FIN_BIN_DIR/lib/pkgconfig"
export PKG_CONFIG_LIBDIR="$FIN_BIN_DIR/lib/pkgconfig"

configure_cmd=(
    ./configure
    --host=$HOST
    --build=$BUILD
    --prefix="$FIN_BIN_DIR"
    --with-lua=luajit
    CPPFLAGS="-I$FIN_BIN_DIR/include -I$FIN_BIN_DIR/include/freetype2 -I$FIN_BIN_DIR/include/luajit-2.1"
    LDFLAGS="-L$FIN_BIN_DIR/lib"
)

if [ "$VERBOSE" = "true" ]; then
    "${configure_cmd[@]}"
else
    "${configure_cmd[@]}" > "$LOG_DIR/love_configure.log" 2>&1
fi

echo "  • Building LÖVE..."
if [ "$VERBOSE" = "true" ]; then
    make -j$(( $(nproc) - 1 ))
else
    make -j$(( $(nproc) - 1 )) | log_output 2>&1
fi

if [ $? -ne 0 ]; then
    error_msg "✗ LÖVE build failed"
    exit 1
fi

echo "  • Installing LÖVE..."
if [ "$VERBOSE" = "true" ]; then
    make install
else
    make install | log_output 2>&1
fi

if [ $? -ne 0 ]; then
    error_msg "✗ LÖVE install failed"
    exit 1
fi

# Copy binary and required libraries to output directory
copy_love_output() {
    local OUTPUT_DIR="${LOVE_OUTPUT_DIR:-$SCRIPT_DIR/output/love}"
    local LIB_DIR="$OUTPUT_DIR/lib"

    mkdir -p "$OUTPUT_DIR" "$LIB_DIR"

    if [ -f "$FIN_BIN_DIR/bin/love" ]; then
        cp "$FIN_BIN_DIR/bin/love" "$OUTPUT_DIR/"
        status_msg "Binary copied to $OUTPUT_DIR/love"
    else
        error_msg "LÖVE binary not found at $FIN_BIN_DIR/bin/love"
        return 1
    fi

    # Copy all LÖVE dependencies (longest filename version only, excluding SDL2)
    local LIBS=(
        "libogg"
        "libvorbis"
        "libvorbisenc"
        "libvorbisfile"
        "libtheora"
        "libtheoradec"
        "libtheoraenc"
        "libmodplug"
        "libmpg123"
        "libopenal"
        "libluajit-5.1"
    )

    echo "  • Copying required libraries..."
    for lib in "${LIBS[@]}"; do
        # Find the longest versioned .so file (actual file, not symlink)
        local longest=$(find "$FIN_BIN_DIR/lib" -name "${lib}.so.*" -type f 2>/dev/null | sort -V | tail -1)
        if [ -n "$longest" ]; then
            local basename=$(basename "$longest")
            # Extract first version number: libvorbis.so.0.4.9 -> libvorbis.so.0
            local shortname=$(echo "$basename" | sed -E 's/(.+\.so\.[0-9]+).*/\1/')
            cp "$longest" "$LIB_DIR/$shortname"
            echo "    Copied: $basename -> $shortname"
        fi
    done

    status_msg "Libraries copied to $LIB_DIR"
}

copy_love_output

status_msg "════════════════════════════════════════════════"
status_msg "✅ LÖVE2D Build Complete!"
status_msg "════════════════════════════════════════════════"
echo ""
echo "Installation Summary:"
echo "  LÖVE Binary: $FIN_BIN_DIR/bin/love"
echo "  Output Copy: ${LOVE_OUTPUT_DIR:-$SCRIPT_DIR/output/love}/love"
echo "  Libraries: ${LOVE_OUTPUT_DIR:-$SCRIPT_DIR/output/love}/lib/"
echo "  Sysroot libs: $FIN_BIN_DIR/lib/"
echo "  Headers: $FIN_BIN_DIR/include/"
echo ""
echo "Test with: $FIN_BIN_DIR/bin/love --version"
