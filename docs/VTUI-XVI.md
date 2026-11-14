# XVI: PETSCII / VTUI editor for Commander X16

The original is preserved in `attic/xvi.p8`, its separate binding in
`attic/vtui.p8`, and its library binaries alongside them. Source history before
the attic move (`9e19f18`) has it at `src/xvi.p8`.

## Restored build

`src/xvi.p8` is now the modern PETSCII/VTUI entrypoint. It imports XVI2's
gap-buffer command engine and selects `src/vtui/` frontend modules. This revives
the original's VTUI/PETSCII purpose without duplicating the editing engine.
The archived screen-as-document implementation remains available for reference.

Build from the repository root:

```sh
make vtui JAR=/absolute/path/prog8c-14.0-BETA3-all.jar
# equivalent:
make build XVI_EDITOR=xvi JAR=/absolute/path/prog8c-14.0-BETA3-all.jar
```

Output is `xvi.prg`; XVI2 remains `xvi2.prg`. Both target X16. The binary is
embedded in the PRG, so no external VTUI install is needed.

## Full document in RAM

VTUI no longer serves as authoritative text storage. An 8 KiB contiguous gap
buffer at $6800..$87ff stores the document; the display is a 56-row viewport,
with horizontal panning for long lines. Capacity is bytes, not screen rows:
thousands of short lines can fit, while a few long lines consume the same space.
The native test saves and reloads 202 lines, including off-screen yank/paste.

The arena is a finite 8 KiB, not the X16's entire banked RAM. Expanding it to
banked storage is future work. VTUI occupies $8800..$8c14 and BSS follows it.

## PETSCII behavior

- Editing retains printable PETSCII, including high-bit graphics and case bytes.
- Document separators are CR; CRLF and LF input normalize to CR.
- Other file bytes, including control bytes, survive load/save.
- Control bytes display as spaces rather than changing colors/modes.
- Saving writes the document, never a scan of visible VRAM.
- Commands use the shared XVI2 dispatcher; they are not restricted to the
  legacy screen editor's older command subset.
- UI/save-and-quit limitations of the shared engine still apply.

[VTUI binary interface](VTUI-INTERFACE.md) documents every binding and the binary
hash. Its modern wrapper replaces the old private compiler strlen dependency.
The active binary adds a reproducible 73-byte charset patch: the archived converter did not support high-bit PETSCII. See `tools/rebuild_vtui.py`; the original binary stays intact in the attic.

For cross-platform vi development, use [p8vi](https://github.com/retrodores/p8vi).
