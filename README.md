# Axiom

[![License: Axiom SAL 1.0](https://img.shields.io/badge/License-Axiom_SAL_1.0-blue.svg)](LICENSE)

Integrity proof engine for AI-generated software logic.



## What is Axiom?

Axiom provides deterministic verification results and local replay-bound verification artifacts within supported kernel verification scope, using bounded model checking (BMC), CEGAR, and a dual-assurance path (Z3 SMT + Lean 4 replay). It does not constitute a full formal proof of correctness for all program properties.

**Interpretation rule**: Unsupported or invalid input → documented non-success (non-zero exit code family; `INVALID_INPUT=3` is the post-v1 target, currently emitted as exit 1) → **not** a verification claim. `result.status` post-v1 semantics are preserved as-is.

## Quick Start

```bash
# Prerequisites
# - Nim 2.2.10+ (https://nim-lang.org/install.html)
# - Lean 4.29.0+ (https://leanprover.github.io/lean4/doc/quickstart.html)
# - Z3 4.13+ (https://github.com/Z3Prover/z3)

# Install
nimble install

# Run
ax prove --limit 1      # verify top-priority kernel symbols (bounded)
ax report --json        # machine-readable report (schemaVersion: axiom.report.v1)
ax cert verify <cert.json>  # verify a certificate against the local trust journal
ax help                 # full command surface
```

> **제품 범위**: bounded preview — 실제 measured coverage는 `ax report --json`의 `metrics.vkd`를 참조하세요.

## Status

| Phase | Description | Status |
|-------|-------------|--------|
| Phase 1 | BMC Fast-Path (SWAT) — Z3 SMT-LIB2 bounded model checking | ✅ Implemented (v1 scope) |
| Phase 2 | CEGAR Loop (Detective + Legislator) — CE analysis + LLM invariant drafting | ✅ Implemented (v1 scope) |
| Phase 3 | Scribe + K-Induction — LLM theorem generation with k-induction fallback | ✅ Implemented (v1 scope) |
| Phase 4 | Judge + Kernel Verification — Lean 4 replay, vacuity check, tactic backtrack (dual-assurance: Z3 + Lean) | ✅ Implemented (v1 scope) |

## Architecture

```
src/
├── core/           Domain — pure calculation, types, BMC engine
├── verification/   Infrastructure — Lean LSP, Z3 bridge, CEGAR, certificates
├── cli/            Presentation — CLI entry point
├── mcp/            Presentation — MCP protocol extension
├── ui/             Presentation — TUI reporter
├── gate/           Gate — static analysis enforcement (nimtry)
├── personas/       Verification personas (Judge, Detective, Scribe, Legislator, SWAT)
├── sieve/          Subjective Logic signal classification
├── frontend/       Language frontends (Nim, extensible)
└── translator/     SMT-LIB ↔ Lean translation
```

## Development

```bash
# Build
nim c src/cli/main.nim

# Run gates (pre-commit)
bin/run-gate

# Run tests
nim c -r tests/gateway/all_gateway_runner.nim
```

## Documentation

- [AGENTS.md](AGENTS.md) — Agent operation guide and project policy
- [docs/spec/](docs/spec/) — Technical specifications
- [docs/history/](docs/history/) — Decision records
- [docs/spec/certified_patterns/](docs/spec/certified_patterns/) — Lean 4 verified patterns

## License

Copyright © 2026 Suhyok Yoon. All rights reserved, subject to the permissions expressly granted under the license.

Axiom is distributed under the **Axiom Source-Available License 1.0** (`LicenseRef-Axiom-SAL-1.0`) — see [LICENSE](LICENSE) for the full license text.

- Verification of Public Source Code is free for both personal and commercial use (§1.1).
- Commercial, organizational, or production verification of Private Source Code requires a Commercial Agreement (§1.2).
- An exception applies for non-commercial personal use (§1.3).
- Competing services require separate authorization (§2).
- Third-party materials are licensed under their respective licenses — see [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).

Historical license note: during a brief public-availability window early in the repository's history (from 2026-03-15 to 2026-03-23, under repository names including "Archright/Devlog" and "Archright/Axiom"), this project was publicly distributed under the Apache License 2.0. Rights lawfully granted under the Apache License 2.0 during that window remain unaffected. Current and future versions are distributed under the Axiom Source-Available License 1.0.

## Contact

Licensing and commercial inquiries: please contact the project through this GitHub repository — open an issue, or reach the repository owner via their GitHub profile.
