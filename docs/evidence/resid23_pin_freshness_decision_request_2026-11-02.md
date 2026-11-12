# RESID-23 핀 최신성 조사 완결 — operator 결정 요청 (2026-11-02)

> **종류**: RESID-23(Archright/.github `admission-gate-v2.yml` side-pin 최신성)의 조사(INVESTIGATING) 완결 기록 + operator 결정 요청서. 본 문서는 조사 결과와 **권고**만 정본화한다 — 재핀 여부의 최종 판정과 값 갱신(Archright/.github 저장소 측 변경)은 조직 operator의 권한이며, 본 문서가 착지시키는 것은 문서뿐이다(docs-only).
> **상태**: RESID-23 work_state **READY → 재핀 착지·readback 확인**(2026-11-02 — operator 판정 ① 수령·§8 기입, Archright/.github PR #252 MERGE·org ruleset 갱신 완료). disposition 부여·진행 계정 정리는 ledger 갱신 7차에서 수행.
> **권고**: **① 재핀 권장** — 후보 `6a2a5475697083e9d1c751293b0ea769d8ded603`(2026-10-27T14:45:56Z, blob 현행성·main 조상 관계 실측 검증 완료). 판정·착지는 operator.
> **관측 시각**: 2026-11-02T02:33Z 기준. 모든 GitHub 호출은 **읽기 전용 GET**(Archright/.github·Archright/Axiom·org search) — 쓰기 호출 0건, org 변수·ruleset 변경 0건.
> **권위**: 아래 표가 가리키는 GitHub API 관측·blob·compare 실측이 각 주장의 근거다. 본 문서는 Reporter다(Authority ≠ Adapter — AGENTS.md §2.3).

---

## 1. 대상·핀 구조 (조사 범위 확정)

`admission-gate-v2.yml`은 **Archright/.github** 저장소의 파일이다(현행 main `d76caf956000175bbc78f9b25bced842c02992a5`, blob `41893f8495204a40e73151aefb56ebeeaa4762bb` — 2026-10-31 readback(`resid22_org_repin_closure_2026-11-02.md` §1) 이후 이동 없음을 ls-remote로 재확인). 파일 내 `uses:` 핀 6행은 모두 **Archright/Axiom** 저장소의 파일을 참조한다:

| 줄 | 피참조 (Archright/Axiom 경로) | 핀 커밋 | blob @핀 | blob @Axiom main | 판정 |
|---|---|---|---|---|---|
| :266 | `.github/actions/setup-axiom-toolchain` (action.yml) | `18b180094a19096f15a268eeb110a1c7f2f4cfba` | `262d42b74b0beb7639e7f105005903a8cf720a10` | `b65bf7b70cdd7be45ae17747aef642358af676fa` | **불일치 — drift (본 조사 대상)** |
| :584 | `.github/workflows/runner-pool-acceptance.yml` | `18b180094a19096f15a268eeb110a1c7f2f4cfba` | `de255e798727dba0e6e3dee15085b07e044d4eaf` | `8a530f746d2471f24ed95c40ce935fdda5ca1b57` | **불일치 — drift (본 조사 대상)** |
| :440, :666 | `.github/workflows/admission-check.yml` | `f18713934dad76b375897fb111798499ece34e47` | `b9792fc61825f05f81b43e9dd4db4d36bede0630` | `b9792fc61825f05f81b43e9dd4db4d36bede0630` | 일치 — 내용 현행 |
| :492, :549 | `.github/workflows/certificate-mint.yml` | `d117ae8e2230906d4517a890d6b01e8b3c1e8c03` | `479f9b5b5a22a92c292f60f790e54d45a423ea5e` | `479f9b5b5a22a92c292f60f790e54d45a423ea5e` | 일치 — 내용 현행 |

- **핀 커밋 실체**: `18b180094a19096f15a268eeb110a1c7f2f4cfba` = Archright/**Axiom** 커밋(2026-10-17T10:36:09Z, "Merge pull request #906 from Archright/ci/lane-upload-hidden-files").
- **read 경로 정정 기록**: 과거 커밋 고정 판정을 재검증하며 Archright/**.github** 측 commits/compare API로 `18b180094…`를 조회하면 **HTTP 404/422**("No commit found for SHA") — 핀 SHA는 .github가 아니라 Axiom 저장소의 오브젝트다. 조회를 `repos/Archright/Axiom`으로 정정해 재수행했으며, 실패 시도도 은폐 없이 기록한다(resid22 문서 §1의 404 정정 관례 준수).

## 2. drift 2핀 조사 — 핀→@main 변화 전수

핀 커밋 이후 대상 2경로를 건드린 커밋은 **총 4건** 전부이며, 분류는 버그 수정 3·보안(공급망) 하드닝 1·호환성 파괴 0이다:

| 커밋 | 시각(UTC) | 경로 | 분류 | 내용 |
|---|---|---|---|---|
| `0ecd532e1c` | 2026-10-20T11:27 | rpa | 버그 수정 (범위 의미론) | "release L2 gate asserts its real executed-job scope" — SL-09 실행 범위 수리(승격 아님, 에포크 정의 불변) |
| `1837fa64c4` | 2026-10-20T16:43 | rpa | 버그 수정 (계약 파싱 결함) | reusable-workflow outputs를 object 형식(description/value)으로 수리 — bare mapping은 워크플로 파싱 자체를 실패시킴(PR #979 이후 main이 HTTP 422로 디스패치 불능이던 실측 포함) |
| `03e3731a79` | 2026-10-20T17:26 | action | 버그 수정 (correctness) | LFS-safe closure archive — 자격증명 없는 체크아웃에서 LFS-tracked 경로가 `git archive`의 smudge를 유발해 keygen이 실패(실측 run 39463081984) |
| `6a2a547569` | 2026-10-27T14:45 | rpa+action | 보안·견고성 하드닝 | dpkg lock timeout 300s + **choosenim init.sh sha256 고정·불일치 fail-closed** + arm64 tarball sha256 검증 + curl 유한 재시도 |

- **main 측 구조 변화**: `runner-pool-acceptance.yml`에 workflow_call **outputs 4종 신설**(`executed_jobs`·`scope_sl09`·`scope_sl09_reason`·`epoch_id`)과 항상-실행 `sl09-scope` 잡 — `executed-jobs` 잡이 실행 잡 집합의 권위를 출력으로 발행.
- **admission 소비 계약 판정: 불변(additive)**. (a) :266 action — 호출자는 `cache-save-enabled`·`cache-build-source` inputs만 전달; pin↔main diff hunk 전부가 run 스텝 내부(`runs:` 선언·inputs 불변). (b) :584 callee — inputs(`target_sha`·`force_full`) 동일; 호출자는 결과 롤업만 소비(admission-gate-v2.yml :687 `RESULT_GATEWAY: ${{ needs.gateway.result }}`), main의 신규 outputs는 호출자가 참조하지 않는 **추가**다. → 재핀은 호출자 관측 계약을 바꾸지 않는다.

## 3. 핀 버전이 보유한 결함 (main은 수정 — 핀은 미수취)

1. **rpa — 무조건 false 게이트(침묵 결함)**: 핀 버전의 `select.outputs`는 `scope_sl09`를 선언하지 않는데 하류가 `needs.select.outputs.scope_sl09 == 'true'`를 참조 → 모든 모드에서 항상 `''`. SL-09 승격 후에도 gateway 레인이 구조적으로 복원 불가(실패가 아닌 침묵 스킵). 현재 epoch N+7(SL-09 미승격)에서는 main과 동일하게 미실행 — **오늘의 관측 행위 차이는 0**이다. 결함은 승격 전환 시 비로소 침묵 결함으로 전환된다.
2. **action — LFS 경로 실패(실측)**: 핀 버전의 keygen/probe `git archive`는 LFS-tracked 경로 존재 시 자격증명 없는 체크아웃에서 실패(측정 run 39463081984 — B/M 생성대 첫 착지 런).
3. **action — dpkg 락 즉사(관측)**: unattended-upgrades가 lock-frontend를 홀드하면 apt가 즉시 exit 100(관측 2026-10-27). main은 `DPkg::Lock::Timeout=300`으로 수리.
4. **action — 미해시 부트스트랩 실행(공급망 노출, 지속)**: 핀 버전은 `curl -sSf …/choosenim/init.sh | sh -s -- -y` — 내용 해시 고정 없는 이동 표적 파이프 실행. main은 sha256 고정(`6c38d83e5f33…`)+불일치 시 실행 거부 fail-closed.

## 4. 나머지 4핀 재확인 — drift 재발 없음

- :440/:666 `admission-check.yml@f18713934dad…` — 핀 커밋 존재 확인(commits API, 2026-10-31T03:24:46Z) + blob@main `b9792fc6…` = §8 = 핀 blob → **현행 유지**.
- :492/:549 `certificate-mint.yml@d117ae8e22…` — 핀 커밋 존재 확인(2026-10-29T07:40:01Z) + blob@main `479f9b5b…` = §8 = 핀 blob → **현행 유지**.
- Archright/.github main HEAD `d76caf956…` — ls-remote 재실측, 10-31 이후 불변.
- **회전 파급 범위**: `18b180094…` 참조는 code search(GET)로 양쪽 저장소 전수 확인 — Archright/.github에서는 `admission-gate-v2.yml` 1개 파일(:266·:584 2행)뿐, Archright/Axiom에서는 docs/evidence·data 기록 6건뿐(워크플로·config 핀 0건). 재핀의 값 변경 대상은 동 파일 2행이 유일하다.

## 5. 권고 (본 문서는 권고만 — 최종 판정은 operator)

**① 재핀 권장.**

- **후보 revision**: `6a2a5475697083e9d1c751293b0ea769d8ded603`(2026-10-27T14:45:56Z).
  - 양 대상 경로의 **최종 변경 커밋**(이후 대상 경로 커밋 0건) — blob@후보 = blob@main 실측 일치(action `b65bf7b70…`, rpa `8a530f746…`).
  - main의 조상(compare `6a2a547569...main` behind_by 0) — 회전 후에도 두 blob은 이후 커밋이 없어 현행 유지.
  - 대안: 현행 Axiom main HEAD `291cb2f081eb3f25a74b78db2d3fdd36ab4a731e`(blob 동일 — §1 실측). 최소 회전(6a2a547569) vs 최신 HEAD 중 선택은 operator 몫. 기존 2핀(admission-check@f18713934·certificate-mint@d117ae8e)이 "착지 시점의 최근 커밋에 핀, blob 현행 유지" 관례임이 §1 표와 일치.
- **근거**:
  1. 핀 버전은 main에서 이미 수정된 **실측 결함 4종**을 보유한다(§3) — ④는 현재도 지속되는 공급망 노출, ①은 승격 전환 시 침묵 결함화, ②③은 재발 시 게이트 지연·실패.
  2. 호출자 소비 계약 불변(§2) — 재핀은 현행 epoch에서 behavior-neutral이므로 게이트 의미론(§0.12) 변경 아닌 결함 수리다. 재핀 시 사전등록 관측 계약 수반 여부는 operator가 명시(RESID-22 ③ 전례 참조).
  3. GitHub 공식 문서가 SHA 핀의 비용으로 "important bug fixes and security updates 미수취"를 명시(§6-3) — SHA 핀 정책은 신선도 검토 절차와 짝이다. RESID-23의 "핀 최신성 검토"가 그 절차다.
- **② 동결 유지 선택 시**: "오늘 행위 차이 0"(§3-1)만으로는 근거가 부족 — §3-2/3/4의 결함 수용(특히 미해시 부트스트랩 실행의 지속 노출)을 명시적으로 선언하는 근거 기록이 필요하다.
- **③ 판정 보류 조건**: 재핀 후보의 blob 현행성이 파괴되는 신규 커밋이 대상 경로에 착지하면 본 조사는 무효화 — §1 표 재실행 후 재권고.
- **착지 참고(재핀 채택 시)**: 값 갱신 PR은 **Archright/.github** 대상(조직 operator 권한 — RESID-22 org re-pin 전례와 동일 구조)이며 :266/:584 핀 값과 인접 주석 갱신을 수반한다. Axiom 저장소 측 후속 조치는 불요(§4 파급 범위 실측).

## 6. Context7 공식 문서 근거 (docs.github.com — GitHub Actions)

Context7 `/websites/github_en_actions`(docs.github.com/actions, 2026-10-29 스냅샷)에서 확인한 공식 권고 3건:

1. **Secure use reference — "Using third-party actions"**: "Pin actions to a full-length commit SHA … helps mitigate the risk of a bad actor adding a backdoor to the action's repository, as they would need to generate a SHA-1 collision … **verify it is from the action's repository and not a repository fork**." — 본 조사가 핀 SHA의 소속 저장소를 실측해 정정한 절차(§1 read 경로 정정)와 정합.
2. **Reusing workflows — "Calling a reusable workflow"**: ref로 SHA·tag·branch 모두 가능하며 "**Using the commit SHA is the safest option for stability and security**."
3. **Find and customize actions — "Using SHAs"**: "SHAs are immutable and therefore more reliable than tags or branches. **However, this approach means you will not automatically receive updates for an action, including important bug fixes and security updates.**" — RESID-23의 실제 상황(핀이 수정 4건 미수취, §3)과 정확히 대응하는 공식 근거. SHA 핀의 보안 이득은 신선도 검토 주기라는 운영 비용과 짝을 이룬다.

## 7. 재현·소비

```bash
# 핀 원문·blob 대조 (GET만)
gh api repos/Archright/.github/contents/.github/workflows/admission-gate-v2.yml?ref=main --jq .sha   # 41893f84…
gh api "repos/Archright/Axiom/contents/.github/actions/setup-axiom-toolchain/action.yml?ref=18b180094a19096f15a268eeb110a1c7f2f4cfba" --jq .sha   # 262d42b7…
gh api "repos/Archright/Axiom/contents/.github/actions/setup-axiom-toolchain/action.yml?ref=main" --jq .sha                        # b65bf7b7…
gh api "repos/Archright/Axiom/contents/.github/workflows/runner-pool-acceptance.yml?ref=18b180094a19096f15a268eeb110a1c7f2f4cfba" --jq .sha       # de255e79…
gh api "repos/Archright/Axiom/contents/.github/workflows/runner-pool-acceptance.yml?ref=main" --jq .sha                            # 8a530f74…
# 핀 이후 대상 경로 커밋 전수
gh api "repos/Archright/Axiom/commits?sha=main&path=.github/actions/setup-axiom-toolchain&per_page=100"
gh api "repos/Archright/Axiom/commits?sha=main&path=.github/workflows/runner-pool-acceptance.yml&per_page=100"
# 후보 SHA 검증 (blob 현행성 + 조상 관계)
gh api "repos/Archright/Axiom/contents/.github/actions/setup-axiom-toolchain/action.yml?ref=6a2a5475697083e9d1c751293b0ea769d8ded603" --jq .sha    # b65bf7b7…
gh api "repos/Archright/Axiom/contents/.github/workflows/runner-pool-acceptance.yml?ref=6a2a5475697083e9d1c751293b0ea769d8ded603" --jq .sha        # 8a530f74…
gh api "repos/Archright/Axiom/compare/6a2a547569...main" --jq '{ahead_by, behind_by}'                                              # behind_by 0
# 회전 파급 범위
gh api "search/code?q=repo:Archright/.github+18b180094a19096f15a268eeb110a1c7f2f4cfba"
gh api "search/code?q=repo:Archright/Axiom+18b180094a19096f15a268eeb110a1c7f2f4cfba"
```

## 8. operator 결정 기록 (판정 시 기입)

| 필드 | 값 |
|---|---|
| 판정 | **① 재핀 채택** — 인간 operator 명시 지시(제안 `6a2a547569…`로 조직 workflow 참조 변경) |
| 판정자·시각 | 인간 operator(조직 소유자) — 2026-11-02, 세션 지시로 수령·기록 |
| ① 선택 시: 착지 revision·사전등록 관측 계약 수반 여부 | 착지 revision: 제안 `6a2a5475697083e9d1c751293b0ea769d8ded603`에서 **게이트 강제 편차** `f18713934dad76b375897fb111798499ece34e47`. PR #252 첫 시도에서 pin-promotion-gate(DEBT#473)가 제안 SHA를 "epoch-승격 아님"으로 FAIL(fail-closed·waiver 불가 — 2026-10-21 waiver 경로 제거) → `f18713934`는 (a) 제안의 직계 조상이며 (b) 3경로 blob이 제안·현행 main과 동일(setup-axiom-toolchain `b65bf7b70…`·runner-pool-acceptance `8a530f746…`·admission-check `b9792fc618…`=승격값)인 epoch-승격 SHA로 착지 — **컨텐츠는 제안과 동일, 편차 사유는 게이트 강제뿐**. 사전등록 관측 계약: 미수반(§2 additive·behavior-neutral 판정 — operator 지시에 계약 요건 명시 없음). post-repin 첫 admission-gate v2 실행은 본 결정 기록 PR의 Axiom CI(merge_group)에서 새 핀으로 관측된다 |
| ② 선택 시: 수용 선언 근거 문서 | (해당 없음 — ① 채택) |
| 착지 PR(.github 측)·readback 링크 | Archright/.github **PR #252 MERGE** `0684026f1b929ed9b9c3884be4da3dc89aa2bdc6`(2026-11-02T04:47:57Z, native merge — diff :266·:584 2행 전부로 §4 회전 파급 범위 예측과 일치). org ruleset 2종 갱신: axiom-admission-gate `25218071`·landing-integrity `23943917` workflows rule sha → `0684026f…`(enforcement=active 유지, landing-integrity.yml blob 불변). readback(2026-11-02 GET 재실측): admission-gate-v2.yml@HEAD 핀 `f18713934…` 4곳(:266·:440·:584·:666)·ruleset sha `0684026f…` 2종·원격 HEAD `0684026f…` 전부 일치 |
