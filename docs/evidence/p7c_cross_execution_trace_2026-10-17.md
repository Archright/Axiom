# P7c 교차 실행 승격 추적 — 적색 런 원장 기록의 합격 권위 판정 (2026-10-17)

> **종류**: 결정 입력 증거 (decision-input) — 본 문서는 계약 변경을 수행·확정하지 않는다(Reporter). merge-admission 권위는 GitHub(ruleset 20303214)와 기존 정본(`docs/spec/certification_continuity_contract.md`, ADR-0032)에 그대로 있다.
> **문서 목적**: P7c 계약("적색 런 append 금지 — 별도 계획 필요" 등록: prereg §6.1 → followup §5.1)의 **변경 필요 여부에 대한 입력 증거**다. 다음 3개를 엄격히 구분해 기록한다: **§1** 현재 의도된 append-on-red 동작(사실 — 설계 원문), **§2** 실패 런 기록의 후속 합격 승격 가능성(증거 — Row (a) 판정), **§3** evidence CAS 교차 실행 재사용(별개 의미 — 잔여 검토 목록). §4는 진단 보존 현황, §5는 권고·결정 요청이다.
> **계보**: `docs/evidence/mg_evidence_gate_prereg_2026-10-17.md` §6.1 → `docs/evidence/mg_evidence_gate_followup_2026-10-17.md` §5.1 → `docs/evidence/mg_evidence_gate_canary2_2026-10-17.md` → `docs/evidence/org_gate_handoff_2026-10-04.md`.
> **측정 원문**: 인용은 전부 조사 로그 원문 복사다(인용부 안은 편집 불가). 라인 인용은 `.github/workflows/admission-check.yml`·`src/verification/judgment_cas.nim` 등 해당 시점 트리 기준이며, `certificate-mint.yml`은 org 중앙 저장소 `Archright/.github` 소유다.

---

## 1. 현재 의도된 append-on-red 동작과 그 근거 (사실 — 설계 원문)

**append 자체는 막혀 있지 않다.** 적색 런도 mint가 원장에 기록한다 — 결함이 아니라 **의도된 "evidence authority" 설계**다. 막혀 있는 것은 소비가 합격 권한으로 변하는 경로다(§2).

### 1.1 mint `if: !cancelled()` — admission 실패와 무관한 실행

- org caller(`admission-gate-v2.yml`)의 `mint-prepare`/`mint-publish`는 `needs:[admission]`에도 `if: !cancelled()`라서 **admission 실패와 무관하게 실행**된다. 측정된 DAG와 의도 주석: `docs/evidence/org_gate_handoff_2026-10-04.md:46-61`(작업 그래프), **:246** 원문:

  > "they run even when `admission` fails — deliberate … 'certificate minting is an evidence authority' … the verdict's four-way ∧ is what ultimately enforces fail-closed"

- P7c 판정 원장 append는 `if: scope_sl15 && venue=='landing'`뿐 — **admission-success 조항이 없다**(`certificate-mint.yml:2380-2381`, append 실행 :2493-2507). mint 자체도 결론을 검증하지 않는다 — ":364-366 conclusion 미검증(게이트 needs+verdict가 대신)".
- **즉 적색 런의 레코드는 원장에 들어간다.**

### 1.2 red suite + green self-check = staged evidence file (flush 4 지점)

- `tests/unit/test_s1a_lean_golden.nim:403-434` — flush 테스트가 관찰 로그를 집계해 self-check(:415-420) 후 기록(:427-428), 재파일 검증(:431-434). Nim unittest는 `check` 실패를 누적하고 프로세스는 **맨 끝에** non-zero 종료하므로, 스위트의 다른 테스트가 빨간 상태에서도 flush 테스트는 실행되고, flush 자체의 self-check가 green이면 증거 파일이 stage된다. (단, flush 테스트 **내부** check가 먼저 실패하면 그 시점부터 본문이 스킵되어 기록 없음 — unittest의 per-test abort.)
- `tests/unit/proof_integrity_test.nim:243-269` (write :262), `tests/unit/test_d2_golden.nim:447-465` (write :458), `tests/unit/test_d2_persist.nim:173-187` (write :179, 실패 시 `quit(1)` fail-closed).
- 4개 모두 `writeSubjectEvidenceFile`(`src/verification/judgment_cas.nim:1362`)로 수렴 → **"red suite + green self-checks = staged evidence file"** 확인.

