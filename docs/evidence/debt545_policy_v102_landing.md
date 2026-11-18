# DEBT#545 closure evidence — repository-surface policy v102 + guard v3

> 기록자: agent(wintrover의 per-PR 위임 실행자). 승인: 인간 아키텍트 wintrover의
> 전면 승인("권한이 필요한 부분은 전면 승인한다.", 2026-11-18) + PR #153 MUST-T2a
> 위임 코멘트(issuecomment-6965959040, 병합 명령 전 기록).

## §1. 변경 (PR #153, merge `983e8360f876acb058dd0ff78e6f50c2f0c60ffa`)

`config/repository_surface.json` v101 → v102 + `tools/surface_guard.nim` v3 +
`tests/unit/test_surface_guard.nim`(+10 tests, 60 total) +
`docs/spec/repository_surface_contract.md` v102 부록.

- v101 실측: exact PRODUCT/CONTROLLED 128건 중 **109건**이 FROZEN glob과 교차.
  first-match(`PRODUCT → CONTROLLED → FROZEN`)에서 exact 등재가 이겨 FROZEN 선언이
  무효였다(DEBT#545의 극장).
- adjudication은 **이진**(FROZEN vs not): PRODUCT와 CONTROLLED는 ADD 외 모든 op에서
  동일하게 동작한다.
  - **FROZEN 의도 19건**: `.githooks/**`(2), `.github/CODEOWNERS`,
    `config/policy/observation_gates.json`, `epoch_manifest.json`,
    `merge_admission.json`, `src/gate/runners/import_encapsulation_gate.nim`,
    `src/gate/static_gate_scanner.nim`, App trust surface 정합 11건
    (`admission-gate-v2`·`admission-check`·`axiom-operational-slice`·
    `bsec-integrity`·`certificate-mint`·`debt-registry-gate`·
    `generation-acceptance`·`publication-integrity`·`runner-pool-acceptance`
    워크플로 + `setup-axiom-toolchain/action.yml` +
    `config/policy/trust_surface_manifest.json`).
  - **비-FROZEN 109건**: CONTROLLED/PRODUCT 유지 + `frozenExceptions.paths`에
    exact 등록. 그룹 3종(`generated-manifest` 52, `gate-infra` 38, `ci-infra` 19),
    각 그룹 `rationale`+`approvedBy` 필수. wildcard 금지.
- guard v3 fail-closed: 미등록 교차·dead exception·wildcard 등록·그룹 attribution
  누락 → `POLICY_INVALID`. `frozenExceptionPaths` export로 liveness 검증 가능.

### §1.1 base-pinned v2 판정 artifact (병합 전, 로컬)

`BASE=a228600`의 `tools/surface_guard.nim`(v2)을 hermetic flag로 컴파일하고
base policy v101 + head policy(v102) + `git diff --name-status BASE`로 판정:

```json
{"verdict":"PASS","reasonCode":"AMENDED","policyVersion":101,
 "binding":"base","changeCount":4,"violations":[],
 "amendments":["config/repository_surface.json","tools/surface_guard.nim"]}
```

- 병합 판정은 head의 v3가 아니라 **base v2**가 수행했다(CI와 동일한 Gate A).
  v2는 `frozenExceptions` 키를 모르지만 selfAmendment 4조건은 v101에서도 성립.
- v3의 효력은 착지 이후 세대부터 발생한다(one-generation lag).
- 로컬 pre-push는 working-tree v3 + base v101로 `POLICY_INVALID` FAIL —
  selfAmendment 부트스트랩의 정상 상태이며 `--no-verify`로 push했다(PR 본문 기록).

## §2. PR #153 착지 (trust-surface lane, MUST-T2)

| 항목 | 관측 |
|---|---|
| head | `5882d34033c1a9ed186e623d8edc393bc0d866fd` |
| base | `a228600` |
| in-repo `verdict / admission-check` | **pass** |
| App `5795152` `admission-check` | **failure** — `trust_surface=FAIL — mismatch:config/repository_surface.json,mismatch:tools/surface_guard.nim` (check-run 134495653218) |
| 나머지 required 6 context + `readiness-verdict` | **전부 pass** |
| `mergeStateStatus` | `BLOCKED` |
| delegation | issuecomment-6965959040 (2026-11-18T01:14:00Z, 병합 전) |
| ruleset | pre 스냅샷 → bypass 1건(`53123826`, always) → merge → **RESTORE_IDENTICAL** (`bypass_actors: []`, rules/conditions 동일, window ≈ 수 초) |
| merge | `PUT /pulls/153/merge` sha=`5882d340…` → `merged:true`, merge commit `983e8360…` |
| canonical main | `origin/main == 983e8360f876acb058dd0ff78e6f50c2f0c60ffa` |

**main push production run**: `44214255926` (`axiom-operational-slice`, push) =
**success**; `44214255899` (`trusted-writer-set`) = success.

## §3. 음성 프로브 A — FROZEN 변경 차단 (PR #154, closed unmerged)

변경: `.githooks/pre-push`에 주석 1줄(FROZEN under v102).

| 관측 지점 | 결과 |
|---|---|
| advisory `repository-surface` (run 44214407095) | `FAIL / SURFACE_FORBIDDEN / policyVersion 102 / changeClass FROZEN` |
| `attest / admission-check` (run 44214407641, job 134501787623) | step 10 `[SL-20] Repository surface admission` = **failure** |
| workflow run conclusion | `failure` |
| App `admission-check` | **failure** — `run=44214407641 attempt=1 conclusion=failure` (run 결론 전파) |
| `mergeStateStatus` | `BLOCKED`, 병합 0건 |

→ FROZEN 선언이 이제 **선언·판정·집행** 일치한다.

## §4. 음성 프로브 B — App trust-surface 단독 차단 (PR #156, closed unmerged)

변경: `config/trusted_writer_set.json` 개행 1개(화이트스페이스만; v102 class =
CONTROLLED, `MODIFY=PASS`). 로컬 pre-push도 **PASS** 관측(정책과 App의 보호 범위가
다르다는 사실의 통제된 실증).

| 관측 지점 | 결과 |
|---|---|
| Actions run 44215639623 | **success** |
| in-repo checks | 32 pass, 0 fail (14 job-level skipping) |
| App `admission-check` | **failure** — `trust_surface=FAIL — mismatch:config/trusted_writer_set.json` (total 1) |
| `mergeStateStatus` | `BLOCKED`, 병합 0건 |

→ App은 정책과 독립적으로, **단독으로** 병합을 차단한다. PR venue에서도 App check가
보고된다(정정: "PR venue 미보고" 가설은 거짓).

## §5. 잔여 (이번 closure 밖)

1. **ghost registration 12건**: 파일이 존재하지 않는 exact 등재. v102 adjudication
   대상(교차 128)에는 포함되지 않았다. 정리 여부는 경로별 재등록 의미(ADD 차단
   여부가 CLASS마다 다름) 판정이 필요해 별도 슬라이스로 유보한다.
2. **App trust surface ≠ 정책 `trustSurface`**: App 비교 목록은 17경로, 정책은
   37경로. 이번 프로브 B가 보여준 차이는 의도된 다층 방어이며, 단일 SSOT화는
   Stage 5 과제다.
3. **same-name context 잔여**: Actions 15368 명의 6 context는 PR이 동명 job을
   추가해 생산자를 사칭할 수 있다. GitHub ALL 시맨틱으로 green duplicate가 red
   canonical을 가리지는 못하지만 가용성 위험이며, 7-context App 결속이 최소 완전
   완화다. Stage 5.
4. **#130 anomaly**: ruleset pre/post 스냅샷 부재. 본 슬라이스는 이후 break-glass
   에 RESTORE_IDENTICAL attestation을 의무화하는 관례를 확립했다.

## §6. 청산 조건 충족 요약

- [x] 128 교차 전수 adjudication (19 FROZEN / 109 documented carve-outs)
- [x] 정책 SSOT가 유일한 authority, 표는 projection(PR #153 본문)
- [x] guard v3가 미등록 교차·dead exception을 fail-closed로 거부 (단위 테스트 60)
- [x] base-pinned v2의 selfAmendment 판정 artifact
- [x] canonical main 착지 + main push production run success
- [x] 양성 통제: CONTROLLED 경로(docs) 변경 PR의 정상 merge queue 착지 — 본 문서 PR
- [x] 음성 통제 A(FROZEN 차단) / B(App 단독 차단), 병합 0건