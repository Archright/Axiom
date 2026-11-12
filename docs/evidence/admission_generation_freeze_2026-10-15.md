# Admission Generation Freeze Record — H₀/H₁ 동결 (Slice A)

> **성격**: admission generation 세대 경계(정본: [docs/spec/admission-generation.md](../spec/admission-generation.md))의 **FREEZE / RECORD** 시점 기록 — AGENTS.md §2.5 단계 1–2 수행. 규범은 스펙 문서가 담고, 본 문서는 2026-10-15 시점의 측정 원문·명령·판독값만 담는다.
> **작성일**: 2026-10-15.
> **작업 환경**: Axiom 저장소 `docs/admission-generation-freeze` 브랜치(HEAD `0a4734457` == origin/main — docs-only PR 본문), 컨트롤러 저장소 `Archright/.github`는 read-only API 판독(`gh api`, classic PAT, org admin — [github_ruleset_api_quirks.md](../spec/github_ruleset_api_quirks.md) 인증 실측 조건과 동일).
> **측정 원칙**: 모든 항목에 실측 명령과 판독값을 병기한다(§0.9 — 극장 아님). [V] 표기 = 본 문서 작성 세션에서 재현·관측된 채널이다.

---

## §1. H₀ 자격 (3다리 — 정본 §3.2의 측정)

| 다리 | 판정 | 근거 (2026-10-15 실측) |
|---|---|---|
| 1. 시간 경계 | **성립** | 컨트롤러 main의 마지막 커밋 = `abe66968dbcb4746f5c79d43341d564422108253` (2026-10-14T16:17:41Z), 이후 커밋 0건, 원격 HEAD와 일치. |
| 2. 실행 증거 | **성립 [V]** | H₀에서 실행된 최후 green merge_group 런 = **38681365187** (created 2026-10-15T04:25:19Z, conclusion success). 재현: `gh api repos/Archright/Axiom/actions/runs/38681365187 --jq '{event, status, conclusion, created_at}'` → `{"event":"merge_group","status":"completed","conclusion":"success","created_at":"2026-10-15T04:25:19Z"}`. |
| 3. 원자 승격 | **성립 [V]** | H₀→H₁ 전이 = PR #218 native merge 단일 커밋 `e968b5c0c20b7c63adaad74a235c31392b6ac497` (2026-10-15T05:59:01Z, pin-promotion-gate pass). 재현: `gh pr view 218 --repo Archright/.github --json state,mergedAt,mergeCommit` → `{"state":"MERGED","mergedAt":"2026-10-15T05:59:01Z","mergeSha":"e968b5c0…"}`. |

---

## §2. 핀 스냅샷 — 전 `uses:` 전수조사 (H₁ 기준 [V])

조립자 2파일을 **각각의 세대 커밋에서 직접 판독**했다(캐시·요약 없음).

```bash
gh api "repos/Archright/.github/contents/.github/workflows/admission-gate.yml?ref=e968b5c0c20b7c63adaad74a235c31392b6ac497" --jq '.content' | base64 -d | grep -n "uses:"
gh api "repos/Archright/.github/contents/.github/workflows/landing-integrity.yml?ref=e968b5c0c20b7c63adaad74a235c31392b6ac497" --jq '.content' | base64 -d | grep -n "uses:"
```

**admission-gate.yml@H₁ — 8참조 (행 번호는 판독 원문)**:

