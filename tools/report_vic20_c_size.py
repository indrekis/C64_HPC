#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import sys

def parse_int(s: str) -> int:
    return int(s, 0)

def main() -> None:
    if len(sys.argv) < 2:
        raise SystemExit("usage: report_vic20_c_size.py PRG [DRIVE_BIN] [MAP] [EXPECTED_LOAD] [MEM_END]")

    prg = Path(sys.argv[1])
    data = prg.read_bytes()
    if len(data) < 2:
        raise SystemExit(f"{prg}: too short")

    load = data[0] | (data[1] << 8)
    body = len(data) - 2
    end = load + body - 1 if body else load - 1

    expected = parse_int(sys.argv[4]) if len(sys.argv) > 4 else None
    mem_end = parse_int(sys.argv[5]) if len(sys.argv) > 5 else 0x1DFF

    print("VIC20_C C size report:")
    print(f"  file: {prg}")
    print(f"  load address: ${load:04X}")
    print(f"  PRG body: {body} bytes")
    print(f"  memory range: ${load:04X}-${end:04X}")
    print(f"  memory limit: ${mem_end:04X}")
    print(f"  free before screen: {mem_end - end if end <= mem_end else -(end - mem_end)} bytes")

    if expected is not None and load != expected:
        raise SystemExit(f"{prg}: expected load ${expected:04X}, got ${load:04X}")
    if end > mem_end:
        raise SystemExit(f"{prg}: exceeds memory limit by {end - mem_end} bytes")

if __name__ == "__main__":
    main()
