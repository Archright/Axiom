# Stage 2 Cutover Runbook — 단일 앵커 B* + failure-code 관측 (2026-10-13)

> **상태: DRAFT (미착지)** — 본 문서는 승인된 CI-recovery 계획 Stage 2
> (단일 앵커 B* + failure-code 관측 가능성)의 **Epoch Cutover 실행
> 러북**이다. 정본: AGENTS.md §2.5 + [docs/agents/ci_epoch_cutover.md]
> (10단계 절차). 모든 pin 회전·ruleset 변경·push·PR 생성은 본 러북의
> 실행 단계에서 **인간 승인 하에** 수행된다. 드래프트 단계에서는
> 아래 Step 3(세대 준비)의 두 브랜치만 존재하며 아무것도 push되지
> 않았다.
>
> **권위 계약(§2.3)**: merge-admission의 authority는 GitHub다. 본
> 러북의 명령은 그 판정을 대체하지 않으며, required checks 0건 =
> UNKNOWN / NOT READY로 해석한다.

## 0. 현재(구) 세대 핀 스냅샷 — Step 1 Freeze / Step 2 Record의 입력

| 바인딩 | 현재값 | 위치 |
|---|---|---|
| TWS `trustedAdmissionWorkflowSha` | `09ff52b3596cbf116fa7e6c64b0763f91443f3b2` | `config/trusted_writer_set.json` |
| epoch_manifest `productionExecutionPin` | `09ff52b3596cbf116fa7e6c64b0763f91443f3b2` | `config/policy/epoch_manifest.json` (ciEpochId `N+7`) |
| org callee pin (admission-gate → admission-check, 2 호출) | `288a410a041e4e889e6afe1a67c25bdcaa956344` | `Archright/.github` `.github/workflows/admission-gate.yml` (`stage: attest` 호출 + `stage: verdict` 호출) |
| 구 세대 admission-check.yml blob sha | `09ff52b3596cbf116fa7e6c64b0763f91443f3b2` | `git show origin/main:.github/workflows/admission-check.yml \| git hash-object --stdin` |
| 신세대 admission-check.yml blob sha (드래프트 기준값) | `b4d4e828c6ea7b7ff14f1522f128ffb87a0f2e81` | `feat/s2-single-anchor-observability` — **cutover 시 Step 4(a)에서 재계산 필수** (리베이스/수정 시 변동) |

검증(2026-10-13 실측): TWS 핀 == epoch_manifest 핀 == origin/main 워크플로
blob sha — A2 pin pair 정합. 이 값들이 본 러북의 **rollback 타깃**이다.

## Step 1 — Freeze (불변 베이스라인 고정)

```bash
git -C . fetch origin
git tag -a ci-epoch/n7-freeze-2026-10-13 1de52a5f95db83f11cdeb3663405d817b47035b6 \
  -m "Freeze: pre-Stage2 admission generation (callee 288a410a, wf blob 09ff52b3)"
git push origin ci-epoch/n7-freeze-2026-10-13
```

동등하게 immutable reference면 충분하다(태그명은 예시). Frozen epoch는
삭제하지 않는다(§2.5 판정 기준).

## Step 2 — Record (핀·바인딩 기록)

```bash
jq -r '.trustedAdmissionWorkflowSha' config/trusted_writer_set.json
jq -r '.productionExecutionPin, .ciEpochId' config/policy/epoch_manifest.json
gh api repos/Archright/.github/contents/.github/workflows/admission-gate.yml \
  --jq '.content' | base64 -d | grep -n 'admission-check.yml@'
git show origin/main:.github/workflows/admission-check.yml | git hash-object --stdin
```

기록 위치: 본 문서 §0 표 + 착지 PR 본문. (측정·역사 데이터는 AGENTS.md에
두지 않는다 — §5 SSOT.)

## Step 3 — Tombstone + New Epoch (세대 준비 — 이미 존재하는 두 브랜치)

- **Tombstone**: 구 세대(callee `288a410a` + wf blob `09ff52b3`)는 폐기
  예정임을 본 절로 기록한다. Tombstone은 required-check 우회·검증 면제를
  의미하지 않는다 — canonical cutover 전까지 구 세대가 계속 집행한다.
