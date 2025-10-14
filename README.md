# exo - A Web Browser for Playdate

exo is a minimalist web browser for the Playdate console that uses a unique "exo web browser" architecture: instead of rendering arbitrary web pages, it uses a curated list of websites with XPath-based rules to extract and display only the content you want to see.

## Features

- **Curated browsing**: Only supports websites with defined extraction rules
- **XPath content extraction**: Precise control over what content is displayed
- **Pure text display**: No images, links, or JavaScript - just readable content
- **Monochrome optimized**: Designed for Playdate's 400x240 1-bit display
- **Crank & button navigation**: Scroll with the crank or D-pad

## Architecture

exo uses a hybrid Lua/C architecture:
- **Lua**: UI, navigation, HTTP fetching, and rendering
- **C + libxml2**: HTML parsing with XPath support

The XPath union query design preserves document order, so headers and paragraphs appear in the same order as the source HTML.

## Building

### Prerequisites

1. **Playdate SDK**: Install from https://play.date/dev/
2. **C Compiler**:
   - macOS: Xcode command line tools (`xcode-select --install`)
   - Windows: Visual Studio
   - Linux: gcc and standard build tools
3. **libxml2**:
   - macOS: Usually pre-installed, or use Homebrew: `brew install libxml2`
   - Windows: Download from http://xmlsoft.org/
   - Linux: `sudo apt-get install libxml2-dev` (Debian/Ubuntu)

### Build Steps

1. Set the Playdate SDK path:
```bash
export PLAYDATE_SDK_PATH=/path/to/PlaydateSDK
```

2. Build the C extension:
```bash
mkdir build
cd build
cmake ..
make
cd ..
```

This compiles the HTML parser and copies `pdex.dylib` (or `.dll`/`.so`) to the `source/` directory.

3. Build the Playdate bundle:
```bash
pdc source exo.pdx
```

4. Run in Simulator:
```bash
open exo.pdx  # macOS
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
  xpath = "//article//h1 | //article//h2 | //article//p"
}
```

**Pattern matching rules:**
- Patterns are Lua string patterns (similar to regex)
- Use `^` and `$` for exact matching
- Use `%.` to escape literal dots
- Use `.*` as wildcard
- More specific patterns should come first

**XPath guidelines:**
- Use union (`|`) to select multiple element types
- Results automatically preserve document order
- Focus on content areas (e.g., `//article//p` not just `//p`)
- Test against real HTML before deploying

## Supported Sites

Currently configured:
- **Christian Science Monitor Text Edition**: Front page and articles

## Project Structure

```
exo/
├── source/
│   ├── main.lua       # Entry point and main browser logic
│   ├── sites.lua      # Site configuration rules
│   └── pdex.dylib     # Compiled C extension (generated)
├── lib/
│   └── htmlparser.c   # C HTML parser using libxml2
├── CMakeLists.txt     # Build configuration
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

## Resources

- Playdate SDK: https://sdk.play.date/
- libxml2 documentation: http://xmlsoft.org/
- XPath tutorial: https://www.w3schools.com/xml/xpath_intro.asp
