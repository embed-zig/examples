# embed-zig examples

[CI](https://github.com/embed-zig/examples/actions/workflows/ci.yml)

Host-side example apps and integration tests for [embed-zig](https://github.com/embed-zig/embed-zig). Generated manifests and `build.zig.zon` files are produced by `make` (see `tools/gen_zon_files/`).

## Requirements

- Zig **0.15.2** (see `tools/gen_zon_files/package.json` → `zon.minimum_zig_version`)
- `make`

## Quick start

```bash
make
zig build test
```

`make` runs the ZON/manifest generator and refreshes fingerprints as needed. CI runs the same `make` check on Ubuntu, then `zig build test` on Linux, macOS, and Windows.

## ESP builds

ESP matrix builds are separate from the default `zig build test` flow and need ESP-IDF; see `esp/` and the root `zig build esp` step when `-Didf=...` is set.