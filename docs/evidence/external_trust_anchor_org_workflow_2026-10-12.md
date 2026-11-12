# 외부 신뢰 앵커 — org required workflow `Archright/.github` admission-gate.yml (UNKNOWN 해소 기록)

- **Date**: 2026-10-12
- **성격**: 문서화 전용 (evidence) — 정책·권한·워크플로 변경 없음. hard-assumption
  감사에서 미문서화 상태로 남아 있던 신뢰면 사각지대(UNKNOWN)를 **명시적 외부 신뢰
  앵커로 기록**한다. 이 문서는 어떤 gate도 추가/삭제하지 않는다.
- **관측 도구**: `tools/ci/golive_detect.sh` (동일 브랜치 착지 — 실행된 핀의
  content-addressed 관측기, GET-only reporter)
- **인접 기록**: `data/e4e5/landing_boundaries/2026-10-12T011330Z-pin-promotion-lag-addendum.json`
  (PR #763 — 핀 승격 지연 실측)과 상호 보완 — 본 문서는 신뢰 앵커의 구조와 검증
  등식을, 부록은 지연 실측을 담는다.

---

## 1. 기록되는 사실 (Fact)

### 1.1 실행 authority — NEW dual-mode

org 저장소 `Archright/.github`의 `.github/workflows/admission-gate.yml`은 병합
어드미션의 **실행 authority**다.

- 근거: `config/policy/merge_admission.json:13-17` — `requiredWorkflowDetection` =
  `{repositoryId: 1182157951, workflowPath: ".github/workflows/admission-gate.yml",
  verdictJob: "admission-check"}`. 동 파일 description v1.8.0: "execution
  authority = org workflow" (ruleset `workflows` rule이 감지되는 NEW 모드).
- LEGACY 모드(ruleset rule 부재 시)의 증거 authority(`requiredValidations` =
  `admission-check` @ workflowId 365692388 + `src/cli/merge_cli.nim`
  RequiredWorkflowIds 이중 결속)는 v1.8.0 이후에도 유지된다 — 본 문서는 그
  균형을 변경하지 않는다.

### 1.2 in-repo 신뢰면 목록 밖 — 구조적(BY DESIGN)

`config/policy/merge_admission.json:18-30`의 `trustSurface`(그리고
`config/repository_surface.json`의 클래스 범위)는 **본 저장소 경로**만 다룬다.
실행 authority인 org workflow 파일은 `Archright/.github` 소유로 **본 저장소 밖에
있으며**, 따라서 in-repo 표면 목록에 있을 수 없다. 이것은 누락이 아니라 소유
구조의 귀결이다: org 소유 파일의 변경 권한은 org 측에 있고, 본 저장소는 그
**결과(실행된 핀 identity)**를 관측·검증하는 쪽이다. 이 구조적 사실 자체는
`config/repository_surface.json` knownBlindSpots(v62)에도 기록되어 있다 —
"admission-gate.yml lives in Archright/.github (required workflow; org ruleset
24233738 pulls org main ref=main) … OUTSIDE this inventory".

> 이 문서가 닫는 것: "실행 authority가 in-repo trustSurface 밖에 존재하는데
> 어디에도 명시되지 않은" 상태(UNKNOWN). 이제 이 앵커는 이 문서로 명시된다.

### 1.3 content-addressed 통제 — pin-promotion-gate (DEBT#473)

org `admission-gate.yml`은 Axiom callee를 고정 ref에 핀한다:

```
uses: Archright/Axiom/.github/workflows/admission-check.yml@<REF>
```

- 회전 메커니즘: org 저장소의 Dependabot github-actions 자동화가 교차저장소 핀
  갱신 PR을 생성(2026-10-07 착지 실측, DEBT#473 UPDATE — org PR #64/#65/#66로 3핀
  동시 회전 실측) + 사람의 병합. 수동 핀 회전 handoff는 제거됨.
