# exo - A Web Browser for Playdate

exo is a minimalist web browser for the Playdate console that uses a unique "exo web browser" architecture: instead of rendering arbitrary web pages, it uses a curated list of websites with CSS selector-based rules to extract and display only the content you want to see.

## Features

- **Curated browsing**: Only supports websites with defined extraction rules
- **CSS selector content extraction**: Precise control over what content is displayed
- **Pure text display**: No images, links, or JavaScript - just readable content
- **Monochrome optimized**: Designed for Playdate's 400x240 1-bit display
- **Crank & button navigation**: Scroll with the crank or D-pad

## Architecture

exo uses a hybrid Lua/C architecture:
- **Lua**: UI, navigation, HTTP fetching, and rendering
- **C + lexbor**: HTML parsing with CSS selector support

The CSS selector design preserves document order, so headers and paragraphs appear in the same order as the source HTML.

## Building

### Prerequisites

1. **Playdate SDK**: Install from https://play.date/dev/
2. **CMake**: Version 3.14 or higher
3. **C Compiler**:
   - macOS: Xcode command line tools (`xcode-select --install`)
   - Windows: Visual Studio
   - Linux: gcc and standard build tools
4. **Playdate ARM Compiler** (for device builds): Included with Playdate SDK at `/usr/local/playdate/gcc-arm-none-eabi-*`

### Build Steps

**Quick Build (Recommended):**

```bash
# Set Playdate SDK path
export PLAYDATE_SDK_PATH=/path/to/PlaydateSDK

# Build everything (Simulator + Device)
./build.sh all

# OR build just Simulator
./build.sh sim

# OR build just Device
./build.sh device

# Create .pdx bundle
./build.sh pdx
```

**Manual Build:**

```bash
# For Simulator
mkdir build_sim && cd build_sim
cmake ..
make -j
cd ..

# For Device
mkdir build_device && cd build_device
export PATH="/usr/local/playdate/gcc-arm-none-eabi-9-2019-q4-major/bin:$PATH"
cmake -DCMAKE_TOOLCHAIN_FILE=$PLAYDATE_SDK_PATH/C_API/buildsupport/arm.cmake ..
make -j
cd ..

# Create .pdx bundle
pdc source exo.pdx
```

**Run:**
```bash
open exo.pdx  # macOS Simulator
# OR
PlaydateSimulator exo.pdx
```

## Usage

### Current Test Mode

Press the **A button** to load a test CS Monitor article.

Use:
- **Crank**: Scroll smoothly through content
- **D-pad Up/Down**: Scroll by page increments

### Adding Sites

Edit `source/sites.lua` to add support for new websites:

```lua
{
  name = "Site Name",
  pattern = "^https://example%.com/articles/.*",
  selector = "article h1, article h2, article p"
}
```

**Pattern matching rules:**
- Patterns are Lua string patterns (similar to regex)
- Use `^` and `$` for exact matching
- Use `%.` to escape literal dots
- Use `.*` as wildcard
- More specific patterns should come first

**CSS Selector guidelines:**
- Use comma-separated selectors to select multiple element types
- Results automatically preserve document order
- Focus on content areas (e.g., `article p` not just `p`)
- Standard CSS3 selectors are supported
- Test against real HTML before deploying

## Supported Sites

Currently configured:
- **Christian Science Monitor Text Edition**: Front page and articles

## Project Structure

```
exo/
├── source/
│   ├── main.lua       # Entry point and main browser logic
│   ├── sites.lua      # Site configuration rules with CSS selectors
│   ├── pdex.dylib     # Compiled C extension for Simulator (generated)
│   └── pdex.bin       # Compiled C extension for Device (generated)
├── lib/
│   └── htmlparser.c   # C HTML parser using lexbor
├── third_party/
│   └── lexbor/        # HTML/CSS parsing library (git submodule)
├── CMakeLists.txt     # Build configuration
├── build.sh           # Build script
├── CLAUDE.md          # Development documentation
└── README.md          # This file
```

## Development

See `CLAUDE.md` for detailed development documentation, architecture decisions, and API references.

### Testing

1. Test in Simulator first (faster iteration)
2. Use `print()` for debugging (output appears in Simulator console)
3. Test on actual hardware periodically

### Adding Features

Future enhancements could include:
- URL entry UI (keyboard input)
- Bookmark management
- History tracking
- Better error handling and retry logic
- Support for more sites

## License

This project is open source. Feel free to use and modify for your own purposes.

## Cloning the Repository

This project uses git submodules for the lexbor library:

```bash
git clone --recurse-submodules <repository-url>
```

Or if already cloned:
```bash
git submodule update --init --recursive
```

## Resources

- Playdate SDK: https://sdk.play.date/
- lexbor library: https://github.com/lexbor/lexbor
- CSS Selectors: https://www.w3schools.com/cssref/css_selectors.php
