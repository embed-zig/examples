# Build and run the standalone Zig ZON generator.
# The generator installs its binary under `.build/gen_zon_files/` and writes staged outputs under
# `.build/`, then mirrors package `build.zig.zon` files into their package roots.

.DEFAULT_GOAL := all

.PHONY: all zon build.zig.zon esp/build.zig.zon desktop/build.zig.zon

ZIG ?= zig
GEN_ZON_BUILD_FILE := tools/gen_zon_files/build.zig
GEN_ZON_PREFIX := .build/gen_zon_files
GEN_ZON_ARGS := --repo-root . --build-dir .build

all: zon

zon:
	ZIG=$(ZIG) $(ZIG) build gen --build-file $(GEN_ZON_BUILD_FILE) --prefix $(GEN_ZON_PREFIX) -- $(GEN_ZON_ARGS)

build.zig.zon esp/build.zig.zon desktop/build.zig.zon: zon
	@:
