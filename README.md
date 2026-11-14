# XVI2

A vi-style text editor written in Prog8, focused on the **Commander X16**.

For our Prog8 vi clone focused on **cross-platform use**, see [p8vi](https://github.com/retrodores/p8vi). XVI2's active build, renderer and tests target X16; this repository no longer ships a C64 port.

XVI2 is a work in progress. It has modal editing, file loading and saving, line yank/paste, and horizontal panning over long lines. Its text store uses a gap buffer; store-level undo is not yet connected to editor commands.

## Build and try it

See [BUILDING.md](BUILDING.md) for the tested Linux build and basic Windows x16emu launch. The current build uses **Prog8 14.0-BETA3** with optimization disabled.

The **Build** GitHub Actions workflow builds the X16 program on Linux and uploads `XVI2.PRG`. Focused TAP suites run in Prog8 VM and headless x16emu. Full editor UI and disk-I/O testing remain manual.

## Documentation

- [XVI2 wiki](https://github.com/retrodores/XVI/wiki)
- [Quick help](readme.txt)
- [Manual regression checklist](regression-test.md)
- [Sample files](samples/)
- [Change history](CHANGELOG)
- [Original VTUI/PETSCII XVI and revival assessment](docs/VTUI-XVI.md)

The quick-help/regression files contain older fixed-width wording: the current X16 editor displays a 76-column window and pans over longer lines.

Historical code and binaries live in [attic/](attic/). The original VTUI-based XVI is preserved there; it is not currently an active build target.

For more links: https://x16files.com/hub/editors.html#pkg-XVI2

<img width="1282" height="963" alt="XVI2 editor" src="https://github.com/user-attachments/assets/455c5df5-99ac-4f7b-80bd-df552f5bbd71" />
