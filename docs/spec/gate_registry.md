# Gate Registry

## Overview

The gate registry is the SSOT for all gates in the Axiom quality gate chain.
It is built entirely at **compile time** from two sources:

1. **`src/gate/manifest.d/*.json`** — 81 individual per-gate JSON files + `_index.json`, loaded at compile time by `gate_codegen.nim` via `slurp()`
2. **`src/gate/runners/*.nim`** — runner files discovered via `gorge()`

> **Historical note:** The old monolithic single-file gate manifest has been
> deleted. Gate registration now uses the per-gate JSON files under
> `src/gate/manifest.d/`. This document has been updated to reflect the current
> architecture.

## Manifest Format

Each gate is defined in its own JSON file under `src/gate/manifest.d/`. The
`_index.json` file lists all gate JSON filenames (one per line) and serves as
the master index for compile-time slurping.

Example gate file (`src/gate/manifest.d/nim-check.json`):

```json
{
  "id": "nim-check",
  "name": "Axiom nim check gate",
  "layer": "functional",
  "entry": "bin/nim_check_gate",
  "stages": [
    "pre-commit"
  ],
  "filesPattern": ".nim|axiom.nimble|config.nims",
  "passFilenames": true,
  "weight": "heavy",
  "argsTemplate": [
    "$repoRoot",
    "$mode",
    "$maxJobs"
  ],
  "depsDirs": [
    "bin/nim_check_gate"
  ],
  "tier": 2
}
```

### Required Fields

| Field | Type | Description |
|-------|------|-------------|
| `id` | string | Unique gate identifier (must be lexicographically sorted within `_index.json`) |
| `name` | string | Human-readable name |
| `layer` | string | `"meta"` (L1) or `"functional"` (L2) |
| `entry` | string | Path to runner binary/source (e.g. `src/gate/runners/my_gate`) |
| `stages` | string[] | Subset of `["pre-commit", "pre-push", "manual", "ci"]` |
| `weight` | string | `"light"`, `"medium"`, or `"heavy"` |

### Optional Fields

| Field | Type | Description |
|-------|------|-------------|
| `filesPattern` | string | Regex/pipe-delimited pattern for changed-file matching |
| `passFilenames` | bool | Whether filenames are passed as arguments |
| `envVars` | array | `[{name: string, value: string}]` environment variables |
| `argsTemplate` | string[] | CLI argument template (e.g. `["$repoRoot", "$mode"]`) |
| `depsDirs` | string[] | Dependency directories for Merkle cache when `entry=""` |
| `tier` | int | Priority tier for ordering |

## How `gate_codegen.nim` Works

### Compile-Time Loading

`gate_codegen.nim` reads all gate definitions at compile time using Nim's
`slurp()` function:

```nim
# 1. Read the index file listing all gate JSON filenames
let indexContent = slurp("src/gate/manifest.d/_index.json")

# 2. For each entry, slurp the individual gate JSON file
let path = "src/gate/manifest.d/" & f
let content = slurp(path)
```

`slurp` is the Nim compile-time equivalent of `staticRead` — both read files
into string constants at compile time. `slurp` is used here because it creates
compile-time file dependencies, which means `config.nims` regenerates
`_index.json` before compilation when any `manifest.d` file changes.

No runtime file I/O is needed — all gate data is embedded as compile-time
constants.

### Runner Discovery

```nim
const DiscoveredRunnersRaw = gorge("ls src/gate/runners/*.nim 2>/dev/null || true")
```

`gorge()` executes a shell command at compile time. During `nim check` the
Nim VM does not spawn shells, so this returns empty. During `nim c`, the full
runner list is available for bidirectional verification.

### Gate Construction

The `AllGatesSorted` constant is built in a `block:` expression that:

1. Parses the embedded JSON from each gate file
2. Iterates over all entries from `_index.json`
3. Maps string enums to Nim enums (`GateStage`, `GateLayer`, `GateWeight`)
4. Constructs `GateConfig` objects
5. Sorts by `cmpGateIdPriority` (id ascending, then priority descending)

### Public API

```nim
func allGates*(): seq[GateConfig]
```

Returns the sorted gate list. All gate consumers MUST use this function.

## Adding a New Gate

1. Create the runner file in `src/gate/runners/` (or use an existing `bin/` binary).
2. Create a new JSON file in `src/gate/manifest.d/` with all required fields.
   Use an existing gate JSON file as a template.
3. Add the filename to `src/gate/manifest.d/_index.json` in lexicographic order.
4. Run `nim c --hints:off -o:/tmp/test src/gate/gate_registry.nim` to verify
   compilation and bidirectional verification.
5. Run the manifest consistency gate:
   `nim c -r --hints:off src/gate/runners/manifest_consistency_gate.nim`

## 게이트 등록 워크플로 (결정론적 자동화)

`_index.json`은 수동 편집이 **금지**된 생성 파일이다. 단일 진실 원천(SSOT)은
`src/gate/manifest.d/<gate-id>.json` 개별 매니페스트 파일이며,
`_index.json`은 항상 이 디렉터리의 스냅숏이다.

### 절차

1. **매니페스트 생성**: `src/gate/manifest.d/<gate-id>.json` 파일을 작성한다.
   기존 JSON 파일을 템플릿으로 사용한다.
2. **인덱스 재생성**: `nim r tools/regen_index.nim`을 실행한다.
   이 도구는 `walkDir("src/gate/manifest.d")`로 모든 `*.json` 파일을 수집하고
   (`_index.json` 제외), `sort()`한 후 `_index.json`에 덮어쓴다.
   결과는 항상 결정론적(lexicographic order)이다.
3. **빌드 검증**: 빌드 파이프라인의 manifest-hygiene-gate가
   `_index.json`과 `manifest.d/*.json`의 일치 여부(해시/개수)를 자동 검증한다.

### 경고

`_index.json`을 수동으로 편집하면 SSoT 드리프트가 발생한다.
편집 내용은 다음 `nim r tools/regen_index.nim` 실행 시 무조건 덮어써지며,
빌드 무결성 검증에서도 실패한다. **절대 수동 편집하지 말 것.**

## Architecture Assertions

The registry enforces these compile-time invariants:

- **L1→L0 Boundary**: Meta gates cannot reference `gate_hook` or `pre-commit`.
- **Pre-commit Time Budget**: Heavy gates cannot run in pre-commit (< 10s budget).
- **Pre-push Weight**: Functional gates in pre-push must have `weight >= medium`.
- **depsDirs Requirement**: Functional gates with empty `entry` must have `depsDirs`.
- **Sort Stability**: Double-sort produces identical ordering.
- **Unique IDs**: No duplicate gate definitions.
- **Bidirectional Verification**: Every manifest runner entry has a `.nim` file;
  every gate-like runner file has a manifest entry.
