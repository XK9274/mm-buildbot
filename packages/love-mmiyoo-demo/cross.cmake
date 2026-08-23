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
