# 조사 결과 — Axiom 외부 저장소 검증 지원 여부

## 0. 한 줄 요약

**외부 저장소 검증은 지원되며, 실제로 end-to-end로 동작한 선례가 있습니다.** 진입 경로는 `ax prove --project <외부repo>` + `AXIOM_STATE_DIR`이며, 외부 주체의 명제는 `config/spec/*.json`의 `soExplicit` 오버레이로 선언합니다. **단, `ax vkd sync` / `ax scope lock`은 Axiom 자체 저장소 전용이므로 외부 주체에는 쓸 수 없습니다.** nim-libp2p에 대한 사전 정의된 명제는 **없습니다**(0건).

---

## (a) 코드베이스에 사전 정의된 명제/요구사항 목록

### A-1. 외부 주체 명제 오버레이 5건 (`config/spec/` — 유일하게 합법적인 명제 위치)

| 파일 | specId | 주체 | 명제 (canonicalSpecIR) | 상태 |
|---|---|---|---|---|
| `config/spec/base36_sizing_relational_spec.json` | `SPEC-B36-RELATIONAL` | nim-stew `stew/base36.nim` `encodedLength`/`decodedLength` | `0<=n`, `n<=33297371974204966`, `decodedLength(encodedLength(n))==n`, `encodedLength(n)>=1`, `!overflowAt(...)` ×2 | soExplicit |
| `config/spec/nim_stew_base32_rem_spec.json` | `SPEC-B32-REM-RANGE` | nim-stew `stew/base32.nim::decodedLength` | `0<=length`, `length mod 8 >= 0`, `length mod 8 <= 7` | soExplicit |
| `config/spec/nim_stew_base36_cout_spec.json` | `SPEC-B36-COUT` | nim-stew `stew/base36.nim::decodedLength` | `3<=L`, `L<=3`, `decodedLength(L)>=2` (K=2 외부관측 핀) | soExplicit |
| `config/spec/nim_stew_base36_sidecar.json` | `SPEC-B36-SIDECAR` | nim-stew `stew/base36.nim::decodedLength` | defect `length==1 → result==(length+4)`, control `length==2 → result==1` | soExplicit + 해시바인드 adoption(`3f55eaa7…`) |
| `config/spec/toml_d2_agent_spec.json` | `SPEC-TOML-D2-AGENT` | **nim-toml-serialization** `toml_serialization/lexer.nim::scanString` 등 | `1<=c`, `c<=255`, `c!=10`, `c!=13`, `c!=34`, … | soExplicit |

> **nim-libp2p에 대한 오버레이는 0건**입니다. `config/spec/` 5개 모두 nim-stew / nim-toml-serialization 대상입니다. 전 저장소 grep 결과 nim-libp2p 언급은 `experiments/act2-wp-toml-b1-input-integrity/p0d2/peer_survey.md:67` (nimbus-eth2가 libp2p 비콘 노드라는 서술) 뿐, 검증 대상으로는 없습니다.

### A-2. 대응 제품 계약 문서 (`docs/spec/`)
- `docs/spec/base36_sizing_binding_contract.md` — S0, 관계적 정리 + `high(int) div 277` 타이트 경계
- `docs/spec/nim_stew_base32_rem_binding_contract.md` — PR-E, 나머지 범위 정리 (`0<=length`는 discharged hypothesis)
- `docs/spec/nim_stew_base36_cout_contract.md` — S0, 출력 사이징 C_out
- `docs/spec/nim_stew_base36_sidecar_contract.md` — 폐쇄 문법 `nim-sidecar-expr-v1` + 해시바인드 adoption
- `docs/spec/toml_d2_agent_binding_contract.md` — 문자 제어 게이트 결함

### A-3. 제품 계약 상의 근거 문서
- `docs/spec/productization_contract.md` **§10 "External Verification Subject Execution Context (Act 2)" — Ratified 2026-08-27** (`:362-459`). §10.1 Surface(`:371`), §10.2 Identity4축(`:377-390`), §10.3 Workspace 격리 + `AXIOM_STATE_DIR` fail-closed(`:419-423`), §10.5 Acceptance M1–M4(`:430-432`)

### A-4. 스펙 레지스트리
`docs/spec/spec_registry.json` — `SPEC-B36-RELATIONAL`, `SPEC-B36-COUT` 등록됨. `SPEC-B32-REM-RANGE`·`SPEC-B36-SIDECAR`·`SPEC-TOML-D2-AGENT`는 **미등록(계약 문서가 "pending, epoch-scale"로 명시)**.