### 1.3 attest — 레인이 빨갛게 실패해도 실행된다

- 레인 실패 → `go-critical-rollup`이 callee 워크플로를 red로 만든다(`admission-check.yml:2897-2918`, "skipped/cancelled lanes are NEVER green").
- 그러나 `admission-check` job은 `if: always()`라서 레인 실패 후에도 **계속 실행**된다(`:676` needs + `:701-704` always() — 주석 :670-675).
- 레인의 judgment 파일 12종은 `always()` 업로드(`:2843-2862`)되고, attest의 armed branch가 basis=EXECUTED로 증거 파일을 **요구·소비**해 레코드를 재작성한다(`judgment_cas.nim:1891-1909`, 증거 부재 = fail-closed :1894-1899). witness는 `always()`로 업로드(`:2409-2442`).

이것이 prereg §6.1(`mg_evidence_gate_prereg_2026-10-17.md:66`)과 후속 추증 §5.1(`mg_evidence_gate_followup_2026-10-17.md:94`)이 "적색 런 append 금지 — 별도 계획 필요"로 등록한 살아있는 뉘앙스다.

## 2. 실패 런 기록의 후속 합격 승격 가능성 — 증거 (Row (a))

**판정: Row (a)** — 실패 런의 기록이 이후에도 **합격 권한**을 갖지 못한다(post-gate). 정밀화: gate 이전에는 정답이 아니었다 — pre-gate MG 재사용은 실제로 가능했고(게이트가 닫은 것), gate 이후 모든 권위 보유 경로에서 REUSED 기반 합격이 구조적으로 봉쇄된다.

### 2.1 소비 체인 (REUSED가 합격으로 이어지려면 거쳐야 하는 경로)

- plan consult: `planJudgmentCasForSubjectWithTransport`(`judgment_cas.nim:1492-1597`) — env 계약(:1508-1515) → 클로저 유도(:1531-1541) → **강제 게이트(:1559-1562)** → `hasEvidence`(:1565) → `fetchEvidenceRecord`(:1573) → payload 검증(:1585) → epoch 동등성(:1589-1594) → `jReused`(:1595-1596).
- attest REUSED leg: `runJudgmentAttestBranchForSubject`(`:1799-1937`) — decision 파일 basis 검증(:1845-1853), key 재유도 대조(:1875-1889), REUSED면 원장 재인출 + `verifyJudgmentReuse`(:1910-1928, 재검증 본체 `:1756-1784`: key 일치 :1767 + payload 계약 :1776 + epoch :1779-1783) 후 레코드 **verbatim 재게시**(:1929-1934 — "append of an identical (key, payload) is an exactly-once no-op").
- mint P7c 결속: witness basis ∈ {EXECUTED, REUSED} **수용**(`certificate-mint.yml:2480-2482`), key/projection byte 결속(:2483-2492).

### 2.2 큐 판정(org caller merge_group) — REUSED 불가능, 3중 차단

1. **yml 배선**: `AXIOM_JUDGMENT_CAS_FORCE_EXECUTED: ${{ github.event_name == 'merge_group' && '1' || '' }}` (`admission-check.yml:2694-2696`) — callee는 caller의 event_name을 상속(실측: `mg_evidence_gate_prereg_2026-10-17.md:5`, MG 런 → landing, PR 런 → preflight).
2. **코드 단락회로**: `judgmentForceExecutionArmed`(`:1468-1475`, env=="1" **또는** `GITHUB_EVENT_NAME==merge_group` 보조 벨트) → **리저 consult 이전에** `jExecuted` 강제(`:1559-1562`). 저장 레코드는 읽히지도 않는다.
3. **attest 측 증명**: SSOT 집합 동등성(`admission-check.yml:1700-1712`) + **merge_group 한정 전 서브젝트 `"basis":"EXECUTED"` 강제**(`:1718-1730` — 비EXECUTED 하나면 fail-closed).

