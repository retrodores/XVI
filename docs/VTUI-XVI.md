# Original VTUI/PETSCII XVI

## Preserved source
- `attic/xvi.p8`: original editor with inline VTUI bindings.
- `attic/vtui.p8`: separate VTUI bindings.
- `attic/VTUI-C1C7.BIN` and `attic/VTUI1.0.BIN`: library binaries.
- Before the attic move (`9e19f18`), source history contains it at `src/xvi.p8`.

The original loads lines directly onto the screen. Saving scans visible cells with `vtui.scan_char()`, converts screen codes through `scr2pet()`, and writes CR after each row. Rectangle operations implement copy/paste and row movement. The screen is effectively the document store.

## Revival alongside XVI2
Yes: preserve it as a separate X16 PETSCII/VTUI program alongside XVI2's ISO/ASCII editor. A gap buffer can store PETSCII bytes, but the integration needs these steps:

1. Restore an independent VTUI baseline and build target. Update obsolete Prog8 imports/APIs and validate binary entry points with the selected VTUI binary and ROM.
2. Reserve VTUI's fixed `$8800` region. Do not simply reuse XVI2's program-end-to-`$9f00` text allocation: it can overlap the embedded library.
3. Make the raw-byte gap store the document of record. Render a viewport from it; stop reconstructing the saved document by scanning the screen.
4. Add a PETSCII document layer. XVI2's `doctext.clean()` is unsuitable unchanged because it replaces non-ASCII bytes with spaces.
5. Define graphics, character-set case, reverse-video and CR handling explicitly. Route edits, load/save, yank/paste and scrolling through that layer.
6. Add byte-round-trip and rendered-screen tests on X16, including high-bit/graphics bytes, long lines, gap boundaries and scrolling.

Preserving raw PETSCII text bytes is a sensible first scope. Arbitrary embedded color/control sequences need an explicit policy: displayed glyphs and color attributes are different things, and a gap buffer alone does not solve that representation.

This is a source-based feasibility assessment. The archived editor has not been revalidated against BETA3/r49, and this change does not add a restored executable or build target.

For cross-platform vi development, see [p8vi](https://github.com/retrodores/p8vi). XVI/XVI2 in this repository focus on Commander X16.
