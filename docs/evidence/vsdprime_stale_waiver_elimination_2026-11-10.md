# VS-δ′ stale waiver elimination — 3단계 착지·재검증 기록 (2026-11-10)

> **종류**: 착지·재검증 기록 (landing + re-verification record). VS-δ′(계획 mister-miracle-cable-hawkeye, 승인 2026-11-10)의 실행 결과를 기계 관측 원문으로 고정한다.
> **권위**: 본 문서는 기록이다 — 병합 판정 권위는 GitHub(ruleset `main` 26702792의 required checks + merge queue)이며, 본 문서는 그 어떤 판정도 대체하지 않는다(Authority ≠ Adapter, AGENTS.md §2.3). surface 판정은 advisory다(required 아님) — 이 구분은 §4에서 정밀화한다.
> **수치 표기 규약**: 모든 행은 관측된 명령 또는 `파일:행` 출처를 붙인다. PR·런 상태는 `gh` 관측 시점 값을 쓴다.

---

## 1. 결과 요약 (Terminal Outcome 관측)

- **Stage 1(정책 승격)**: PR #60 — `config/repository_surface.json` policyVersion v95→v96, CONTROLLED 2 exact 경로 등록. MERGE `e5c0ef5ecaf3d1a867e7b969449e153e17f2a402` (2026-11-10T04:41:25Z, merge queue 경유, 2-parent).
- **Stage 2(원자적 정리)**: PR #62 — stale waiver 9엔트리 제거 + 죽은 import 2줄 + 미사용 `sets`. MERGE `3368a696a051b310d752277ea92eadc556189c64` (2026-11-10T05:56:35Z, merge queue 경유, 2-parent).
- **Stage 3(main 재검증)**: merge SHA 체크아웃에서 §5의 재검증 전 세트 PASS + `bin/debt_engine --validate` EXIT=0 + §3-⑤ 우선순위 재실험 관측.

## 2. 신규 관측 — stale 9건은 2026-11-04 escalation survey가 놓친 것이었다

`config/decision_binding.waiver.json` `grandfather` 259건 중 9건이 대상 파일 미존재(트리 probe 실측). 2026-11-04 waiver escalation survey는 이 9건을 관측하지 못했다 — survey는 checker exit-code 경로만 봤고, checker는 waiver 대상 파일 존재를 검증하지 않기 때문이다(소비자 4곳 전부 미검증: `tools/decision_binding_checker.nim:101` 실존 파일만 순회, `src/gate/runners/decision_binding_gate.nim:89` 문자열 비교, `tools/hermetic_build.nim:1671,1760-1776` fileExists 없으면 스킵, `src/verification/evidence_cas.nim:97` 다이제스트만). 미존재 파일은 매칭 자체가 발생하지 않아 **불발(inert)** — checker exit 0과 stale 존재가 공존하는 원인이었다. 본 VS-δ′가 이 격차를 최초로 관측·기록하고, VS-2(별도 workstream, checker 불변조건 추가)가 재발을 방지한다.

stale 9건 (waiver JSON 행번호, 2026-11-10 기준):

| 행 | file | 비고 |
|---|---|---|
| :514 | `src/core/parsers/nav.nim` | |
| :524 | `src/core/parsers/tree_sitter/cache.nim` | |
| :529 | `src/core/parsers/tree_sitter_extractor.nim` | |
| :534 | `src/core/parsers/tree_sitter_parse.nim` | |
| :539 | `src/core/parsers/tree_sitter_parser.nim` | |
| :774 | `src/core/types/symbolic_types_expr.nim` | 現 위치 `src/core/symbolic/…` — 구경로만 |
| :954 | `src/gate/runners/ci_pipeline_health_gate.nim` | |
| :959 | `src/gate/runners/ci_skip_detector_gate.nim` | |
| :999 | `src/gate/runners/private/documentation_first_gate_procs_part1.nim` | 디렉터리 부재 |

관측 명령: `jq -r '.grandfather[].file' config/decision_binding.waiver.json | while read f; do [ -e "$f" ] || echo "STALE: $f"; done` → 9행 (Stage 2 착지 후 0행, §5-③).

## 3. 관측 (Observation) — 명령 원문

### ① Stage 0 — 계획 §3 사실의 현 main 재확정 (2026-11-10, origin/main 6d4a963)

