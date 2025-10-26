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
if (NOT DEFINED PLAYDATE_DEVICE)
    set(PLAYDATE_DEVICE OFF)
endif()

# Configure lexbor options for minimal embedded build
set(LEXBOR_BUILD_SHARED OFF CACHE BOOL "Don't build shared library")
set(LEXBOR_BUILD_STATIC ON CACHE BOOL "Build static library")
set(LEXBOR_BUILD_EXAMPLES OFF CACHE BOOL "Don't build examples")
set(LEXBOR_BUILD_TESTS OFF CACHE BOOL "Don't build tests")
set(LEXBOR_BUILD_UTILS OFF CACHE BOOL "Don't build utils")
set(LEXBOR_INSTALL_HEADERS OFF CACHE BOOL "Don't install headers")
set(LEXBOR_WITHOUT_THREADS ON CACHE BOOL "Build without threads")

# Add lexbor as subdirectory
add_subdirectory(third_party/lexbor)

# Platform-specific settings
if (PLAYDATE_DEVICE)
    # Building for Playdate device (ARM)
    set(TARGET_NAME pdex.bin)
    set(CMAKE_C_COMPILER "${PLAYDATE_SDK_PATH}/bin/arm-none-eabi-gcc")
    set(CMAKE_CXX_COMPILER "${PLAYDATE_SDK_PATH}/bin/arm-none-eabi-g++")
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

# Create the library
add_library(${PROJECT_NAME} SHARED
    lib/htmlparser.c
)

# Compile definitions required by Playdate SDK
if (PLAYDATE_DEVICE)
    target_compile_definitions(${PROJECT_NAME} PRIVATE
        TARGET_EXTENSION=1
        TARGET_PLAYDATE=1
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

# Link libraries
target_link_libraries(${PROJECT_NAME}
    lexbor_static
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

# Copy to source directory after build
if (PLAYDATE_DEVICE)
    add_custom_command(TARGET ${PROJECT_NAME} POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy
        $<TARGET_FILE:${PROJECT_NAME}>
        ${CMAKE_SOURCE_DIR}/source/pdex.bin
    )
else()
    add_custom_command(TARGET ${PROJECT_NAME} POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy
        $<TARGET_FILE:${PROJECT_NAME}>
        ${CMAKE_SOURCE_DIR}/source/pdex${CMAKE_SHARED_LIBRARY_SUFFIX}
    )
endif()
