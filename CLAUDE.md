# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is **exo**, a web browser for the Playdate console. Due to the Playdate's hardware constraints, exo uses a unique "exo web browser" architecture:

- **Curated browsing**: A curated list of supported websites
- **CSS selector-based content extraction**: For each supported site, custom rules specify which content to display using CSS selectors
- **Content filtering philosophy**: Instead of blocking unwanted content, we explicitly specify what to show
- **Pure content**: Text only, no images, links, or JavaScript
- **Simplicity first**: Straightforward implementation, optimize only when needed
- **Pure Lua**: All code written in Lua for easy debugging and portability

## Hardware Constraints

The Playdate console has:
- 400x240 monochrome display
- 16MB RAM
- 4GB storage
- 30 fps default refresh rate (max 50 fps)
- 64 simultaneous file handle limit

## Technology Stack

- **Pure Lua**: All code written in Lua (UI, navigation, HTML parsing, rendering)
- **lua-htmlparser**: Pure Lua HTML parser (https://github.com/msva/lua-htmlparser)
- **No compilation**: Edit Lua files and rebuild .pdx instantly with `pdc`
- **No large dependencies**: Must work within Playdate's constraints

## Build System

### Prerequisites
- Playdate SDK installed with `PLAYDATE_SDK_PATH` environment variable set
- That's it! No compilers, no build tools required

### Project Structure
```
exo/
  source/
    main.lua           # Entry point, rendering, networking
    sites.lua          # Site configuration rules
    htmlparser.lua     # HTML parser (lua-htmlparser)
    ElementNode.lua    # DOM node implementation
    voidelements.lua   # HTML void elements list
    pdxinfo            # Playdate metadata
  CLAUDE.md            # This file
  README.md            # User documentation
```

### Building

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

## Architecture

### Core Components

1. **Rule Engine** (Lua)
   - Manages the curated list of supported websites in `sites.lua`
   - Stores CSS selector rules for each site
   - Supports wildcard URL patterns for matching article pages
   - Format: `{ name, pattern, selector }`

2. **HTTP Client** (Lua)
   - Fetches HTML content from supported websites using Playdate's async networking API
   - Loads entire HTML into memory (simple approach)
   - Callbacks for headers, data, completion, and errors

3. **HTML Parser** (Lua using lua-htmlparser)
   - Parses HTML documents (handles malformed HTML gracefully)
   - Applies CSS selectors to extract content in document order
   - Returns list of `{type, content}` tables to rendering code
   - Pure Lua implementation - easy to debug

4. **CSS Selector Engine** (Lua)
   - Uses lua-htmlparser's built-in `select()` method
   - Full jQuery-style selector support (see CSS Selector Guidelines section)
   - Supports classes, IDs, attributes, combinators, pseudo-classes
   - Preserves document order automatically

5. **Renderer** (Lua)
   - Takes extracted content and renders to monochrome display
   - Handles text wrapping, scrolling, and basic layout
   - Supports crank and button navigation
   - Different font styles for h1, h2, h3, and p tags

### CSS Selector Content Extraction Design

**Key Design Decision**: Use CSS selectors instead of XPath for simplicity and Lua compatibility.

#### How It Works

1. **Parse HTML**: Use lua-htmlparser to build DOM tree
   ```lua
   local root = htmlparser.parse(html)
   ```

2. **Iterate Over Selectors**: Loop through selector array
   ```lua
   for _, selector in ipairs(selectors) do
       -- Apply each selector
   end
   ```

3. **Apply Each Selector**: Use library's select() method
   ```lua
   -- Library handles all selector complexity
   local elements = root:select(selector)

   for _, element in ipairs(elements) do
       local text = element:getcontent()
       -- Add to results
   end
   ```

4. **Return Format**:
   ```lua
   {
     {type = "h1", content = "Article Title"},
     {type = "p", content = "First paragraph..."},
     {type = "h2", content = "Section Header"},
     {type = "p", content = "Second paragraph..."}
   }
   ```

#### Advantages
- Pure Lua - easy to debug with print()
- No compilation required
- Simple to understand and modify
- Selectors passed as arrays - no string parsing needed
- Document order preserved naturally
- Works identically on Simulator and Device

### Lua parseHTML Function

Function signature in `main.lua`:
```lua
-- Input: HTML string, array of CSS selectors
-- Output: Array of {type, content} tables
-- Returns: results_table on success, or (nil, error_message) on failure
local content, err = parseHTML(html_string, {"h1", "h2", "p"})
```

Implementation details:
- Parse HTML with lua-htmlparser
- Use library's built-in `select()` method for each selector
- Return results as Lua table (no JSON encoding needed)
- Simple error handling

## Development Workflow

1. Edit Lua files in `source/` directory
2. Rebuild with `pdc source exo.pdx` (instant - no compilation)
3. Test in Simulator with `open exo.pdx`
4. Use `print()` for debugging (appears in Simulator console)
5. Test on actual hardware periodically

## Key APIs

### Playdate Lua APIs
- `playdate.graphics.*` - Drawing and display
- `playdate.getCrankChange()` - Crank input for scrolling
- `playdate.buttonIsPressed()` - Button input
- `playdate.network.*` - HTTP networking (async)
- `playdate.datastore.*` - Persistent storage (for bookmarks/history)

### lua-htmlparser API
- `htmlparser.parse(html_string)` - Parse HTML, returns root node
- `node.name` - Tag name (e.g., "h1", "p")
- `node:getcontent()` - Get text content of node
- `node.nodes` - Array of child nodes
- `node.attributes` - Table of attributes

## Site Configuration Format

Store in `source/sites.lua`:

```lua
sites = {
  {
    name = "Example Site",
    pattern = "^https://example%.com/.*",
    selector = {"h1", "h2", "p"}
  },
  {
    name = "Blog Article",
    pattern = "^https://blog%.example%.com/posts/.*",
    selector = {"article h1", "article h2", "article p"}
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

### CSS Selector Guidelines

The library supports a rich subset of jQuery selectors:

**Basic selectors:**
- `element` - elements with tag name (e.g., `h1`, `p`, `div`)
- `#id` - elements with specific id
- `.class` - elements with specific class
- `*` - all elements

**Attribute selectors:**
- `[attribute]` - has attribute
- `[attribute='value']` - attribute equals value
- `[attribute!='value']` - attribute not equals value
- `[attribute^='value']` - attribute starts with value
- `[attribute$='value']` - attribute ends with value
- `[attribute*='value']` - attribute contains value
- `[attribute~='value']` - attribute contains word value
- `[attribute|='value']` - attribute starts with value or value-

**Combinators:**
- `ancestor descendant` - descendant of ancestor
- `parent > child` - direct child of parent
- `:not(selector)` - elements not matching selector

**Array of selectors:**
- Each selector in the array is evaluated independently
- Results from all selectors are combined in document order

**Complex examples:**
- `article.blog-post > h1` - h1 that is direct child of article with class blog-post
- `.content p:not(.caption)` - paragraphs in .content but not with class caption
- `div[data-type='article'] h2` - h2 inside divs with data-type attribute

Test selectors against real HTML before deployment. Results preserve document order.

### Example: Generic Test Site

```lua
{
  name = "Example.com",
  pattern = "^https?://example%.com.*",
  selector = {"h1", "h2", "p"}
}
```

This will extract:
- All `<h1>` tags
- All `<h2>` tags
- All `<p>` tags
- In document order

## Testing Approach

- Test network fetching with A button (loads remy.wang)
- Use `print()` statements liberally for debugging
- Check Simulator console for debug output
- Test scrolling and navigation with crank and buttons
- Verify document order preservation in extracted content
- Test CSS selectors against real HTML before deployment

## Debugging

The Playdate Simulator console shows:
- All `print()` output from Lua code
- Network activity (GET requests, headers, response status)
- Data received callbacks with byte counts
- Error messages and stack traces
- Very helpful for debugging!

## Future Enhancements

Potential improvements:
- **Advanced selectors**: Support for classes (`.class`), IDs (`#id`), attributes (`[attr]`)
- **URL input**: Keyboard UI for entering arbitrary URLs
- **Bookmarks**: Save favorite sites
- **History**: Track visited pages
- **Better error handling**: Retry logic, timeouts
- **More sites**: Expand curated list

## References

- Playdate SDK Lua: https://sdk.play.date/Inside%20Playdate.html
- lua-htmlparser: https://github.com/msva/lua-htmlparser
- CSS Selectors: https://www.w3schools.com/cssref/css_selectors.php
- Lua Patterns: https://www.lua.org/pil/20.2.html
