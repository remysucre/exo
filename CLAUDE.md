# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is **exo**, a web browser for the Playdate console. Due to the Playdate's hardware constraints, exo uses a unique "exo web browser" architecture:

- **Curated browsing**: A curated list of supported websites
- **XPath-based content extraction**: For each supported site, custom rules specify which content to display using XPath queries
- **Content filtering philosophy**: Instead of blocking unwanted content, we explicitly specify what to show
- **Pure content**: Text only, no images, links, or JavaScript
- **Simplicity first**: Straightforward implementation, optimize only when needed

## Hardware Constraints

The Playdate console has:
- 400x240 monochrome display
- 16MB RAM
- 4GB storage
- 30 fps default refresh rate (max 50 fps)
- 64 simultaneous file handle limit

## Technology Stack

- **Primary language**: Lua (for UI, navigation, and high-level logic)
- **Performance-critical code**: C with libxml2 (for HTML parsing with XPath support)
- **Why C?**: Pure Lua XML parsers lack XPath support, which is essential for our content extraction design
- **No large dependencies**: Must work within Playdate's constraints

## Build System

### Prerequisites
- Playdate SDK installed with `PLAYDATE_SDK_PATH` environment variable set
- C compiler for Simulator builds:
  - macOS: Xcode command line tools
  - Windows: Visual Studio
  - Linux: gcc
- ARM embedded compiler for device builds (included with Playdate SDK)
- libxml2 development libraries

### Project Structure
```
exo/
  source/
    main.lua          # Entry point
    sites.lua         # Site configuration rules
    images/           # UI assets (optional)
    sounds/           # Audio feedback (optional)
  lib/                # C extensions
    htmlparser.c      # libxml2 wrapper for XPath queries
  CMakeLists.txt      # Build configuration
```

### Building

#### C Extension
```bash
mkdir build
cd build
cmake ..
make
```

#### Playdate Bundle
```bash
# Compile to .pdx bundle (includes compiled C library + Lua code)
pdc source exo.pdx

# Run in Simulator
open exo.pdx  # macOS
# OR
PlaydateSimulator exo.pdx
```

## Architecture

### Core Components

1. **Rule Engine** (Lua)
   - Manages the curated list of supported websites in `sites.lua`
   - Stores XPath rules for each site
   - Supports wildcard URL patterns for matching article pages
   - Format: `{ name, pattern, xpath }`

2. **HTTP Client** (Lua)
   - Fetches HTML content from supported websites
   - Loads entire HTML into memory (simple approach)
   - Basic error handling

