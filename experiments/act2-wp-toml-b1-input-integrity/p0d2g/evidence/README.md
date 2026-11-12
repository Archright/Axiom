# evidence/ — p0d2g 큐리이티드 증거 (2026-10-17 커밋 스냅샷)

이 디렉터리는 본 슬라이스의 2026-10-17 실행 산출물 중 추적 가치가 있는 부분집합의
**읽기 전용 스냅샷**이다. 파일 대응은 `SHA256SUMS`가 보증한다. **원본은 이동시키지
않았다** — 모든 원시 산출물은 이 슬라이스의 gitignored 디렉터리(`runs/`·`state_*/`·
`vault_*/`·`env*/`)에 그대로 남아 있으며, 전체 런의 재생성은 `../replay_agent.sh`
(공정 전제조건·pristine materialization·결함 런 + 콜드 재실행·조건 C1–C5 판정 포함)이
담당한다. `../AGENT_SPEC.md`와 `../discovery/`(발견 원문 2건, sha256
`e3b20c9d6293c249…`·`0b329a4498eabe6f…`)는 바인딩 커밋 `efc90940d`에서 이미 커밋되어
있어 본 디렉터리에 중복 수록하지 않는다.

## run ↔ state ↔ target 대응 (Phase E, cwd=Axiom3 루트 고정, scope lock 시드)

| 스냅샷 | 원본 run | state | vault | target | exit | 판정 요지 |
|---|---|---|---|---|---|---|
| `defect/` | `runs/e_defect.{err,exit}` | `state_e1` | `vault_e_defect` | `toml_serialization/lexer.nim::scanString` | 1 | GateVerdict FAIL — `scanString` **clDisproved**(BMC SAT, certRed, irHash `5c05274c…`), 동일 런에서 `d2CommentGateReject` **clProved**(certZ3Candidate, irHash `cf15872b…`) — 차동. `canonicalRunDigest` `3516fcfc…` |
| `defect_cold/` | `runs/e_defect2.{err,exit}` | `state_e3` | `vault_e_defect2` | 동일 | 1 | 콜드 재실행 — digest **MATCH**(`3516fcfc…`), claimId·irHash 동일, `.err` diff는 vault 경로 1행뿐 |
| `control_refusal/` | `runs/e_control.{err,exit}` | `state_e2` | `vault_e_control`(빈) | `toml_serialization/lexer.nim::d2CommentGateReject` | 2 | standalone control은 frontier NotFound fail-closed 거부 — 대조 커널은 census 주소 가능 전용이며 대조 판정은 결함 런 안에서만 관측된다 |

- `defect/ax_proof_state.json`·`ax_prove_trajectory.jsonl`·`z3_telemetry.jsonl` ←
  `state_e1/logs/` · `defect/manifest.json` ← `vault_e_defect/manifest.json`
- `defect_cold/ax_proof_state.json` ← `state_e3/logs/`
- `vault_e_control/`는 **빈 디렉터리**다(런이 솔버 도달 전 거부 — 빈 볼트 자체가
  거부 관측의 일부). git은 빈 디렉터리를 추적하지 않으므로 이 사실의 유일 커밋 기록은
  본 문서와 `control_refusal/e_control.err`의 NotFound 라인이다.
- `defect/e_replay_harness_c0.nim` ← `runs/e_replay_harness_c0.nim` — 결함 런에서
  생성된 유일한 재생 하니스 보존본. **scanString의 하니스가 아니다** — Q3 collateral
  `calcDynamicTimeoutCore`의 것으로, gitignored 원본 raw(`runs/e_replay_harness_c0.nim`
  및 `state_e1/.axiom/tmp/replay/74fded71cfe77375/replay_harness.nim`)와 **주석 외
  바이트 동일**이다(원본 대조 확인). 이 커밋 사본에만 `nim-check: skip` 보존 헤더가
  붙는다(p0d2f 선례 — `.githooks/pre-commit` Part 1 스킵 계약; Axiom3 트리의 번역
  단위가 아니므로). scanString의 ce-replay는 P4 bool-binding 갭(`pipeline_gap/`)으로
  발화하지 않았다 — 그 부재가 본 슬라이스 ACCEPTANCE INCOMPLETE의 루트다.
- `orig_pragma/` — 원본 헤더 직접 부착 한계 관측(`ORIG_PRAGMA_LIMIT.md`)과 변형
  패치(`variant_orig.patch`, 1531B). 슬라이스 루트의 동명 파일이 SSOT이며 본 사본은
  스냅샷 핀이다.
- `pipeline_gap/` — P4 bool-binding 승격 갭 기록(`PIPELINE_GAP_P4_BOOL_BINDING.md`).
  슬라이스 루트의 동명 파일이 SSOT이며 본 사본은 스냅샷 핀이다.

## 툴체인 (관측 시점)

`state_e1/logs/ax_proof_state.json` `executionIdentity.toolchainIdentity` —
Nim 2.2.10 · Lean 4.33.0 · z3 4.13.3 · linux-amd64. `bin/ax` v0.3.7, 바인딩 커밋
`efc90940d` (branch `followup/d2-agent-vertical`).
