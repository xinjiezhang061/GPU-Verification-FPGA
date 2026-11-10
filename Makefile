PYTHON ?= python3
IVERILOG ?= iverilog
VVP ?= vvp
WIDTH ?= 32
HEIGHT ?= 24
SEED ?= 42
RANDOM_COUNT ?= 200
WAVES ?= 0
BUILD := build/$(WIDTH)x$(HEIGHT)

.PHONY: test vectors regression clean

test: vectors $(BUILD)/rasterizer.vvp
	cd "$(BUILD)" && $(VVP) rasterizer.vvp +VECTORS=vectors.txt +SEED=$(SEED) $(if $(filter 1,$(WAVES)),+WAVES)

vectors:
	mkdir -p "$(BUILD)"
	$(PYTHON) sim/reference.py --output "$(BUILD)/vectors.txt" --seed $(SEED) \
		--random-count $(RANDOM_COUNT) --width $(WIDTH) --height $(HEIGHT)

$(BUILD)/rasterizer.vvp: rtl/triangle_rasterizer.sv sim/tb_rasterizer.sv Makefile
	mkdir -p "$(BUILD)"
	$(IVERILOG) -g2012 -Wall -s tb_rasterizer \
		-Ptb_rasterizer.WIDTH=$(WIDTH) -Ptb_rasterizer.HEIGHT=$(HEIGHT) -o "$@" $(filter %.sv,$^)

regression:
	$(MAKE) test WIDTH=32 HEIGHT=24 SEED=42
	$(MAKE) test WIDTH=32 HEIGHT=24 SEED=2027
	$(MAKE) test WIDTH=1 HEIGHT=1 RANDOM_COUNT=25
	$(MAKE) test WIDTH=128 HEIGHT=128 RANDOM_COUNT=25

clean:
	rm -rf build
