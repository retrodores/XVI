# XVI2

A vi-style text editor for the Commander X16, written in Prog8.
The current code also includes a C64 port.

XVI2 is a work in progress. It has modal editing, file loading and saving,
line yank/paste, and horizontal panning over long lines. The shared text
store uses a gap buffer; its undo support is not yet connected to editor commands.

## Build and try it

See [BUILDING.md](BUILDING.md) for the tested Linux build and Windows
x16emu instructions. The current X16 build uses **Prog8 14.0-BETA3**
with optimization disabled.

The **Build** GitHub Actions workflow compiles the X16 version on Linux
and uploads `XVI2.PRG` as a downloadable artifact. Compilation is checked;
the workflow does not run an emulator.

## Help and testing

- [Quick help](readme.txt)
- [Manual regression checklist](regression-test.md)
- [Sample files](samples/)
- [Change history](CHANGELOG)

Historical code, binaries, and editing leftovers live in [attic/](attic/).

For more links: https://x16files.com/hub/editors.html#pkg-XVI2

<img width="1282" height="963" alt="XVI2 editor" src="https://github.com/user-attachments/assets/455c5df5-99ac-4f7b-80bd-df552f5bbd71" />
