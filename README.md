# Exo Web Browser for the Playdate Console

To build, run `pdc source exo`.

Use the crank to move the cursor (left edge of screen), then click A to follow links and B to go back.

## What is An Exo Web Browser?

An exo web browser is designed for constrained devices.
The [playdate console](https://play.date) is an example:
 not only does the device have limited CPU, RAM, and storage,
 control is also limited to a D-pad, two buttons, and a crank,
 and the display is tiny and monochrome.
As such, `exo` does not support arbitrary HTML pages.
Instead, it relies on custom code to parse a curated
 list of websites and transform them into
 a structure that is easy to render.
Think ad blockers, but instead of specifying what to block,
 the custom code specifies what to show.
[`source/siteparsers.lua`](source/siteparsers.lua) has some examples.

## Design Philosophy
Simplicity is the guiding principle for many of `exo`'s design choices:
- This is a pure Lua codebase with zero dependencies
- There are no inline links, only plain text paragraphs and standalone links
- Scrolling is solely controlled by the crank
- Rendering follows [immediate mode](https://en.wikipedia.org/wiki/Immediate_mode_(computer_graphics)) with little optimization

The main motivation is to make the code hard to break and easy to maintain.
To keep things as simple as possible, we are willing to sacrifice performance and features.
For example, immediate mode rendering constantly redraws the screen,
 but it greatly simplifies rendering logic.
For another example, the D-pad could also be used for scrolling,
 but we chose the crank as the only way to move the cursor.
The rule of thumb is: we will avoid features and optimizations as long as
 `exo` can be used without them.

## Acknowledgement
`exo` uses [lua-htmlparser](https://github.com/msva/lua-htmlparser/tree/master) for parsing HTML,
 and the Asheville font developed by Panic for Playdate,
 with the `Asheville-Sans-14-Bolder` variant stolen from [Constellation Browser](https://particlestudios.itch.io/constellation-browser).

`exo` takes inspiration from the following work:
- [Constellation Browser](https://particlestudios.itch.io/constellation-browser)
- [Hopper](https://tkers.itch.io/hopper)
- [gemtext](https://geminiprotocol.net/docs/gemtext-specification.gmi)
- [A Plea for Lean Software](https://cr.yp.to/bib/1995/wirth.pdf)

The name `exo` comes from the concept of [exocompilation](https://dl.acm.org/doi/10.1145/3519939.3523446),
 a compiler technique to generate efficient code with a little help from the programmer.