| 행 | `uses:` | 핀 |
|---|---|---|
| :225 | `actions/checkout@11d5960a326750d5838078e36cf38b85af677262` (주석 `# v4`) | 커밋 SHA ✓ |
| :256 | `Archright/Axiom/.github/actions/setup-axiom-toolchain@ba773d0631b5757525b16d8fd62e220492e98e76` | 커밋 SHA ✓ |
| :385 | `actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02` (`# v4`) | 커밋 SHA ✓ |
| :430 | `Archright/Axiom/.github/workflows/admission-check.yml@dc527994c987cad9d7d83f1dc27650d0c15eb63e` | 커밋 SHA ✓ |
| :481 | `Archright/Axiom/.github/workflows/certificate-mint.yml@aa051134359ee37e50bf30bcc58187c58aa6fe3a` | 커밋 SHA ✓ |
| :538 | `Archright/Axiom/.github/workflows/certificate-mint.yml@aa051134359ee37e50bf30bcc58187c58aa6fe3a` | 커밋 SHA ✓ |
| :573 | `Archright/Axiom/.github/workflows/runner-pool-acceptance.yml@ba773d0631b5757525b16d8fd62e220492e98e76` | 커밋 SHA ✓ |
| :650 | `Archright/Axiom/.github/workflows/admission-check.yml@dc527994c987cad9d7d83f1dc27650d0c15eb63e` | 커밋 SHA ✓ |

**landing-integrity.yml@H₁ — 3참조**: `actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1` (`# v7.0.1`) ×3 (:78, :171, :346) — 커밋 SHA ✓.

**피호출 워크플로 3종을 각 핀 SHA에서 판독**(`gh api repos/Archright/Axiom/contents/.github/<file>?ref=<pin>`):

| 파일 @ 핀 | 외부 참조 (전부 커밋 SHA ✓) | `./` 상대 |
|---|---|---|
| admission-check.yml @ `dc527994…` | checkout `11d5960a…` ×3, upload-artifact `ea165f8d…` ×7, download-artifact `d3f86a10…` ×4 | `./.github/actions/setup-axiom-toolchain` ×2 |
| certificate-mint.yml @ `aa0511343…` | checkout `11d5960a…` ×2, upload-artifact `ea165f8d…` ×1 | `./.github/actions/setup-axiom-toolchain` ×2 |
| runner-pool-acceptance.yml @ `ba773d0631…` | checkout `11d5960a…` ×5, upload-artifact `ea165f8d…` ×9, download-artifact `d3f86a10…` ×7 | `./.github/actions/setup-axiom-toolchain` ×4 |

**복합 액션 내부** — `setup-axiom-toolchain/action.yml` @ `ba773d0631…`: `actions/cache/restore@0057852bfaa89a56745cba8c7296529d2fc39830` ×2 (:322, :388) + `actions/cache/save@0057852b…` ×1 (:925) — 커밋 SHA ✓.

**합계 판정**: 외부 참조 전부 커밋 SHA 핀, `./` 상대 8건(같은 커밋 내부 — 구조적 불변), `docker://` **0건**. **uses-graph fully SHA-closed [V]**.

**H₀→H₁ diff (주석 전용 확인 [V])**: `diff` 판독 결과 admission-gate.yml의 변경은 :51-54의 주석 4줄뿐 — 비주석 변경 0줄. H₁ 헤더는 "org ruleset 24233738(axiom-admission-gate)이 이 파일을 ref: main(가변)으로 참조하며, 불변 SHA pin은 Archright/Axiom docs/spec/admission-generation.md의 promotion 절차로 적용한다"로 정화되어 **본 스펙 문서를 promotion 앵커로 지정**한다. H₀의 동일 위치 주석("org ruleset 24041674 … sha pin하며")은 시점에 맞지 않는 허위 서술이었다(24041674는 2026-09-30/10-01 사이 24233738 sha-less ref:main으로 대체됨 — `docs/evidence/epoch_record_oracle_select_2026-09-30.md` §8.3, `docs/evidence/epoch_record_base_artifact_2026-10-01.md` §2.3).

---

## §3. ruleset verbatim 파라미터 (2026-10-15, S4 이전 상태 [V])

```bash
gh api orgs/Archright/rulesets/24233738
gh api orgs/Archright/rulesets/23943917
```

