# Filesystem Migration Baseline — 2026-08-18

> **Status: HISTORICAL / NON-NORMATIVE**
>
> 이 문서는 `docs/spec/filesystem_contract.md`(normative) 정의 직전의 **마이그레이션 기준 스냅샷**이다.
> 허용 목록으로 읽지 말 것. Normative 규칙은 Contract V1의 allowed/forbidden/state 명시적 테이블이다.
> 이 스냅샷은 Contract 이행 전 상태를 기록한 evidence일 뿐이다.

## Baseline 정보

- **HEAD**: `b1483a6e3d3780980f7e8b01aa824f4a48513ac6`
  `feat(readiness): H1 fresh evidence R1-R8 normalization + CONDITIONAL GO decision + report`
- **Date**: 2026-08-18
- 사전 상태: `git rm CONTRIBUTING.md QUICKSTART.md` 실행됨 (staged deletion, 미커밋)

## 루트 인벤토리 (pre-migration)

### Tracked 루트 엔트리

`AGENTS.md` `Dockerfile.build` `LICENSE` `Makefile` `README.md`
`axiom.lock` `axiom.nimble` `axiom.toml` `config.nims` `flake.nix`
`lake-manifest.json` `lakefile.toml` `lean-toolchain` `lfs_exceptions.json`
`nimble.lock` `promotion_intent.json` `proof_universe.lock`
`topology.json` `topology.lock` `topology_policy.json`
`.axiom_root` `.cursorrules` `.dockerignore` `.editorconfig`
`.env.example` `.envrc` `.envrc.example` `.gitattributes` `.gitignore`
`benchmarks/` `config/` `data/` `docs/` `logs/` `proofs/` `src/`
`templates/` `tests/` `tools/`
`.config/` `.githooks/` `.github/` `.opencode/` `.aws/`(nol)
`debug_real.nims` `deferred_migration.json`

### Untracked (비-ignored) 루트 아래

- `data/readiness/decision.2026-08-18.json` (readiness CONDITIONAL GO 산출물)
- `data/readiness/decision.2026-08-18.recovery.json`
- staged deletions: `CONTRIBUTING.md`, `QUICKSTART.md` — 사용자 요청으로 삭제 대기

### Ignored 루트 엔트리

`.axiom/` `.cache/` `.lake` `.nimcache/` `bin/` `build/` `cli/`
`config.json` `deps/` `nimcache/` `nimble.paths` `opencode.json`
`tmp/` `trusted/` `vendor/` (+ `logs/` 일부, `data/` 일부 ignored 규칙)

## 디렉터리별 상태 요약

| Entry      | Tracked | Contents                                   |
|------------|---------|--------------------------------------------|
| `bin/`     | 0       | 1056 ELF executables, 0 tracked, whitelist 규칙 |
| `build/`   | 0       | generated build state                      |
| `logs/`    | 1       | `logs/audit/tier_classification.json` tracked, 나머지 ignored |
| `cli/`     | 0       | `main`(7.2MB) + `run_gate`(125KB) ELF — generated |
| `benchmarks/` | 2    | tracked: `perf_budget.json`, `perf_latest.json`; untracked: `perf_baseline.json`, `report.html`, `tier_stats.json` |
| `trusted/` | 0       | journal 포함 bundle, 전체 ignored (`trusted/journal/`) |
| `templates/` | 7    | tracked, 참조자 0 |
| `tmp/`     | 0       | 2711 files / 64MB, ignored |
| `deps/`    | 0       | `deps/bin/drnim` 단독, 참조 0 |
| `nimcache/` `.nimcache/` `.lake` | 0 | regen 가능 build cache |
| `vendor/`  | 0       | ed25519 + z3, 전체 ignored |

## 마이그레이션 방향 (이 문서가 아닌 Contract가 권위)

- `cli/` → `bin/` 실행 표면 통합 (canonical: `bin/ax`, `bin/run_gate`, `bin/axiom-gate`)
- `benchmarks/` → `data/benchmarks/`
- `trusted/` → `data/trusted/` (tracking/lifetime 규칙 불변: I2)
- `templates/` → `docs/templates/`
- 삭제: `tmp/` `deps/` `nimcache/` `.nimcache/` `.lake` `debug_real.nims` `deferred_migration.json`