- **New Epoch (Axiom 사이드)**: `feat/s2-single-anchor-observability`
  — admission-check.yml(baseSha 입력·B* 바인딩·애노테이션·always()
  업로드) + merge_admission.json v1.13.0 + ADR-0027 Amendment B +
  본 러북. 착지 경로는 **MUST-T2**(아래) — trustSurface 2건을 건드리므로
  **인간 수동 머지 필수**.
- **New Epoch (org 사이드)**: `Archright/.github`
  `feat/anchor-resolve-bstar` — `anchor-resolve` DAG-head job(PR venue
  전용, B* 해석·40-hex 검증·job output `B_STAR`) + PR-venue 소비자
  전환(closure-deriver `BASE_SHA` · mint-prepare/mint-publish
  `baseSha`) + admission-check 2호출에 `baseSha:` 전달.
  merge_group 표현식은 불변.

## Step 4(프로토콜 5) — Atomic Binding Update (원자 바인딩 회전)

**TWS 핀과 epoch_manifest 핀을 신세대 admission-check.yml blob sha로
하나의 커밋에서 동시 회전한다.** 부분 갱신 금지(§2.5 — 절차 5).

```bash
# (a) Axiom 세대 PR이 main에 착지된 직후, main에서:
git checkout main && git pull --ff-only origin main
NEW_WF_BLOB="$(git hash-object .github/workflows/admission-check.yml)"
printf '%s' "$NEW_WF_BLOB" | grep -qE '^[0-9a-f]{40}$'   # 40-hex guard
echo "NEW_WF_BLOB=$NEW_WF_BLOB"                          # ← 기록값과 대조

# (b) 단일 커밋 회전 (trustSurface 2건 = config/policy/**, TWS):
git checkout -b ci/epoch-n8-single-anchor-binding
jq --arg s "$NEW_WF_BLOB" '.trustedAdmissionWorkflowSha = $s' \
  config/trusted_writer_set.json > /tmp/tws.json && mv /tmp/tws.json config/trusted_writer_set.json
jq --arg s "$NEW_WF_BLOB" '.productionExecutionPin = $s' \
  config/policy/epoch_manifest.json > /tmp/epoch.json && mv /tmp/epoch.json config/policy/epoch_manifest.json
git diff --stat   # 정확히 2 파일만 변경되었는지 확인
git add config/trusted_writer_set.json config/policy/epoch_manifest.json
bin/axiom-gate commit -m "ci: epoch N+8 atomic binding update — TWS+epoch pin -> $NEW_WF_BLOB"
```

불변식: 회전 후 `trustedAdmissionWorkflowSha == productionExecutionPin ==
git hash-object(admission-check.yml@main)` — 셋 중 하나라도 불일치면
identity 스텝이 fail-closed로 차단한다(구 세대에서도 동일 — A2 pin pair).

## Step 5(프로토콜 6) — Local / Targeted Verification

```bash
# (a) YAML/JSON 파싱 (parse-probe 스타일):
python3 -c "import yaml;yaml.safe_load(open('.github/workflows/admission-check.yml'));print('callee YAML OK')"
python3 -c "import json;json.load(open('config/policy/merge_admission.json'));print('policy JSON OK')"
jq -e '.version == "1.13.0"' config/policy/merge_admission.json

# (b) 셸 블록 구문 게이트 (등록 도구 — v19):
tools/ci/validate_workflow_shell.sh

# (c) 핀 삼각형 등식:
test "$(jq -r .trustedAdmissionWorkflowSha config/trusted_writer_set.json)" \
  = "$(jq -r .productionExecutionPin config/policy/epoch_manifest.json)" && echo "pin pair OK"

# (d) verdict predicate (컨텍스트가 있을 때만 적용 가능 — GitHub API 필요):
bin/ax merge <PR번호> --dry-run --json | jq '.verdict'   # 선택적 targeted probe
```

기존 CI 전체를 반복 실행하지 않는다(§2.5 판정 기준 1항).

## Step 6(프로토콜 7) — Short Validation (최소 실실행)

- 신세대 callee가 **파싱되는지**는 다음 PR-venue 런 1회로 검증한다:
  workflow_call 입력 오탈자·표현식 과오 시 GitHub는 0-job
  startup_failure를 내는데, 그것이 최소 검증 신호다(quirk:
  `docs/spec/gh_run_observation_quirks.md` Q4/Q4a — 21000자 표현식
  한도·주석 내 토큰 금지).
