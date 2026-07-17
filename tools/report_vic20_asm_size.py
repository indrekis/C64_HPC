from __future__ import annotations

from pathlib import Path
import re
import sys

DEFAULT_LOAD_EXPECTED = 0x1001
DEFAULT_SCREEN_START = 0x1E00


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
    if len(argv) not in (3, 4, 5, 6):
        print(
            "usage: report_vic20_asm_size.py "
            "<prg> <drive_image_bin> [mapfile] [expected_load] [ram_limit]",
            file=sys.stderr,
        )
        return 2

    prg_path = Path(argv[1])
    drive_path = Path(argv[2])
    map_path = Path(argv[3]) if len(argv) >= 4 else None
    expected_load = (
        parse_hex(argv[4]) if len(argv) >= 5 else DEFAULT_LOAD_EXPECTED
    )
    screen_start = (
        parse_hex(argv[5]) if len(argv) >= 6 else DEFAULT_SCREEN_START
    )

    data = prg_path.read_bytes()
    if len(data) < 3:
        raise SystemExit(f"{prg_path} is too short to be a PRG")
    load = data[0] | (data[1] << 8)
    body_size = len(data) - 2
    body_first_free = load + body_size
    body_last = body_first_free - 1

    if load != expected_load:
        raise SystemExit(
            f"VIC20 ASM load address is ${load:04X}, expected ${expected_load:04X}"
        )
    if body_first_free > screen_start:
        raise SystemExit(
            f"VIC20 ASM PRG body reaches ${body_first_free:04X}, "
            f"beyond screen start ${screen_start:04X}"
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

    free_after_body = screen_start - body_first_free
    free_after_bss = screen_start - ram_first_free
    if free_after_bss < 0:
        raise SystemExit(
            f"VIC20 ASM RAM use reaches ${ram_first_free:04X}, "
            f"beyond screen start ${screen_start:04X}"
        )

    print("VIC20 ASM size report:")
    print(f"  PRG body:       ${load:04X}-${body_last:04X} ({body_size} bytes)")
    print(f"  1541 image:     {drive_size} bytes")
    print(f"  BSS:            {bss_info}")
    print(f"  free after PRG: {free_after_body} bytes before screen ${screen_start:04X}")
    print(f"  free after BSS: {free_after_bss} bytes before screen ${screen_start:04X}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
