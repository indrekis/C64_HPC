GENERATED_FILES := src/generated_*.cfg src/generated_*.inc src/generated_*.h src/generated_*.s build/*.lst build/vic20uc.s

PYTHON=python3
CA65=ca65
LD65=ld65
PETCAT=petcat
C1541=c1541
CL65=cl65
CC65=cc65


all: c64 c64-disk vic20 vic20-disk vic20u vic20u-disk vic20u-asm vic20u-asm-disk build/vic20uc_u.d64 \
	build/vic20uc_3k.d64

build:
	mkdir -p build

src/generated_drive.inc src/generated_c64.inc src/generated_drive.cfg src/generated_c64.cfg: tools/config.py tools/make_includes.py | build
	$(PYTHON) tools/make_includes.py

build/drive_worker.o: src/drive_worker.asm src/generated_drive.inc | build
	$(CA65) --listing build/drive_worker.lst -o build/drive_worker.o src/drive_worker.asm

build/drive_worker.prg: build/drive_worker.o src/generated_drive.cfg | build
	$(LD65) -C src/generated_drive.cfg -o build/drive_worker.prg build/drive_worker.o --mapfile build/drive_worker.map

build/c64_worker.o: src/c64_worker.asm src/generated_c64.inc | build
	$(CA65) --listing build/c64_worker.lst -o build/c64_worker.o src/c64_worker.asm

build/c64_worker.prg: build/c64_worker.o src/generated_c64.cfg | build
	$(LD65) -C src/generated_c64.cfg -o build/c64_worker.prg build/c64_worker.o --mapfile build/c64_worker.map

build/c64_worker.bin: build/c64_worker.prg | build
	tail -c +3 build/c64_worker.prg > build/c64_worker.bin

build/c64_bench.bas: src/benchmark.bas.in build/drive_worker.prg build/c64_worker.prg tools/make_basic.py tools/config.py | build
	$(PYTHON) tools/make_basic.py
	mv build/benchmark.bas build/c64_bench.bas

build/c64_bench.prg: build/c64_bench.bas | build
	$(PETCAT) -w2 -o build/c64_bench.prg -- build/c64_bench.bas

build/c64_bench.d64: build/c64_bench.prg | build
	rm -f build/c64_bench.d64
	$(C1541) -format "c64bench,01" d64 build/c64_bench.d64 -write build/c64_bench.prg c64bench

disk: build/c64_bench.d64

# -----------------------------------------------------------------------------
# VIC-20 + 1541 variants.  These targets are additive and keep the original C64
# default build unchanged.
.PHONY: c64 c64-disk vic20 vic20-disk vic20u vic20u-disk vic20u-asm vic20u-asm-disk clean-vic20

c64: build/c64_bench.prg build/c64_worker.bin

c64-disk: build/c64_bench.d64

src/generated_vic20.inc src/generated_vic20.cfg: tools/config.py tools/make_vic20_includes.py
	$(PYTHON) tools/make_vic20_includes.py

build/vic20_drive.bin: build/drive_worker.prg tools/make_drive_image.py tools/config.py | build
	$(PYTHON) tools/make_drive_image.py
	mv build/vic20/drive_image.bin build/vic20_drive.bin
	rmdir build/vic20 2>/dev/null || true

build/vic20_worker.o: src/vic20_worker.asm src/generated_vic20.inc | build
	$(CA65) --listing build/vic20_worker.lst -o build/vic20_worker.o src/vic20_worker.asm

build/vic20_worker.prg: build/vic20_worker.o src/generated_vic20.cfg | build
	$(LD65) -C src/generated_vic20.cfg -o build/vic20_worker.prg build/vic20_worker.o --mapfile build/vic20_worker.map

build/vic20_worker.bin: build/vic20_worker.prg | build
	tail -c +3 build/vic20_worker.prg > build/vic20_worker.bin

build/vic20_bench.bas: src/vic20_benchmark.bas.in build/vic20_drive.bin build/vic20_worker.prg tools/make_vic20_basic.py tools/config.py | build
	mkdir -p build/vic20
	cp build/vic20_drive.bin build/vic20/drive_image.bin
	$(PYTHON) tools/make_vic20_basic.py --mode local
	mv build/vic20/vic20.bas build/vic20_bench.bas
	rm -rf build/vic20

build/vic20_bench_body.prg: build/vic20_bench.bas | build
	$(PETCAT) -w2 -o build/vic20_bench_body.prg -- build/vic20_bench.bas

build/vic20_bench.prg: build/vic20_bench_body.prg build/vic20_drive.bin build/vic20_worker.prg tools/make_vic20_basic.py | build
	mkdir -p build/vic20
	cp build/vic20_drive.bin build/vic20/drive_image.bin
	cp build/vic20_bench_body.prg build/vic20/benchmark_body.prg
	$(PYTHON) tools/make_vic20_basic.py --mode local --package
	mv build/vic20/benchmark.prg build/vic20_bench.prg
	rm -rf build/vic20

build/vic20_bench.d64: build/vic20_bench.prg | build
	rm -f build/vic20_bench.d64
	$(C1541) -format "vic20bench,01" d64 build/vic20_bench.d64 -write build/vic20_bench.prg vic20bench

vic20: build/vic20_bench.prg build/vic20_worker.bin build/vic20_drive.bin

vic20-disk: build/vic20_bench.d64


build/vic20u_bench.bas: src/vic20u_benchmark.bas.in build/vic20_drive.bin tools/make_vic20u_basic.py tools/config.py | build
	$(PYTHON) tools/make_vic20u_basic.py

build/vic20u_bench_body.prg: build/vic20u_bench.bas | build
	$(PETCAT) -w2 -o build/vic20u_bench_body.prg -- build/vic20u_bench.bas

build/vic20u_bench.prg: build/vic20u_bench_body.prg build/vic20_drive.bin tools/make_vic20u_basic.py | build
	$(PYTHON) tools/make_vic20u_basic.py --package

build/vic20u_bench.d64: build/vic20u_bench.prg | build
	rm -f build/vic20u_bench.d64
	$(C1541) -format "vic20u,01" d64 build/vic20u_bench.d64 -write build/vic20u_bench.prg vic20u

vic20u: build/vic20u_bench.prg build/vic20_drive.bin

vic20u-disk: build/vic20u_bench.d64

# Unexpanded VIC-20 pure-assembly variant.
# It produces one PRG: BASIC SYS stub + 6502 host + local VIC worker + embedded
# compact 1541 drive image. Runtime I/O goes through KERNAL calls.
src/generated_vic20u_asm.inc build/vic20u_asm_drive.bin: build/vic20_drive.bin tools/make_vic20u_asm_inc.py tools/config.py | build
	$(PYTHON) tools/make_vic20u_asm_inc.py

build/vic20u_asm.o: src/vic20u_asm.asm src/generated_vic20u_asm.inc build/vic20u_asm_drive.bin | build
	$(CA65) -I . --listing build/vic20u_asm.lst -o build/vic20u_asm.o src/vic20u_asm.asm

build/vic20u_asm.prg: build/vic20u_asm.o src/vic20u_asm.cfg tools/report_vic20u_asm_size.py | build
	$(LD65) -C src/vic20u_asm.cfg -o build/vic20u_asm.prg build/vic20u_asm.o --mapfile build/vic20u_asm.map
	$(PYTHON) tools/report_vic20u_asm_size.py build/vic20u_asm.prg build/vic20u_asm_drive.bin build/vic20u_asm.map

build/vic20u_asm.d64: build/vic20u_asm.prg | build
	rm -f build/vic20u_asm.d64
	$(C1541) -format "vic20ua,01" d64 build/vic20u_asm.d64 -write build/vic20u_asm.prg vic20ua

vic20u-asm: build/vic20u_asm.prg

vic20u-asm-disk: build/vic20u_asm.d64


# Unexpanded VIC-20 C variant.
# This is a cc65 C counterpart of vic20u_asm: BASIC SYS stub from the cc65
# runtime, C host/scheduler, local VIC worker, and embedded compact 1541 image.
src/generated_vic20uc.h src/generated_vic20uc_segments.s build/vic20uc_drive.bin build/vic20ucdrv.prg: build/vic20_drive.bin tools/make_vic20uc_inc.py tools/config.py | build
	$(PYTHON) tools/make_vic20uc_inc.py

build/vic20uc.s: src/vic20uc.c src/generated_vic20uc.h | build
	$(CC65) -t vic20 -Oirs --add-source -o build/vic20uc.s src/vic20uc.c

build/vic20uc.o: build/vic20uc.s | build
	$(CA65) -t vic20 --listing build/vic20uc.lst -o build/vic20uc.o build/vic20uc.s

build/vic20uc_startup.o: src/vic20uc_startup.s | build
	$(CA65) -t vic20 --listing build/vic20uc_startup.lst -o build/vic20uc_startup.o src/vic20uc_startup.s

build/vic20uc_kernal.o: src/vic20uc_kernal.s | build
	$(CA65) -t vic20 --listing build/vic20uc_kernal.lst -o build/vic20uc_kernal.o src/vic20uc_kernal.s

build/vic20uc_math.o: src/vic20uc_math.s | build
	$(CA65) -t vic20 --listing build/vic20uc_math.lst -o build/vic20uc_math.o src/vic20uc_math.s

build/vic20uc_segments.o: src/generated_vic20uc_segments.s | build
	$(CA65) -t vic20 --listing build/vic20uc_segments.lst -o build/vic20uc_segments.o src/generated_vic20uc_segments.s


clean-vic20:
	rm -rf build/vic20 build/vic20_* build/vic20u_* build/vic20uc* build/vic20_worker.o build/vic20_worker.prg build/vic20_worker.bin build/vic20_worker.map src/generated_vic20.inc src/generated_vic20.cfg src/generated_vic20u_asm.inc src/generated_vic20uc.h src/generated_vic20uc_segments.s
# -----------------------------------------------------------------------------


# --- VIC20UC dual variants ---
.PHONY: vic20uc-u vic20uc-3k vic20uc-u-disk vic20uc-3k-disk vic20uc-variants vic20uc-variant-disks

vic20uc-u: build/vic20uc_u.prg
vic20uc-3k: build/vic20uc_3k.prg
vic20uc-u-disk: build/vic20uc_u.d64
vic20uc-3k-disk: build/vic20uc_3k.d64
vic20uc-variants: build/vic20uc_u.prg build/vic20uc_3k.prg
vic20uc-variant-disks: build/vic20uc_u.d64 build/vic20uc_3k.d64

build/vic20uc_u_startup.o: src/vic20uc_startup.s src/vic20uc_u.cfg | build
	$(CA65) -t vic20 --listing $(@:.o=.lst) -o $@ src/vic20uc_startup.s

build/vic20uc_3k_startup.o: src/vic20uc_startup.s src/vic20uc_3k.cfg | build
	$(CA65) -t vic20 -D VIC20UC_3K=1 --listing $(@:.o=.lst) -o $@ src/vic20uc_startup.s

build/vic20uc_u.prg: build/vic20uc_u_startup.o build/vic20uc_kernal.o build/vic20uc_math.o build/vic20uc_segments.o build/vic20uc.o src/vic20uc_u.cfg src/generated_vic20uc.h src/generated_vic20uc_segments.s build/vic20uc_drive.bin build/vic20ucdrv.prg tools/report_vic20uc_size.py | build
	$(CL65) -t vic20 -C src/vic20uc_u.cfg -m build/vic20uc_u.map -o build/vic20uc_u.prg build/vic20uc_u_startup.o build/vic20uc_kernal.o build/vic20uc_math.o build/vic20uc_segments.o build/vic20uc.o
	$(PYTHON) tools/report_vic20uc_size.py build/vic20uc_u.prg build/vic20uc_drive.bin build/vic20uc_u.map 0x1001 0x1DFF

build/vic20uc_3k.prg: build/vic20uc_3k_startup.o build/vic20uc_kernal.o build/vic20uc_math.o build/vic20uc_segments.o build/vic20uc.o src/vic20uc_3k.cfg src/generated_vic20uc.h src/generated_vic20uc_segments.s build/vic20uc_drive.bin build/vic20ucdrv.prg tools/report_vic20uc_size.py | build
	$(CL65) -t vic20 -C src/vic20uc_3k.cfg -m build/vic20uc_3k.map -o build/vic20uc_3k.prg build/vic20uc_3k_startup.o build/vic20uc_kernal.o build/vic20uc_math.o build/vic20uc_segments.o build/vic20uc.o
	$(PYTHON) tools/report_vic20uc_size.py build/vic20uc_3k.prg build/vic20uc_drive.bin build/vic20uc_3k.map 0x0401 0x1DFF

build/vic20uc_u.d64: build/vic20uc_u.prg build/vic20ucdrv.prg | build
	rm -f build/vic20uc_u.d64
	$(C1541) -format "vic20uc,01" d64 build/vic20uc_u.d64 -write build/vic20uc_u.prg vic20uc -write build/vic20ucdrv.prg vic20ucdrv

build/vic20uc_3k.d64: build/vic20uc_3k.prg build/vic20ucdrv.prg | build
	rm -f build/vic20uc_3k.d64
	$(C1541) -format "vic20uc,01" d64 build/vic20uc_3k.d64 -write build/vic20uc_3k.prg vic20uc -write build/vic20ucdrv.prg vic20ucdrv
# --- end VIC20UC dual variants ---

.PHONY: clean
clean:
	rm -f $(GENERATED_FILES)
	@mkdir -p build
	@find build -mindepth 1 -maxdepth 1 -exec rm -rf {} +
