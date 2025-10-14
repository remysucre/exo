cmake_minimum_required(VERSION 3.14)
project(exo)

set(CMAKE_C_STANDARD 11)

# Set the Playdate SDK path
if (NOT DEFINED ENV{PLAYDATE_SDK_PATH})
    message(FATAL_ERROR "PLAYDATE_SDK_PATH environment variable not set")
endif()

set(PLAYDATE_SDK_PATH $ENV{PLAYDATE_SDK_PATH})
set(PD_C_API "${PLAYDATE_SDK_PATH}/C_API")

# Find libxml2
find_package(LibXml2 REQUIRED)

# Platform-specific settings
if (APPLE)
    set(TARGET_NAME pdex.dylib)
    set(CMAKE_OSX_ARCHITECTURES "arm64;x86_64")
elseif (WIN32)
    set(TARGET_NAME pdex.dll)
else()
    set(TARGET_NAME pdex.so)
endif()

# Create the library
add_library(${PROJECT_NAME} SHARED
    lib/htmlparser.c
)

# Compile definitions required by Playdate SDK
target_compile_definitions(${PROJECT_NAME} PRIVATE
    TARGET_EXTENSION=1
    TARGET_SIMULATOR=1
)

# Include directories
target_include_directories(${PROJECT_NAME} PRIVATE
    ${PD_C_API}
    ${LIBXML2_INCLUDE_DIR}
)

# Link libraries
target_link_libraries(${PROJECT_NAME}
    ${LIBXML2_LIBRARIES}
)

# Output settings
set_target_properties(${PROJECT_NAME} PROPERTIES
    OUTPUT_NAME pdex
    PREFIX ""
    SUFFIX ""
)

# Set the output extension based on platform
if (APPLE)
    set_target_properties(${PROJECT_NAME} PROPERTIES SUFFIX ".dylib")
elseif (WIN32)
    set_target_properties(${PROJECT_NAME} PROPERTIES SUFFIX ".dll")
else()
    set_target_properties(${PROJECT_NAME} PROPERTIES SUFFIX ".so")
endif()

# Copy to source directory after build
add_custom_command(TARGET ${PROJECT_NAME} POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy
    $<TARGET_FILE:${PROJECT_NAME}>
    ${CMAKE_SOURCE_DIR}/source/pdex${CMAKE_SHARED_LIBRARY_SUFFIX}
)
