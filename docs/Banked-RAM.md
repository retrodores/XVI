# Detected banked RAM

Both XVI2 (ISO/ASCII) and XVI (PETSCII/VTUI) use the same banked gap buffer.
Capacity comes from the X16 KERNAL through `cx16.numbanks()`, not an assumption
about how many RAM sockets are populated. Prog8 maps the KERNAL's zero count
for a fully populated machine to 256 banks.

| Installed RAM | Detected banks | Document capacity |
|---|---:|---:|
| 512 KiB | 64 | 491,520 bytes (480 KiB) |
| 1 MiB | 128 | 1,015,808 bytes (992 KiB) |
| 1.5 MiB | 192 | 1,540,096 bytes (1,504 KiB) |
| 2 MiB | 256 | 2,064,384 bytes (2,016 KiB) |

Banks 0–3 are reserved; document storage owns banks 4 through the detected last
bank during the editor session. This is a standalone-editor allocation, not a
shared heap or a promise to coexist with other banked-RAM applications. Main
RAM holds code, BSS, viewport/yank storage and staging buffers. VTUI remains at
$8800..$8c14; there is no fixed $6800 document arena.

## Storage and transfers

`src/bankstore.p8` implements the active `buffer` block. Length, capacity, gap
position/size, marks, line numbers and horizontal offsets use signed 32-bit
`long` values. The no-result sentinel is -1. All logical positions are zero
based, while document lines are one based. Text length plus free gap equals
capacity. At most 2,064,384 document bytes fit; line count depends on their
lengths and separators, with no 16-bit line-count ceiling.

`src/cx16/bankram.p8` maps logical offset zero to bank 4 at $a000. Transfers
split at the 8 KiB window boundary. Its native copy routine saves/restores the
RAM-bank selector and interrupt flags, masking IRQs while the window is
selected. Gap moves use a 512-byte unbanked bounce buffer and work even when
only a few bytes remain free.

File input/output uses a separate 512-byte main-RAM staging buffer. ROM disk
calls never receive a pointer into the bank window. Saving appends the selected
frontend's newline; loading normalizes input and removes that final newline.
A full-capacity document can therefore round-trip with its extra on-disk final
newline. Oversized input still reports truncation; keep the original file.

The viewport remains 76 columns by 56 rows. The four-column line gutter shows
`####` beyond line 9,999; the footer shows the full document line/column/count.
Yank storage remains 1,024 bytes, including a line separator; longer lines may
be edited but cannot be yanked whole. Long-distance moves and scans are linear,
so larger capacity does not imply instant navigation on a 65C02.

## Development and verification

The old `buffer.p8`/`gapbuffer.p8` contiguous library remains for its separate
API/undo tests. It is not the editors' active text store. Editor undo is still
not connected. VM document tests use a test-only RAM transport; native tests
exercise real bank switching and ROM file I/O.

Run all wrappers with the emulator variables documented in BUILDING.md, then
repeat native suites with `X16_RAM_KB=2048` (default 512). The two banked suites
exercise both frontends: full-capacity fill/save/reload, 8 KiB and 64 KiB
boundaries, the highest bank, narrow-gap movement, marks, overflow rejection,
wide windows and more than 65,535 lines. CI covers 512 KiB and 2 MiB; intermediate
populations use the same detected-count calculation but are not separately
emulated in CI. Interactive editor sessions remain manual.

For our cross-platform Prog8 vi clone, see [p8vi](https://github.com/retrodores/p8vi).
