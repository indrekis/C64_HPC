from __future__ import annotations

from pathlib import Path
import re
import sys

LOAD_EXPECTED = 0x1001
SCREEN_START = 0x1E00


def parse_hex(s: str) -> int:
    return int(s.replace("$", "").replace("0x", ""), 16)


def parse_segments(map_path: Path) -> dict[str, tuple[int, int, int]]:
    if not map_path.exists():
        return {}
    segments: dict[str, tuple[int, int, int]] = {}
    line_re = re.compile(
        r"^\s*([A-Za-z_][A-Za-z0-9_]*)\s+"
        r"([0-9A-Fa-f]{4,6})\s+([0-9A-Fa-f]{4,6})\s+([0-9A-Fa-f]{4,6})\b"
    )
    for line in map_path.read_text(errors="replace").splitlines():
        m = line_re.match(line)
        if not m:
            continue
        name = m.group(1)
        start = parse_hex(m.group(2))
        end = parse_hex(m.group(3))
        size = parse_hex(m.group(4))
        segments[name] = (start, end, size)
    return segments


def main(argv: list[str]) -> int:
    if len(argv) not in (3, 4):
        print(
            "usage: report_vic20u_asm_size.py <prg> <drive_image_bin> [mapfile]",
            file=sys.stderr,
        )
        return 2

    prg_path = Path(argv[1])
    drive_path = Path(argv[2])
    map_path = Path(argv[3]) if len(argv) == 4 else None

    data = prg_path.read_bytes()
    if len(data) < 3:
        raise SystemExit(f"{prg_path} is too short to be a PRG")
    load = data[0] | (data[1] << 8)
    body_size = len(data) - 2
    body_first_free = load + body_size
    body_last = body_first_free - 1

    if load != LOAD_EXPECTED:
        raise SystemExit(
            f"VIC20U ASM load address is ${load:04X}, expected ${LOAD_EXPECTED:04X}"
        )
    if body_first_free > SCREEN_START:
        raise SystemExit(
            f"VIC20U ASM PRG body reaches ${body_first_free:04X}, "
            f"beyond screen start ${SCREEN_START:04X}"
        )

    drive_size = drive_path.stat().st_size if drive_path.exists() else 0
    segments = parse_segments(map_path) if map_path else {}
    ram_first_free = body_first_free
    bss_info = "not parsed"
    if "BSS" in segments:
        bss_start, bss_end, bss_size = segments["BSS"]
        if bss_size:
            ram_first_free = max(ram_first_free, bss_end + 1)
            bss_info = f"${bss_start:04X}-${bss_end:04X} ({bss_size} bytes)"
        else:
            bss_info = f"empty at ${bss_start:04X}"

    free_after_body = SCREEN_START - body_first_free
    free_after_bss = SCREEN_START - ram_first_free
    if free_after_bss < 0:
        raise SystemExit(
            f"VIC20U ASM RAM use reaches ${ram_first_free:04X}, "
            f"beyond screen start ${SCREEN_START:04X}"
        )

    print("VIC20U ASM size report:")
    print(f"  PRG body:       ${load:04X}-${body_last:04X} ({body_size} bytes)")
    print(f"  1541 image:     {drive_size} bytes")
    print(f"  BSS:            {bss_info}")
    print(f"  free after PRG: {free_after_body} bytes before screen ${SCREEN_START:04X}")
    print(f"  free after BSS: {free_after_bss} bytes before screen ${SCREEN_START:04X}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