→ **어떤 큐 판정 경로도 REUSED 판정에 도달할 수 없다.** 카나리 실측 일치: MG run 39004833947 4 subject 전부 EXECUTED, `basis=REUSED = 0`(`mg_evidence_gate_canary2_2026-10-17.md:30-36`).

### 2.3 PR venue(org caller pull_request) — 판정 기계 자체가 미가동

- 레인 job: `if: always() && stage=='attest' && (merge_group || workflow_call)`(`:2528-2531`) — **PR에서 스킵**.
- attest witness step: `venue == 'landing'` 요구(`:1582`) — PR에서 스킵. PR = 정적 preflight 전용이며 "PR venue의 결과는 착지 자격이 아니다"(ADR-0032; `mg_evidence_gate_followup_2026-10-17.md:11-13` — 실측 로그 `venue=preflight`, 런 39004512386).

### 2.4 직접 workflow_call — REUSED 가능하나 권위 0 (프로젝트가 명시 인정한 잔여 표면)

- 이벤트가 `workflow_call`이면 벨트 발화 안 함(단위 시나리오 5: `mg_evidence_gate_prereg_2026-10-17.md:38`), venue=landing(`admission-check.yml:725`) → 레인·attest가 REUSED basis를 **허용**(`:1731-1732` else 분지). followup §1이 이것을 "실행 재사용이 남는 유일 표면"으로 명시(`mg_evidence_gate_followup_2026-10-17.md:26`).
- 그러나:
  - **(i) required-check 불가**: 필수 컨텍스트는 ruleset 20303214의 org 게이트 verdict job명 `admission-check`에 결속(`org_gate_handoff_2026-10-04.md:321`) — 직접 호출 run은 필수 검사가 아니다.
  - **(ii) mint 불가**: 활성화 가드가 `runObj.path == .github/workflows/admission-gate-v2.yml` 강제(`certificate-mint.yml:305`) + runId self-binding(:252) + 이벤트 화이트리스트 {pull_request, workflow_call, merge_group}(:304) — 직접 호출 run의 산출물로는 인증서 민팅·원장 append가 원천 차단.
  - **(iii) 호출자 부재**: 저장소 내 `uses:`로 두 워크플로를 호출하는 곳 0건(전수 grep), `workflow_dispatch` 트리거도 없음(`admission-check.yml:105-163` — workflow_call 단일).

→ **새 same-repo 래퍼가 생겨도 합격 권한·원장·인증서 어느 것도 얻지 못한다.**

### 2.5 판정 원장의 다른 소비자 전수

- 판정 CAS: 위 2곳(plan `:1565`/`:1573`, attest `:1917`)이 전부.
- **evidence CAS(§15.3 chain b+c 스킵)**: `attestation_orchestrator.nim:472-485` — armed attest가 `AXIOM_EVIDENCE_CAS_*`로 consult(`admission-check.yml:1605-1616`). **벨트가 이쪽은 덮지 않는다** — MG 착지에서도 HIT 가능. 별개 의미·잔여 검토는 §3.
- `extraction_provenance.nim:378-391` — 자체 키 스킴의 provenance read(재해시·재검증 fail-closed). 판정과 무관.
- verdict predicate의 side-ref **인증서** 스캔(`admission-check.yml:2330`) — 판정 레코드가 아닌 인증서 개체. two-pass convergence로 **인증서의 cross-run 소비는 문서화된 정상 설계**(`org_gate_handoff:97-99,121`).
- append는 P7b/P7c(`certificate-mint.yml:2219-2220`, `:2380-2381` — publish job :1237-1243)가 유일하고, `admission-check.yml`에는 append 경로가 없다.

