# Building the restored editors

XVI2 uses the untouched pre-gap-buffer source and Prog8 12.0.1. Install Java 21,
64tass and make, then run:

```sh
curl -fL https://github.com/irmen/prog8/releases/download/v12.0.1/prog8c-12.0.1-all.jar -o prog8c-12.0.1-all.jar
echo '83bfbade1ee8cdc0cf846740339a6e3c4656aa1f5b63f55b054e5c0f18c810a0  prog8c-12.0.1-all.jar' | sha256sum -c -
make build
```

Output: `xvi2.prg`. Leave optimization enabled, as in the historical build.

```sh
make vtui
```

Output: `xvi.prg`, copied from the recovered March 2024 executable. This is not a
fresh compilation of the recovered VTUI source. That source is deliberately
unchanged and has old compiler compatibility issues documented in
[restoration details](docs/RESTORATION.md).

Run either PRG with x16emu using its normal PRG-loading option. CI checks source
identity and compiles XVI2; it does not claim gap-buffer coverage or a successful
VTUI recompilation. Source restoration checks run with `prove -v t/*.t`.
