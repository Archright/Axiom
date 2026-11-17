# E5 — 제3자 재현: 동일 증거 → 동일 판정·동일 decisionDigest (콜드 레인)

> DEBT#537 청산 증거 체인의 E5. 스펙 §6 절차를 축어 미러한 독립 재현 — 워크플로
> 증거 artifact를 별도 워크트리에 복원하고, 콜드 빌드·게이트 재실행으로 판정을
> 재계산해 업로드된 판정과 비교한다. 원본 관측: `raw/replay_result.json`,
> `raw/replay_provenance.txt`.

## §1. 절차 (워크플로 readiness-verdict 잡의 콜드 레인 축어 미러)

1. **체크아웃**: `git worktree add --detach /tmp/replay_wt e3ec8ae…` (production run
   43911956696의 head — run-manifest `gitHead`와 일치).
2. **증거 복원**: artifact `readiness-verdict-evidence`의 `data/readiness/evidence/R1–R8.json`,
   `logs/run-manifest.json`, `logs/r3_relocation.json(+.sha256)`를 원래 경로에 복원
   (참조 decision `build/readiness_start_decision.json`은 별도 보존 — 게이트가 새로 쓴다).
3. **콜드 서플라이**: `build/nimcache`·`.axiom/cache`·`proofs/.lake`·`proofs/build`·
   B-layer fingerprint·4개 바이너리 purge → `make ci-compile -j4` →
   `AXIOM_ROOT= bin/ax --check-provenance`.
4. **게이트**: `AXIOM_HERMETIC_BUILDING=1 nim c …readiness_start_gate` →
   `AXIOM_CI=1 AXIOM_CI_PRESERVE_CACHE=1 AXIOM_CI_REPO_HEAD=e3ec8ae… AXIOM_CI_TREE_DIGEST=$(git ls-tree -r HEAD | sha256sum) ./bin/readiness_start_gate`.
5. **비교**: verdict·conditions·decisionDigest(+ evaluationTime 제외 전필드).

## §2. 관측 (2026-11-16 UTC)

| 항목 | 관측값 |
|---|---|
| identity | HEAD == `e3ec8ae…` == AXIOM_CI_REPO_HEAD; 사전 dirty = 복원 증거 8개 파일뿐(전부 §4.6 제외 경로) |
| supply verify | `AXIOM_PROVENANCE: OK — embedded BuildSourceHash == live src tree (vs1-tree-hash/1:5894238184686856199)` == run-manifest `.sourceTree.buildSourceHash` (콜드 레인 의미 결속 — per-TREE, never per-byte) |
| 게이트 exit | 0 (판정 CONDITIONAL GO → 허용) |
| 판정 | **CONDITIONAL GO**, conditions `[R7=FAIL]` |
| **decisionDigest** | `0bcb25bd79286b356ee382278acf55a60f9eac9f381883a6e61a0ec318f1377b` — **업로드된 판정과 동일** |
| 전필드 비교 | evaluationTime 제외 **decision json 전체 동일**(byte-level) |
| 유효기간 | 재평가 시점 2026-11-16T17:22:43Z < freshUntil 2026-12-16 (스펙 §6 validity 축) |

## §3. 증명하는 것

동일 증거 + 동일 트리 + 동일 환경 → **동일 판정·동일 digest**. 게이트의 순수성만이
아니라, 증거가 트리에 결속되고(run-manifest buildSourceHash 대조) 재현자가 독립
빌드로 같은 결론에 도달한다는 것(스펙 §1 Replay 단계)을 실증한다. decisionDigest의
preimage가 판정 의미 필드(verdict·conditions·invariantStates)만 포함하므로
evaluationTime 차이는 재현 무결성을 침해하지 않는다(스펙 §6 정의).
