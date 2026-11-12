# Admission Generation Divergence Test — 런타임 sha 준수 입증 (2026-10-16)

> **종류**: [docs/spec/admission-generation.md](../spec/admission-generation.md) §6.1 발산 테스트(drift-guard divergence test)의 실행·관측 기록. Slice A §6 후속 — **"GitHub 런타임이 ruleset의 `sha` 필드를 존중한다"를 첫 세대에서 직접 관측 불가**라는 §6.1의 인식론적 한계를 본 테스트로 닫는다.
> **판정 규칙(§6.1)**: 컨트롤러 main이 핀을 지난 뒤의 다음 admission 런에서 E1(`referenced_workflows`) 지문이 불변이면 **PASS**(실행이 sha에 의해 지배). 지문이 전진하면 **FAIL**(ref 준수 — §5.7 failure 원복 판정).

## 1. 세대 정체성 (테스트 시작 시점 관측)

- **S (ruleset 고정 sha)**: `135644a30291f2956e90b09a819fa7fe43371dd4`
  - `GET /orgs/Archright/rulesets/24233738` → workflows[0] = `{path: .github/workflows/admission-gate.yml, repository_id: 1182157951, sha: 135644a302…}`, `updated_at = 2026-10-15T23:36:12.703+09:00`
  - `GET /orgs/Archright/rulesets/23943917` → 동일 sha, `updated_at = 2026-10-15T23:36:14.278+09:00`
  - S = 테스트 시작 시점 컨트롤러 main HEAD(P3 pin 회전 PR Archright/.github#220의 MERGE, 2026-10-15T14:31:15Z) — 즉 **pin == ref인 상태에서 출발하지 않는** 것이 본 테스트의 전제다(아래 §2에서 ref를 일부러 앞지른다).
- **S 세대 선언 핀-트리플** (`admission-gate.yml@135644a302…` `uses:` 직접 판독):
  - `admission-check.yml@dc527994c987cad9d7d83f1dc27650d0c15eb63e`
  - `certificate-mint.yml@689ff9eaf63c9e3ac8ae33aefcef84a74cb0c467` (P3 회전 aa0511343→689ff9eaf 포함 세대)
  - `runner-pool-acceptance.yml@ba773d0631b5757525b16d8fd62e220492e98e76`

## 2. main 전진 (발산 유발 — §6.1 "무해한 컨트롤러 커밋")

- 컨트롤러 PR **Archright/.github#221** (`ci/divergence-marker-h3-20261016`) — README-only 마커("2026-10-16: divergence-test marker — main advances past the pinned admission generation; see Archright/Axiom docs/spec/admission-generation.md §6"), workflow 내용 변경 0줄.
- 게이트: **pin-promotion-gate (DEBT#473) SUCCESS**, mirror checks SKIPPED(컨트롤러 미러 입력 부재 — 정상), mergeStateStatus CLEAN.
- MERGE: **`9a89f55521069cfc17b9aa9ec6ac0379b60f8ec1`** (native MERGE) = **H_adv**.
- **H_adv ≠ S** ✓ — ruleset 재핀 없이 컨트롤러 main이 핀을 앞지른 상태를 의도적으로 만들었다(§4.3 재핀 의무의 유일한 절차적 예외가 본 §6.1 테스트다 — 테스트 후 재핀은 핀 회전 슬라이스 소관).

## 3. 관측 차량 — 정정 docs PR의 큐 착지

- 차량 PR: **Archright/Axiom#855** "docs: p3 acceptance record — exact re-pin window correction (append-only)", 커밋 `800d37f39243bffc3ad0b9cab1a33d75c9482cc0` — docs-only 6줄([p3_landing_acceptance_2026-10-15.md](p3_landing_acceptance_2026-10-15.md) §8 append-only 정정: E3 ceremony review residual #1 verbatim 값 + 라이브 ruleset readback 대조). 본문에 발산 결과 선기재 없음(no-peeking).
- 로컬 검증: pre-commit 3게이트 PASS(anti-theater / layer-enforcement 1602 files / stale-cert), pre-push 14개 push-admissibility 전부 green(OID 스냅샷 경유).
- pull_request 게이트 12건 전부 success 후 큐 진입(`gh pr merge --merge` → merge queue).
- **MERGE: `a445de383d762a65d894f4b97dced3a757ba8ae9`** (2026-10-15T16:55:53Z, GitHub native MERGE). 동일 큐 그룹에 병렬 진입한 #857(registry hygiene T2, 별도 워크스트림)과의 **그룹 커밋**으로 착지 — 그룹 head_sha가 곧 머지 커밋이다.

## 4. 관측 (핵심 산출물) — 런 38770493931

merge_group admission-gate 런 **38770493931** (생성 2026-10-15T16:37:01Z, queue branch `gh-readonly-queue/main/pr-855-c606c437348f8c26dd0d8e099ca80db7ecda2000`, group head_sha `a445de383d…`):

- **E1 `referenced_workflows`** — 생성 시점(16:39Z)과 완료 후 재판독 모두 동일:
  - `Archright/Axiom/.github/workflows/admission-check.yml@dc527994c987cad9d7d83f1dc27650d0c15eb63e`
  - `Archright/Axiom/.github/workflows/certificate-mint.yml@689ff9eaf63c9e3ac8ae33aefcef84a74cb0c467`
  - `Archright/Axiom/.github/workflows/runner-pool-acceptance.yml@ba773d0631b5757525b16d8fd62e220492e98e76`
- **런 판정**: `conclusion: success` (완료 2026-10-15T16:55:42Z).
- **관측 시점 S_now 재판독**: ruleset 24233738 sha = `135644a302…` (불변 — 관측 창에서 F2의 재핀 없음).
- **관측 시점 컨트롤러 main**: `9a89f55521069cfc17b9aa9ec6ac0379b60f8ec1` (H_adv) **≠ S_now** ✓.
- **대조 베이스라인(발산 전)**: pr-851의 MG 런 **38761686880**(2026-10-15T15:35:33Z, 당시 main == S)의 E1 지문 = 상기와 **완전히 동일**한 트리플.
- E2(`Uses:` 로그 라인): 본 환경의 job-log 엔드포인트에서 grep 가능한 `Uses:` 라인 미추출 — 본 판정은 §6.1이 규정한 E1 지문 채널로 성립한다(E2는 동결 기록 §6의 별도 실측 유지).

## 5. 판정

**PASS** — 실행은 ruleset `sha` 필드에 의해 지배된다.

1. 지문 == S 세대 선언 핀-트리플(3요소 전부 일치) — 발산 전 베이스라인과도 동일(불변).
2. 관측 시점 컨트롤러 main(H_adv `9a89f555…`) ≠ S_now(`135644a302…`) — ref가 지배했다면 조립자 지문이 `9a89f555…`가 참조하는(즉 main 추적) uses-graph로 전진했어야 한다. 전진하지 않았다.
3. 런 success + 착지는 GitHub native MERGE 커밋 `a445de383d…`(E4 착지 정체성) — green이 관측을 마스킹하지 않았다(E1 지문을 직접 대조).

§6.1의 "미입증 가설"이 소멸했다 — Slice A의 런타임 sha 준수는 본 관측으로 **입증된 사실**이 된다. §5.7 success 행의 요건(발산 테스트 수행) 충족.

## 6. 명령어 (재현)

```bash
# 세대 판독
gh api /orgs/Archright/rulesets/24233738 --jq '{sha: .rules[0].parameters.workflows[0].sha, updated_at}'
gh api /orgs/Archright/rulesets/23943917 --jq '{sha: .rules[0].parameters.workflows[0].sha, updated_at}'
gh api "repos/Archright/.github/contents/.github/workflows/admission-gate.yml?ref=135644a30291f2956e90b09a819fa7fe43371dd4" --jq '.content' | base64 -d | grep -n "uses:"
# main 전진 관측
gh api repos/Archright/.github/commits/main --jq '{sha: .sha, msg: .commit.message}'
# 런 관측 (E1)
gh api "repos/Archright/Axiom/actions/runs?event=merge_group&per_page=15" --jq '.workflow_runs[] | select(.name=="admission-gate") | "\(.id) \(.conclusion) \(.head_branch)"'
gh api repos/Archright/Axiom/actions/runs/38770493931 --jq '{conclusion, referenced_workflows}'
gh api repos/Archright/Axiom/actions/runs/38761686880 --jq '.referenced_workflows'  # 발산 전 베이스라인
```
