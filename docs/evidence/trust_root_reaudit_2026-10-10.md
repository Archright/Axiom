# 신뢰 루트 소급 감사 기록 — S0' (2026-10-10)

- **감사 대상**: main 신뢰 루트(검증기 자신)의 closure 핀 — `config/trusted_writer_set.json`의 `trustedCheckerTreeClosure`
- **H0**: `999327ab088a73d80f4088f21d4625b4c0587867` (측정 시점 origin/main HEAD — #667 병합 `88b52abec` 및 이후 #654·#662 포함)
- **값 생성 authority**: 기존 `tools/ci/derive_checker_closure.nim` (재구현·손편집 없음 — ADR-0025 파생 authority)
- **성격**: 사후 감사·소급 수용 기록. #667("rotation 정합 3종 — closure 재앵커", 2026-10-09 17:08:38Z 병합, 리뷰 0건)이 이미 수행한 핀 840→857 재앵커를 H0에서 재측정하여 대조하고, 아키텍트 수용문을 기록한다.
- **판정 요약**: 재측정 **Δ=∅** (핀 == 유도, 857 멤버 집합 동일). 수용문 §4. 후속 등록 §5. 정규 구멍(S1-C/D) 기록 §6. 픽스처 계획 §7.

---

## §1. 재측정 실측 — Δ=∅ 확인

명령(H0 커밋 대상, 워킹 트리 무관 — deriver는 `git ls-tree <ref>`/`git show <ref>:<path>`로만 분석):

```bash
nim c --hints:off --skipParentCfg --skipProjCfg --skipUserCfg --noNimblePath \
  --path:src -o:bin/derive_checker_closure tools/ci/derive_checker_closure.nim   # exit 0
bin/derive_checker_closure --ref 999327ab088a73d80f4088f21d4625b4c0587867       # exit 0
git show 999327ab088a73d80f4088f21d4625b4c0587867:config/trusted_writer_set.json
```

| 비교 항목 | 값 |
|---|---|
| derived(H0) 멤버 수 | 857 (exit 0, UNRESOLVED 0건) |
| line-set(pin@H0) 멤버 수 | 857 |
| **Δ (핀 − 유도)** | **∅** — only-in-pin 0건, only-in-derived 0건, 집합 동일 `True` |

핀 파싱은 `src/cli/merge_cli.nim`의 정준 함수(`stripJsoncComments` :441 — 문자열 인식 상태기계 / `pinClosureLineSet` :486 — `<mode> <type> <sha>\t<path>` 라인셋 투영)와 동일 알고리즘으로 수행했다(측정 스크립트는 이 알고리즘의 1:1 이식). 바이트 형식은 deriver emit과 동일하므로 집합 비교가 곧 계약 비교다.

**판정**: H0에서 핀은 실제 검증기 트리 closure과 정확히 일치한다. #667의 재앵커는 정합 상태를 만들었고, 이후 #662·#654 병합까지 클로저 멤버 내용을 변동시키지 않았다.

## §2. Δ 분해 — 재앵커 Δ 재확인 (구 base 73ed69a5a 대비)

구 base **B = `73ed69a5a`** (merge #665 — #667이 cut된 지점):

```bash
bin/derive_checker_closure --ref 73ed69a5a    # exit 0
git show 73ed69a5a:config/trusted_writer_set.json
```

| 측정 | 값 |
|---|---|
| pin@B (제네시스 핀, 진부) | 840 멤버 |
| derived(B) — B 실측 트리 | 857 멤버 |
| 경로 추가 | **17** |
| 경로 삭제 | **0** |
| 공통 경로 840 중 sha 드리프트 | **101** |
| Δ(pin@B ↔ derived@B) 라인 차이 | only-in-pin 101 + only-in-derived 118 (= 드리프트 101 + 신규 17) |

핵심 구조 실측: **derived(B) == pin@H0 == derived(H0)** (추가 0·삭제 0·드리프트 0 — 857 멤버 집합 3중 동일). 즉 #665 병합 시점에 이미 실측 트리 closure은 857로 수렴해 있었고, #667이 바꾼 것은 **진부해진 핀 파일 하나**뿐이다. 트리는 B→H0 구간 불변, 핀만 840(진부)→857(실측)로 재앵커됐다.

제네시스 핀의 출생: `7c6a3370f02b43d424c91036ce976165cd3e51e1` (2026-09-26, "chore(trust): genesis closure pin — trustedCheckerTreeClosure 최초 설치 (deriver@c893b6e88 산출 840 members, ADR-0025 §7 genesis 1회)"). 840은 09-26 시점 deriver 도달 분이며, 그 이후 (a) 새로 출생해 클로저에 편입된 경로와 (b) deriver 도달 확대로 편입된 기존 경로가 17을 채우고, 같은 기간 멤버 내용 변경이 101건의 sha 드리프트를 만들었다.

## §3. 17멤버 도입 출처 실측표

측정 방법: 경로별 `git log --diff-filter=A -- <path>`로 출생 커밋 확정 → GitHub `commits/<sha>/pulls`로 PR 연관 확인(공백 = main 직접 푸시) → PR별 `reviews` 수 집계. 측정일 2026-10-10.

### 3.1 PR 경유 (6개 PR, 9경로 — 전원 리뷰 0건)

| 경로 | 출생 커밋 | 출생일 | 도입 PR | 리뷰 | 병합(UTC) |
|---|---|---|---|---|---|
| src/core/utils/decision_algebra.nim | `dddc3b19` | 2026-10-03 | #446 | 0 | 10-03T07:29:53Z |
| src/verification/accounting/execution_context.nim | `1359b699` | 2026-10-04 | #462 | 0 | 10-04T09:53:58Z |
| src/verification/evidence_cas.nim | `54aac2d1` | 2026-10-06 | #493 | 0 | 10-06T03:44:12Z |
| src/verification/evidence_ledger.nim | `54aac2d1` | 2026-10-06 | #493 | 0 | (동일 커밋) |
| src/core/utils/build_provenance.nim | `bb310fd4` | 2026-10-08 | #577 | 0 | 10-08T02:34:32Z |
| src/infrastructure/provenance_probe.nim | `7bca8ae9` | 2026-10-08 | #577 | 0 | (동일 PR) |
| src/verification/counterexample_replay.nim | `9bee856c` | 2026-10-08 | #589 | 0 | 10-08T05:44:14Z |
| src/verification/judgment_cas.nim | `12852186` | 2026-10-08 | #606 | 0 | 10-08T15:11:16Z |
| src/verification/obligation/golden_fixture_ir.nim | `12852186` | 2026-10-08 | #606 | 0 | (동일 커밋) |

특기 사항: `src/cli/evidence_cli.nim`은 2026-04-30 `9afe0c12`로 출생(직접 푸시) → 2026-06-04 `00a4abf8` 삭제 → **#493(54aac2d1, 2026-10-06)이 재추가** — 경로 생애가 PR과 직접 푸시를 모두 거친 유일 사례.

### 3.2 main 직접 푸시 출생 (5커밋, 8경로 — PR 없음, 리뷰 채널 부재)

| 경로 | 출생 커밋 | 출생일 | PR 연관 |
|---|---|---|---|
| src/cli/evidence_cli.nim | `9afe0c12` | 2026-04-30 | 없음 (`commits/<sha>/pulls` = `[]`) |
| src/gate/runners/delegation_enforcer.nim | `0103645f` | 2026-06-18 | 없음 |
| src/gate/utils/macro_dispatcher.nim | `ec573258` | 2026-07-11 | 없음 |
| src/verification/symbolic_test_synth.nim | `ec573258` | 2026-07-11 | 없음 |
| src/gate/runners/decision_binding_gate.nim | `5cbb7586` | 2026-07-31 | 없음 |
| src/core/gate/trust_commit_scope_scan.nim | `d7e6921d` | 2026-08-15 | 없음 |
| src/core/trusted/trust_authority_spec.nim | `d7e6921d` | 2026-08-15 | 없음 |
| src/gate/runners/trust_commit_scope_gate.nim | `d7e6921d` | 2026-08-15 | 없음 |

### 3.3 계획 언급 8개 PR의 교차 검증 (#587·#597)

계획(반박 4)이 열거한 8개 PR #446·#462·#493·#577·#587·#589·#597·#606의 리뷰 수를 전수 실측: **8개 모두 리뷰 0건** (측정 `reviews=0`). 단, 경로 출생과의 대응은 위 표대로 6개 PR이며, **#587("DEBT#471 enforcement path", 10-08T04:12:34Z)과 #597("DEBT#497 follow-up", 10-08T07:57:52Z)은 17경로 중 어느 것도 출생시키지 않았다** — 실측 diff 기준 두 PR은 17경로에 속하는 기존 파일들(trust_commit_scope_scan/gate·decision_binding_gate·delegation_enforcer 등)과 클로저 멤버 내용을 수정해 **101건 sha 드리프트의 기여자**로서 같은 감사 범위에 들어온다. (리뷰 채널 부재라는 성격 판정에는 차이가 없다.)

### 3.4 성격 판정 — bypass도 허점도 아닌 "강제 채널 부재"

- **판정식 선행**: 제네시스 핀(판정식 정합 3종의 기준점) = 2026-09-26 `7c6a3370`.
- **착지 권한 후행**: required check + in-place deriver 권한의 실측 근거는 `.github/workflows/admission-check.yml` 주석("the 2026-10-09 in-place derived-closure derivation compiles tools/ci/derive_checker_closure from B", merge_group runs 37951806316/37952005666 2026-10-10 측정)과 #667 병합(2026-10-09T17:08:38Z).
- **공백**: 09-26 → 10-09 = **13일**. 이 기간의 8개 PR과 5건 직접 푸시가 클로저 내용을 17경로 추가·101 sha 드리프트만큼 움직였고, 그 어느 것도 클로저 정합 강제 아래 착지하지 않았다.
- **규칙 위반 여부**: main ruleset(REST `rulesets/20303214`) 실측 — `required_approving_review_count: 0`, `bypass_actors: []`. 즉 리뷰 0 병합은 전원 **규칙상 합법**이고 bypass 행사도 없었다. 판정식 허점 경유 주장은 성립하지 않는다(허점 확대 불요).
- **판정**: 신뢰 루트가 "승인 없이" 움직인 것은 맞으나, 그 원인은 우회가 아니라 **클로저 정합 강제가 착지 권한에 결속되기 전의 13일 공백(강제 채널 부재)** 다. 사후 처방은 위반자 처벌이 아니라 (1) 소급 수용(§4), (2) 정규 구멍 수선(§6), (3) 상시 감시(§7 — watcher) 다.

## §4. 아키텍트 수용문 (소급 수용)

> **"H0·Δ·#667의 closure 재앵커를 소급 수용한다 — 출처는 아키텍트의 승인 계획(2026-10-10)이며, 에이전트는 기록만 한다."**

- 수용 범위: §1의 H0 정합 실측(Δ=∅), §2의 Δ 분해(추가 17·삭제 0·공통 101 sha 드리프트), #667(`88b52abec`, 2026-10-09 17:08:38Z)이 수행한 핀 840→857 재앵커 전체.
- 출처 문서: 아키텍트 승인 계획 "신뢰 루트 재베이스 — S0–S4 슬라이스 (반박 2종 반영)" (2026-10-10, 세션 플랜 `groot-barry-allen-killer-frost.md`).
- 권한 선언: 본 문서의 에이전트(작성자)는 이 수용을 **기록**했을 뿐, 수용 행위자가 아니다 (계획 Authority Preflight: "아키텍트 승인(S0 수용문)은 에이전트가 스스로 부여하지 않는다").

## §5. 후속 등록

| # | 후속 작업 | 내용 | 착수 조건 |
|---|---|---|---|
| 1 | **NORMAL 구멍 수선 회전 PR** | 판정식(`src/cli/merge_cli.nim` `adjudicateRotation`)이 **NORMAL에서도 ④(line-set(pin@H) == set(H))를 평가**하도록 수선 — §6의 구멍을 구조적으로 폐쇄. §6의 앵커 테스트(`tests/cli/test_merge_cli.nim` S1-C/D 스위트)가 이 PR에서 GO→DENY로 반전된다(T2b 선례). 수선 PR 자체는 회전 경로(④ 신규 앵커 정합)로 착지. | 본 슬라이스 착지 + #666 착지 후, 정상 회전 경로로 |
| 2 | **TrustSurface 파생화** | merge_cli.nim·TWS를 코드 고정에서 정적 파생(deriver 산출)으로 이전 — 현재의 "이상형"(파생 대상이 파생 authority를 심사하는 구조) 해소 | 후속 1의 정상 경로 복구 후 |

## §6. 정규 구멍 S1-C/D — NORMAL 분기의 pin@H 공허 (실측 기록)

### 6.1 벡터 (순수 코어 실측 — `adjudicateRotation`, merge_cli.nim:550-558)

`closureEqual = (derivedH == derivedB) ∧ (derivedB == pinBSet)`. 트리와 pin@B을 건드리지 않고 **pin@H 내용만 변조한 PR**은 `closureEqual=true` → **NORMAL(GO)** 즉시 통과하며, ①–④는 NORMAL에서 평가되지 않는다(`vacuous-true`, merge_cli.nim:553). 즉 착지되는 pin@H의 내용 정확성(=set(H))을 **아무도 검증하지 않는다**.

현행 통과 실측: `tests/cli/test_merge_cli.nim` 스위트 "adjudicateRotation — NORMAL hole S1-C/D: pin@H content-only tamper lands GO (current behavior anchor)" — 변조 pin@H로도 `rqNormal`·`reasonCode=∅`·④ 공허-참을 확인. 이 테스트는 **앵커**다: 후속 수선(§5-1)에서 기대가 DENY로 반전된다(T2b 선례 — 수선과 함께 뒤집히는 것을 문서화한 회귀 앵커).

### 6.2 피해 시나리오 (가용성 공격)

1. 공격자(또는 사고)가 pin 파일의 `trustedCheckerTreeClosure` 내용만 변조한 PR을 착지시킨다 → NORMAL GO (§6.1).
2. **다음 PR부터 큐 전면 동결**: 이후 모든 PR은 base에 변조 핀을 가진 채 트리를 변경하므로 `closureEqual=false` → ROTATION 후보 → ③에서 `line-set(pin@B) != set(B)` (**ROT_OLD_PIN**)로 전원 거부. 수복을 위한 정상 재앵커 PR조차 동일하게 ③ 거부.
3. **수복 경로가 게이트 밖**: TWS는 `file_path_restriction` 밖이라 bypass로도 PR 수정 권한이 생기지 않음 → **main 직접 푸시**만이 수복 수단(감시자 출력§7이 정안값 제공).
4. 무결성은 유지된다(fail-closed — 변조 핀 아래에서 승인되는 변경은 없음, 오히려 전부 거부됨). 손실은 **가용성**이다.

### 6.3 #666의 L1이 이 구멍을 못 닫는 이유

#666의 pinHeadBlobSha 대조는 "pin-H.json이 진짜 H 트리의 파일이다"만 증명한다 — 그 **내용이 set(H)와 일치하는가**는 보지 않는다. 내용 정확성 검증은 오직 ④뿐이며, ④는 NORMAL에서 평가되지 않는다(§6.1).

### 6.4 수복 계획

- **긴급 수복(동결 발생 시)**: main 직접 푸시로 핀을 실측값에 재앵커. 정안값 = `closure-watcher` 워크플로의 deriver 출력(§7 — 동일 레시피·동일 authority로 재생 가능).
- **구조 수복(§5-1 후속 회전 PR)**: NORMAL에서도 ④를 평가하도록 판정식 수선 — 변조 핀 PR은 `ROT_NEW_PIN`으로 거부되고, §6.1 앵커 테스트는 DENY 기대로 반전 확정된다.
- **수선 전 완화**: §7 감시자가 6시간 주기로 핀↔유도 불일치를 탐지해 탐지 간격을 시간 수준으로 축소한다 (불일치 = 위 2의 동결 상태 또는 트리 드리프트 — 두 경우 모두 같은 시그널).

## §7. S3'/S4' — 픽스처·감시자 준비 기록

### 7.1 C1 픽스처 — `docs/guides/closure-fence-note.md` (본 PR에서 신설)

- 목적: **무 bypass 정상 경로 통과 실측용 무해 문서**. 파일은 클로저 밖 멤버(실측: `docs/guides/**`는 857 멤버 라인셋에 없음 — §1 라인셋 기준 `outside`)이므로 착지해도 Δ=∅를 유지한다.
- 실측 방법(착지 후): `landing_observe.sh <C1-PR>` → TERMINAL_SUCCESS + ruleset/audit log에 bypass 흔적 부재.

### 7.2 C2 픽스처 — `src/cli/version.nim` 단일 주석 수정 (**#666 착지 후에만 실행**)

- 픽스처 설계: `src/cli/version.nim`에 주석 1줄 추가(클로저 멤버·trustSurface 어디에도 새 의미 없음). 브랜치: `docs/trust-root-audit`에서 분기한 `fix/c2-fence-probe`, 본문에 기대 코드 명시.
- **지금 실행하지 않는 이유(실측)**: (a) `src/cli/version.nim`은 **클로저 멤버**(§1 라인셋 `MEMBER` 실측) — 주석만으로 sha 드리프트 → 핀과 불일치. (b) 현 main의 MG는 #666 미착지로 rotation facts 부재 → **UNSPECIFIED 스킵**이고 deny 자체가 존재하지 않아 거부를 관측할 수 없다.
- **#666 착지 후 기대 판정**: closureEqual=false → ① 통과(멤버 경로는 pin@B keys = allowlist) → ③ 통과(핀@B 정합 base) → **④ 실패 → `ROT_NEW_PIN`** 거부 (ROT_ALLOWLIST가 아닌 이유: version.nim은 allowlist 안의 멤버이므로 ①이 아니라 ④가 막는다; trustSurface 멤버(merge_cli.nim·TWS)를 쓰면 TRUST_SURFACE_MODIFIED로 새어 C2가 깨지므로 version.nim을 택함).

### 7.3 S4' 감시자 — `closure-watcher` (본문 준비 완료, 착지는 정책 2단계 절차 대기)

- 트리거: `schedule`(cron `17 */6 * * *` — 6시간 주기, 정각 회피) + `workflow_dispatch`. 저장소 최초 schedule 워크플로.
- 절차: main HEAD checkout → `setup-axiom-toolchain`(핀 통일 — 인라인 choosenim 금지, `provision-scope: full`) → deriver in-place 컴파일(#666 레시피 그대로) → `--ref HEAD` 출력 ↔ 핀 라인셋(§1과 동일 알고리즘) 대조 → 불일치 시 exit 1(fail-closed) + 추적 이슈 자동 생성.
- 알림 공식: schedule 워크플로 실패 알림의 수신자 = **이 파일의 cron을 마지막으로 수정한 계정(현재 `wintrover`)** (1인 고정 — 절차적 보강으로 이슈 생성 병행).
- 권한: `contents: read` + `issues: write`(이슈 생성) — **`actions: write` 없음**, `contents: write` 없음 → TWS(ADR-0022 §4, contents:write 보유 워크플로만 규율) 대상 외 신규 authority 아님.
- 파생 안전: 워크플로 파일은 클로저 멤버 아님(§1 라인셋 `outside` 실측) — 신설만으로 Δ 변동 없음(브랜치 HEAD 재유도로 재확인).
- **본문 위치(실측에 의한 주차)**: `.github/workflows/**`는 표면 정책 v72의 FROZEN 경계(`config/repository_surface.json`, `.github/**`)라 신설 ADD가 `SURFACE_FORBIDDEN` fail-closed다(측정: `make check-repository-surface` → verdict FAIL, violations = closure-watcher.yml 1건). 정책 개정은 본 슬라이스 권한 밖(정책 PR의 push는 `docs/spec/repository_surface_contract.md`가 정의한 Owner 수용-risk 경로를 전제 — 본 슬라이스는 bypass·`--no-verify` 금지)이므로, 검증 완료된 본문을 `docs/evidence/closure_watcher_workflow.yml`(PRODUCT 경로 — PASS 실측)에 **주차**한다.
- **착지 절차(2단계 선등록 — v52/v55/v65–v72 선례)**: (1) Owner의 정책 PR이 `.github/workflows/closure-watcher.yml`을 FROZEN→CONTROLLED 선등록(v73); (2) 후속 소비 PR이 주차 본문을 동일 내용으로 `.github/workflows/closure-watcher.yml`에 배치 — 그 시점부터 6시간 cron이 가동되고 §6.4의 완화가 활성화된다. 주차 본문은 착지 가능 상태로 검증 완료: YAML 파싱·`run:` 블록 보간 토큰 0건(quirk Q4)·내장 파서 실측(H0 데이터 정합 OK / 변조 시 exit 1 양방향).

---

## 부록 A. 측정 환경

- 측정일: 2026-10-10 / 측정 저장소: `/tmp/wt-trust` (`docs/trust-root-audit` worktree, origin/main 기반)
- Nim 2.2.10 (choosenim 고정 — 저장소 핀과 동일)
- deriver 컴파일: `nim c --hints:off --skipParentCfg --skipProjCfg --skipUserCfg --noNimblePath --path:src -o:bin/derive_checker_closure tools/ci/derive_checker_closure.nim` → exit 0
- GitHub 실측: `gh pr view {446,462,493,577,587,589,597,606,667}` (`reviews`), `gh api repos/Archright/Axiom/commits/<sha>/pulls`, `gh api repos/Archright/Axiom/rulesets/20303214`
- 극장 판정 참고: §6의 구멍은 무결성 fail-closed를 훼손하지 않으며(§6.2-4), 코드 주석에 "vacuous-true under NORMAL"로 이미 문서화된 알려진 한계 — 신규 극장이 아니므로 Theater 레지스트리 등록 대상이 아니라 **문서화된 구멍+수복 계획**으로 기록한다(§5-1, §6.4).
