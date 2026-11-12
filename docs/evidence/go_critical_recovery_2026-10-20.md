# GO-critical 레인 red 복구 — s1a evidenceId 이중 해시 (2026-10-20)

> **종류**: 사고 기록 + 복구 절차 증거 (AGENTS.md §5 — docs/evidence/는 실행 증거).
> **원칙**: 이 문서는 **관측된 사실만** 기록한다. 병합은 발생하지 않았으며, 본 문서는
> 병합·main green을 주장하지 않는다 (§6).
> **관측일**: 2026-10-20 (실행 주체: wintrover 세션 — GitHub Actions API 읽기 + 로컬 재현).
> **관련**: [docs/spec/strict_completeness_binding.md](../spec/strict_completeness_binding.md)
> §2.5 (CLE evidenceId 계약), PR #965, PR #961 (7ac99157f, strict-closure 랜딩).

---

## 1. 사고 요약

`main`(7ae9561a)의 merge-queue 필수 검증에서 GO-critical 레인(레인 0 =
`tests/unit/test_s1a_lean_golden.nim` 단독)이 **red**였다. 원인은 **테스트 기대값의
이중 해시**다 — PR #961(Phase 1A)이 evidenceId 여섯 컴포넌트 **프리이미지**에
`completenessBindingDigest`를 추가했는데, 테스트는 이미 해시된 legacyId를 다시 해싱하는
기대값을 유지했다. 구현(main)은 올바르고 테스트 기대값이 틀렸다 — 즉 **테스트 전용
결함**이다. 수정은 PR #965(`fix/s1a-evidenceid-preimage`, head
`5aa8d9aa20be5e0ea7670beff524de094f371109`)로 준비되었으며 **OPEN 상태다(휴먼 병합
필요). 병합은 이 문서 작성 시점까지 발생하지 않았다.**

## 2. 관측된 사실 (GitHub Actions, 읽기 전용 API)

### 2.1 실패 런 (EXECUTED — 실제 실행으로 관측된 red)

| 항목 | 관측값 |
|---|---|
| 런 | `39374305024` (admission-gate), 2026-10-20T05:19:48Z 생성 |
| 큐 브랜치 | `gh-readonly-queue/main/pr-965-c53192fabeafe9181c3b263e63368f7c5b8b1222` |
| 실패 job | `attest / go-critical-lane (0)` (id `118469349149`, conclusion failure) |
| 후속 실패 | `attest / go-critical-rollup`, `admission-check` (needs edge 전파) |
| 통과 형제 | `attest / go-critical-lane (1)` (proof_integrity/d2 레인) success |

job `118469349149` 로그의 원문 (GitHub 로그 라인 번호):

- L1006: `AXIOM_JUDGMENT_CAS: EXECUTED — no record for the current closure (fresh judgment)`
  — 레인이 s1a 스위트를 **실제 실행**(EXECUTED basis)했음을 표시.