### 2.6 epoch 안정성 — 실패 런 기록은 같은 세대 내 소비 가능 상태로 존재한다

`executionEpoch = sha256(toolchain|config|bundle)`(`src/verification/accounting/execution_context.nim:84`; 구성 :77-86). toolchain은 바이너리 컴파일타임 상수(Nim 버전 :80, lean-toolchain 핀 :83/:103, z3, arch :116, div/rem 프로파일 :117-123), config는 실행계약 다이제스트 — env는 `canonicalizeEnvValue`로 정규화(`src/verification/obligation/identity.nim:53-93`: 시스템 PATH는 canonicalize-away, elan/lean 경로만 보존)되어 러너 PATH 노이즈를 흡수한다. bundle은 lean/lake 바이너리 바이트(:77). **실무 체감**: 툴체인 핀 고정(AGENTS §3 — Nim 2.2.10, elan 경유 Lean) + 라벨 전용 이미지 롤은 epoch 구성요소를 바꾸지 않게 설계됨(`certificate-mint.yml:178-181` — "label-only rolls flipped a_fp … (114/114 census)", 2026-10-01 제거) → **epoch는 툴체인/계약 롤이라는 의도적 사건 사이에는 수일~수주간 불변**. 즉 실패 런의 기록은 같은 세대 내 이후 런에서 원칙적으로 소비 가능한 상태로 원장에 남는다 — 그래서 **소비 측 봉쇄(게이트)가 결정적인 이유**다.

### 2.7 판정 근거 요약 (사용자 프레이밍에 대한 정정 포함)

- **Row (b) 전제("이후 합격 정당화 가능")는 권위 경로에서 거짓**: red 런 기록이 소비되려면 (같은 클로저 키 + 같은 epoch + 게이트 미장착)이 필요한데, 유일한 미장착 소비 표면(direct workflow_call)은 required-check·mint·원장 모두에서 권한이 없다(§2.4). 착지 합격(큐 verdict)과 인증서는 REUSED에 절대 서지 않는다.
- **Row (c) 전제("계약상 원칙적 금지")도 거짓**: red 런 append는 금지가 아니라 **의도된 evidence-authority 설계**다(§1, `org_gate_handoff:246` "!cancelled() … deliberate"). append 금지는 등록된 **미래 계획**(prereg §6.1 → followup §5.1 — `docs/spec/certification_continuity_contract.md` P7c-x 계약 개정 + org 핀 회전 의례 필요)이지 현행 불변식이 아니다.
- **"gate가 답을 바꿨다"는 지적은 정확**: pre-gate에는 MG 재사용이 가능했고(벨트·강제·집합검증 모두 부재), 이것이 이번 세대가 차단한 것이다(`mg_evidence_gate_prereg_2026-10-17.md:11` "merge_group 착지 런의 … REUSED로 GO-critical 테스트를 건너뛰는 것을 차단").

## 3. evidence CAS §15.3 교차 실행 재사용 — 별개 의미와 잔여 검토

### 3.1 별개 의미의 명시 — "캐시 적중" ≠ "합격 권한 획득"

**"캐시 적중(HIT)이 발생한다"와 "실패 런 기록이 합격 권한을 획득한다"는 다른 사실이다.** evidence CAS HIT는:

- payload가 **실행 신원 증거**(§15.3 체인 b+c의 커널 재실행 스킵)이지 **테스트 판정이 아니다**.
- **테스트(레인)는 그대로 실행된다** — 스킵되는 것은 체인 b+c의 커널 재실행뿐이다.
- **read마다 전면 재검증**한다(`evidence_ledger.nim:380-390`).
- consult 경로: armed attest가 `AXIOM_EVIDENCE_CAS_*`로 consult(`attestation_orchestrator.nim:472-485`, `admission-check.yml:1605-1616`). **벨트가 이쪽은 덮지 않는다** — MG 착지에서도 HIT 가능(§2.5의 인접 표면; 조사에서 "사용자가 열거하지 않은 경로 1건"으로 지적된 항목).

