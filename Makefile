PYTHON ?= python3
IVERILOG ?= iverilog
VVP ?= vvp
WIDTH ?= 32
HEIGHT ?= 24
SEED ?= 42
RANDOM_COUNT ?= 200
WAVES ?= 0
SCENE ?= examples/overlap.json
BUILD := build/$(WIDTH)x$(HEIGHT)

.PHONY: test vectors test-renderer render regression clean

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

$(BUILD)/renderer.vvp: rtl/triangle_rasterizer.sv rtl/gpu_renderer.sv sim/tb_renderer.sv Makefile
	mkdir -p "$(BUILD)"
	$(IVERILOG) -g2012 -Wall -s tb_renderer \
		-Ptb_renderer.WIDTH=$(WIDTH) -Ptb_renderer.HEIGHT=$(HEIGHT) -o "$@" $(filter %.sv,$^)

test-renderer: $(BUILD)/renderer.vvp
	$(PYTHON) sim/render_reference.py --output "$(BUILD)/renderer-tests.txt" \
		--width $(WIDTH) --height $(HEIGHT) --seed $(SEED)
	cd "$(BUILD)" && $(VVP) renderer.vvp +VECTORS=renderer-tests.txt $(if $(filter 1,$(WAVES)),+WAVES)

render: $(BUILD)/renderer.vvp
	$(PYTHON) sim/render_reference.py --output "$(BUILD)/scene.txt" \
		--width $(WIDTH) --height $(HEIGHT) --seed $(SEED) --scene "$(SCENE)"
	cd "$(BUILD)" && $(VVP) renderer.vvp +VECTORS=scene.txt +PPM=frame.ppm $(if $(filter 1,$(WAVES)),+WAVES)

regression:
	$(MAKE) test WIDTH=32 HEIGHT=24 SEED=42
	$(MAKE) test WIDTH=32 HEIGHT=24 SEED=2027
	$(MAKE) test WIDTH=1 HEIGHT=1 RANDOM_COUNT=25
	$(MAKE) test WIDTH=128 HEIGHT=128 RANDOM_COUNT=25
	$(MAKE) test-renderer WIDTH=32 HEIGHT=24 SEED=42
	$(MAKE) test-renderer WIDTH=9 HEIGHT=7 SEED=2027
	$(MAKE) test-renderer WIDTH=1 HEIGHT=1

clean:
	rm -rf build
