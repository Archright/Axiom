# C_out SAT→cvConfirmed 경로 미발화·커버리지 판정 — VS-2 PR-4 parity 조사

> **Status**: Investigation evidence record — 조사 전용 (src 무수정)
> **Created**: 2026-10-31
> **Investigated revision**: `origin/main` = `53e49e1139a35d854946f3d7d8d4a78b37a66e31` (worktree `work/inv-cout`; PR #1130 merge `b16d25c1c` 이후, PR #1131/#1132 docs PR 포함)
> **Investigated PR**: VS-2 PR-4 — cout (body-carry/C_out payload) lane flip, PR #1130, merge OID `b16d25c1c2a8184483b5f9d4da33469049c5a57b` (2026-10-30T14:19:59Z)
> **SSOT**: [docs/design/vs2_external_subject_registry_spec_2026-10-24.md](../design/vs2_external_subject_registry_spec_2026-10-24.md) (§1.4, §2.7, §2.8, §5, §7) + [docs/evidence/nim_stew_base36_cout_slice_2026-10-10.md](nim_stew_base36_cout_slice_2026-10-10.md) (2026-10-10형 골든 실행)
> **질문**: (1) PR #1130의 parity 실행에서 "2026-10-10형 SAT→cvConfirmed 파이프라인 경로"가 발화하지 않은 이유는 무엇인가? (2) 무수정 in-tree 테스트 스위트가 그 의미(반증 보증)를 실제로 대신 보증하는가 — 커버리지 갭인가?

---

## 1. 파이프라인 실체 — SAT→cvConfirmed 전환 경로 (src 근거)

"2026-10-10형 SAT→cvConfirmed 파이프라인 경로"는 다음 5단계 사슬이다. 각 단계의 발동 조건을 file:line으로 고정한다.

| # | 단계 | 근거 | 발동 조건 |
|---|---|---|---|
| a | BMC SAT 후보 + 모델 | `src/verification/batch_uap/ir_pipeline_runner.nim:1348-1350` | `bmcOutcome.status == sosSat and bmcCe.model.len > 0` — 모델 없는 SAT 후보는 승격 불가 (`src/core/trusted/candidate_evidence.nim:31-36`, DECISION-0303: "the P4 cvConfirmed promotion would be unreachable for every BMC SAT" 방지) |
| b | P4 witness admission | `src/verification/counterexample_validator.nim:144-180` (DECISION-0311 `validateCounterexample`) | 후보가 비지 않고(`candidate.isEmpty()` false, :151) 모델이 있으며(:153) 모델에 상태가 있으면(:155) Z3로 `pre ∧ ¬post`를 discharge — **solver SAT → `cvConfirmed`** (:173-174), Unsat/타임아웃/모순 → cvSpurious/cvUnresolved (fail-closed) |
| c | 승격 | `src/verification/counterexample_validator.nim:182-193` (DECISION-0312 `finalizeVerdict`) | `cvConfirmed` → `makeDisproved(smBMC, …, psBounded)` = **`vsDisproved`** (I3 binding). 저장소 전체에서 `makeDisproved` 호출부는 이 한 곳뿐이고(`grep` 실측 — §5), `makeDisproved` 정의는 `src/core/trusted/verification_result_types.nim:106-108` — 즉 **vsDisproved는 cvConfirmed 승격의 유일 산물** |
| d | ce-replay (BUG_FOUND 페이로드) | `src/verification/batch_uap/ir_pipeline_runner.nim:1605-1624` | `status == vsDisproved` ∧ `provenance != vpInductiveLoop`(BMC lane 전용) ∧ `model.len > 0` → `replayConfirmedDisproof`; `replay.agreed` → `[ce-replay] … BUG_FOUND payload assembled (N records)` (:1613-1615), 불일치/불가 → fail-closed cvUnresolved 강등 (:1616-1624) |
| e | 노드 터미널 (exit 1) | `src/verification/batch_uap/loop_driver.nim:509-522` | `verification.status == vsDisproved` → hard-failure 노드 터미널. "Fail-closed direction: only the P4 finalizer's cvConfirmed promotion produces vsDisproved" (:517-519) |

ce-replay 어댑터의 subject 식별: `src/verification/counterexample_replay.nim:929` — `git -C <repoRoot> rev-parse HEAD`로 `subjectGitRef` 측정, 측정 불가·porcelain 불일치 → `rvUnavailable` (fail-closed, :32, :931, :1049-1072).

## 2. "2026-10-10형" 선행 사건

- **골든 실행**: [docs/evidence/nim_stew_base36_cout_slice_2026-10-10.md](nim_stew_base36_cout_slice_2026-10-10.md) — S2 슬라이스 BUG_FOUND(C_out) 판정. 당시 `bin/ax prove --project /tmp/b36slice/nim-stew --target "stew/base36.nim::decodedLength"` 실행에서 **C_out 레인이 발화**: `canonical-declined` → BMC lane fall-through → BMC SAT(`L=3`) → P4 `cvConfirmed` → **`vsDisproved`** (문서 82행) → ce-replay agreed **14 records** (83행) → exit 1 (86행).
- **당시 발화가 가능했던 조건**: sidecar 채택 문서(`config/spec/nim_stew_base36_sidecar.json`, adoptedAt 2026-10-19)가 아직 없어, `decodedLength`를 지배하는 레인이 C_out뿐이었다.
- **정정 이력** (문서 99행): 최초 계측에서는 P4 승격 반박의 노드 계층 소비자가 없어 legacy UAP fall-through가 노드를 `no_obligation`으로 분류 → exit 0(spin6). `a4a7af76b`가 stage2Budget에 P4 `vsDisproved` 노드 터미널을 추가 — 그 코드가 현재 `loop_driver.nim:509-522`이고, 코멘트에 "observed 2026-10-10, base36 C_out spin"이 기록되어 있다(:516).
- 따라서 "**2026-10-10형**" = 위 1절 a–e 사슬이 C_out 레인에서 라이브로 발화해 BUG_FOUND(C_out)·exit 1로 수렴하는 실행 형태를 지칭한다.

## 3. PR #1130 parity 실행에서의 미발화 원인

### 3.1 원인 1 (지배적) — 설계된 dispatch 우선순위에 의한 C_out 셰도잉

`ax prove`의 외부 주제 후보 dispatch는 `isEligible` 클로저(`src/cli/axiom_engine.nim:5393-5452`)에서 일어난다:

1. 커널 레지스트리 hit 우선 (:5396-5397).
2. **레지스트리 dispatch 루프** (:5412-5428): `prepared.subjectRegistry.entries`를 **ascending (precedence, specRelPath)** 순회. sidecar (precedence 10)가 C_out (precedence 20)보다 먼저 consult된다.
3. 두 레인은 **동일한 (module, symbol) 키**를 지배한다:
   - sidecar: `overlayDeclaresSidecarSubject` = `modulePath == domain.modulePath and fnName == domain.symbol` (`axiom_engine.nim:2308-2313`) — adoption이 pin한 `stew/base36.nim::decodedLength`
   - C_out: `overlayDeclaresCoutSubject` = 동일 형태 (`axiom_engine.nim:1344-1349`) — `decodedLength`
4. 루프의 반환 프로토콜: `synth.isOk()`면 **ok(true)와 ok(false) 모두 즉시 return** (:5423-5424) — err만 다음 레인으로 fall-through. sidecar 합성이 성공(ok(true))하는 순간 dispatch가 종료되어 **C_out 어댑터(capabilityAdapterFor의 cout 분기, :4476-4477)는 consult되지 않는다.**

이것은 우연이 아니라 설계다: VS-2 spec §1.4 — "sidecar 10 < cout 20 — all three govern `stew/base36.nim::decodedLength`; **the hash-bound adoption must win when present**" (spec 116-117행; engine 코멘트 :5402-5408 "the HASH-BOUND adoption must decide first"). PR-3(#1099) 본문도 "the registry loop moves ABOVE the still-unflipped chain arms … precedence §1.4 requires the HASH-BOUND adoption to decide first"로 명시한다.

**PR #1130 parity 실행의 관측과의 일치**: PR 본문의 parity 세션 로그에서 accepted/excluded 라인은 `sidecar carriers synthesized … obligations=3/3 eligible=true/true`와 `frontier eligibility gate: excluded 442 … eligible=1` — 즉 이 실행에서 합성·의무 실행된 유일 후보는 **sidecar 캐리어**였고, `decodedLength_cout_binding` 합성 라인은 부재하다. PR 본문 비클레임이 이를 그대로 기록한다: "the C_out synthesis/obligation line did not fire on this target". C_out 캐리어가 합성되지 않았으므로 1절 a–e 사슬 전체(C_out의 SAT→cvConfirmed)가 도달 불가였다.

### 3.2 원인 2 (하위 조건) — subject identity fail-closed층

C_out arm이 발화하더라도 사슬 완주에는 git identity를 가진 subject가 필요하다:

- canonical(Lean kernel) leg: `buildSubjectBinding`은 `measureSubjectGitRef`가 빈 문자열을 반환하면 `err("subject binding: subjectGitRef unmeasurable …")`로 fail-closed한다 (`src/verification/obligation/canonical_verification.nim:1510-1514`; subject root 해석은 :834-863 `resolveSubjectRepoRoot` — 콘텐츠 수신(content-carried)이며 threaded root가 없으면 의도적으로 `""`, WP4-a B-5b).
- ce-replay leg: `subjectGitRef` 측정 불가·porcelain 불일치 → `rvUnavailable` (`counterexample_replay.nim:929-931`).

PR #1130 본문의 대응 관측: "The C_out seal/replay legs reported `evidence=inconclusive sealError=subject binding: subjectGitRef unmeasurable` against the non-git store copy — fail-closed, never fabricated". 즉 이 실행 세션에서 git identity 비보유 subject 표현(store copy)에 대한 seal leg는 fail-closed로 기록됐다. 반면 **sidecar-defect의 ce-replay는 pin 일치 git-identity subject(`nim-stew@1853f20b`, blob `b8a42a6a…`)에서 실측됐다** — "replay agreed; BUG_FOUND payload assembled (13 records)" (PR 본문). PR-3(#1099) 실행에서는 같은 sidecar ce-replay가 subject HEAD≠pin 1853f20b로 `rvUnavailable` fail-closed였으므로(PR-3 본문 parity 절), PR-4 실행의 차이는 레인 로직이 아니라 **subject 정체성 전제의 충족 여부**다.

### 3.3 parity가 측정하는 것 — 발화와 무관한 축

"6/6 entries registry-decision == chain-decision, mismatches=0"은 **엔트리별 활성화 결정** 비교다:

- `axiom_engine.nim:5257-5356` registryParityShadow: 엔트리마다 `registryActive`(엔벨로프 유효; optional 레인은 shared pin — 모듈 부재 시 inert, :5275-5294) vs `chainActive`(퇴역 체인의 반사실 — 플립 레인은 legacy loader+pin을 관측 전용으로 재계산, C_out은 :5324-5330 `loadBase36CoutOverlayDomain` 결과)를 비교해 로그(:5341-5356). 동작 변경 없음(observability-only, :5264-5268).
- 즉 parity bar(spec §7: mismatch 0 + accepted/excluded 필드 순서 라인)는 **어느 레인이 그 심볼을 지배하는지의 결정 일치**만 보증하며, SAT→cvConfirmed 사슬의 발화를 요구하지도 관측하지도 않는다. parity 결과와 미발화는 모순이 아니라 별개 축이다.

## 4. 커버리지 판정 — 무수정 in-tree 스위트가 대신 보증하는가

### 4.1 PR #1130이 통과시킨 5종 스위트 (PR-4 베이스 `474392b11` 이후 무수정 — `git diff 474392b11..HEAD -- <5 files>` 빈 diff 실측)

| 스위트 | 단언 내용 (대표 file:line) | 담당 보증 |
|---|---|---|
| `tests/unit/test_base36_cout_binding.nim` (26 tests = 11/7/5/3) | Suite 1: soExplicit 로드·도메인/K/결정벡터 핀·8종 fail-closed 변형 (:79-145). Suite 2: 단일-기원 캐리어 형태·β-splice 정확-1회·스코프 가드 (:151-252). Suite 3: **실제 ce-replay 어댑터 end-to-end** — 손으로 만든 SAT 모델(`sat\n(define-fun length … #x…0003`, :337-338)을 git 초기화 fixture(:271-282)에 실행, **무조건** `replay.agreed`·4요소 레코드 단언 (:329-352). Suite 4: **실제 파이프라인** `runIrPipelineWithCas` (:359-364) — `vsDisproved` ∧ `replay.verdict=rvAgree` ∧ clDisproved ∧ 4요소 (:370-410), dirty 시 fail-closed cvUnresolved 강등 (:380-384, :404-410) | **SAT→cvConfirmed 사슬의 의미** (아래 4.2) |
| `tests/unit/obligation_subject_binding_test.nim` (25 tests) | I1 바운드 의무 정체성: 결정론·컴포넌트 완전성·shadow model 불가·심드 실패 폐쇄·평가 구현 다이제스트·단일-기원 바인딩 (suite 제목 :57-415) | subject 바인딩의 fail-closed 정체성 (3.2층의 의미) |
| `tests/unit/test_external_subject_registry.nim` (596 L) | 로더·엔벨로프 거절(중복 specId/미지 capability/<expr> 슬롯/우선순위 충돌 등)·어댑터 검증(d2 규칙 verbatim)·`publishExternalCandidate` 경유 합성·결정론·NOT-an-adoption 가드 (:155-586) | **dispatch 와이어링의 단위층** (3.1층의 의미) |
| `tests/unit/test_bug_attribution_display.nim` (34 tests) | §2.8 표시 경로: 라이브 SPEC-B36-COUT 투영 — "Axiom-Defined Rule Violated / Bug Suspected / upstream-spec", machineStates `[vsDisproved, rvAgree]` (:403-441), 블록 부재 ≠ Unknown (:443-464, :558) | display seam (PR-4의 §2.8 rewiring) |
| `tests/unit/test_base36_contract_policy.nim` (14 tests) | I4 canonical 검증 정책, I5 out-of-tree soExplicit 오버레이 권위 (:44, :124) | 계약 권위층 |

### 4.2 SAT→cvConfirmed 경로 자체는 in-tree에서 실측된다 — 갭 없음 (경로 의미 축)

핵심 사실: **테스트의 `vsDisproved` 단언은 곧 cvConfirmed 승격의 발화 증거다.** §1-c에서 확정했듯 vsDisproved의 생산자는 `makeDisproved` 한 곳(cvConfirmed 케이스)뿐이며 직접 대입 경로도 없다(`grep "= vsDisproved"` src 실측 — 단언문 외 0건). 따라서:

- Suite 4가 `runIrPipelineWithCas`(실제 `ir_pipeline_runner` 파이프라인) 결과에 `res.verification.status == vsDisproved`를 단언하는 한 (:378, :403), 그 테스트 실행은 **BMC SAT → Z3 재검증 → cvConfirmed → vsDisproved** 전환이 실제로 일어났음을 기계적으로 증명한다. 2026-10-10 문서도 "판정 스위트는 실제 `runIrPipelineWithCas` 경로에서 vsDisproved ∧ clDisproved ∧ 4요소를 측정"(142행)으로 기록한다.
- Suite 3은 어댑터(`replayConfirmedDisproof`)의 agreed 경로를 **무조건적으로** 실측한다 — 조건부가 아닌 `check replay.agreed` (:342)이므로, 환경이 어떻든 ce-replay 동의 경로의 실재는 매 실행 검증된다.
- fail-closed 방향도 대칭으로 검증된다: Suite 4의 두 번째 수용 상태(demote → `rkCandidateCounterexample` + `replay:` 진단, :380-384)와 Suite 3의 shape-파생 fail-closed (:309-315), Suite 2의 스코프 가드 (:219-252)는 cvSpurious/cvUnresolved 강등이 조작 불가능함(위조 불가)을 보증한다.

즉 PR-4 비클레임이 위임한 "반증 의미는 무수정 스위트의 in-tree leg가 대신 입증"이라는 주장은 **경로의 의미(승격 조건·I3 결합·4요소 페이로드·fail-closed 강등)에 대해서는 성립한다 — 갭 없음.** 본 조사가 이를 환경 의존이 아닌 실측으로 확인했다: 클린 트리에서 무수정 스위트가 2026-10-10형 경로(`replay agreed … 14 records`)를 라이브 재현하고, 더티 트리에서는 fail-closed 강등 분기로 수렴한다(§5.1).

### 4.3 남는 한계 — 라이브 CLI 조합 관측의 셰도잉 (갭의 정확한 성질)

갭이 전혀 없는 것은 아니다. 정확한 성질은:

1. **조각별 커버 vs 라이브 조합**: 5종 스위트는 (i) 어댑터 leg(`loadBase36CoutOverlayDomain`/`synthesizeBase36CoutCandidate` — PR-4 이후 어댑터의 validate/synthesize leg와 VERBATIM 동일 procs, PR 본문)를 직접 호출하고, (ii) 레지스트리 로더를 단위로, (iii) 파이프라인을 단위로 검증한다. **`prepareProofRun` dispatch → C_out 합성 → 파이프라인**의 라이브 조합을 한 번에 통과하는 in-tree 아티팩트는 없다.
2. **라이브 조합의 현재 발화 불가능성**: 저장소의 `config/spec/`에 sidecar 채택 문서가 존재하는 한(§3.1), 실제 `ax prove --target stew/base36.nim::decodedLength` 실행은 sidecar에서 dispatch가 종료된다 — C_out의 라이브 SAT→cvConfirmed는 **설계상 관측 불가**다. 2026-10-10 골든 실행(프리-레지스트리·프리-sidecar 엔진)이 그 형태의 마지막 라이브 관측이다.
3. **조합을 잇는 장치와 그 한계**: (i) parity shadow는 활성화 결정만 비교(§3.3) — 합성→판정 체인의 라이브 발화는 보증하지 않는다. (ii) 어댑터 leg = public procs verbatim은 PR 본문의 서술이지 기계 검증은 아니다 — 다만 4개 스위트가 같은 procs를 컴파일·실행하므로 어댑터가 다른 구현을 가리키면 스위트가 깨진다(컴파일-계약). (iii) dispatch 순서·ok/err 프로토콜은 레지스트리 스위트와 engine 코멘트(:5398-5428)로 고정되지만, "sidecar가 decodedLength에서 이기면 C_out이 도달 불가"라는 상호작용 자체를 단언하는 테스트는 없다.

**판정**: 경로 의미 축 — **갭 없음** (4.2). 라이브 CLI 조합 관측 축 — **설계된 셰도잉에 의한 관측 소멸**이며, 이는 보증 상실이 아니라 보증 이동이다(해시-바운드 채택 우선 = spec §1.4의 의도). 다만 "이동이 온전한가"는 조각별 합성 논증에 의존하며, 그 마지막 연결고리(sidecar 우선 → C_out 불도달 상호작용)만 기계 단언이 없다 — 이것이 유일한 잔여 갭이고, 성질은 **관측 가능성 갭**(보증 갭 아님)이다.

## 5. 실측 (2026-10-31, 본 조사 워크트리에서 수행)

```
$ git diff --stat 474392b11..HEAD -- tests/unit/test_base36_cout_binding.nim \
    tests/unit/obligation_subject_binding_test.nim tests/unit/test_bug_attribution_display.nim \
    tests/unit/test_base36_contract_policy.nim tests/unit/test_external_subject_registry.nim
(빈 출력 — 5종 모두 PR-4 베이스 이후 바이트 무수정)

$ grep -c "^  test \"" tests/unit/test_base36_cout_binding.nim
26

$ grep -rn "makeDisproved(" src/ --include="*.nim"
src/verification/counterexample_validator.nim:189:    result = makeDisproved(smBMC, candidate.provenance, psBounded)
(저장소 전체 호출부 1곳 = cvConfirmed 케이스)

$ AXIOM_IRCHECK_CMD=<ircheck> nim r --hints:off --warnings:off tests/unit/test_base36_cout_binding.nim
(아래 §5.1의 두 실행)
```

### §5.1 스위트 실측 기록 (26/26, 양 분기 모두 관측)

실행 1 — **클린 트리** (`git status --porcelain` = 0항목): **RC=0, [OK] 26, [FAILED] 0**. 파이프라인 스위트가 **2026-10-10형 경로를 in-tree에서 라이브 발화**시켰다:

```
[INFO] ir_pipeline_runner: [ce-replay] decodedLength_cout_binding — replay agreed; BUG_FOUND payload assembled (14 records)
  [OK] the honest subject's C_out obligation is refuted — or fails closed
  [OK] the claim leg derives clDisproved
  [OK] the counterexample payload carries the four BUG_FOUND elements — or fails closed
```

`replay agreed … (14 records)`는 골든 실행과 동일한 레코드 수이며, `[ce-replay]` 발행 조건이 `status == vsDisproved`(§1-d, ir_pipeline_runner.nim:1605)이므로 이 로그 라인 자체가 **BMC SAT → Z3 재검증 → cvConfirmed → vsDisproved** 전환의 실측 증거다 (vsDisproved의 생산자는 makeDisproved 한 곳 — §1-c).

실행 2 — **더티 트리** (untracked 파일 1건 존재 — 본 문서 초안이 porcelain을 오염): **RC=0, [OK] 26, [FAILED] 0**. 수용된 두 상태 중 fail-closed 강등 분기가 관측됐다:

```
[INFO] ir_pipeline_runner: [ce-replay] decodedLength_cout_binding — replay rvUnavailable:subject tree drifted during replay (hash/porcelain mismatch); fail-closed cvUnresolved
  [OK] the honest subject's C_out obligation is refuted — or fails closed
```

이 강등은 ir_pipeline_runner.nim:1616-1624에서 **vsDisproved에 도달한 뒤에만** 가능하므로(강등 코드의 진입 조건이 승격된 상태), 이 분기 역시 승격이 일어났음을 전제한다 — 위조 불가. 환경 오염은 판정을 조작하지 않고 fail-closed 방향으로만 움직인다는 스위트 설계("exactly two accepted states, never a fabricated verdict")가 그대로 실측됐다.

기타 실측: 스위트 컴파일·실행에는 `bin/ax` 무결성 검사가 요구되어 worktree에서 `nimble build` (Nim 2.2.10)로 표준 경로 준비; ircheck는 operations.md Trap 4 표준 경로(`AXIOM_IRCHECK_CMD`)로 주입. state dir은 `/tmp/ax_b36_cout_test_state` (저장소 무오염 — 실행 후 porcelain은 본 문서 1건만 표시).

## 6. PR-1/2/3 선순위 레인과의 관례 정합성

| PR | 레인 | ce-replay 발화 여부 | 기록 방식 |
|---|---|---|---|
| PR-1 #1097 (bv) | arithmetic-law | **발화** — `[ce-replay] bvSliceLenActual — replay agreed; BUG_FOUND (13 records)`, node FAILED, exit 1 | 정상 관측으로 기록 |
| PR-3 #1099 (sidecar) | body-carry | **미발화** — subject HEAD≠pin → `rvUnavailable` fail-closed | 비클레임으로 명시: "No claim that the counterexample replay executed … failed closed on a subject-identity precondition and is reported as-is" |
| PR-4 #1130 (cout) | body-carry | **미발화(C_out)** — dispatch 셰도잉(§3.1) + store-copy fail-closed(§3.2); sidecar-defect은 발화(13 records) | 비클레임으로 명시: "No claim that the C_out counterexample executed the 2026-10-10 golden SAT→cvConfirmed path … the suite's in-tree refutation legs are green" |

세 PR 모두 (a) parity bar(spec §7)를 mismatch 0·accepted/excluded 라인으로 충족하고, (b) SAT→cvConfirmed 미발화 시 그 이유를 fail-closed 관측으로 as-is 기록하며, (c) 위임된 보증을 무수정 스위트의 in-tree leg로 대체한다는 동일 형태다. **관례 정합성: 정합.** parity bar가 발화를 요구하지 않는 이상 미발화는 인수 가능 관측이고, PR-4는 PR-1/2/3의 기록 관례를 정확히 따랐다.

## 7. 권고 (구현 금지 — 계획 필요 항목)

잔여 갭(§4.3-3)의 성질이 "관측 가능성"이므로 최소 해결은 구현이 아니라 **관측 복원**이다:

1. **sidecar 부재 트리에서의 라이브 C_out 재관측 1회**: sidecar는 presence-optional이므로, `config/spec/nim_stew_base36_sidecar.json`을 제외한 spec dir로 `ax prove --target stew/base36.nim::decodedLength`를 1회 실행하면 C_out arm(precedence 20)이 라이브로 발화한다 — 2026-10-10형 경로의 현행 엔진(레지스트리 dispatch 포함) 재관측. 엔진 수정 0건, 관측 1회.
   - 주의: pin 일치 git-identity subject(nim-stew@1853f20b)에서 실행해야 §3.2층이 fail-closed 되지 않는다.
2. **(선택, PR-6 이후)** dispatch 상호작용 단언: "sidecar 합성 ok(true) 시 C_out 미도달"을 fixture 스위트에 추가하는 것은 구현이 아니라 테스트 1건이나, §0.12상 신규 보증 추가가므로 계약 개정 판단이 선행되어야 한다 — 본 조사는 이를 요구하지 않는다.

## 8. Non-conclusions / UNKNOWN

- **UNKNOWN**: PR #1130 parity 세션의 원시 로그는 저장소에 커밋되어 있지 않아(검색 실측 — docs/·logs/·data/에서 해당 parity 라인 미발견), 본 문서의 실행 관측은 PR #1130 본문 인용에 의존한다. PR 본문은 GitHub 저장 기록이므로 변조 방지 참조로 유효하나, 원시 stderr 전문은 UNKNOWN으로 명시한다.
- 본 문서는 C_out·sidecar 외 레인(bv/d2/sizing/rem)의 발화 상태를 재판정하지 않는다(PR-1/2 본문 기록으로 충분 — §6).
- `nim-stew@<sha>` 프로젝트 참조의 내부 해석(store copy vs git clone)은 CLI 인자 해석층까지 역추적하지 않았다 — PR 본문의 "non-git store copy"/"git-identity subject" 대비 관측만 인용한다. (§3.2의 fail-closed 코드 경로는 코드로 확정됨.)
- 2026-10-10 문서의 스위트 내역("합성 8")과 현행 파일(합성 7, 총 26)의 세부 불일치는 역사 기록 문제로 판단하며 현행 값을 권위로 삼는다(총수 26은 일치).
