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

VTUI no longer serves as authoritative text storage. The shared banked gap
buffer stores the document independently of the 56-row viewport, with
horizontal panning for long lines. Both frontends detect installed RAM and
reserve banks 0–3: 480 KiB of text capacity on a stock 512 KiB machine, or
2,016 KiB on a fully populated 2 MiB machine. Logical offsets and line numbers
are 32-bit. See [banked RAM](Banked-RAM.md) for exact limits and tests.

VTUI occupies $8800..$8c14 and BSS follows it. The former fixed $6800..$87ff
text arena is gone; document bytes live in banks 4 through the detected last bank.

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