| 항목 | 관측 | 출처 |
|---|---|---|
| main 이동 | 5f3595a → 6d4a963 (PR #54) — 계획은 5f3595a 기준 작성 | `git fetch origin && git log --oneline -3 origin/main` |
| stale 9건 | 경로·행번호 전부 §3과 정확 일치 (위 표) | jq + 존재 probe |
| 2파일 미등록 | CONTROLLED 배열에 `src/gate/predicates/types.nim`·`src/gate/handlers/architecture_handlers.nim` 부재 | `git show origin/main:config/repository_surface.json \| jq -r '.classes.CONTROLLED[]' \| grep …` |
| policyVersion | 95 (v96 편집 전) | `jq -r '.policyVersion'` |
| 죽은 import | architecture_handlers.nim `:15` `core/gate/transitive_hash`·`:16` `core/progress/lexicographic_terminator` — 심볼 0사용 | `grep -n 'import'` + 심볼 grep |
| `sets` 미사용 | types.nim `:11` `import std/[os, strutils, tables, sets, hashes]` — sets 고유 심볼 0사용 (계획 인용은 :12, 실측 :11 — 1행 인용 편차, 변경 대상 무모호) | grep + nim check |
| nimtry 지문 행불변 | `normalizeDetail`이 detail에서 `:행(:열)` 제거 후 지문 계산("Strip line:col numbers from detail to make fingerprints stable across edits") — 2줄 제거 시뮬레이션 후 `bin/nimtry src/` EXIT=0 (4262건 debt anchored 동일) | `src/gate/nimtry/nimtry_cli.nim:87-110` + 실험 |
| waiver 해시 pin 0건 | JSON `bfce1424…`·TOML `c01d741d…` 현재 해시가 data/·docs/·compliance/·config/ 어디에도 없음 — stale 제거가 pinned digest를 깨뜨리지 않음 | `sha256sum` + grep |

### ② Stage 1 — 정책 승격 PR #60

- 커밋 `280e763` "surface(policy): register architecture gate pair as CONTROLLED (v96)" — diff 1파일 +4/-2 (v95 선례 `f6ec252`와 동형: policyVersion 승격 + CONTROLLED 2행 + knownBlindSpots 마지막 항목에 v96 노트).
- push: `git push --no-verify` — 문서화된 수용 리스크 경로(계약 Owner 결정 #1·#18(c)). 이 클론은 `core.hooksPath=.githooks`로 pre-push가 활성이고 push-admissibility가 `check-repository-surface` 포함(Makefile `PUSH_ADMISSIBILITY_GATES`) — 정책 PR 자신은 BASE(v95)에서 FROZEN(정책 파일) MODIFY라 통상 push가 불가능한 구조.
- pre-commit(커밋 시점)은 전 파트 통과: anti_theater·layer_enforcement(1627파일 PASS)·stale_cert·hermetic decision-binding audit·canonical build gate. fresh 워크트리는 `src/gate/config.nims:13-19` 무결성 가드가 `bin/ax` 부재 시 게이트 빌드를 차단하므로 공식 경로 `nim c -d:release -o:bin/ax src/cli/main.nim`로 부트스트랩했음(nimble build 서술 준용).
- CI 관측: `repository-surface` **fail 2m48s — by design**(advisory·required 아님; v86/v89/v90·v95(PR #46) 선례와 동일 패턴). 필수 체크 pass.
- **신규 관측 — 필수 체크는 5종이 아니라 6종**: ruleset `main`(26702792, active)의 `required_status_checks` = admission-check·bsec-integrity·debt-registry-gate·generation-acceptance·axiom-operational-slice·**publication-integrity**. v95 노트가 "ruleset 6번째 required context로 예정"이라 예견한 publication-integrity가 활성화돼 있었다(계획 작성 시점의 "필수 5종" 서술과의 차이 — 관측이 권위). license-scan(scancode-toolkit 전체 스캔, `timeout-minutes: 45`)이 최장축: PR-head 27m41s.
- merge: `gh pr merge 60 --merge` → merge queue 진입 → merge_group 검증 → **MERGED**, merge SHA `e5c0ef5ecaf3d1a867e7b969449e153e17f2a402` = merge_group head. 2-parent: `git log --pretty=%P -1 e5c0ef5e` → `1332419bd9b2e237e4b50165232c3f069e3a9043 280e763d10ed859026779551635c9302a885e49c` (네이티브 2-parent MERGE).

### ③ Stage 2 — 원자적 정리 PR #62

- 브랜치 재생성: Stage 1 착지 후 `git checkout -B workstream/dprime origin/main`(e5c0ef5e) — rebase가 아닌 fresh 분기.
- 커밋 `65c6efe` "chore(waiver): remove 9 stale grandfather entries and dead imports (VS-dprime)": `config/decision_binding.waiver.json` 45행(9×5행 블록) 삭제·`src/gate/handlers/architecture_handlers.nim` 2행 삭제·`src/gate/predicates/types.nim` 1행 수정(+1/-48). 소비자 4곳 코드 무변경·검증 코드 신규 0.
- 로컬 검증(착지 전 전부 관측):
  1. `make check-repository-surface` → `{"verdict":"PASS","policyVersion":96,"binding":"base","changeCount":3,"violations":[]}` EXIT=0 (BASE=v96 — 2파일 MODIFY=CONTROLLED PASS, waiver JSON은 미분류→PRODUCT MODIFY PASS)
  2. `nim check` 2파일 → 각 EXIT=0·Error 0건 (Nim CLI는 `--run` 없이 다중 파일 인자를 거부하므로 파일별 실행 — "arguments can only be given if the '--run' option is selected"는 인용 방식 오류지 코드 오류 아님)
  3. stale probe → 0행 (259→250)
  4. `make check-decision-binding` → EXIT=0 (WARN 67 functions missing {.axiomDecision.} — escalation threshold 30일 미도달 경로). WARN 카운트의 두 소비자 차이(같은 트리 재현): `bin/decision_binding_checker` 51건 vs `bin/hermetic_build --check-decision-bindings` 67건 — 두 도구 모두 `src/`를 순회하나 waiver 면제 집합을 다르게 소비한다(hermetic이 TOML waiver의 exempt_files/exempt_modules을 별도 적용). 둘 다 WARN 경로 exit 0로 판정 동일. 3파일 격리 실험(동일 워크트리에서 3파일만 e5c0ef5e로 되돌려 재실행 → 67건 동일)으로 본 변경과 무관임을 확정.
- 통상 push: pre-push 훅 전부 통과 — push-admissibility 15종 게이트(check-debt·check-nim-theater·doc-path-validator·check-determinism·check-proof-unit-consistency·check-proof-unit-reconcile·check-repository-surface·check-git-access·check-monitor-purity·check-workflow-shell-syntax·check-epoch-transaction·check-merge-admission-cert-mirror·check-layer-enforcement·check-layer-negative·validate-root-layout) 전부 green, pin@OID 앵커 통과. 152s 소요(120s developer-feedback 예산 경고 — 운영 정책값, 불변식 아님).
- CI: `repository-surface` **pass 2m14s** — v96 CONTROLLED 등록의 본문 PR 효과 (Stage 1에서 by-design FAIL이었던 것과 대비).
- merge: `gh pr merge 62 --merge` → merge queue 진입 → merge_group(head `3368a696a`) 검증(probe-merge-queue·landing-integrity·generation-acceptance·debt-registry-gate·bsec-integrity·admission-gate·axiom-operational-slice·publication-integrity 전부 success) → **MERGED**, merge SHA `3368a696a051b310d752277ea92eadc556189c64` = merge_group head. 2-parent: `git log --pretty=%P -1 3368a696a` → `5ff3ce7e6ee764f319e37d61f4ea7167a69cc3f6 65c6efee4a258b3f9c871adf65e04c30971e1765` (네이티브 2-parent MERGE — 전 main은 release 0.6.1 bump PR #61).

### ④ 부트스트랩 관측 (재현 참고)

- `bin/build_all_gates --release` → 84 gates: 82 built, 2 accepted-dead skip (DEBT#492 documentation_first_gate_selftest·DEBT#491 unified_gate_runner_procs — `data/debt_registry.json` closed WONT_FIX Theater/Dead Gate, source sha256 결속 — 레지스트리가 승인한 정상 스킵).

### ⑤ §6-② 우선순위 실험 — CONTROLLED 개별 등록 vs FROZEN glob (v96 착지 후)

v95 실험(계획 §6-②, 2026-11-10: CONTROLLED 개별 등록 `.github/workflows/publication-integrity.yml`이 `.github/**` FROZEN glob과 양쪽 매칭 시 CONTROLLED로 판정·위반 목록 제외)과 동일 메커니즘의 v96 재실험:

```
$ printf 'M\tsrc/gate/predicates/types.nim\nM\tsrc/gate/handlers/architecture_handlers.nim\nM\tsrc/gate/nimtry/nimtry_cli.nim\n' > synth_diff.name-status
$ bin/surface_guard --policy config/repository_surface.json --diff synth_diff.name-status
{
  "verdict": "FAIL", "reasonCode": "SURFACE_FORBIDDEN", "policyVersion": 96, "changeCount": 3,
  "violations": [ { "path": "src/gate/nimtry/nimtry_cli.nim", "status": "M", "changeClass": "FROZEN", "reasonCode": "SURFACE_FORBIDDEN" } ],
  ...
}
EXIT=1
```

- `src/gate/predicates/types.nim`·`src/gate/handlers/architecture_handlers.nim` (M, CONTROLLED 등록) → **위반 목록 제외 = MODIFY PASS**.
- `src/gate/nimtry/nimtry_cli.nim` (M, 미등록 — `src/gate/**` FROZEN glob 흡수) → **SURFACE_FORBIDDEN** — glob 집행은 나머지 전부에 그대로 유지됨.
- 전체 EXIT=1은 fail-closed 정상 동작 (합성 diff에 실제 FROZEN 위반이 있으므로).

### ⑥ Stage 3 — merge SHA 재검증 (최종 관측, 2026-11-10)

워크트리를 `git checkout --detach 3368a696a051b310d752277ea92eadc556189c64`로 고정하고 재검증 전 세트를 실행:

| # | 명령 | 관측 | EXIT |
|---|---|---|---|
| R1 | `make check-repository-surface` | `{"verdict":"PASS","policyVersion":96,"binding":"base","changeCount":0,"violations":[]}` | 0 |
| R2 | `nim check --hints:off --warnings:off src/gate/handlers/architecture_handlers.nim` / `…/src/gate/predicates/types.nim` (파일별) | 각 Error 0건 (Nim CLI는 `--run` 없이 다중 파일 인자 거부 — 파일별 실행이 정확한 형식) | 0 / 0 |
| R3 | stale probe (`jq -r '.grandfather[].file' … \| while read f; do [ -e "$f" ] \|\| echo "STALE: $f"; done \| wc -l`) | **0행 — main에서 stale=0 달성** | — |
| R4 | `make check-decision-binding` | WARN 51(checker)·67(hermetic) functions missing `{.axiomDecision.}` — escalation threshold 30일 미도달 WARN 경로 (아래 소비자 관측 참조) | 0 |
| R5 | `bin/debt_engine --validate` | Checks 1610/1610 passed·0 failed, Metric evaluation 5 PASS 0 DRIFT | 0 |
| R6 | §6-② synthetic diff 실험 (위 ⑤와 동일 명령, merge SHA 정책) | CONTROLLED 2파일 위반 목록 제외(MODIFY PASS)·미등록 `src/gate/nimtry/nimtry_cli.nim` SURFACE_FORBIDDEN — 전체 verdict FAIL | 1 (fail-closed 정상: 합성 diff에 실제 FROZEN 위반 포함) |

**소비자 4곳 직접 관측** (merge SHA): (1) `bin/decision_binding_checker` EXIT=0 (WARN 51) (2) `bin/decision_binding_gate` EXIT=0 (3) `bin/hermetic_build --check-decision-bindings --escalation-threshold 30` EXIT=0 (WARN 67) (4) `src/verification/evidence_cas.nim:96` `PolicyDigestInputPaths` live 다이제스트 — CI attest 경유(admission-check attest 잡 PASS 관측). WARN 카운트의 두 소비자 차이(51 vs 67, 동일 트리 재현)는 waiver 면제 집합 소비 차이다(checker는 JSON grandfather만, hermetic은 TOML exempt_files/exempt_modules 별도 적용) — 둘 다 WARN 경로 exit 0로 판정 동일.

## 4. 권한 기록 정밀화 (과장 없는 구분)

세 사실은 **별개**다 — 증거 문서·PR 본문이 이를 혼동·과장하지 않는다:

1. **advisory surface 판정**: `repository-surface` check는 required가 아니다. Stage 1 정책 PR에서 FAIL(by design — BASE 정책 바인딩상 정책 파일 자신이 FROZEN MODIFY)·Stage 2 본문 PR에서 PASS. 이 판정은 merge를 좌우하지 않는다.
2. **필수 CI + merge queue**: 병합 판정 권위는 GitHub ruleset `main`(26702792)의 required 6종(publication-integrity 포함 — 본 실행에서 관측 확정)과 merge queue(merge_group 검증)다. FROZEN 등급 자체를 서버가 강제하지 않는다 — `--no-verify`로 스킵한 것은 로컬 pre-push 훅뿐이며, 필수 CI·merge queue는 그대로 통과해야 했고 실제로 통과했다.
3. **Owner Decision 기록**: v96 CONTROLLED 승격의 권한 근거는 Owner Decision (2026-11-10) — 승인된 계획(mister-miracle-cable-hawkeye)이 기록이며 PR #60 본문·v96 노트가 그 소비다. `--no-verify`는 훅 우회일 뿐 권한 부여가 아니다(계약 문서화 경로).

## 5. Known Risks·후속 (본 계획 범위 박)

- **2026-12-01 경보 전환**: 잔여 250 waiver 전부 expires=2026-12-31·escalation-threshold 30일 → 2026-12-01부터 checker WARN→FAIL — 본 정리와 무관하게 잔존(VS-3 별도 과제, Owner 결정 필요).
- **VS-2**: checker에 grandfather 엔트리 file 존재 fail-closed 불변조건 추가(별도 workstream, stale 재발 방지).
- DEBT#522 incremental regeneration 하위·DEBT#523·#524·worktree 8기: 계획 Explicitly Out of Scope 그대로.
