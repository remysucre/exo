cmake_minimum_required(VERSION 3.14)
project(exo)

set(CMAKE_C_STANDARD 11)

# Set the Playdate SDK path
if (NOT DEFINED ENV{PLAYDATE_SDK_PATH})
    message(FATAL_ERROR "PLAYDATE_SDK_PATH environment variable not set")
endif()

set(PLAYDATE_SDK_PATH $ENV{PLAYDATE_SDK_PATH})
set(PD_C_API "${PLAYDATE_SDK_PATH}/C_API")

# Detect build target (Simulator or Device)
# When using arm.cmake toolchain, CMAKE_SYSTEM_PROCESSOR will be "ARM"
if (CMAKE_SYSTEM_PROCESSOR STREQUAL "ARM")
    set(PLAYDATE_DEVICE ON)
    message(STATUS "Building for Playdate Device (ARM)")
else()
    set(PLAYDATE_DEVICE OFF)
    message(STATUS "Building for Playdate Simulator")
endif()

# Collect all lexbor source files directly (don't build as separate library)
file(GLOB_RECURSE LEXBOR_SOURCES
    ${CMAKE_CURRENT_SOURCE_DIR}/third_party/lexbor/source/lexbor/*.c
)

# Exclude Windows-specific port files (we use POSIX on macOS/Linux/embedded)
list(FILTER LEXBOR_SOURCES EXCLUDE REGEX ".*/ports/windows_nt/.*")

# Platform-specific settings
if (PLAYDATE_DEVICE)
    # Building for Playdate device (ARM)
    # Compiler is set by arm.cmake toolchain file
    set(TARGET_NAME pdex.bin)
elseif (APPLE)
    # Building for Simulator on macOS
    set(TARGET_NAME pdex.dylib)
    set(CMAKE_OSX_ARCHITECTURES "arm64;x86_64")
elseif (WIN32)
    # Building for Simulator on Windows
    set(TARGET_NAME pdex.dll)
else()
    # Building for Simulator on Linux
    set(TARGET_NAME pdex.so)
endif()

# Create the library with all sources compiled together
# Device builds create an OBJECT library (collection of .o files), Simulator uses SHARED
if (PLAYDATE_DEVICE)
    add_library(${PROJECT_NAME} OBJECT
        ${PLAYDATE_SDK_PATH}/C_API/buildsupport/setup.c
        lib/htmlparser.c
        ${LEXBOR_SOURCES}
    )
else()
    add_library(${PROJECT_NAME} SHARED
        lib/htmlparser.c
        ${LEXBOR_SOURCES}
    )
endif()

# Compile definitions required by Playdate SDK
if (PLAYDATE_DEVICE)
    target_compile_definitions(${PROJECT_NAME} PRIVATE
        TARGET_EXTENSION=1
        TARGET_PLAYDATE=1
        __FPU_USED=1
    )
    target_compile_options(${PROJECT_NAME} PRIVATE
        -mfpu=fpv5-sp-d16
    )
else()
    target_compile_definitions(${PROJECT_NAME} PRIVATE
        TARGET_EXTENSION=1
        TARGET_SIMULATOR=1
    )
endif()

# Include directories
target_include_directories(${PROJECT_NAME} PRIVATE
    ${PD_C_API}
    ${CMAKE_CURRENT_SOURCE_DIR}/third_party/lexbor/source
)

# Output settings
set_target_properties(${PROJECT_NAME} PROPERTIES
    OUTPUT_NAME pdex
    PREFIX ""
    SUFFIX ""
)

# Set the output extension based on platform
if (PLAYDATE_DEVICE)
    set_target_properties(${PROJECT_NAME} PROPERTIES SUFFIX ".bin")
elseif (APPLE)
    set_target_properties(${PROJECT_NAME} PROPERTIES SUFFIX ".dylib")
elseif (WIN32)
    set_target_properties(${PROJECT_NAME} PROPERTIES SUFFIX ".dll")
else()
    set_target_properties(${PROJECT_NAME} PROPERTIES SUFFIX ".so")
endif()

# Post-build: link object files and copy to source directory
if (PLAYDATE_DEVICE)
    # Create custom target to link all object files into a single relocatable binary
    # Use a response file to handle the long list of object files
    add_custom_target(pdex_bin ALL
        DEPENDS ${PROJECT_NAME}
        COMMAND ${CMAKE_COMMAND} -E echo "$<TARGET_OBJECTS:${PROJECT_NAME}>" > ${CMAKE_BINARY_DIR}/objects.txt
        COMMAND ${CMAKE_C_COMPILER} -nostartfiles -mthumb -mcpu=cortex-m7
                -mfloat-abi=hard -mfpu=fpv5-sp-d16 -D__FPU_USED=1
                -Wl,--cref,--gc-sections,--no-warn-mismatch,--emit-relocs
                -Wl,-T${PLAYDATE_SDK_PATH}/C_API/buildsupport/link_map.ld
                -o ${CMAKE_BINARY_DIR}/pdex.elf
                @${CMAKE_BINARY_DIR}/objects.txt
                -lm
        COMMAND ${CMAKE_COMMAND} -E copy ${CMAKE_BINARY_DIR}/pdex.elf ${CMAKE_SOURCE_DIR}/source/pdex.elf
        COMMENT "Linking device binary"
        COMMAND_EXPAND_LISTS
    )
else()
    add_custom_command(TARGET ${PROJECT_NAME} POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy
        $<TARGET_FILE:${PROJECT_NAME}>
        ${CMAKE_SOURCE_DIR}/source/pdex${CMAKE_SHARED_LIBRARY_SUFFIX}
    )
endif()
