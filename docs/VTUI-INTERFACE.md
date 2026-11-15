# Maintained VTUI binary interface

The active file is `src/vtui/VTUI.BIN`, derived reproducibly from the archived
`VTUI-C1C7.BIN`. This is the project's maintained variant, not a claim that it
matches upstream VTUI master. Keep the archive intact when changing the active
binary. The 73-byte charset extension has maintained assembly source; the rest remains the preserved binary.

## Binary layout and initialization

- File size: 1,047 bytes: two dummy load-address bytes followed by 1,045 payload bytes.
- The modern Prog8 binding uses `%asmbinary "src/vtui/VTUI.BIN", 2` at `$8800`.
- Payload occupies `$8800..$8c14`, including the project charset extension.
- `initialize()` is a relocation initializer. Call exactly once after each fresh
  load. Do not call it repeatedly against an already-relocated image.
- The payload begins with a BRA over its jump table. The initializer establishes
  zero-page pointers in `$02..$06` and relocates the table/binary.
- Document bytes live in detected banked RAM, outside main-RAM code/BSS.
  Compiler-managed BSS follows the binary. Code, binary and BSS must remain
  disjoint as the program grows. See [banked RAM](Banked-RAM.md).
- The full PRG embeds the binary. There is no external VTUI file to install.

The original stale binding comment said $1000, but its block and entrypoints
were actually $8800. The active binding documents the real address.

## Entry points

These declarations use current Prog8 `extsub` syntax (the modern replacement
for historical ROM-subroutine binding terminology). Registers below are the
calling convention from the preserved binary interface. Addresses are tied to
the bundled variant; changing the jump table requires changing these binds.

| Address | Prog8 declaration |
|---|---|
| `$8800` | `extsub $8800 = initialize() clobbers(A, X, Y)` |
| `$8802` | `extsub $8802 = screen_set(ubyte mode @A) clobbers(A, X, Y)` |
| `$8805` | `extsub $8805 = set_bank(bool bank1 @Pc) clobbers(A)` |
| `$8808` | `extsub $8808 = set_stride(ubyte stride @A) clobbers(A)` |
| `$880b` | `extsub $880b = set_decr(bool incrdecr @Pc) clobbers(A)` |
| `$880e` | `extsub $880e = clr_scr(ubyte char @A, ubyte colors @X) clobbers(Y)` |
| `$8811` | `extsub $8811 = gotoxy(ubyte column @A, ubyte row @Y)` |
| `$8814` | `extsub $8814 = plot_char(ubyte char @A, ubyte colors @X)` |
| `$8817` | `extsub $8817 = scan_char() -> uword @AX` |
| `$881a` | `extsub $881a = hline(ubyte char @A, ubyte length @Y, ubyte colors @X) clobbers(A)` |
| `$881d` | `extsub $881d = vline(ubyte char @A, ubyte height @Y, ubyte colors @X) clobbers(A)` |
| `$8820` | `extsub $8820 = print_str(str txtstring @R0, ubyte length @Y, ubyte colors @X, ubyte convertchars @A) clobbers(A, Y)` |
| `$8823` | `extsub $8823 = fill_box(ubyte char @A, ubyte width @R1, ubyte height @R2, ubyte colors @X) clobbers(A, Y)` |
| `$8826` | `extsub $8826 = pet2scr(ubyte char @A) -> ubyte @A` |
| `$8829` | `extsub $8829 = scr2pet(ubyte char @A) -> ubyte @A` |
| `$882c` | `extsub $882c = border(ubyte mode @A, ubyte width @R1, ubyte height @R2, ubyte colors @X) clobbers(Y)              ; NOTE: mode 6 means 'custom' characters taken from r3 - r6` |
| `$882f` | `extsub $882f = save_rect(ubyte ramtype @A, bool vbank1 @Pc, uword address @R0, ubyte width @R1, ubyte height @R2) clobbers(A, X, Y)` |
| `$8832` | `extsub $8832 = rest_rect(ubyte ramtype @A, bool vbank1 @Pc, uword address @R0, ubyte width @R1, ubyte height @R2) clobbers(A, X, Y)` |
| `$8835` | `extsub $8835 = input_str(uword buffer @R0, ubyte buflen @Y, ubyte colors @X) clobbers (A) -> ubyte @Y             ; NOTE: returns string length` |
| `$8835` | `extsub $8835 = input_str_lastkey(uword buffer @R0, ubyte buflen @Y, ubyte colors @X) clobbers (Y) -> ubyte @A     ; NOTE: returns lastkey press` |
| `$8835` | `extsub $8835 = input_str_retboth(uword buffer @R0, ubyte buflen @Y, ubyte colors @X) clobbers () -> uword @AY     ; NOTE: returns lastkey press, string length` |
| `$8838` | `extsub $8838 = get_bank() clobbers (A) -> bool @Pc` |
| `$883b` | `extsub $883b = get_stride() -> ubyte @A` |
| `$883e` | `extsub $883e = get_decr() clobbers (A) -> bool @Pc` |


