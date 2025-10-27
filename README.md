# exo - A Web Browser for Playdate

exo is a minimalist web browser for the Playdate console that uses a unique "exo web browser" architecture: instead of rendering arbitrary web pages, it uses a curated list of websites with CSS selector-based rules to extract and display only the content you want to see.

## Features

- **Curated browsing**: Only supports websites with defined extraction rules
- **CSS selector content extraction**: Precise control over what content is displayed
- **Pure text display**: No images, links, or JavaScript - just readable content
- **Monochrome optimized**: Designed for Playdate's 400x240 1-bit display
- **Crank & button navigation**: Scroll with the crank or D-pad
- **Pure Lua**: Easy to debug and modify, no compilation needed

## Architecture

exo is written entirely in Lua:
- **UI & Rendering**: Playdate graphics API for monochrome display
- **HTML Parsing**: lua-htmlparser (https://github.com/msva/lua-htmlparser)
- **CSS Selectors**: Simple selector engine supporting tags, descendants, and multiple selectors
- **HTTP Fetching**: Playdate's async networking API

The CSS selector design preserves document order, so headers and paragraphs appear in the same order as the source HTML.

## Building

### Prerequisites

1. **Playdate SDK**: Install from https://play.date/dev/
2. Set `PLAYDATE_SDK_PATH` environment variable

### Build Steps

```bash
# Set Playdate SDK path
export PLAYDATE_SDK_PATH=/path/to/PlaydateSDK

# Create .pdx bundle
pdc source exo.pdx

# Run in Simulator
open exo.pdx  # macOS
# OR
PlaydateSimulator exo.pdx
```

That's it! No compilation, no build tools required - just pure Lua.

## Usage

### Current Test Mode

- Press **B button** to test with local HTML
- Press **A button** to try fetching from remy.wang

Controls:
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
- **Basic selectors**: `h1`, `.class`, `#id`, `[attribute]`
- **Multiple selectors**: `h1, h2, p` (comma-separated)
- **Combinators**: `article p` (descendant), `div > p` (child)
- **Pseudo-classes**: `:not(selector)`
- **Attribute matching**: `[href^='https']`, `[class*='article']`
- Full jQuery-style selector support via lua-htmlparser
- Results automatically preserve document order

## Supported Sites

Currently configured:
- **Example.com**: Generic test site
- **Christian Science Monitor Text Edition**: Front page and articles (requires network access)

## Project Structure

```
exo/
├── source/
│   ├── main.lua           # Entry point and main browser logic
│   ├── sites.lua          # Site configuration rules
│   ├── htmlparser.lua     # HTML parser (lua-htmlparser)
│   ├── ElementNode.lua    # DOM node implementation
│   ├── voidelements.lua   # HTML void elements list
│   └── pdxinfo            # Playdate metadata
├── CLAUDE.md              # Development documentation
└── README.md              # This file
```

## Development

### Testing

1. Test in Simulator first (faster iteration)
2. Use `print()` for debugging (output appears in Simulator console)
3. Edit Lua files directly - just rebuild with `pdc source exo.pdx`
4. Test on actual hardware periodically

### Debugging

The Simulator console shows:
- Print statements from your code
- Network activity (requests, headers, data received)
- Errors and stack traces

### Adding Features

Future enhancements could include:
- URL entry UI (keyboard input)
- Bookmark management
- History tracking
- Better error handling and retry logic
- Support for more sites (full jQuery-style selectors already supported!)

## Technology

- **Pure Lua**: All code in Lua for easy debugging
- **lua-htmlparser**: Pure Lua HTML parser
- **Playdate SDK**: Graphics, input, and networking APIs
- **No compilation**: Edit and reload instantly

## License

This project is open source. Feel free to use and modify for your own purposes.

## Resources

- Playdate SDK: https://sdk.play.date/
- lua-htmlparser: https://github.com/msva/lua-htmlparser
- CSS Selectors: https://www.w3schools.com/cssref/css_selectors.php
