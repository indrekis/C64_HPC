PYTHON=python3
CA65=ca65
LD65=ld65
PETCAT=petcat
C1541=c1541

all: build/benchmark.prg

build:
	mkdir -p build

src/generated_drive.inc src/generated_c64.inc src/generated_drive.cfg src/generated_c64.cfg: tools/config.py tools/make_includes.py | build
	$(PYTHON) tools/make_includes.py

build/drive_worker.o: src/drive_worker.asm src/generated_drive.inc | build
	$(CA65) -o build/drive_worker.o src/drive_worker.asm

build/drive_worker.prg: build/drive_worker.o src/generated_drive.cfg | build
	$(LD65) -C src/generated_drive.cfg -o build/drive_worker.prg build/drive_worker.o --mapfile build/drive_worker.map

build/c64_worker.o: src/c64_worker.asm src/generated_c64.inc | build
	$(CA65) -o build/c64_worker.o src/c64_worker.asm

build/c64_worker.prg: build/c64_worker.o src/generated_c64.cfg | build
	$(LD65) -C src/generated_c64.cfg -o build/c64_worker.prg build/c64_worker.o --mapfile build/c64_worker.map

build/benchmark.bas: src/benchmark.bas.in build/drive_worker.prg build/c64_worker.prg tools/make_basic.py tools/config.py | build
	$(PYTHON) tools/make_basic.py

build/benchmark.prg: build/benchmark.bas | build
	$(PETCAT) -w2 -o build/benchmark.prg -- build/benchmark.bas

build/benchmark.d64: build/benchmark.prg | build
	rm -f build/benchmark.d64
	$(C1541) -format "bench,01" d64 build/benchmark.d64 -write build/benchmark.prg benchmark

disk: build/benchmark.d64

clean:
	rm -rf build src/generated_drive.inc src/generated_c64.inc src/generated_drive.cfg src/generated_c64.cfg
	