- 검증 관찰점: (1) `anchor-resolve` B* 해석 성공, (2) identity 스텝
  `ANCHOR_INPUT_MISMATCH` 부재(= B* == B 성립), (3) 애노테이션·
  always() 업로드가 NOT-ADMIT 리허설(의도 실패 PR)에서 증거를 남기는지.

## Step 7(프로토콜 8) — Canonical Cutover

1. **큐 배수 REQUIREMENT**: canonical cutover 전에 merge queue를
   비운다(in-flight PR 0건).
   - **조정 지점 — PR #803**: `feat/rust-subject-v1`(OPEN, 외부 세션
     소유)이 큐에 있다. **본 세대 작업자가 건드리지 않는다** — 소유
     세션과 착지 시점을 조정하거나 명시적 park 후 큐 배수를 선언한다.
2. **Dependabot callee pin 회전**: `Archright/.github`의 admission-gate가
   `Archright/Axiom/.github/workflows/admission-check.yml@288a410a…`
   2건을 신세대 main merge sha로 회전 (org `feat/anchor-resolve-bstar`
   착지 + Dependabot pin PR 또는 동등 수동 회전 — org 측 절차 준수).
3. **pin-promotion-gate 상태 전이**: `PREPARED → PINNED` 확인
   (회전된 callee sha가 org ruleset required-workflow로 등록됨).
4. **확인 명령**:
   ```bash
   gh api repos/Archright/.github/contents/.github/workflows/admission-gate.yml \
     --jq '.content' | base64 -d | grep -n 'admission-check.yml@'
   gh api repos/Archright/Axiom/rulesets -q '.[].rules[] | select(.type=="required_status_checks")'
   ```

## Step 8(프로토콜 9) — Production Acceptance

- **평범한 PR 1건**이 신세대에서 **green 착지**해야 한다 (merge-queue
  경로, verdict GO, 애노테이션 0건, `admission-verdict-*` 아티팩트 존재).
- GitHub platform semantics·authority boundary·continuity 확인:
  required check `admission-check` = 신세대 callee 런, `bsec-integrity`
  불변, `bypass_actors=[]` 불변.
- 수동 머지 경로(MUST-T2)로 착지한 trustSurface PR 자체는 acceptance
  카운트가 아니다 — 평범한 코드 PR 건이 기준이다.

## Step 9(프로토콜 10) — Rollback

신세대에서 결함 발견 시 **frozen epoch로 명시 재회전**한다(부분 롤백
금지 — Step 4와 동일 원자성):

```bash
OLD_WF_BLOB="09ff52b3596cbf116fa7e6c64b0763f91443f3b2"
git checkout -b ci/rollback-n8-to-n7
jq --arg s "$OLD_WF_BLOB" '.trustedAdmissionWorkflowSha = $s' \
  config/trusted_writer_set.json > /tmp/tws.json && mv /tmp/tws.json config/trusted_writer_set.json
jq --arg s "$OLD_WF_BLOB" '.productionExecutionPin = $s' \
  config/policy/epoch_manifest.json > /tmp/epoch.json && mv /tmp/epoch.json config/policy/epoch_manifest.json
bin/axiom-gate commit -m "ci: rollback epoch N+8 -> N7 (wf blob $OLD_WF_BLOB)"
# org 측: callee pin을 288a410a041e4e889e6afe1a67c25bdcaa956344로 재회전
# (Revert PR — org 측 절차 준수)
```

Rollback 불가 상태가 되면 영구 제거가 아니라 §2.5의 명시 판정을 요구한다.

## MUST-T2 — 인간 터치포인트 (사용자 개입 필수)

**Axiom 사이드 세대 PR은 trustSurface 2건을 수정한다 —
`.github/workflows/admission-check.yml` + `config/policy/merge_admission.json`
(둘 다 merge_admission.json trustSurface 열거) — 따라서 auto-merge가
아니라 `TRUST_SURFACE_MODIFIED` 수동 머지 경로(CODEOWNERS 리뷰 + TWS 핀
ceremony)로 **인간이 직접 머지**해야 한다.** 이 PR은 본 러북 Step 4의
선행조건이며, 에이전트가 머지해서는 안 된다 (merge authority = GitHub
네이티브 MERGE, AGENTS.md §2; 수동 경로 계약 = merge_admission.json
v1.8.0/v1.12.0 trustSurface + `dryRunExit` TRUST_SURFACE_MODIFIED→0).

