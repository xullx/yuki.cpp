# YUKI directory structure

`C:\Yuki` is the single canonical YUKI root.

## Source and runtime

There is no separate `app` copy.

`src` contains the editable source code that implements YUKI.
The same canonical source is used by the local runtime.

## Directories

- `src` - canonical Python and visualizer source code
- `launch` - PowerShell controller and service lifecycle
- `config` - runtime configuration and personality data
- `bin` - native executables used by YUKI
- `models` - local model weights
- `backends` - alternate/local inference backend installations
- `tools` - developer, diagnostic and benchmark utilities
- `benchmarks` - benchmark specifications and local benchmark data
- `benchmarks/spec` - source-controlled benchmark contracts
- `docs` - architecture and project documentation
- `third_party` - third-party notices and licenses
- `logs` - generated service logs
- `state` - generated runtime state
- `cache` - disposable runtime caches
- `archive` - retired implementations, migrations and backups

## Benchmark data

Generated benchmark data under `benchmarks/runs`,
`benchmarks/registry`, and `benchmarks/experiments` is local
and excluded from Git.

The benchmark architecture contract lives at:

`C:\Yuki\benchmarks\spec\architecture.json`

## Core local services

- 8083 - ASR
- 8084 - Brain
- 8085 - Visualizer
- 8086 - Voice TTS
- 8087 - Twitch TTS, on demand

## Canonical rule

New YUKI code must not be duplicated into an `app` directory or a
separate `Yuki-Source` tree. Source paths should resolve under
`C:\Yuki`.