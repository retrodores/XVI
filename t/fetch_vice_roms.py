#!/usr/bin/env python3
"""Fetch checksum-pinned C64 ROMs from VICE's own source mirror."""
import hashlib
import pathlib
import sys
import urllib.request

REVISION = "f765978dfa2bf6fda332454428ce1a8557107324"
ROMS = {
    "basic-901226-01.bin": "89878cea0a268734696de11c4bae593eaaa506465d2029d619c0e0cbccdfa62d",
    "kernal-901227-03.bin": "83c60d47047d7beab8e5b7bf6f67f80daa088b7a6a27de0d7e016f6484042721",
    "chargen-901225-01.bin": "fd0d53b8480e86163ac98998976c72cc58d5dd8eb824ed7b829774e74213b420",
}

def main():
    dest = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "build/tools/vice-roms")
    dest.mkdir(parents=True, exist_ok=True)
    for name, digest in ROMS.items():
        path = dest / name
        if path.exists() and hashlib.sha256(path.read_bytes()).hexdigest() == digest:
            continue
        url = f"https://raw.githubusercontent.com/VICE-Team/svn-mirror/{REVISION}/vice/data/C64/{name}"
        with urllib.request.urlopen(url, timeout=30) as response:
            data = response.read()
        if hashlib.sha256(data).hexdigest() != digest:
            raise RuntimeError(f"checksum mismatch for {name}")
        path.write_bytes(data)
        print(f"Verified {name}")

if __name__ == "__main__":
    main()