## 조정·STOP 사항

- **PR #803** (`feat/rust-subject-v1`, 외부 세션): 큐 배수 요구와 충돌
  가능 — 본 세대 작업자가 touch 금지, 소유 세션과 조정 (Step 7.1).
- 본 러북 단계에서는 push·PR 생성·pin 회전·ruleset 변경 일절 수행하지
  않았다 — 모든 회전 명령은 실행 단계의 인간 승인 하에만 유효하다.

## 실행 기록 (2026-10-13, 실행 완료)

> 헤더의 "DRAFT (미착지)"는 작성 시점 상태 기록이다 — 본 절은 그 뒤의
> 실행 완료 기록이며 append로만 남고 위 절차 본문을 개정하지 않는다.
> **절차 이탈 1건(Step 1)을 은폐 없이 정밀 기록한다.**

- **Step 1 — Freeze 스킵(선언된 이탈)**: freeze 태그
  (`ci-epoch/n7-freeze-2026-10-13`)는 **생성되지 않았다**. pin-pair
  회전이 PR #804 안에서 **coherent generation 대안**으로 착지해 본
  runbook의 post-merge Step 4(원자 바인딩 회전)를 대체했다 — §2.5의
  "일관된 세대 전환" 불변식은 태그가 아니라 단일 원자 커밋으로 충족됐다.
  구 세대 롤백 타깃은 §0 표 기록값(TWS·epoch 핀 `09ff52b3`, org callee
  `288a410a`)이 계속 보유한다.
- **Step 2 — Record**: §0 표(원 세대 핀 4종 + 신세대 드래프트 blob)가
  기록 담당. 착지 후 pin 삼각형 등식 검증 — `trustedAdmissionWorkflowSha
  == productionExecutionPin == admission-check.yml@main blob` ==
  **`b4d4e828c`**.
- **Step 3 — Tombstone + New Epoch**: Axiom 사이드 세대 PR **#804 MERGED
  — `ed9b3730`, 06:13:56Z**(B* 바인딩 callee + merge_admission.json
  v1.13.0 + ADR-0027 Amendment B + 본 runbook). org 사이드 New Epoch
  (`feat/anchor-resolve-bstar`) = org PR **#196 MERGED — `878b9003`,
  06:23:01Z**.
- **Step 4 — Atomic Binding Update(대체 경로로 실행)**: org 트리거 PR
  **#191 MERGED — 06:17:29Z** → Dependabot callee pin PR **#192·#193·
  #194·#195 전부 MERGED**(admission-gate 2호출 핀 → `ed9b3730`) → pin
  삼각형 재검증(위 등식, `b4d4e828c`)으로 원자성 확인.
- **Step 5·6 — 최소 실실행(첫 수용은 FAIL)**: 첫 acceptance 시도
  merge_group 런 **38359095521 FAIL** — `mint-publish` **MINT_PUB_TREE**
  (원인: gateway transitive-skip 회귀 —
  `docs/spec/gh_run_observation_quirks.md` Q10, PR 내용 결함 아님). org
  수정 PR **#197 MERGED — `4a81d18a`, 07:16:42Z**.
- **Step 7 — Canonical Cutover(재진입)**: 큐 배수·수정 세대 위 재진입 —
  PR **#805 재arm 07:17:05Z**(치유 사이클 전투 실행 —
  `docs/agents/merge_admission_observation.md` 부록 (e)).
- **Step 8 — Production Acceptance: PASS**: PR **#805 MERGED — 07:58:53Z,
  `12ab65d4`**(parents=2, admission-verdict 아티팩트 존재, error
  애노테이션 0건, `landing_observe` TERMINAL_SUCCESS). 수정 후 **4회
  연속 green MG 착지** — #807 07:37:48Z · #808 07:40:21Z · #809
  07:56:28Z · #805 07:58:53Z. 평범한 코드 PR이 신세대 merge-queue 경로로
  green 착지(verdict GO·애노테이션 0건·`admission-verdict-*` 존재) —
  수용 기준 충족.
