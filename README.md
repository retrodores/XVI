# XVI2 and original XVI / VTUI

vi-style editors for Commander X16, written in Prog8.

The active source has been restored to the versions before the gap-buffer work:

- **XVI2:** exact source from `47d6569`, immediately before the gap-buffer merge.
- **XVI / VTUI:** untouched original source and VTUI binaries recovered from the attic.

See [restoration details](docs/RESTORATION.md) for exact provenance, build limits
and the distinction between recovered VTUI source and the older archived PRG.
The banked gap-buffer and subsequent display changes are no longer active.

Build XVI2 with [BUILDING.md](BUILDING.md). `make vtui` recovers the original
archived executable; it does not recompile or modernize the VTUI source.
The previous November 15–16 prereleases contain the reverted experiment.

For our Prog8 vi clone focused on cross-platform use, see
[p8vi](https://github.com/retrodores/p8vi).