**24233738 `axiom-admission-gate`** (판독값 축약 없음):
```json
{"id":24233738,"name":"axiom-admission-gate","enforcement":"active",
 "conditions":{"ref_name":{"include":["refs/heads/main"],"exclude":[]},
               "repository_name":{"include":["Axiom"],"exclude":[]}},
 "rules":[{"type":"workflows",
           "parameters":{"do_not_enforce_on_create":false,
             "workflows":[{"path":".github/workflows/admission-gate.yml",
                           "repository_id":1182157951,"ref":"main"}]}}]}
```

**23943917 `landing-integrity`** (판독값 축약 없음):
```json
{"id":23943917,"name":"landing-integrity","enforcement":"active",
 "conditions":{"ref_name":{"include":["refs/heads/main"],"exclude":[]},
               "repository_name":{"include":["Axiom"],"exclude":[]}},
 "rules":[{"type":"workflows",
           "parameters":{"do_not_enforce_on_create":false,
             "workflows":[{"path":".github/workflows/landing-integrity.yml",
                           "repository_id":1182157951,"ref":"main"}]}}]}
```

**판정**: 양 ruleset 모두 enforcement active, `sha` 필드 **부재** — `ref: main` 가변 핀이 현행 상태다. 이것이 S4(정본 §5)가 닫을 결함이며, 본 기록은 S4 이전 동결 상태의 증거다. S4 실행 후의 readback은 그 시점 별도 증거 문서로 남는다.

---

## §4. 큐 / in-flight 스냅샷 (동결 시점)

| 항목 | 관측 | 방법 |
|---|---|---|
| in-flight merge_group 런 | **0건 [V]** | `gh api "repos/Archright/Axiom/actions/runs?event=merge_group&status=in_progress" --jq '.total_count'` → `0` |
| 큐 대기 엔트리 채널 | **미제공 (404)** | `gh api repos/Archright/Axiom/branches/main/merge-queue/entries` → HTTP 404 "Branch not found" — 이 토큰/플랜에서 entries 엔드포인트가 제공되지 않는다(관측 그대로 기록 — 추정 채움 금지). |

**판정**: 관측 가능한 in-flight는 0이다. 큐 대기열의 직접 목록 채널 부재는 S4 전환 절차(정본 §5.1 빈 큐 확인)가 **실행 시점 자체 관측**을 다시 수행해야 하는 이유다 — 본 기록은 전환 실행의 사전 조건을 대리 증명하지 않는다.

---

## §5. S2 착지 기록 — PR #218 (H₁ 승격)

| 항목 | 값 |
|---|---|
| PR | Archright/.github **#218** [V] (`gh pr view 218 --repo Archright/.github --json state,mergedAt,mergeCommit` → `MERGED`, 2026-10-15T05:59:01Z, merge commit `e968b5c0c20b7c63adaad74a235c31392b6ac497`, base `main`) |
| 내용 1 — dependabot ignore | `dependabot.yml`에 `ignore:` 4항목 — `Archright/Axiom/.github/workflows/admission-check.yml`, `certificate-mint.yml`, `runner-pool-acceptance.yml`, `actions/setup-axiom-toolchain` |
| 내용 2 — 헤더 정화 | `admission-gate.yml` 주석 전용 truthification(비주석 변경 0줄 — §2 diff 실측) |
| 부수 효과 | dependabot이 회전 대기 PR **#214–#217을 착지 시 자동 폐쇄** |
| 세대 태그 [V] | `git ls-remote --tags https://github.com/Archright/.github.git \| grep admission-gen` → `admission-gen-h0-20261015` → deref `abe66968…`(tag object `880d3be3…`) · `admission-gen-h1-20261015` → deref `e968b5c0…`(tag object `b594562a…`) — annotated, 컨트롤러 원격 존재 확인 |
| 런타임 지문 [V] | 직후 최후 green merge_group 런 38681365187(§1 다리 2)의 `referenced_workflows`가 §6의 핀-트리플과 정확 일치 |

---

## §6. [V] 채널 실측 — 수용 증거 4중 채널의 가용성 (정본 §6의 측정)

