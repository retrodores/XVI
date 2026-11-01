#!/usr/bin/env python3
"""Execute a C64 TAP PRG in VICE console mode, with bounded execution."""
import os
import pathlib
import re
import subprocess
import sys
import tempfile

def main():
    prg = pathlib.Path(sys.argv[1]).resolve()
    roms = pathlib.Path(os.environ["VICE_ROMS"]).resolve()
    args = [os.environ["VICE"], "-default", "-console", "+sound", "-warp",
            "-debugcart", "-limitcycles", "100000000",
            "-drive8type", "0", "-virtualdev8", "-iecdevice8",
            "-device8", "1", "+fs8savep00", "-autostartprgmode", "1",
            "-kernal", str(roms / "kernal-901227-03.bin"),
            "-basic", str(roms / "basic-901226-01.bin"),
            "-chargen", str(roms / "chargen-901225-01.bin")]
    with tempfile.TemporaryDirectory(prefix="xvi2-vice-") as temp:
        proc = subprocess.run(
            [*args, "-fs8", temp, "-autostart", str(prg)],
            cwd=temp, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            timeout=45, text=True, encoding="latin1")
        outputs = [p for p in pathlib.Path(temp).iterdir()
                   if p.name.lower() == "tap.out"]
        if len(outputs) != 1:
            print(proc.stdout)
            raise RuntimeError("VICE produced no unique TAP output file")
        tap = outputs[0].read_text(encoding="ascii")
        print(tap, end="" if tap.endswith("\n") else "\n")
        # A deliberate failed assertion exits 1; preserve its TAP for prove.
        if proc.returncode not in (0, 1) or not re.search(
                rf"DBGCART: exit\({proc.returncode}\)", proc.stdout):
            print(proc.stdout)
            raise RuntimeError(f"VICE did not complete via debugcart ({proc.returncode})")
        if not re.search(r"^1\.\.\d+$", tap, re.M):
            raise RuntimeError("C64 test program emitted no TAP plan")
        if proc.returncode == 1 and not re.search(r"^not ok\b", tap, re.M):
            raise RuntimeError("VICE failed without a failed TAP assertion")
        print("# C64 test program completed")
if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"Bail out! VICE test runner: {exc}")
        sys.exit(1)
