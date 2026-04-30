# embed-zig examples

[![CI](https://github.com/embed-zig/examples/actions/workflows/ci.yml/badge.svg)](https://github.com/embed-zig/examples/actions/workflows/ci.yml)

Host-side example apps and integration tests for [embed-zig](https://github.com/embed-zig/embed-zig). Package manifests are committed directly and share the same `embed_zig` dependency version.

## Requirements

- Zig **0.15.2**

## Quick start

```bash
zig build test
```

CI runs `zig build test` on Linux, macOS, and Windows.

## ESP builds

ESP matrix builds are separate from the default `zig build test` flow and need ESP-IDF; see `esp/` and the root `zig build esp` step when `-Didf=...` is set.