- L1330: `tests/unit/test_s1a_lean_golden.nim(348, 23): Check failed: e.evidenceId == expected`
  — **테스트 파일 348행**(프리-#965 기대값 비교 지점).
- L1331: `` e.evidenceId was 4e5b7b841f9c463f707cf39224bf5d51e701a8bc3ceea3697794d5dadd4404f3 ``
- L1333: `[FAILED] evidenceId = H(6 components) and identity components are distinct spaces`

### 2.2 통과 런 (REUSED — 실행 0건의 skip, red 소명 아님)

| 항목 | 관측값 |
|---|---|
| 런 | `39376949288` (admission-gate), 2026-10-20T05:49:24Z 생성, 같은 큐 브랜치 |
| 관련 job | `attest / go-critical-lane (0)` (id `118477549765`, conclusion **success**) |

같은 job 로그 원문:

- L1033: `AXIOM_JUDGMENT_CAS: REUSED — record 660467cbe8ee re-verified (closure re-derivation + executionEpoch + per-read re-hash all passed)`
- L1105: `[admission-tests] SKIP — tests/unit/test_s1a_lean_golden.nim (AXIOM_JUDGMENT_CAS basis=REUSED — record re-verified, no kernel run this attempt)`
- L1106: `[admission-tests] PASS — 0/0 GO-critical admission tests green (lane=0: tests/unit/test_s1a_lean_golden.nim)`

**해석 (관측 기반)**: 이 green은 `basis=REUSED` 판정에 따라 **테스트를 0건 실행한
skip**이다 (`PASS — 0/0`). 실행된 red 관측(§2.1)은 이 런에서 재실행되지 않았으므로,
이 PASS는 s1a red의 해소를 **입증하지 않는다** — AGENTS.md §2.3: required checks가
실질 0건이면 UNKNOWN / NOT READY이지 SUCCESS가 아니다. 외부 계약으로도, GitHub는
"**A job that is skipped will report its status as "Success". It will not prevent a
pull request from merging, even if it is a required check.**"라고 명시한다
([Control jobs with conditions](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/control-jobs-with-conditions))
— 즉 required check의 skip은 플랫폼상 Success로 보고될 수 있으므로, 레인 스텝이
"platform counts skipped steps as success, so a silent skip would be theater"를
전제로 skip 사실을 명시 출력하는 것이다 (`admission-check.yml` 레인 스텝 주석).

### 2.3 레인 정의 (인용 지점 검증)

- `.github/workflows/admission-check.yml:2533` — `go-critical-lane:` job
  (merge_group / workflow_call 전용; pull_request 이벤트에선 skipping — PR #965 head
  푸시의 `attest / go-critical-lane`이 skipping인 것은 정상이며 통과 아님).
- `.github/workflows/admission-check.yml:2548-2550` — matrix lane 0 =
  `tests/unit/test_s1a_lean_golden.nim` 단독 (`subjects: s1a`).
- `.github/workflows/admission-check.yml:2556-2560` — 레인이 **executor tree B**
  (base.sha 체크아웃, workspace root)를 checkout하는 스텝.
- `.github/workflows/admission-check.yml:2781-2829` — `[lane] GO-critical admission
  tests` 스텝: `make test-fast-one T=$t` 실행, `basis=REUSED`면 SKIP, `EXECUTED`면
  PASS 문구.
- `Makefile:1006-1009` — `test-fast-one` 타깃 (단일 테스트 증분 검증).

### 2.4 PR #965 상태 (관측 시점)

- state `OPEN`, `mergeable: MERGEABLE`, base `main`, head
  `5aa8d9aa20be5e0ea7670beff524de094f371109`
  (https://github.com/Archright/Axiom/pull/965).
- 변경은 `tests/unit/test_s1a_lean_golden.nim` **단일 테스트 파일** — 구현 파일 없음
  (독립 리뷰 결론: **MINIMAL CORRECT**, §4).
- PR 리뷰·코멘트 0건에서 본 문서 세션이 독립 리뷰 결과를 PR 코멘트로 기록했다.

## 3. 로컬 검증 (이 세션 — 워크트리 재현)

관측 사실 — 복구 브랜치의 로컬 신규 빌드 재현 결과:

- 명령 (워크트리 `/tmp/axiom-s1a-hardening`, 브랜치 `fix/s1a-failclosed-docs`,
  베이스 = PR #965 head):

  ```
  nim c -d:release --hints:off --warnings:off -o:bin/ax src/cli/main.nim
  AXIOM_IRCHECK_CMD=<repo>/proofs/.lake/build/bin/ircheck \
    nim c --hints:off --warnings:off --nimcache:build/nimcache/test \
    -o:/tmp/axiom-s1a-axone tests/unit/test_s1a_lean_golden.nim
  AXIOM_IRCHECK_CMD=<repo>/proofs/.lake/build/bin/ircheck /tmp/axiom-s1a-axone
  ```

- 결과 (2026-10-20 실행, 종료 코드 0): **전 스위트 통과** — 14 `[OK]`, 1
  `[SKIPPED]`(판정 CAS flush — 비무장 설계 동작), 0 실패. 원문:

  ```
  [Suite] S1-A — Generic lowering produces genuine Lean kernel ACCEPT
    [OK] generic lowering renders the actual IR body + I6 theorem
    [OK] genuine Lean 4.33 kernel ACCEPTS the generated theorem
    [OK] mul/div body renders the Certified subset and the kernel ACCEPTS it

  [Suite] S1-A — Full canonical chain yields vdVerified (genuine KAA)
    [OK] executeCanonicalVerification produces a genuine VERIFIED result
    [OK] mul/div fixture proves through the full chain (mul body support)
    [OK] S1-B identity fixture (result == x) proves through the chain
    [OK] full chain is deterministic (same input → same identities)
    [OK] toolchain fingerprint is deterministic across two calls
    [OK] toolchain fingerprint is not the old hardcoded constant

  [Suite] S2 — CanonicalLeanEvidence binds obligation/proposition/source/KAA
    [OK] canonical evidence exists and is internally hash-consistent
    [OK] evidenceId = H(6 components) and identity components are distinct spaces
    [OK] negative control — strict binding removed, marker kept → no evidenceId (fail-closed)
    [OK] canonical KAA projection is deterministic across runs
    [OK] splice resistance — cross-assembled genuine evidence is rejected
    [SKIPPED] judgment CAS flush — the canonical judgment set (armed: emit; unarmed: pass)
  ```

  강화 3점이 모두 이 PASS에 포함된다: materializer fail-closed `check` 3종,
  `cleCompletenessBindingDigest.len == 64` 가드(「evidenceId = H(6 components)」
  테스트 선행 단언), binding-removed 음성 제어의 양성/음성 레그. setup 내 실패
  `check`가 해당 테스트를 FAILED로 중단시킨다는 unittest 의미론
  ([nim-lang.org/docs/unittest.html](https://nim-lang.org/docs/unittest.html))이
  materializer fail-closed 경로의 관측 가능성을 정의한다.

## 4. 독립 리뷰 결과 (이 세션)

PR #965에 대한 독립 리뷰 결론: **MINIMAL CORRECT**.

- **test-only**: diff는 `tests/unit/test_s1a_lean_golden.nim`의 기대값 유도 한 곳 —
  이중 해시 제거, 구현 변경 0.
- **splice-resistance preserved**: `newCanonicalLeanEvidence`의 KAA↔source
  (`receiptArtifactIdentity == sha256(leanSource)`), theorem-name, toolchain
  fail-closed 결속은 그대로이며, 로컬 스위트의 `splice resistance` 테스트가 `[OK]`로
  재확인됨.
- **local fresh-build PASS**: §3 — 워크트리에서 bin/ax + 테스트 바이너리 신규 빌드 후
  전 스위트 통과.

## 5. 복구 절차 (휴먼 게이트) — 에이전트 금지 규칙 포함

1. PR #965(test-only 기대값 수정)에 대한 독립 리뷰 기록(§4) → **휴먼이 병합 판단**.
2. 병합은 GitHub merge authority로만 확정된다(AGENTS.md §2 — merge authority는
   GitHub). 큐 재진입 시 `go-critical-lane`이 `EXECUTED` basis로 재실행되어야 하며,
   `basis=REUSED`/`PASS — 0/0` skip(§2.2)으로는 필수 검증이 충족되지 않는다.
3. **명시적 규칙: 에이전트는 required checks를 우회하지 않는다.** required check의
   재실행·재판정 대체·skip 해석에 의한 통과 처리·`--no-verify`·ruleset 변경 — 모두
   금지다. 실패한 필수 검증의 유일한 복구 경로는 (a) 결함 수정(test-only PR) +
   (b) 휴먼 승인 하의 필수 검증 재실행이다.
4. 복구 작업의 레인 범위: 본 사고의 red는 **레인 B(executor tree = base.sha)의
   s1a 단일 테스트**뿐이다(§2.3). 레인 1(proof_integrity/d2)과 나머지 필수 검증은
   실패 런에서 success로 관측됐다 — 복구는 이 레인에 한한다.

## 6. 이 문서가 주장하지 않는 것

- **병합은 발생하지 않았다.** PR #965는 OPEN이며 휴먼 병합 대기다.
- **main green을 주장하지 않는다.** 마지막 EXECUTED 관측은 red(§2.1)다; 이후 green
  관측은 REUSED skip(§2.2)뿐이라 필수 검증의 재실행 소명은 없다.
- 본 문서는 측정 경제성·레인 설계 변경을 다루지 않는다(범위 닫힘 — §2.2 작업 범위
  정책). 레인 스킵 자체의 계약은 `admission-check.yml` 레인 스텝과
  [docs/evidence/go_critical_parallel_decomposition_2026-10-11.md](go_critical_parallel_decomposition_2026-10-11.md)
  계열의 선행 증거를 따른다.