### 3.2 미확정 항목 (입증 완료 아님 — P7c-x 계약 개정 시 검토 대상 목록)

다음은 본 조사에서 **입증하지 않은 항목**이며, 미확정으로 기록한다:

1. **직접 workflow_call 잔여 표면**: 현재 호출자 0건(§2.4 (iii))까지가 실측이며, 미래의 same-repo 래퍼 발생 가능성에 대한 상시 봉쇄는 본 조사의 입증 대상이 아니었다.
2. **evidence CAS HIT의 실측 빈도**: 실운영에서 HIT가 실제로 얼마나 발생하는지에 대한 측정치가 없다.
3. **전체 경로 재검증의 실운영 커버리지**: read마다의 전면 재검증(`evidence_ledger.nim:380-390`)이 실운영 경로 전체를 커버하는지의 실측이 없다.

→ P7c-x 계약 개정 요청 시 위 3건부터 검토한다(§5).

## 4. 적색 런 포렌식 현황 — 진단 보존 계층은 이미 존재한다

- **레인**: judgment 파일 12종 `always()` 업로드, 30일 보존(`admission-check.yml:2843-2862` — 주석 :2837-2838 "post-mortem reachability when a lane failed AFTER producing records"), 테스트별 FAIL/duration 행(:2825-2833).
- **attest**: judgment-record 번들(`:1771-1789`), evidence-record(`:1755-1761`), witness+verdict(`:2409-2442`) 전부 `always()`·30일.
- **verdict**: NOT-ADMIT 시에도 로그 조립 + `::error` annotation(`:2346-2358`) + `always()` 업로드(`:2397-2407`, if-no-files-found: error).
- **잡 로그**: GitHub 조직 보존 기준(기본 90일). 실제 포렌식 관행은 `gh run view --log` 원문 인용(`mg_evidence_gate_*_2026-10-17.md` 전 계보) + 선례 `docs/evidence/mg_red_forensics_2026-10-14.md`. 공식 문서: GitHub Docs — artifact & log retention([docs.github.com artifact-and-log-retention](https://docs.github.com/en/actions/managing-workflow-runs/storing-workflow-data-as-artifacts#about-artifact-and-log-retention)).

## 5. 권고 (증거 기반 보류 — 확정 아님)

**현재 동작 유지 + P7c 가드 보류** — 조사 판정 원문: "**Append 금지는 보류된 상태가 올바르며, 그 근거가 이제 완전하다.**" append는 의도된 evidence-authority 설계(§1)이고, 소비가 합격 권한으로 변하는 경로는 구조적으로 봉쇄됐다(§2, Row (a)).

단, 이는 **"증거 기반 보류"**이며 입증의 종점이 아니다:

- §3.2의 미확정 3건(직접 workflow_call 잔여 표면·evidence CAS HIT 실측 빈도·전체 경로 재검증 커버리지)은 입증 완료가 아니다.
- 계약 개정(P7c-x) 요청이 발생하면 §3.2 목록부터 검토한다. 개정 수반 사항(followup §5.1): (a) `docs/spec/certification_continuity_contract.md` P7c-x 계약 개정, (b) **org 핀 회전 의례** — certificate-mint.yml은 org 중앙 저장소 `Archright/.github` 소유(핀 callee 잠복 결함 선례: `docs/evidence/incident_pinned_callee_deadlock_bypass_2026-10-09.md`).

### 결정 요청 (아키텍트)

P7c 처분을 결정할 것:

| 안 | 내용 | 근거 |
|---|---|---|
| (가) | **유지 확정** — 적색 런 append 현행 동작을 의도 설계로 확정, 가드 계속 보류 | Row (a)(§2) — 합격 권위 경로 봉쇄 완전, append 금지는 현행 불변식이 아님(§1) |
| (나) | **P7c-x 개정 개시** — append 금지(또는 조건부 append) 계약 개정 착수 | §3.2 미확정 3건부터 검토 필요 + prereg §6.1/followup §5.1 등록 계획 이행 |
