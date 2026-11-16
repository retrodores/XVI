# Restored baselines

The gap-buffer experiments and the later display changes are reverted from the
active tree. They remain in Git history; this rollback does not rewrite history.

## XVI2

`src/xvi2.p8` and `src/debug.p8` are byte-for-byte copies from
`47d6569e8f8a29ce08f519fc122059ed62926ae5`, the parent of gap-buffer merge
`2b1d791`. This restores the original fixed-line implementation, its original
limits and behavior. No subsequent rendering fixes are retained.

Build with Prog8 12.0.1 and its default optimization. The untouched source builds
with that compiler. Prog8 14.0-BETA3 with -noopt exceeds main RAM, so the previous
compiler/build settings do not apply.

## XVI / VTUI

`src/xvi.p8` and `src/vtui.p8` are unchanged copies from the attic, identical to
the files before the historical attic move at `9e19f18`. The original
`VTUI-C1C7.BIN` and `VTUI1.0.BIN` are restored in the repository root. The patched
VTUI binary, charset assembly and modern wrapper are removed from the active tree.
The original uses VRAM as document storage, with its original green surround
and original commands. No gap buffer, shared XVI2 engine or display rewrite is
retained.

The recovered source mixes historical `string` imports and newer `extsub`
syntax. It does not compile unchanged with the tested Prog8 10.4.2 or 11.0.1:
the former rejects the binding syntax, the latter rejects the old module name.
We have deliberately not edited it to resolve those incompatibilities.

`recovery/XVI-VTUI-ORIGINAL.PRG` is the last tracked historical `xvi` executable,
recovered from `699488283fbd336743bc0549d3de472595dd7d59:xvi` (March 2024).
It predates the recovered source and is an archival executable, not a build of
that newer source. `make vtui` copies this archived binary to `xvi.prg` and says
so explicitly. This is recovery, not a claim of source/binary equivalence.

## Verification

`t/01-restoration.t` checks exact hashes of the restored sources, original
VTUI binaries and recovered PRG. CI also compiles untouched XVI2 with pinned
Prog8 12.0.1. The removed gap-buffer/document/display suites tested the reverted
implementation and no longer describe these restored editors.
