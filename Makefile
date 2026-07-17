GENERATED_FILES := src/generated_*.cfg src/generated_*.inc src/generated_*.h src/generated_*.s build/*.lst

PYTHON=python3
CA65=ca65
LD65=ld65
PETCAT=petcat
C1541=c1541
CL65=cl65
CC65=cc65

all: c64 c64-disk build/vic20_c_u.d64 build/vic20_c_3k.d64 vic20-asm-u vic20-asm-u-disk vic20-asm-3k vic20-asm-3k-disk vic20-c-u vic20-c-u-disk vic20-c-3k vic20-c-3k-disk vic20-bas-u vic20-bas-u-disk vic20-bas-3k vic20-bas-3k-disk vic20-all-disk

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
.PHONY: c64 c64-disk vic20-bas-3k vic20-bas-3k-disk vic20-bas-u vic20-bas-u-disk clean-vic20 vic20-asm-u vic20-asm-u-disk vic20-asm-3k vic20-asm-3k-disk vic20-c-u vic20-c-u-disk vic20-c-3k vic20-c-3k-disk vic20-all-disk

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

build/vic20_bas_3k.bas: src/vic20_benchmark.bas.in build/vic20_drive.bin build/vic20_worker.prg tools/make_vic20_basic.py tools/config.py | build
	mkdir -p build/vic20
	cp build/vic20_drive.bin build/vic20/drive_image.bin
	$(PYTHON) tools/make_vic20_basic.py --mode local
	mv build/vic20/vic20.bas build/vic20_bas_3k.bas
	rm -rf build/vic20

build/vic20_bas_3k_body.prg: build/vic20_bas_3k.bas | build
	$(PETCAT) -w2 -o build/vic20_bas_3k_body.prg -- build/vic20_bas_3k.bas

build/vic20_bas_3k.prg: build/vic20_bas_3k_body.prg build/vic20_drive.bin build/vic20_worker.prg tools/make_vic20_basic.py | build
	mkdir -p build/vic20
	cp build/vic20_drive.bin build/vic20/drive_image.bin
	cp build/vic20_bas_3k_body.prg build/vic20/benchmark_body.prg
	$(PYTHON) tools/make_vic20_basic.py --mode local --package
	mv build/vic20/benchmark.prg build/vic20_bas_3k.prg
	rm -rf build/vic20

build/vic20_bas_3k.d64: build/vic20_bas_3k.prg | build
	rm -f build/vic20_bas_3k.d64
	$(C1541) -format "vic20b3k,01" d64 build/vic20_bas_3k.d64 -write build/vic20_bas_3k.prg vic20b3k

vic20-bas-3k: build/vic20_bas_3k.prg build/vic20_worker.bin build/vic20_drive.bin

vic20-bas-3k-disk: build/vic20_bas_3k.d64

build/vic20_bas_u.bas: src/vic20u_benchmark.bas.in build/vic20_drive.bin tools/make_vic20u_basic.py tools/config.py | build
	$(PYTHON) tools/make_vic20u_basic.py

build/vic20_bas_u_body.prg: build/vic20_bas_u.bas | build
	$(PETCAT) -w2 -o build/vic20_bas_u_body.prg -- build/vic20_bas_u.bas

build/vic20_bas_u.prg: build/vic20_bas_u_body.prg build/vic20_drive.bin tools/make_vic20u_basic.py | build
	$(PYTHON) tools/make_vic20u_basic.py --package

build/vic20_bas_u.d64: build/vic20_bas_u.prg | build
	rm -f build/vic20_bas_u.d64
	$(C1541) -format "vic20bu,01" d64 build/vic20_bas_u.d64 -write build/vic20_bas_u.prg vic20bu

vic20-bas-u: build/vic20_bas_u.prg build/vic20_drive.bin

vic20-bas-u-disk: build/vic20_bas_u.d64

# Unexpanded VIC-20 pure-assembly variant.
# It produces one PRG: BASIC SYS stub + 6502 host + local VIC worker + embedded
# compact 1541 drive image. Runtime I/O goes through KERNAL calls.
src/generated_vic20_asm.inc build/vic20_asm_drive.bin: build/vic20_drive.bin tools/make_vic20_asm_inc.py tools/config.py | build
	$(PYTHON) tools/make_vic20_asm_inc.py

# Unexpanded VIC-20 C variant.
# This is a cc65 C counterpart of vic20_asm: BASIC SYS stub from the cc65
# runtime, C host/scheduler, local VIC worker, and embedded compact 1541 image.
src/generated_vic20_c.h src/generated_vic20_c_segments.s build/vic20_c_drive.bin build/vic20_c_drv.prg: build/vic20_drive.bin tools/make_vic20_c_inc.py tools/config.py | build
	$(PYTHON) tools/make_vic20_c_inc.py

build/vic20_c_u.s: src/vic20_c.c src/generated_vic20_c.h | build
	$(CC65) -t vic20 -Oirs --add-source -o $@ src/vic20_c.c

build/vic20_c_3k.s: src/vic20_c.c src/generated_vic20_c.h | build
	$(CC65) -t vic20 -Oirs -D VIC20_C_3K=1 --add-source -o $@ src/vic20_c.c

build/vic20_c_u.o: build/vic20_c_u.s | build
	$(CA65) -t vic20 --listing build/vic20_c_u.lst -o $@ build/vic20_c_u.s

build/vic20_c_3k.o: build/vic20_c_3k.s | build
	$(CA65) -t vic20 --listing build/vic20_c_3k.lst -o $@ build/vic20_c_3k.s

build/vic20_c_startup.o: src/vic20_c_startup.s | build
	$(CA65) -t vic20 --listing build/vic20_c_startup.lst -o build/vic20_c_startup.o src/vic20_c_startup.s

build/vic20_c_kernal.o: src/vic20_c_kernal.s | build
	$(CA65) -t vic20 --listing build/vic20_c_kernal.lst -o build/vic20_c_kernal.o src/vic20_c_kernal.s

build/vic20_c_math.o: src/vic20_c_math.s | build
	$(CA65) -t vic20 --listing build/vic20_c_math.lst -o build/vic20_c_math.o src/vic20_c_math.s

build/vic20_c_segments.o: src/generated_vic20_c_segments.s | build
	$(CA65) -t vic20 --listing build/vic20_c_segments.lst -o build/vic20_c_segments.o src/generated_vic20_c_segments.s

clean-vic20:
	rm -rf build/vic20 build/vic20_* build/vic20u_* build/vic20uc* build/vic20_worker.o build/vic20_worker.prg build/vic20_worker.bin build/vic20_worker.map src/generated_vic20.inc src/generated_vic20.cfg src/generated_vic20_asm.inc src/generated_vic20_c.h src/generated_vic20_c_segments.s
# -----------------------------------------------------------------------------

# --- VIC20_C dual variants ---
.PHONY: vic20-c-u vic20-c-3k vic20-c-u-disk vic20-c-3k-disk vic20-asm-u vic20-asm-u-disk vic20-asm-3k vic20-asm-3k-disk vic20-bas-u vic20-bas-u-disk vic20-bas-3k vic20-bas-3k-disk vic20-all-disk

vic20-c-u: build/vic20_c_u.prg
vic20-c-3k: build/vic20_c_3k.prg
vic20-c-u-disk: build/vic20_c_u.d64
vic20-c-3k-disk: build/vic20_c_3k.d64
build/vic20_c_u_startup.o: src/vic20_c_startup.s src/vic20_c_u.cfg | build
	$(CA65) -t vic20 --listing $(@:.o=.lst) -o $@ src/vic20_c_startup.s

build/vic20_c_3k_startup.o: src/vic20_c_startup.s src/vic20_c_3k.cfg | build
	$(CA65) -t vic20 -D VIC20_C_3K=1 --listing $(@:.o=.lst) -o $@ src/vic20_c_startup.s

build/vic20_c_u.prg: build/vic20_c_u_startup.o build/vic20_c_kernal.o build/vic20_c_math.o build/vic20_c_segments.o build/vic20_c_u.o src/vic20_c_u.cfg src/generated_vic20_c.h src/generated_vic20_c_segments.s build/vic20_c_drive.bin build/vic20_c_drv.prg tools/report_vic20_c_size.py | build
	$(CL65) -t vic20 -C src/vic20_c_u.cfg -m build/vic20_c_u.map -o build/vic20_c_u.prg build/vic20_c_u_startup.o build/vic20_c_kernal.o build/vic20_c_math.o build/vic20_c_segments.o build/vic20_c_u.o
	$(PYTHON) tools/report_vic20_c_size.py build/vic20_c_u.prg build/vic20_c_drive.bin build/vic20_c_u.map 0x1001 0x1DFF

build/vic20_c_3k.prg: build/vic20_c_3k_startup.o build/vic20_c_kernal.o build/vic20_c_math.o build/vic20_c_segments.o build/vic20_c_3k.o src/vic20_c_3k.cfg src/generated_vic20_c.h src/generated_vic20_c_segments.s build/vic20_c_drive.bin build/vic20_c_drv.prg tools/report_vic20_c_size.py | build
	$(CL65) -t vic20 -C src/vic20_c_3k.cfg -m build/vic20_c_3k.map -o build/vic20_c_3k.prg build/vic20_c_3k_startup.o build/vic20_c_kernal.o build/vic20_c_math.o build/vic20_c_segments.o build/vic20_c_3k.o
	$(PYTHON) tools/report_vic20_c_size.py build/vic20_c_3k.prg build/vic20_c_drive.bin build/vic20_c_3k.map 0x0401 0x1DFF

build/vic20_c_u.d64: build/vic20_c_u.prg build/vic20_c_drv.prg | build
	rm -f build/vic20_c_u.d64
	$(C1541) -format "vic20cu,01" d64 build/vic20_c_u.d64 -write build/vic20_c_u.prg vic20cu -write build/vic20_c_drv.prg vic20ucdrv

build/vic20_c_3k.d64: build/vic20_c_3k.prg build/vic20_c_drv.prg | build
	rm -f build/vic20_c_3k.d64
	$(C1541) -format "vic20c3k,01" d64 build/vic20_c_3k.d64 -write build/vic20_c_3k.prg vic20c3k -write build/vic20_c_drv.prg vic20ucdrv
# --- end VIC20_C dual variants ---

.PHONY: clean vic20-asm-u vic20-asm-u-disk vic20-asm-3k vic20-asm-3k-disk vic20-c-u vic20-c-u-disk vic20-c-3k vic20-c-3k-disk vic20-bas-u vic20-bas-u-disk vic20-bas-3k vic20-bas-3k-disk vic20-all-disk
clean:
	rm -f $(GENERATED_FILES)
	@mkdir -p build
	@find build -mindepth 1 -maxdepth 1 -exec rm -rf {} +

# --- VIC20 ASM dual variants ---
.PHONY: vic20-asm-u vic20-asm-3k vic20-asm-u-disk vic20-asm-3k-disk vic20-c-u vic20-c-u-disk vic20-c-3k vic20-c-3k-disk vic20-bas-u vic20-bas-u-disk vic20-bas-3k vic20-bas-3k-disk vic20-all-disk

vic20-asm-u: build/vic20_asm_u.prg
vic20-asm-3k: build/vic20_asm_3k.prg
vic20-asm-u-disk: build/vic20_asm_u.d64
vic20-asm-3k-disk: build/vic20_asm_3k.d64

build/vic20_asm_u.o: src/vic20_asm.asm src/generated_vic20_asm.inc build/vic20_asm_drive.bin | build
	$(CA65) -I . -o $@ src/vic20_asm.asm

build/vic20_asm_3k.o: src/vic20_asm.asm src/generated_vic20_asm.inc build/vic20_asm_drive.bin | build
	$(CA65) -I . -D VIC20_ASM_3K=1 -o $@ src/vic20_asm.asm

build/vic20_asm_u.prg: build/vic20_asm_u.o src/vic20_asm_u.cfg tools/report_vic20_asm_size.py | build
	$(LD65) -C src/vic20_asm_u.cfg -o $@ build/vic20_asm_u.o --mapfile build/vic20_asm_u.map
	$(PYTHON) tools/report_vic20_asm_size.py $@ build/vic20_asm_drive.bin build/vic20_asm_u.map 0x1001 0x1E00

build/vic20_asm_3k.prg: build/vic20_asm_3k.o src/vic20_asm_3k.cfg tools/report_vic20_asm_size.py | build
	$(LD65) -C src/vic20_asm_3k.cfg -o $@ build/vic20_asm_3k.o --mapfile build/vic20_asm_3k.map
	$(PYTHON) tools/report_vic20_asm_size.py $@ build/vic20_asm_drive.bin build/vic20_asm_3k.map 0x0401 0x1E00

build/vic20_asm_u.d64: build/vic20_asm_u.prg | build
	rm -f $@
	$(C1541) -format "vic20asmu,01" d64 $@ -write build/vic20_asm_u.prg vic20asmu

build/vic20_asm_3k.d64: build/vic20_asm_3k.prg | build
	rm -f $@
	$(C1541) -format "vic20asm3k,01" d64 $@ -write build/vic20_asm_3k.prg vic20asm3k
# --- end VIC20 ASM dual variants ---

# --- VIC-20 all variants disk: begin ---
.PHONY: vic20-all-disk

vic20-all-disk: build/vic20_all.d64

build/vic20_all.d64: \
        build/vic20_bas_u.prg \
        build/vic20_bas_3k.prg \
        build/vic20_c_u.prg \
        build/vic20_c_3k.prg \
        build/vic20_asm_u.prg \
        build/vic20_asm_3k.prg \
        build/vic20_c_drv.prg | build
	rm -f $@
	$(C1541) -format "vic20all,01" d64 $@ \
		-write build/vic20_bas_u.prg vic20bu \
		-write build/vic20_bas_3k.prg vic20b3k \
		-write build/vic20_c_u.prg vic20cu \
		-write build/vic20_c_3k.prg vic20c3k \
		-write build/vic20_asm_u.prg vic20au \
		-write build/vic20_asm_3k.prg vic20a3k \
		-write build/vic20_c_drv.prg vic20ucdrv
# --- VIC-20 all variants disk: end ---
