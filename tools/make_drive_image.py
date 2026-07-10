# tools/make_drive_image.py
from pathlib import Path
from math import sqrt
import config

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / "build"
OUTDIR = BUILD / "vic20"


def read_prg(path: Path) -> tuple[int, bytes]:
    data = path.read_bytes()
    if len(data) < 2:
        raise ValueError(f"{path}: too short")
    return data[0] | (data[1] << 8), data[2:]


def q_table() -> bytes:
    q = []
    for x in range(256):
        v = int(sqrt(65536 - x * x))
        q.append(min(v, 255))
    return bytes(q)


def main() -> None:
    d = config.DRIVE
    load, body = read_prg(BUILD / "drive_worker.prg")
    if load != d["load"]:
        raise ValueError(f"drive_worker.prg load ${load:04X}, expected ${d['load']:04X}")

    image_len = d["end"] - d["load"]
    image = bytearray(body)
    if len(image) > image_len:
        raise ValueError(f"drive worker body is {len(image)} bytes; max image is {image_len}")
    if len(image) < image_len:
        image.extend(bytes(image_len - len(image)))

    table_off = d["table"] - d["load"]
    image[table_off:table_off + 256] = q_table()

    OUTDIR.mkdir(parents=True, exist_ok=True)
    (OUTDIR / "drive_image.bin").write_bytes(bytes(image))
    print(f"wrote {OUTDIR / 'drive_image.bin'}: ${d['load']:04X}-${d['load'] + len(image) - 1:04X}")


if __name__ == "__main__":
    main()