| 채널 | 가용성 | 실측 |
|---|---|---|
| **E1** run object `referenced_workflows` | **직접 채널 — 정확한 callee SHA 반환 [V]** | `gh api repos/Archright/Axiom/actions/runs/38681365187 --jq '[.referenced_workflows[] \| {path, sha, ref}]'` → 3항목: `certificate-mint.yml@aa0511343…`, `admission-check.yml@dc527994…`, `runner-pool-acceptance.yml@ba773d0631…` — 각 `sha`가 핀과 정확 일치, `ref`는 전부 `null`. |
| **E2** job 로그 `Uses:` 라인 | **보조 채널 — 실측됨 (당일 프로브)** | 러너가 내보낸 job 로그에 `Uses:` 라인이 존재하고 E1과 동일 SHA를 보인다. 원문은 job 로그 다운로드로 재현 가능(런 38681365187 — merge_group). |
| **E3** 조립자 커밋 직접 채널 | **부재 — 지문 방법으로 대체** | 런 오브젝트에 조립자(컨트롤러) 커밋을 반환하는 필드가 없고, required-workflow 등록 API는 422-deprecated로 직접 등록 조회가 불가하다(당일 프로브). 대체: 핀-트리플 지문 `{dc527994c…, aa0511343…, ba773d0631…}` + 컨트롤러 git-history 시간 경계로 조립자 정체성을 식별한다. |
| **E4** 착지 정체성 (check identity + MERGE 커밋) | **권위 채널** | required check identity(workflow_id + path 이중 결속)와 GitHub native MERGE 커밋 — 관측 계약은 [docs/agents/merge_admission_observation.md](../agents/merge_admission_observation.md), 착지 계약은 [docs/spec/merge_admission_controller.md](../spec/merge_admission_controller.md) §8b. 본 기록의 PR #218 MERGED 판독(§5)이 이 세대의 E4 원문이다. |

**런타임 sha 준수의 한계(정본 §6.1)의 측정적 표현**: E1의 `sha`와 `ref`가 핀 시점에 같은 커밋(`ref`는 `null`로 직렬화되지만 규칙 원문은 `ref: main`)을 가리키므로, 위 E1 판독만으로는 "sha가 ref를 이겼다"를 증명하지 못한다. 입증은 **발산 테스트**(무해 컨트롤러 커밋 착지 후 다음 admission 런의 E1 지문 불변 관측)로만 가능하다 — 정본 §5.7 success 행의 조건이다.

---

## §7. 재현 명령 일람 (read-only)

```bash
# 세대 태그
git ls-remote --tags https://github.com/Archright/.github.git | grep admission-gen
# 조립자 uses 전수 판독 (H₀/H₁ 각각)
gh api "repos/Archright/.github/contents/.github/workflows/admission-gate.yml?ref=<gen>" --jq '.content' | base64 -d | grep -n "uses:"
gh api "repos/Archright/.github/contents/.github/workflows/landing-integrity.yml?ref=<gen>" --jq '.content' | base64 -d | grep -n "uses:"
# 피호출 3종 + 복합 액션 (각 핀)
gh api "repos/Archright/Axiom/contents/.github/workflows/<file>?ref=<pin>" --jq '.content' | base64 -d | grep -n "uses:"
gh api "repos/Archright/Axiom/contents/.github/actions/setup-axiom-toolchain/action.yml?ref=ba773d0631b5757525b16d8fd62e220492e98e76" --jq '.content' | base64 -d | grep -n "uses:"
# ruleset verbatim
gh api orgs/Archright/rulesets/24233738 ; gh api orgs/Archright/rulesets/23943917
# E1 채널
gh api repos/Archright/Axiom/actions/runs/38681365187 --jq '[.referenced_workflows[] | {path, sha, ref}]'
# in-flight
gh api "repos/Archright/Axiom/actions/runs?event=merge_group&status=in_progress" --jq '.total_count'
# S2 착지
gh pr view 218 --repo Archright/.github --json state,mergedAt,mergeCommit,baseRefName
```
