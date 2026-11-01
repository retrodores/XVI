# Building XVI2

## Commander X16 (tested build)

These instructions build the current source on Linux for the Commander X16.
They use the released Prog8 **14.0-BETA3** compiler and 64tass, with Java 21.

On Ubuntu 24.04:

```sh
sudo apt-get update
sudo apt-get install -y openjdk-21-jdk-headless 64tass make curl
mkdir -p build/tools
curl -fL --retry 3 \
  https://github.com/irmen/prog8/releases/download/v14.0-BETA3/prog8c-14.0-BETA3-all.jar \
  -o build/tools/prog8c-14.0-BETA3-all.jar
echo '7117cabdb1d3ecf11d4f38aa7e2cea570056a3eb2c3b3f4e8593838b1b4115c0  build/tools/prog8c-14.0-BETA3-all.jar' | sha256sum -c -
make build JAR="$PWD/build/tools/prog8c-14.0-BETA3-all.jar"
```

The output is `xvi2.prg` in the repository root. Both `src` and
`src/cx16` must be on the module search path; the Makefile supplies them.

If the compiler is already installed elsewhere:

```sh
make build JAR=/opt/prog8/14.0-BETA3/prog8c-14.0-BETA3-all.jar
```

### Why optimization is disabled

The Makefile defaults to `OPT=-noopt`. With optimization enabled, BETA3
reports "can only take negative of a signed number type" for the unsigned
subtraction expression in `src/gapbuffer.p8`'s `log_change` routine.
The unmodified source compiles and assembles with `-noopt`.
Existing compiler warnings remain; a successful build does not establish
that the editor works correctly at runtime.

To experiment with optimization explicitly, use `make build OPT=`.

### Run on Windows with x16emu

Download the workflow's `xvi2-cx16-prog8-14.0-BETA3` artifact for the X16 target and extract
`XVI2.PRG`, or copy your locally built `xvi2.prg` to Windows.
From the directory containing your installed x16emu and its matching ROM:

```powershell
.\x16emu.exe -prg "C:\path\to\XVI2.PRG" -run
```

Press `i` to begin inserting text; Escape returns to navigation mode.
See [readme.txt](readme.txt) for commands and
[regression-test.md](regression-test.md) for manual testing.
CI also executes focused buffer/document tests headlessly; interactive editor
regression testing is still separate.

## CI

[build.yml](.github/workflows/build.yml) uses Ubuntu 24.04, Java 21,
64tass, and the checksum-verified BETA3 release JAR. Its matrix invokes the same
`make build` target for `cx16` and `c64`, packaging each result as `XVI2.PRG`
in a separate target-named artifact.
It runs on pushes, pull requests, and manual dispatch.

## Other platforms

Platform-specific modules live in `src/<target>/`; shared editor and
buffer code lives directly under `src/`. The Makefile selects modules
using `TARGET`.

A C64 port is present in `src/c64/`. Its Linux build has also been verified with:

```sh
make build TARGET=c64 JAR="$PWD/build/tools/prog8c-14.0-BETA3-all.jar"
```

CI builds both targets independently. The C64 artifact is named
`xvi2-c64-prog8-14.0-BETA3`. The shared test programs also execute under headless X16 emulation;
C64 execution and full editor UI behavior are not covered.
Both targets currently write `xvi2.prg`; copy the output aside before
building another target. Add target-specific instructions and CI coverage
here as more platforms are validated.

## Automated tests (TAP / prove)

From the repository root:

```sh
JAR=/absolute/path/prog8c-14.0-BETA3-all.jar prove -v t/*.t
```

The two VM wrappers run without an emulator. To also execute the same suites
as real 65C02 programs, set `X16EMU` to the absolute x16emu r49 executable
and `X16ROM` to its matching ROM. Install the SDL2 runtime and Python 3 as well
as Java, Perl/prove and 64tass. X16 wrappers skip locally if these variables
are unset; both backends are explicitly required in CI.

The test programs import the existing production modules without editing them.
The VM uses the buffer's portable scan branches; headless X16 tests use the
production platform and assembly helpers through x16emu's `-testbench` mode.
Assertions execute in P8 and emit TAP, which Perl's `prove` evaluates. Compilation,
VM/emulator failures, missing plans and timeouts fail the run.

Coverage includes gap movement and capacity boundaries, page-boundary scans,
marks, undo/redo, document line operations, yank/paste, horizontal windows, and
line-ending normalization. It does not yet cover editor UI, disk load/save,
C64 execution, or a measured percentage of source lines. See `t/AGENTS.md` for
maintenance guidance. Draft release jobs now wait for both test backends too.
