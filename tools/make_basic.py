# tools/make_basic.py

from pathlib import Path
import config


ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "src"
BUILD = ROOT / "build"


def hex4(n: int) -> str:
    return f"${n:04X}"


def read_prg(path: Path):
    data = path.read_bytes()
    if len(data) < 2:
        raise ValueError(f"{path}: too short")

    load = data[0] | (data[1] << 8)
    body = data[2:]
    return load, body


def make_data(start_line: int, data: bytes, per_line: int = 8) -> str:
    lines = []
    line = start_line

    for i in range(0, len(data), per_line):
        nums = ",".join(str(b) for b in data[i:i + per_line])
        lines.append(f"{line} DATA {nums}")
        line += 10

    return "\n".join(lines)


def main() -> None:
    tpl = (SRC / "benchmark.bas.in").read_text(encoding="utf-8")

    drive_load, drive_body = read_prg(BUILD / "drive_worker.prg")
    c64_load, c64_body = read_prg(BUILD / "c64_worker.prg")

    if drive_load != config.DRIVE["load"]:
        raise ValueError(
            f"drive_worker.prg load address is {hex4(drive_load)}, "
            f"expected {hex4(config.DRIVE['load'])}"
        )

    if c64_load != config.C64["load"]:
        raise ValueError(
            f"c64_worker.prg load address is {hex4(c64_load)}, "
            f"expected {hex4(config.C64['load'])}"
        )

    c64_data_start = 12000

    d = config.DRIVE
    c = config.C64

    replacements = {
        "{TOTAL_WORK}": str(config.TOTAL_WORK),
        "{DRIVE_CHUNK}": str(config.DRIVE_CHUNK),
		"{C64_WEIGHT}": str(config.C64_WEIGHT),
		"{DRIVE_WEIGHT}": str(config.DRIVE_WEIGHT),

        "{DRIVE_LOAD}": str(drive_load),
        "{DRIVE_LOAD_HEX}": hex4(drive_load),
        "{DRIVE_LEN}": str(len(drive_body)),

        "{DRIVE_COMMON_HEX}": hex4(d["common"]),
        "{DRIVE_TABLE_HEX}": hex4(d["table"]),
        "{DRIVE_UCMD_HEX}": hex4(d["ucmd"]),
        "{DRIVE_PARAMS_HEX}": hex4(d["params"]),
        "{DRIVE_JOBS_HEX}": f"{hex4(d['job_a'])}/{hex4(d['job_b'])}",

        "{DRIVE_TABLE_DEC}": str(d["table"]),
        "{DRIVE_PARAMS_DEC}": str(d["params"]),
        "{DRIVE_VIA_PRB_LO}": str(d["via_prb"] & 0xFF),
        "{DRIVE_VIA_PRB_HI}": str(d["via_prb"] >> 8),
        "{DRIVE_LED_BIT}": str(d["led_bit"]),

        "{C64_LOAD}": str(c64_load),
        "{C64_LOAD_HEX}": hex4(c64_load),
        "{C64_LEN}": str(len(c64_body)),

        "{C64_PARAMS_HEX}": hex4(c["params"]),
        "{C64_TABLE_HEX}": hex4(c["table"]),

        "{C64_ITERLO_DEC}": str(c["params"] + 0),
        "{C64_ITERHI_DEC}": str(c["params"] + 1),
        "{C64_SEEDLO_DEC}": str(c["params"] + 2),
        "{C64_STATUS_DEC}": str(c["params"] + 3),
        "{C64_INLO_DEC}": str(c["params"] + 4),
        "{C64_INHI_DEC}": str(c["params"] + 5),
        "{C64_SEEDHI_DEC}": str(c["params"] + 6),
        "{C64_TABLE_DEC}": str(c["table"]),

        "{DRIVE_DATA}": make_data(9000, drive_body),
        "{C64_DATA_START}": str(c64_data_start),
        "{C64_DATA}": make_data(c64_data_start, c64_body),
    }

    out = tpl
    for key, value in replacements.items():
        out = out.replace(key, value)

    unresolved = sorted({part for part in out.split() if "{" in part or "}" in part})
    if unresolved:
        raise ValueError(f"unresolved template placeholders: {unresolved[:20]}")

    # petcat -w2 expects BASIC keywords in lowercase.
    out = out.lower()
    out = out.encode("ascii", "strict").decode("ascii")

    BUILD.mkdir(parents=True, exist_ok=True)
    (BUILD / "benchmark.bas").write_text(out, encoding="ascii", newline="\n")


if __name__ == "__main__":
    main()
	