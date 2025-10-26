#!/bin/bash
# Build script for exo - Playdate web browser

set -e  # Exit on error

# Check for PLAYDATE_SDK_PATH
if [ -z "$PLAYDATE_SDK_PATH" ]; then
    echo "Error: PLAYDATE_SDK_PATH environment variable not set"
    exit 1
fi

# Parse command line arguments
TARGET="${1:-all}"

build_simulator() {
    echo "Building for Simulator..."
    mkdir -p build_sim
    cd build_sim
    cmake ..
    make -j$(sysctl -n hw.ncpu)
    cd ..
    echo "✓ Simulator build complete: source/pdex.dylib"
}

build_device() {
    echo "Building for Device..."
    mkdir -p build_device
    cd build_device

    # Ensure SDK's ARM compiler is found first
    export PATH="/usr/local/playdate/gcc-arm-none-eabi-9-2019-q4-major/bin:$PATH"

    cmake -DCMAKE_TOOLCHAIN_FILE=$PLAYDATE_SDK_PATH/C_API/buildsupport/arm.cmake ..
    make -j$(sysctl -n hw.ncpu)
    cd ..
    echo "✓ Device build complete: source/pdex.elf"
}

build_pdx() {
    echo "Creating .pdx bundle..."
    $PLAYDATE_SDK_PATH/bin/pdc source exo.pdx
    echo "Bundle created: exo.pdx"
}

clean() {
    echo "Cleaning build directories..."
    rm -rf build_sim build_device exo.pdx
    rm -f source/pdex.{dylib,elf,so,dll}
    echo "Clean complete"
}

case "$TARGET" in
    sim|simulator)
        build_simulator
        ;;
    device)
        build_device
        ;;
    pdx)
        build_simulator
        build_pdx
        ;;
    all)
        build_simulator
        build_device
        ;;
    clean)
        clean
        ;;
    *)
        echo "Usage: $0 {sim|device|pdx|all|clean}"
        echo "  sim       - Build for Simulator only"
        echo "  device    - Build for Device only"
        echo "  pdx       - Build Simulator and create .pdx bundle"
        echo "  all       - Build for both Simulator and Device (default)"
        echo "  clean     - Remove all build artifacts"
        exit 1
        ;;
esac

echo "Build script complete!"
