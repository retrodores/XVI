# Building XVI2 for Commander X16

XVI2 targets Commander X16. For a Prog8 vi clone focused on cross-platform use, see [p8vi](https://github.com/retrodores/p8vi).

## Tested Linux build

Use the released **Prog8 14.0-BETA3** compiler, Java 21, and 64tass.

On Ubuntu 24.04:

```sh
sudo apt-get update
sudo apt-get install -y openjdk-21-jdk-headless 64tass make curl
mkdir -p build/tools
curl -fL --retry 3 https://github.com/irmen/prog8/releases/download/v14.0-BETA3/prog8c-14.0-BETA3-all.jar -o build/tools/prog8c-14.0-BETA3-all.jar
echo '7117cabdb1d3ecf11d4f38aa7e2cea570056a3eb2c3b3f4e8593838b1b4115c0  build/tools/prog8c-14.0-BETA3-all.jar' | sha256sum -c -
make build JAR="$PWD/build/tools/prog8c-14.0-BETA3-all.jar"
```

Output is `xvi2.prg` in the repository root. Make supplies `src` and `src/cx16` module paths and always selects `-target cx16`. A former `TARGET=c64` override now fails with a p8vi referral rather than producing a mislabeled X16 program.

With an already installed compiler:

```sh
make build JAR=/opt/prog8/14.0-BETA3/prog8c-14.0-BETA3-all.jar
```

### Optimization

Make defaults to `OPT=-noopt`. BETA3's optimizer reports “can only take negative of a signed number type” for unsigned subtraction in `gapbuffer.p8`'s `log_change`. This is a compiler/build issue independent of the removed C64 port.

To investigate optimization deliberately, use `make build OPT=`. Existing compiler warnings remain; compilation alone does not establish correct interactive behavior.

## PETSCII / VTUI XVI

```sh
make vtui JAR="$PWD/build/tools/prog8c-14.0-BETA3-all.jar"
```

This builds `src/xvi.p8` as `xvi.prg`, with the embedded maintained VTUI binary.
`make build XVI_EDITOR=xvi` is equivalent. Set `XVI_EDITOR=xvi` for run/debug/trace.
The default `XVI_EDITOR=xvi2` retains the ISO/ASCII frontend. Both target X16.
See [VTUI editor](docs/VTUI-XVI.md) for its 8 KiB document arena and PETSCII policy.

## Windows x16emu

Download the `xvi2-cx16-prog8-14.0-BETA3` workflow artifact and extract `XVI2.PRG`, or copy a locally built `xvi2.prg`.

From your installed x16emu directory, with its matching ROM:

```powershell
.\x16emu.exe -prg "C:\path\to\XVI2.PRG" -run
```

Press `i` to insert text; Escape returns to navigation. Use the wiki for current commands.

Make also provides `run`, `br` (build/run), `debug`, `trace`, and `clean`. Set `EMU` for your emulator executable.

## CI and draft releases

The workflow builds one X16 artifact on Ubuntu 24.04 using Java 21, 64tass and the checksum-verified BETA3 JAR. It runs on master pushes, pull requests, manual dispatch and `draft-*` tags.

A pushed `draft-*` tag creates a draft prerelease after both X16 frontend builds and test backends pass. Assets are `XVI2-X16.PRG`, `XVI-VTUI-X16.PRG`, and `SHA256SUMS.txt`. No C64 binary is built or packaged. Artifacts are `xvi2-cx16-prog8-14.0-BETA3` and `xvi-cx16-prog8-14.0-BETA3`.

## Automated tests

From the repository root:

```sh
export X16EMU=/absolute/path/x16emu
export X16ROM=/absolute/path/rom.bin
JAR=/absolute/path/prog8c-14.0-BETA3-all.jar prove -v t/*.t
```

Use x16emu r49 and its matching ROM. Install Java 21, 64tass, Perl/prove, Python 3 and SDL2 runtime. Without the emulator variables, the three native X16 wrappers skip locally; VM wrappers still run. CI explicitly requires VM and X16 execution.

The suites import unchanged production buffer/document modules. VM tests use existing portable scan branches through test-only adapters; native X16 tests use the X16 helpers and testbench protocol. Assertions execute in Prog8 and emit TAP to prove.

Coverage includes gap movement/capacity, page-boundary scans, marks, undo/redo APIs, line operations, yank/paste, horizontal windows and line-ending normalization. The PETSCII suite also verifies a 202-line native file round-trip and VTUI rendering. General interactive editor UI and ISO file-I/O coverage remain outside these suites. Compilation errors, crashes, missing plans/completion and timeouts fail. See `t/AGENTS.md`.
