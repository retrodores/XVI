#!/usr/bin/env python3
"""Run a compiled P8 TAP program with x16emu's real headless testbench."""
import os
import pathlib
import re
import subprocess
import sys

def main():
    data = pathlib.Path(sys.argv[1]).read_bytes()
    base = int.from_bytes(data[:2], "little")
    match = re.search(rb"\x9e\s*(\d+)", data[2:40])
    if not match or base != 0x0801 or base + len(data) - 2 >= 0x9f00:
        raise ValueError("expected a BASIC SYS launcher and PRG in main RAM")
    entry = int(match.group(1))
    commands = "".join(f"STM {base+i:04X} {v:02X}\n" for i,v in enumerate(data[2:]))
    commands += f"RUN {entry:04X}\n"
    proc = subprocess.run(
        [os.environ["X16EMU"], "-rom", os.environ["X16ROM"],
         "-testbench", "-echo", "raw", "-sound", "none", "-warp"],
        input=commands, text=True, encoding="latin1", stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, timeout=45,
        env={**os.environ, "SDL_VIDEODRIVER": "dummy", "SDL_AUDIODRIVER": "dummy"})
    output = proc.stdout.replace("\r\n", "\n").replace("\r", "\n")
    # Protocol acknowledgements are not TAP.
    if "# TAP BEGIN\n" not in output:
        raise RuntimeError("no TAP start marker from X16 program")
    output = output.split("# TAP BEGIN\n", 1)[1]
    lines = [l for l in output.splitlines() if l != "RDY"]
    print("\n".join(lines))
    if proc.returncode or not re.search(r"^1\.\.\d+$", output, re.M):
        raise RuntimeError(f"emulator exited with {proc.returncode} or no TAP plan")
    print("# X16 test program completed")
if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"Bail out! x16emu test runner: {exc}")
        sys.exit(1)
