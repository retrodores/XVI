#!/usr/bin/env python3
"""Reproduce the maintained VTUI binary from the pinned archived variant."""
from pathlib import Path
import hashlib
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
ORIGINAL_SHA256 = "8f0eb329f697986f5a6e0309254dbbfcaaab152b915a1169b606f05dfd49aed5"
BASE = 0x8800

def rebuild():
    original = (ROOT / "attic/VTUI-C1C7.BIN").read_bytes()
    if hashlib.sha256(original).hexdigest() != ORIGINAL_SHA256:
        raise ValueError("archived VTUI binary does not match the pinned source")
    payload = bytearray(original[2:])
    with tempfile.TemporaryDirectory(prefix="xvi-vtui-asm-") as work:
        binary = Path(work) / "charset.bin"
        labels = Path(work) / "charset.labels"
        subprocess.run(["64tass", "--nostart", "-o", str(binary), "-l",
                        str(labels), str(ROOT / "src/vtui/charset.asm")], check=True)
        symbols = {name: int(value, 16) for name, value in
                   re.findall(r"^(\w+)\s*=\s*\$([0-9a-f]+)", labels.read_text(), re.M)}
        forward = symbols["pet_to_screen"]
        reverse = symbols["screen_to_pet"]
        if forward != BASE + len(payload):
            raise ValueError("extension origin does not follow the archived payload")
        # initialize() relocates the jump-table's relative target words.
        for offset, expected, address in [(0x26, b"\x4c\x5a\x01", forward),
                                           (0x29, b"\x4c\x6b\x01", reverse)]:
            if payload[offset:offset+3] != expected:
                raise ValueError("unexpected archived jump table")
            payload[offset+1:offset+3] = (address - BASE).to_bytes(2, "little")
        # print_str has an inline copy of the old restricted converter.
        # Replace it with an absolute call; this maintained variant is fixed at $8800.
        restricted = bytes.fromhex("c9 20 90 08 c9 40 90 08 c9 60 90 02 a9 96 e9 3f")
        first = payload.find(restricted)
        second = payload.find(restricted, first + 1)
        if first != 0x15a or second != 0x189:
            raise ValueError(f"unexpected inline converter locations: {first:x}, {second:x}")
        payload[second:second+len(restricted)] = (
            b"\x20" + forward.to_bytes(2, "little") + b"\xea" * (len(restricted)-3))
        payload.extend(binary.read_bytes())
    result = original[:2] + payload
    (ROOT / "src/vtui/VTUI.BIN").write_bytes(result)
    print(f"VTUI.BIN: {len(result)} bytes; SHA-256 {hashlib.sha256(result).hexdigest()}")

if __name__ == "__main__":
    rebuild()
