# Maintaining XVI2 tests

These instructions apply to everything under `t/`.

## Intent and boundaries

Tests should protect observable behavior and stay stable across routine refactors.
The user should not need to maintain them by hand as a recurring task.
When implementing a behavior change or bug fix, the implementing agent owns any
necessary regression test in the same change. Do not rewrite unrelated tests.

Do not modify, split, copy-and-patch, or replace production code to make it testable.
Import the actual files from `src/`. Test adapters and runners belong under `t/`.
Do not weaken expected results, add skips, or label failures TODO merely to get green CI.
If an existing production defect is exposed, report it and handle a production fix
as its own explicit change, rather than silently changing the implementation.

## Layout

- `gapbuffer_test.p8`: buffer API, boundaries, marks, scans, invariants, undo/redo.
- `document_test.p8`: line operations, yank/paste, horizontal windows, normalization.
- `01-*.t`, `02-*.t`: Perl wrappers compiling and executing the P8 programs in Prog8 VM.
- `03-*.t`, `04-*.t`: same programs compiled for cx16 and run with headless x16emu.
- `05-*.t`, `06-*.t`: same suites compiled for c64 and run in VICE console mode.
- `support/c64/tap.p8`: emits ASCII TAP to a temporary VICE filesystem file and
  terminates through the debug cartridge; no editor screen routines are used.
- `run_vice.py`: fresh filesystem per run, cycle/wall-clock limits, completion checks.
- `fetch_vice_roms.py`: fetches revision- and checksum-pinned ROMs from VICE upstream.
- `lib/Prog8Test.pm`: subprocess deadlines, compile/run failure handling, TAP transport.
- `support/tap.p8`: small TAP producer for VM. Assertions execute in Prog8.
- `support/cx16/tap.p8`: TAP producer for X16; exits the emulator after the plan.
- `support/fastmem_platform.p8`: VM-only adapter selecting existing portable scans;
  assembly-only entry points bail out if accidentally called.
- `support/xvi_platform.p8`: VM-only document geometry and file adapters.
- `editor_hooks.p8`: link-only editor UI hooks; fail an assertion if called.
- `run_x16.py`: x16emu testbench protocol, PRG loading and TAP capture.

X16 and C64 runs import their real `src/cx16/` or `src/c64/` platform modules
and `src/fastmem.p8`.
VM runs exercise existing portable scan branches. Never describe the VM adapter
as testing assembly. The current suites do not call load/save, so file adapters
do not establish disk-I/O coverage. Neither suite drives the editor UI.

## Run from the repository root

```sh
JAR=/absolute/path/prog8c-14.0-BETA3-all.jar prove -v t/*.t
```

Java 21, Perl/prove and Python 3 are needed. Native X16 compilation needs 64tass.
Set `X16EMU` to the absolute r49 executable and `X16ROM` to its matching
`rom.bin` to enable the X16 wrappers. Without those variables only the two X16
wrappers skip; the VM tests still run. Set `VICE` to x64sc and `VICE_ROMS` to the directory of ROMs obtained with
`python3 t/fetch_vice_roms.py` to enable the C64 wrappers. Without those variables
only the C64 wrappers skip. CI explicitly runs all three backends.
See `BUILDING.md` and the pinned downloads in `.github/workflows/build.yml`.

## For each change

1. Identify the changed public behavior. Existing tests may already cover it;
   a refactor need not change tests.
2. For a bug, add the smallest input and expected result reproducing it.
   Include a boundary case where relevant: empty, first/last position, exact
   capacity, one byte too large, gap on either side, or a panned line.
3. Assert returned values AND resulting text/state when either can be wrong.
   Use public `buffer.check()` after gap mutations where useful.
4. Reuse the same P8 cases on VM, X16 and C64 when possible. Use explicit
   `\x0a`/`\x0d` for file fixture bytes: `\n` is target-dependent.
   Use `doctext.WIDTH` instead of assuming 76 columns: C64 has 40.
   Do not tie expectations to labels, register allocation, or instruction counts.
5. Run the relevant suites, then all six wrappers with both emulators configured
   before pushing. Preserve TAP plans; crashes, timeouts and missing plans must fail.
6. Update this file or the coverage notes only if the suite's scope or invocation
   changes. Report actual assertions/backends executed, skipped coverage and failures.

Prefer deterministic short cases over broad snapshots. Keep helper APIs small;
this is a project-local TAP helper, not yet a general Prog8 testing framework.