- 미해결 잔여: epoch promotion과 핀 회전의 논리적 단위 결속은 미구현
  (`data/debt_registry.json` DEBT#473, status: open — 본 문서가 닫지 않는다).
  승격 대비 핀 회전 지연의 실측 부록은 PR #763 문서 참조.
- 핀은 **ref(커밋 sha)**이며, 통제의 등식은 content-addressed다: 실행된 ref가
  가리키는 커밋에서의 `admission-check.yml` **blob sha**가 곧 identity다.

### 1.4 핀이 움직일 때 in-repo 측이 검증하는 것 — target blob == TWS

핀 회전(PR 병합)이 일어나면, in-repo 측의 기존 실패-닫힘 검증점들이 아래 등식을
강제한다 (기존 통제 — 본 문서는 이를 기록할 뿐이다):

```
blob(.github/workflows/admission-check.yml @ 핀이 가리키는 커밋)
  == config/trusted_writer_set.json의 trustedAdmissionWorkflowSha
```

- 등식의 원본: `config/trusted_writer_set.json` — `trustedAdmissionWorkflowSha`
  는 `admission-check.yml`의 git blob sha로 정의되며 파일 변경과 원자적으로
  갱신된다 (같은 파일 서술, ADR-0022 §5).
- 실패-닫힘 소비자들 (기존):
  1. `certificate-mint.yml` mint step 2a — mint가 TWS@B를 읽고 fetch한 admission
     blob@B와 대조, 불일치 시 fail-closed (`config/trusted_writer_set.json` 계약
     서술).
  2. `admission-check.yml` preflight — "[preflight] Attest-leg static contrast
     (TWS pin pairing + policy SSOT)" 단계가 blob@B == TWS@B 대조, 불일치 시
     fail-closed (`admission-check.yml:1362-1380`).
  3. `src/cli/merge_cli.nim` — requiredWorkflowDetection/RequiredWorkflowIds
     이중 결속 (NEW 모드 판정 시 org workflow 런 + verdict job을 검증).
- 보강(본 브랜치): `tools/ci/golive_detect.sh`가 **실행된 핀**(위 등식의 좌변)을
  run 기록에서 직접 관측해 등식을 사후 검증한다 — B-workspace 정적 대조만으로는
  닿지 않는 "실행된 것"의 관측.

### 1.5 실행된 핀의 관측 필드 (2026-10-12 실측 확정)

| 우선순위 | 필드 | 성격 |
|---|---|---|
| 1차 | run 객체 `referenced_workflows[].path` = `Archright/Axiom/.github/workflows/admission-check.yml@<REF>` (+`.sha`) | 런의 frozen execution record — run metadata 1회 GET, 로그 보존기한·Q3 quirk 무관 |
| 2차(폴백) | callee job `attest / admission-check` 로그의 `Uses: Archright/Axiom/.github/workflows/admission-check.yml@<REF>` 행 | runner 발행 실행 기록 — Q2/Q3 quirk 적용 (docs/spec/gh_merge_admission_observation_quirks.md) |

run/job API의 나머지 메타데이터(job 목록, head_sha, path 등)는 실행된 callee
버전을 노출하지 않는다(실측 2026-10-12, 런 38189985337/38190181362 정독).

---

## 2. 현재 상태 스냅샷 (2026-10-12, 측정 — 역사 값 아님)

- 구 callee blob: `135bbe3677e282ca7d1794edf430656e7443d94f`
  (핀 `3cefd30793bc6b450a793a48cf813788f7b360fc` 시절).
- Axiom main TWS: `22fe84bab7b4ea212820e9bba96dc3357f71f076` — PR #760
  (d975fc936, toolchain-handoff, T_land 2026-10-12T00:46:47Z)이 회전.
- **org 핀 회전 (관측됨)**: org 저장소 Dependabot PR #168/#169/#170이
  2026-10-12T01:48:54Z–01:52:36Z에 병합되며 3 callee 핀(setup-axiom-toolchain·
  certificate-mint·admission-check)을 `81bd6c608a048e78115a0884a80d4b167847c3ce`
  로 회전. 해당 커밋의 `admission-check.yml` blob = `22fe84ba…` = TWS와 일치
  (등식 성립 — 본 문서 §1.4).
- **go-live: 관측됨 (Observed)** — 첫 new-blob merge_group 런:
  **38193686820 @ 2026-10-12T01:54:13Z** (회전 병합 직후, 시간 정합).
  2026-10-12T03:00:00Z까지 창 스캔: 7런 = pre 4(구 blob; 38192530044 failure 포함)
  + post 3(38193686820·38193723834·38194556640) + unknown 0.
  AFTER 데이터셋은 `golive_detect.sh` 출력 `post_golive.ids`(위 3런)부터
  `merge_latency_audit.sh --compare`에 투입 가능.

## 3. 탐지기 검증 전사 (validation transcript — 기계 관측)

`tools/ci/golive_detect.sh --runs 38189985337,38190181362` (2026-10-12 실측):

```
[golive] TWS 등식 소스: config/trusted_writer_set.json @ main → trustedAdmissionWorkflowSha=22fe84bab7b4…
[golive] run 38189985337: ref=3cefd30793bc blob=135bbe3677e2 → pre-go-live (blob != TWS (old callee blob))
[golive] run 38190181362: ref=3cefd30793bc blob=135bbe3677e2 → pre-go-live (blob != TWS (old callee blob))
[golive] go-live not yet observed — 창 내 2런 전부 pre-go-live(구 blob) 또는 unknown (정상 완료, 추정 없음)
EXIT=0
```

- V1 두 기지 구-callee 런(38189985337, 38190181362 — setup-axiom-toolchain
  69–79s 시절) 모두 `pre_golive` 분류 — 관측 필드는 1차
  `run.referenced_workflows`. ✔ 지상진실과 일치.
- V2 등식 양변 기계 확인 — `--tws-sha 135bbe36…`(구 blob)을 주면 동일 두 런이
  `post_golive`로 전환되고 경계가 `first_post_run_id: 38189985337 @
  2026-10-12T00:57:16Z`로 보고됨(양방향 분기 + 경계 보고의 기계 검증).
- V3 창 모드(`--since 2026-10-12T00:50:00Z --until 01:10:00Z`) — 창 내
  merge_group admission-gate 런 정확히 2건 열거·동일 분류.
- V4 fail-closed 종료 코드 — 비-admission-gate 런 id → 1 / 인자 오류 → 2 /
  TWS ref 미해석 → 2 / 미분류 런 존재 → 3(기록·플래그, 침묵 폐기 없음).
- V5 실제 경계 관측 (회전 후 종단 검증) — `--since 2026-10-12T00:40:00Z
  --until 03:00:00Z`: 회전 병합(01:52:36Z) 이전 런은 전부 구 ref·구 blob,
  이후 런은 전부 신 ref·신 blob으로 분류; 경계
  `first_post_run_id: 38193686820 @ 01:54:13Z`, unknown 0, EXIT=0.
  두 기지 구-런은 이 스캔에서도 `pre_golive`로 재확인됨.

## 4. 경계 (이 문서가 하지 않는 것)

- merge_admission.json·repository_surface.json·워크플로·merge_cli 변경 없음 —
  신뢰면 목록에 org 파일을 "추가"하지도 않는다(소유 구조상 불가·불요).
- DEBT#473의 잔여(promotion 결속)를 해소하지 않는다 — open 유지.
- go-live 판정 자체는 GitHub 실행 기록의 관측이며, 병합 admissibility 판정은
  여전히 GitHub merge authority 소관 (AGENTS.md §2.3, Authority ≠ Adapter).