---

## (b) 최소 PROVEN end-to-end 워크플로 (명령 + 증거 파일)

### ✅ 검증 성공 계층 (VERIFIED 도달) — base32 rem

`docs/spec/nim_stew_base32_rem_binding_contract.md:67-87` 의 터미널 아웃컴:
```
bin/ax prove --project <nim-stew>     # AXIOM_STATE_DIR 설정
→ rem candidate VERIFIED, 인증서에 `rem=` + `modelprofile=` 세그먼트
```
- A1 VERIFIED / A2 2회 결정론 sha256 동일 / A3 `git -C <nim-stew> status --porcelain` empty / A4~A8 fail-closed 부정케이스 8항 (`docs/spec/nim_stew_base32_rem_binding_contract.md:76-87`)
- **주의**: 이 문서는 "Terminal outcome (measurable)" **규격**입니다. 커밋된 VERIFIED 실행 기록 파일은 `docs/evidence/`에 없습니다 — 무거운 증거는 C_out/sidecar 쪽입니다.

### ✅ 실제 파이프라인 완주 (BUG_FOUND 판정, exit 1) — base36 C_out

**명령** (`docs/evidence/nim_stew_base36_cout_slice_2026-10-10.md:71-74`):
```bash
AXIOM_STATE_DIR=<state-dir> bin/ax prove \
    --project /tmp/b36slice/nim-stew --target "stew/base36.nim::decodedLength"
```
**관측** (`:78-86`): 오버레이 채택 → `[canonical-declined]` → BMC+P4 SAT(`L=3`) → `cvConfirmed` → `vsDisproved` → `[ce-replay] … BUG_FOUND payload assembled (14 records)` → `clDisproved` → node `failed` → **exit 1**
**증거 파일**: `docs/evidence/nim_stew_base36_cout_slice_2026-10-10.md` (5링크 사슬, §2.2 4요소 14-record 페이로드, J1/J2 결정론 digest 3종 일치 `:125-138`)

### ✅ 범용 사이드카 E2E (결정론 + 무결성 + fail-closed 전부 입증) — base36 sidecar

**명령** (`experiments/sidecar-adoption-e2e/ACCEPTANCE.md:4`):
```bash
AXIOM_STATE_DIR=<exp>/state_dN AXIOM_PROVE_VAULT_DIR=<exp>/vault_dN \
  bin/ax prove --project /tmp/sidecar_probe/nim-stew \
 --target "stew/base36.nim::decodedLength"
```
- **scope lock 시딩**: 커밋된 `data/verification_scope.lock` 사본을 `<state>/data/verification_scope.lock`로 복사 (엔진이 `AXIOM_STATE_DIR` 하에서 먼저 해석, `src/cli/axiom_engine.nim:3783-3784`) — `ACCEPTANCE.md:111`
- 결과: defect leg **exit 1**, 13-record payload, control UNSAT, unsupported 42/42 fail-closed, 무결성 95파일 pre==post, 결정론 `canonicalRunDigest` d1==d2 == `29db1e36…`
- 증거 파일: `experiments/sidecar-adoption-e2e/{FREEZE.md, ACCEPTANCE.md, INTEGRITY.md}`, `runs/d1_stderr.log`, `runs/d2_stderr.log`, `runs/unsupported_tests.log`, `discovery/agentA{1,2}_raw.md`

### 🔶 부분 성공 (Z3 도달, Lean/KAA 미도달) — getBitsBE
- `experiments/act2-r0-atom-getbitsbe/atom-reproduction.json:14` — 명령: `bin/ax prove --project <nim-stew> --target 'stew/bitops2.nim::getBitsBE' --limit 1`
- 결과: `getBitsBE psFail smBMC/pkZ3Bmc`, `StructuralAST srNoTransformApplied` skip → UAP requests=1 results=0 → **exit 2, verdict BLOCKED** (`verdict.json:12`)
- `experiments/act2-r0-reanchor/r0-reproduction-report.md` — v3 정본, 미선언 ingress 0건, AF_INET 0건, same-class 4중 바이트 일치 (`:99-131`)

---

## (c) 외부 저장소 검증 지원 여부 — 명시적 판정

### ✅ 지원된다 — 근거 메커니즘 (코드)

