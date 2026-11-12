# S0: canonical-main 단일 job slice 폐쇄 기록

> 2026-09-18. 관측 run 35318589721(canonical main H=4593a6f2e)를 근거로 3→1 실행 경계 축소 slice가 production에서 달성되었음을 기록한다. 본 문서는 관측·사실 기록이며, 추가 구현을 포함하지 않는다.
> 판정: **slice CLOSED**.

## 관측 run

| 항목 | 값 |
|---|---|
| run | [35318589721](https://github.com/Archright/Axiom/actions/runs/35318589721) |
| workflow | canonical-main |
| event | push |
| head | `4593a6f2e720248bad0e9b9f450c55cb63ecd4ed` (main) |
| startedAt → updatedAt | `2026-09-18T07:15:48Z` → `07:17:53Z` = **2m05s** (timeout-minutes 15 미만) |
| conclusion | failure (continuity step fail-closed) |

- `gh run view 35318589721 --json conclusion,startedAt,updatedAt` → `{"conclusion":"failure","startedAt":"2026-09-18T07:15:48Z","updatedAt":"2026-09-18T07:17:53Z"}`
- 2m05s = 125s < 600s(15m).

## step 결론 (단일 job `landing`)

| step | 결론 |
|---|---|
| Run actions/checkout@v4 | success |
| deps-verify (host contract — existence checks only, no installs) | success |
| Build bin/ax from the landing checkout | success |
| `[bind]` Bind admitted landing | success |
| `[continuity]` Cert continuity for the landed head | **failure** |
| `[accept]` Append canonical acceptance R(H) | **skipped** |

- `gh run view 35318589721 --json jobs --jq '.jobs[0].steps[] | "\(.conclusion) \(.name)"'` → 위 결론 순서 그대로. fail-closed continuity가 accept를 skip하고 전체 failure로 표면화 — ordered step 의미론이 원 지시 3-job DAG의 "failing step skips the rest"와 일치.

## bind 상세 (모두 로그 07:17 기준)

| layer | 결과 |
|---|---|
| L0 | **PASS** (H1=`b5cc4087067b2ef97491728898056f92b283805f` H2=`efcd9e8f6c1fbc151a2ab8468f92d95efd6ad0ea`) |
| L1 | **PASS** (pr=123 base=b5cc4087067b…) |
| L2 | **PASS** (actor=wintrover run=35316932549 attempt=1) |
| L3a | **PASS 5/5** — verify-static, verify-integration-r1, verify-integration-r2-unit, verify-integration-r2-proof, check-readiness-start (전부 `admission_producer.yml` attempt=1 conclusion=success) |
| L3b | TRUST-SURFACE **PASS** (0 hits) |
| L4 | SKIPPED (tool unavailable; stale gate) |

→ **bind: PASS** (`bind: PASS H=4593a6f2e720248bad0e9b9f450c55cb63ecd4ed`)

## continuity: CC_NO_CERT 경계 보존

로그 원문:

```
no ledger certificate with headSha==parent2 (efcd9e8f6c1fbc151a2ab8468f92d95efd6ad0ea) in the last 20 appends — THIS landing is uncertified (fail-closed)
```

- `tools/ci/run_landing_continuity.sh:148-151` fail-closed 고정(20-append FF-chain walk, 미발견 시 exit 1), `continuity_check.nim:90-91` ccNoCert 경로에 따라 **CC_NO_CERT** reasonCode로 결함을 표면화.
- cert 미존재 = mint authority 부재의 결과(아래 "R(H) 미달성의 구조적 사유")이며, fail-closed 경계는 그대로 보존되어 **인증되지 않은 착지가 통과하지 않음**.

## 구조 (3→1)

| 항목 | 값 |
|---|---|
| 단일 job | canonical-main.yml:89 (`landing`, runs-on axiom-ci) |
| checkout | 1회 — `ref: ${{ github.sha }}` (canonical-main.yml:120,124), fetch-depth 0 |
| nim build | 1회 — `nim c -o:bin/ax src/cli/main.nim` (canonical-main.yml:173-174) |
| actions/cache | 실사용 0 (주석뿐) |
| setup-axiom-toolchain | 실사용 0 (주석뿐) |
| ordered steps | bind → continuity → accept (canonical-main.yml:176,200,209) |

- 이전 3-job DAG(bind/continuity/accept)의 needs-edge 소비자가 존재하지 않았음을 파일 주석이 명시(canonical-main.yml:115-119) — ordered steps 전환이 동작 보존.

## 원 지시 4개 수정분 이행

| # | 지시 | 이행 |
|---|---|---|
| (i) | `ref: main` → 착지 SHA 고정 | canonical-main.yml:124 `ref: ${{ github.sha }}` (주석: NOT ref: main) |
| (ii) | continuity 단일 SSOT | `tools/ci/run_landing_continuity.sh` 기계적 이동 — `uses: ./.github/workflows/` 0건 (merge_continuity.yml은 retirement slice까지 미변경) |
| (iii) | libpcre3 설치 제거 → 존재 검증 fail-closed | deps-verify step(canonical-main.yml:144) — 설치 명령 0, `command -v` 존재 검증 + `deps-verify: FAIL — … fail-closed` |
| (iv) | networkless probe | run 35311197208 deps fail-closed 14s → run 35312574265 → `GITHUB_PATH` 단일 기록점 fix `bcfd928c1` (2026-09-18 15:00:32 +0900, "PATH 전파를 GITHUB_PATH 단일 기록점으로") |

## 경계 보존 실측 3종

| 경계 | 실측 |
|---|---|
| L2_RUN_UNIQUE | run 35316161180 — PR#122 close→reopen으로 admission run 2개 오염 시 게이트 거부(conclusion=failure) = 정상 동작 |
| CC_NO_CERT | run 35318589721 — cert 부재 → continuity fail-closed = 정상 동작 |
| deps fail-closed | run 35311197208 — 호스트 결함 시 5시 32m 24s→38s(=14s) 즉시 실패 = 정상 동작 |

## R(H) 미달성의 구조적 사유 (slice 폐쇄 판정과 무관)

- CI에는 cert mint producer가 **부재**하다 (DEBT#464, data/debt_registry.json:3793). 유일 sanctioned mint = ADR-0021 §D9 수동 operator ceremony(`docs/adr/0021-execution-authority.md:163-180`).
- 따라서 R(4593a6f2e) 부재는 mint authority 부재의 결과이며 3→1 실행 경계 축소의 결함이 아니다. accept chain(accept step 이후 R(H) CAS append)은 cert 존재 시 정상 동작하며 — 아래 양성 대조 — mint authority 도입은 별도 slice(DEBT#464) 소관.

## 양성 대조: cert 존재 시 accept 체인 정상

- `refs/heads/axiom/canonical-acceptances` tip `35ccf7f34`에 R 2건:
  - `eac8cdee9` — certificate ledger append `7295b22246562e0b6062a52d62266a5c68204c22` (PR#118)
  - `35ccf7f34`(tip) — certificate ledger append `e107eeac2a5d4fa059c554e042180a08d37dc5d5` (PR#119)
- DEBT#464 근거: landing H=7295b2224656 (PR#118) canonical-main run 35250462037에서 bind/continuity/accept **all success** — `bound cert: headSha==parent2`, `[cert] Continuity: ccPassed`, `R(7295b2224656) at canonical-acceptances tip eac8cdee9`.
- 결론: cert 존재 시 full chain 성공 → accept 체인 정상; R(4593a6f2e) 부재 = mint authority 부재뿐.

## 결론

3→1 실행 경계 축소(단일 job, checkout·build 1회, ordered bind→continuity→accept)가 production에서 2m05s로 **달성**되었고, L2_RUN_UNIQUE / CC_NO_CERT / deps fail-closed 3종 경계가 모두 실측에서 보존되어 **fail-closed 성격이 유지**된다.

**판정: slice CLOSED** (추가 구현 없음).