3. **HTML Parser** (C using libxml2)
   - Parses HTML documents (uses libxml2's HTML parser, not strict XML)
   - Applies XPath union queries to extract content in document order
   - Returns structured list of `{type, content}` tuples to Lua
   - Exposed to Lua via C API bridge

4. **Renderer** (Lua)
   - Takes extracted content and renders to monochrome display
   - Handles text wrapping, scrolling, and basic layout
   - Supports crank and button navigation

### XPath Content Extraction Design

**Key Design Decision**: Use XPath union expressions to extract multiple element types while preserving document order.

#### How It Works

1. **Single XPath Union Query**: Combine multiple element selectors with `|`
   ```xpath
   //article//h1 | //article//h2 | //article//h3 | //article//p
   ```

2. **Document Order Preservation**: XPath union results are guaranteed to be in document order
   - Headers and paragraphs remain interleaved as they appear in the source
   - No manual sorting needed

3. **Type Information from XML Nodes**: libxml2 provides node metadata automatically
   ```c
   xmlNodePtr node = nodes->nodeTab[i];
   const char* tag_name = (const char*)node->name;  // "h1", "h2", "p", etc.
   xmlChar* content = xmlNodeGetContent(node);
   ```

4. **Return Format to Lua**:
   ```lua
   {
     {type = "h1", content = "Article Title"},
     {type = "p", content = "First paragraph..."},
     {type = "h2", content = "Section Header"},
     {type = "p", content = "Second paragraph..."}
   }
   ```

#### Advantages
- Single efficient XPath query
- Automatic document order preservation
- Type information comes from XML node names (built-in)
- Simple C implementation
- Flexible site configuration

### Lua-C Integration

C function exposed to Lua for HTML parsing:
```lua
-- Input: HTML string, XPath query
-- Output: Array of {type, content} tables in document order
-- Returns: result_table on success, or (nil, error_message) on failure
result = parseHTML(html_string, xpath_query)
```

Implementation details:
- Keep C API minimal
- Pass simple data structures between Lua and C (strings, tables)
- Use libxml2's `htmlReadMemory()` for parsing (handles malformed HTML)
- Use `xmlXPathEvalExpression()` for XPath queries
- Error handling returns nil and error message to Lua

## Development Workflow

1. Test in Simulator during development (faster iteration)
2. Use `print()` for debugging (appears in Simulator console)
3. Keep code simple - optimize only when performance issues are observed
4. Test on actual hardware periodically

## Key APIs

### Playdate Lua APIs
- `playdate.graphics.*` - Drawing and display
- `playdate.getCrankChange()` - Crank input for scrolling
- `playdate.buttonIsPressed()` - Button input
- `playdate.datastore.*` - Persistent storage (if needed for bookmarks/history)
- `playdate.file.*` - File operations

### C API Integration
- `pd->lua->*` - Lua runtime interaction from C
- `pd->lua->registerFunction()` - Register C functions callable from Lua
- `pd->lua->pushString()`, `pd->lua->getArgString()` - Pass strings between C and Lua
- Access Playdate APIs from C using the `playdate_api` struct

## Site Configuration Format

Store in `source/sites.lua`:

```lua
sites = {
  {
    name = "CS Monitor Article",
    pattern = "^https://www%.csmonitor%.com/text_edition/.*",
    xpath = "//h1 | //div[contains(@class, 'story-bylines')]//text() | //article//p | //article//h2 | //article//h3"
  },
  {
    name = "CS Monitor Front Page",
    pattern = "^https://www%.csmonitor%.com/text_edition$",
    xpath = "//h2 | //a[contains(@href, 'text_edition')] | //p"
  },
  -- Additional sites...
}
```

### Pattern Matching Rules
- Patterns are Lua string patterns (similar to regex)
- Use `^` and `$` for exact start/end matching
- Use `%.` to escape literal dots
- Use `.*` for wildcard segments
- **Order matters**: More specific patterns should come first in the list
  - Example: Article pattern (`/text_edition/.*`) must come before front page pattern (`/text_edition$`)

### XPath Guidelines
- Use union (`|`) to select multiple element types in one query
- Results will be in document order automatically
- Keep XPath queries focused on content areas (exclude nav, footer, ads)
- Use container-based queries (e.g., `//article//p`) to scope extraction
- Test XPath queries against real HTML before deployment

### Example: CS Monitor Text Edition

**Front page** (https://www.csmonitor.com/text_edition):
- Section headers: `<h2>` tags
- Article links: `<a>` tags with `href` containing "text_edition"
- Summaries: `<p>` tags

**Article pages** (https://www.csmonitor.com/text_edition/*):
- Title: `<h1>` tag
- Byline: Text within `<div class="story-bylines">`
- Content: `<p>`, `<h2>`, `<h3>` tags within `<article>`

## Testing Approach

- Test XPath rules against real HTML in Simulator
- Test scrolling and navigation with crank and buttons
- Test pattern matching with various URLs
- Verify document order preservation in extracted content

## References

- Playdate SDK Lua: https://sdk.play.date/3.0.0/Inside%20Playdate.html
- Playdate SDK C: https://sdk.play.date/3.0.0/Inside%20Playdate%20with%20C.html
- libxml2 XPath: http://xmlsoft.org/html/libxml-xpath.html
- libxml2 HTML Parser: http://xmlsoft.org/html/libxml-HTMLparser.html