| 단계 | 위치 | 내용 |
|---|---|---|
| CLI surface | `src/cli/axiom_engine.nim:4451-4465` | `--project <dir>` → 절대경로화, 존재 확인, **`AXIOM_STATE_DIR` 없으면 fail-closed(exit 1)** |
| 외부 모드 전환 | `src/cli/axiom_engine.nim:4496-4498` | `setExternalSubjectMode(true)` |
| origin 태깅 | `src/core/trusted/axiom_pragmas_types.nim:31-35` | `AxiomEntryOrigin` = `soAxiomSupport | soExternalSubject` |
| 후보 게이트 | `src/verification/batch_uap/ir_pipeline_runner.nim:1754` | `ve.entry.isKernelScopeMember or (extMode and ve.entry.origin == soExternalSubject)` |
| 주체 IR materialize | `src/infrastructure/external_ir_materializer.nim:434-458` | 외부 심볼 → `RuntimeAxiomEntry{origin=soExternalSubject, isKernel=false}` |
| subject-scoped resolver | `src/cli/axiom_engine.nim:3755-3774` | `makeSubjectResolver` — modulePath를 **CWD가 아닌 sourceRoot** 기준으로 해석 |
| scope lock 해석 | `src/cli/axiom_engine.nim:3783-3784`, `:4088` | `<AXIOM_STATE_DIR>/data/verification_scope.lock` 우선, `loadKernelScope(failClosed=true)` |
| 명제 로더 | `src/cli/axiom_engine.nim:963`, `:1106`, `:1247`, `:1639`, `:2104` | `explicitSpecFromOverlay` — `soExplicit` 고정, 그 외 fail-closed |
| 합성 함수 | `src/cli/axiom_engine.nim:2484/2665/2882/3070/3294` | `synthesizeTomlD2AgentCandidate` / `synthesizeNimSidecarCandidates` / `synthesizeBase36RelationalCandidate` / `synthesizeBase32RemRangeCandidate` / `synthesizeBase36CoutCandidate` |
| census | `src/verification/obligation/candidate_eligibility.nim:223-244` | `CensusScopeExternalSubject="external-subject"`, `NO_EXTERNAL_CANDIDATE` 터미널 |
| journal 소유권 | `src/core/trusted/trust_commit.nim` (WP3-b 수정) | journal base = `AXIOM_STATE_DIR → repoRootForPath → legacy` |

### ❌ 지원되지 않는 부분 (중요 제약)

1. **`ax vkd sync`는 외부 주체를 파라미터화하지 못함** — `src/cli/vkd_sync_cli.nim:63`: `runAxiomEngineCli(@["--limit", "25"], updateLock = true)`. `--project` 없음 → Axiom 자체 커널 전용.
2. **`ax scope lock`도 Axiom 저장소 전용** — `src/cli/scope_cli.nim:217-223` → `writeScopeLockFromRegistry(findRepoRoot())`. 외부 주체의 lock은 **Axiom의 커밋된 lock을 state dir에 복사 시딩**하는 방식 (`experiments/sidecar-adoption-e2e/ACCEPTANCE.md:111`).
   - `ax scope init`(`scope_cli.nim:187-216`)만 대상 저장소에 `.axiom_root`/`axiom.toml`/빈 lock을 만드는 "프로젝트 초기화" 경로입니다.
3. **VKD/VKS 지표는 외부 주체를 분모에 넣지 않음** — `data/verification_scope.lock`: `kernel_total=40`, `vksTotal=23`, exempt 17개(전부 Axiom `src/` 심볼). `config/readiness_policy.json` `r7.vkdContract` = `|VKS ∩ certGreen|/|VKS|`, `vksDerivation="kernel 40 - exempt 17"`. `r1.trustBoundaryLanes` = `nim`, `rust`뿐 — **external lane 없음** → readiness GO는 외부 주체에 대해 발화되지 않음.
4. **외부 심볼에 대한 사전 명제 없음** → 외부 주체 검증은 **지금까지 Axiom이 임의로 만들지 않았습니다**. `soExplicit` 오버레이를 *새로 작성·채택*해야 검증이 성립합니다 (out-of-tree 명제가 없으면 `origin` 게이트가 NOT PROVED로 막음, `docs/spec/base36_sizing_binding_contract.md:36-40`).
5. **주체 무결성 제약**: 주체 트리는 READ-ONLY, `git status --porcelain` empty 유지. `nim-libp2p`는 현재 clean(`a130a7f3`)이므로 적합합니다.

### 🔎 계약상 범위 (in/out of scope)