`print_str2(text, colors, convertchars)` is now an ordinary Prog8 wrapper:
it calculates the byte length and calls print_str. It no longer jumps to the
compiler-private `prog8_lib.strlen` assembly symbol. A true convert flag selects
PETSCII-to-screen conversion (A=0); false selects already-converted bytes
(A=$80), matching the archived wrapper.

The three input_str bindings are alternative return views of the same entry:
length in Y, last key in A, or their packed value in AY. The current frontend
polls keys itself and does not depend on these line-editor variants.

The rectangle API's RAM-type/bank/address/width/height arguments retain the
archived convention; the historical editor used $80 and bank1=true for VRAM
scratch rectangles. The current document is never stored in those rectangles.

## Frontend contract

The shared editor's commands and UI strings remain canonical ASCII. The VTUI
frontend maps command letters and filenames to/from PETSCII. Text editing keys
stay raw PETSCII; document bytes are rendered with pet2scr and plot_char rather
than sent to CHROUT as control commands.

Ordinary printable PETSCII and graphics render as glyphs. Control bytes in files
are preserved but displayed as spaces, not executed. Full embedded
color/control-stream emulation is not implemented. The selected character-set
state is the X16 normal PETSCII state; commands do not implement arbitrary
per-line case-mode changes.

## Verification and maintenance

The native suite t/05-vtui-document.t calls the embedded initializer and
render/scan routines, exercises graphics bytes, checks detected banked capacity, and
saves/reloads a document longer than the viewport. Other rarely used entrypoints
are retained as documented ABI, not all independently tested.

If modifying the binary: update this hash, payload size/address map if changed,
the extsub table, and native tests. Preserve main-RAM code/binary/BSS and banked document separation.

SHA-256 of the active file: `c8e406121ce447b1cc710133a2820b75013334cc111cd4ca7f90471761218de1`.

## Rebuilding the project patch

```sh
python3 tools/rebuild_vtui.py
```

The script verifies the archived binary's SHA-256, assembles
`src/vtui/charset.asm` with 64tass, checks the original table/instruction bytes,
redirects the $8826/$8829 jump-table entries to the new converters, and replaces
the restricted inline converter in print_str with a call to the extension.
It writes the active binary deterministically. No manual binary editing is needed.

The old converter replaced bytes >= $60 with a placeholder. The replacement
handles PETSCII's graphics/case ranges and $ff (pi). Reverse screen-code bits
are presentation state; scr2pet returns a canonical glyph code, not a reverse
control stream. Saving never uses that reverse conversion, so original document
byte spellings are retained.

The extension has no dependency on compiler-private labels. Its absolute call
inside print_str makes the maintained binary explicitly fixed at $8800. If
relocating it, update that call, the extension origin, the Prog8 bindings, and the
memory map together.