`docs/spec/productization_contract.md:11` — "지원 subject scope = (i) **Nim 커널 범위** + (ii) **선언된 Rust certified subset**". 외부 저장소 검증은 **§10 Ratified 계약**으로 별도 경로를 가지며(Act 2), 제품 v1 지원 범위 주장은 그대로 유지됩니다. 즉 **"지원된다"는 것은 "Act 2 외부 주체 실행 컨텍스트가 존재하고 실측 증거가 있다"는 의미**이며, v1 제품 지원 범위가nim-libp2p까지 확장되었다는 주장은 아닙니다.

---

## 부록 — 요청 항목별 요약

| # | 항목 | 결론 |
|---|---|---|
| 1 | WP1 external-symbol-ingress | E1-E3 PASS(결정론 ingress digest `6c3b7c99…`), **E4 BLOCKED(S3-registry-static)** — 커널 스코프 lock과 외부 subject 스코프 공유 불가. E5 Unsupported(PNode 경계). **Partial PASS** — `experiments/act2-wp1-external-symbol-ingress/wp1-result.md` |
| 2 | WP3 exact-external-proof-outcome | "정확한 외부 proof outcome" = `--target` exact 1-match → frontier eligible → obligation 생성 → **Z3/Lean 실제 결과의 정직한 taxonomy 확정**. WP3-a: **Vacuous**(tautology, exit 2, solverMethod=smNone) + journal routing defect 발견. WP3-b: routing·gate 수정, 7/7 회귀 PASS, 결정론 PASS. `wp3-result.md`, `wp3b-result.md`, `wp3-analysis.md` |
| 3 | WP22 / atom-getbitsbe / reanchor | WP22=**proof slice discovery**(결정론 하드필터+랭킹, v4 정정으로 hardEligible 0→6, `wp4-h-0-forensic-closure.md`). atom-getbitsbe=**원자 단위 재현·동일성 증명**(BLOCKED). reanchor=**권위 사슬 재앵커**(ingress manifest 선언=strace 검증자, 미선언 0) |
| 4 | `logs/ax_prove_trajectory.jsonl` | 393줄, `2026-09-17`→`2026-10-09`. phase: skReport 122 / skSwat 80 / skTopology 63 / skRunAccounting 63 / skCliEntry 59 / skCegar 6. **대상은 Axiom 자체 커널 심볼 18종**(최다 `orchestrator_api.nim::normalizeMaxWorkers` 58회). 마지막 entry: `gateVerdict=FAIL, verdict=INCONCLUSIVE, basis=NONE`. `logs/ax_proof_state.json`은 `census.scope="external-subject"`, `terminal="NO_EXTERNAL_CANDIDATE"`, `candidateCount=0` |
| 5 | 계약/정책 | 위 (c) 참조. `docs/spec`의 "external" 언급 67파일/168회. 외부 주체의 **Dedicated 제품 계약**은 §10이 유일한 정본 |
| 6 | 타깃 추가 생명주기 | `ax scope lock`(Axiom 커널 registry→lock 재생성, 멱등) → `ax prove --update-lock`(universe_merkle.lock 유일 기록 권한, `docs/agents/core_rules.md:228` RL-14.12) → `ax vkd sync`(scope lock 재생성 → prove limit 25 → orphan check → baseline 갱신, 실패 시 baseline 롤백, `src/cli/vkd_sync_cli.nim:31-113`). **외부 주체에 대한 동등 명령은 없음** |

---

## 실용 결론 — nim-libp2p에 적용할 최소 경로

선례 3종(안정성·난이도 순):
1. **toml_d2**(다른 외부 저장소, 가장 최근) — `docs/spec/toml_d2_agent_binding_contract.md` + `config/spec/toml_d2_agent_spec.json` 구조를 그대로 모방
2. **base36 sidecar**(범용 사이드카) — 폐쇄 문법 `nim-sidecar-expr-v1`으로 `pre/post`를 `config/spec/nim_libp2p_<sym>.json`에 선언하고 `adoption.adoptedSpecHash`를 해시바인드
3. **base36 C_out**(결함 판정) — 반례 존재 시 BUG_FOUND까지 도달 가능

필수 선행조건: (1) `config/spec/<new>.json` 작성 + **사용자 승인에 의한 adoption 기록**, (2) `config/spec` 내 overlay를 읽는 합성기 연결(`synthesizeNimSidecarCandidates`가 `overlayDeclaresSidecarSubject`로 module+symbol 키 매칭), (3) `AXIOM_STATE_DIR` 시드(커밋된 `data/verification_scope.lock` 복사), (4) `--target "<path>::<sym>"` exact 지정.