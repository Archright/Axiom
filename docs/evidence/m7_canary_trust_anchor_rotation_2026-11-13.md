# m7 Canary Trust Anchor Rotation — ruleset 26996019→27097366 (2026-11-13)

> **종류**: 실행 증거 기록 (rotation evidence). 목적은 Trust Anchor 상수 회전의 측정 근거·검증 출력·재현 명령을 한 문서에 고정하는 것이다.
> **권위**: 본 문서는 기록이며 어떤 판정도 대체하지 않는다. 착지 판정 권위는 GitHub ruleset·required checks·merge queue다(`Authority ≠ Adapter`, AGENTS.md §2.3).
> **브랜치**: `chore/canary-ruleset-anchor-rotation` (base `main` `d01e00d`).
> **결정 바인딩**: `config/policy/merge_admission.json` v1.19.0 조항 — m7 canary guard는 **의도적으로 동적 해석에서 면제**된다(`PROD_RULESET_ID`는 Trust Anchor 상수; canary는 런타임에 자신의 보호 대상을 발견해서는 안 된다). 회전 관례 선례: 20303214→26702792(v1.19.0) · 26702792→26996019(v1.21.0, E10 rotation lane PR #4 — lane 3파일: policy json + script + E10 문서).

---

## 1. 드리프트 증상 (measured)

`tools/ci/m7_canary_drill.sh`의 prod guard verification 단계(`GET $BASE_URL/rulesets/$PROD_RULESET_ID`, script :214)가 구 앵커 **26996019**에 대해 **HTTP 404**를 받는다 — ruleset이 2026-11-12에 재생성되어 id가 교체됐기 때문이다. 가드 계약상 fetch 실패는 UNKNOWN(exit 3, fail-closed; script :227-231)이므로 m7 canary는 더 이상 drill을 수행할 수 없다.

실측(2026-11-13, `gh api`):

```
$ gh api /repos/Archright/Axiom/rulesets/26996019
{"message":"Not Found","documentation_url":"https://docs.github.com/rest/repos/rules#get-a-repository-ruleset","status":"404"}gh: Not Found (HTTP 404)
```

## 2. Live ruleset readback (전수 6종)

`gh api "/repos/Archright/Axiom/rulesets?per_page=100"` (2026-11-13 실측):

| id | name | source | enforcement | created_at | updated_at |
|---|---|---|---|---|---|
| 25218071 | axiom-admission-gate | Archright (org-level) | active | 2026-10-16T13:51:13.748+09:00 | 2026-11-12T19:23:49.443+09:00 |
| 23943917 | landing-integrity | Archright (org-level) | active | 2026-09-24T23:30:36.075+09:00 | 2026-11-12T19:23:50.637+09:00 |
| **27097366** | **main** | Archright/Axiom (repo-level) | **active** | 2026-11-12T16:10:00.467+09:00 | 2026-11-12T19:20:26.599+09:00 |
| 27097369 | cas-probe-scratch | Archright/Axiom (repo-level) | active | 2026-11-12T16:10:01.459+09:00 | 2026-11-12T16:10:01.666+09:00 |
| 27097390 | execution-surface-create | Archright/Axiom (repo-level) | disabled | 2026-11-12T16:10:29.286+09:00 | 2026-11-12T18:16:26.534+09:00 |
| 27097391 | artifact-hygiene | Archright/Axiom (repo-level) | disabled | 2026-11-12T16:10:30.393+09:00 | 2026-11-12T18:16:26.333+09:00 |

신규 앵커 27097366 상세 — 스크립트 가드가 검증하는 정확한 술어(script :216-:221)와의 대조:

| guard 조건 | 실측값 | 판정 |
|---|---|---|
| `name == "main"` | **main** | PASS |
| `enforcement == "active"` | **active** | PASS |
| required_status_checks 비어있지 않음 | **6 contexts** — admission-check·bsec-integrity·debt-registry-gate·generation-acceptance·axiom-operational-slice·publication-integrity (전부 integration_id 15368) | PASS |
| merge_queue `merge_method == "MERGE"` | **MERGE** | PASS |

→ 보호 전제(premise) 성립 — 회전 후 가드가 200+정합을 관측할 것의 측정 근거.

## 3. 2026-11-12 ruleset 재생성의 문서화 여부 (정직 기록)

- 저장소 전수 검색(`grep -rn 27097366 docs/ config/ tools/ src/ tests/ data/ .github/`): 재생성 **사건 자체를 기록한 문서는 없다**. 신규 id 27097366는 오직 두 2026-11-13 수용 증거 문서의 권위 헤더에 **사후 인용**으로만 등장한다(`vs_r1_c1_optimization_acceptance_2026-11-13.md:4` · `vs_r2_authority_followups_acceptance_2026-11-13.md:4` — 착지 판정 권위 열거). `docs/history/`는 0건(exit 1).
- 재생성의 **주체·경위·의도는 UNKNOWN** — 본 문서는 측정 사실(created_at 2026-11-12T16:10:00.467+09:00 · enforcement active · 구 id 404)만 기록하며 이유를 지어내지 않는다. E10(2026-11-11)이 기록한 4종 재생성(26996019/26996021/26996020/26996023, Phase 4 readback)과는 별개의, 문서화되지 않은 후속 재생성이다.
- 구 E10 id의 **live 운영 미러는 `m7_canary_drill.sh:71` 하나뿐**이다. 26996020·26996021·26996023는 dated history(E10)에만 존재한다(불변). `config/policy/merge_admission.json`의 26996019 언급은 v1.21.0 changelog(불변 역사 기록)이며, live fetcher(GPA L2 · `tools/merge_ruleset_drift_monitor.nim` · `tools/ci/landing_observe.sh`)는 v1.19.0 이후 **이름 해석**이라 이번 재생성에 무영향이다.

## 4. 회전 (rotation)

| 항목 | 값 |
|---|---|
| 변경 | `tools/ci/m7_canary_drill.sh:71` `PROD_RULESET_ID="26996019"` → `"27097366"` — **1행** |
| 방식 | 문서화된 상수-회전 관례(v1.19.0: 20303214→26702792 · v1.21.0/E10: 26702792→26996019) — 이름 기반 동적 해석으로의 전환 **아님**(설계 제약, §결정 바인딩) |
| lane | 2파일 — script + 본 문서 (E10 lane의 policy json은 v1.21.0 이후 불필요: merge_admission.json의 26996019 언급은 불변 changelog이며 live 바인딩이 아님) |
| 무변경 | guard 검증 술어(:216-:221) · ruleset PUT 거부(:265-:268) · default-base 거부(:200-:203) · 판정 어휘(M6) · exit 코드 매핑 — 전부 원문 그대로. 헤더 주석의 26702792/20303214 언급은 v1.19.0/v1.21.0 역사 서술로 보존한다(E10 회전이 상수만 교체한 것과 동일한 최소 diff) |

## 5. 검증 (2026-11-13, 워크트리 `/tmp/axiom-wt-canary`)

| 검증 | 명령 | 출력/관측 | 판정 |
|---|---|---|---|
| 문법 | `bash -n tools/ci/m7_canary_drill.sh` | exit 0 | PASS |
| dry-run(무네트워크 안전 모드) | `bash tools/ci/m7_canary_drill.sh --canary-pr 1 --repo Archright/Axiom --dry-run` | plan이 `GET …/rulesets/27097366 (prod guard verification — the Trust Anchor must BE the live surface: name=main ∧ active ∧ required checks ∧ merge_queue MERGE)` + `[dry-run] guards: production ruleset 27097366 refused` 출력 → `[dry-run] PASS — plan well-formed`, exit 0 | PASS |
| 가드 전제 실측 | `gh api /repos/Archright/Axiom/rulesets/27097366 --jq '{name, enforcement, required_checks_count, contexts, merge_method}'` | `{"contexts":[admission-check, bsec-integrity, debt-registry-gate, generation-acceptance, axiom-operational-slice, publication-integrity],"enforcement":"active","merge_method":"MERGE","name":"main","required_checks_count":6}` — §2 표의 4조건 전부 성립 | PASS |
| 구 앵커 소멸 확인 | `gh api /repos/Archright/Axiom/rulesets/26996019` | HTTP 404 | 관측됨(§1 드리프트 원인 확정) |
| 자격 증명 가드 불변 | `env -u AXIOM_DIAG_TOKEN bash tools/ci/m7_canary_drill.sh --canary-pr 1 --repo Archright/Axiom` | `m7_canary_drill: FAIL — AXIOM_DIAG_TOKEN absent. … gh auth / GITHUB_TOKEN fallbacks are structurally absent`, exit 2 | PASS(fail-closed 유지) |

**정직 기록(가드 실행 경계)**: 스크립트 내부의 live 가드 단계(GET 200 → 4조건 판정 → drill 계속)는 in-job minted `AXIOM_DIAG_TOKEN`을 요구한다(헤더 계약: gh-auth 폴백의 구조적 부재). 로컬 검증은 (a) dry-run 플랜 (b) 가드와 **동일 술어·동일 엔드포인트**의 live readback(`gh api`) (c) 자격 증명 가드 fail-closed 관측으로 구성했다. 본 회전 후 첫 라이브 drill은 `.github/workflows/diagnostic-authority.yml`(run_canary=true)의 다음 실행에서 수행된다 — 그 관측은 본 문서 범위 밖(후속 기록).

## 6. 외부 문서 근거 (official docs — AGENTS.md §0.5)

- GitHub REST "Repo rulesets" (docs.github.com/en/rest/repos/rules, Context7 `/websites/github_en_rest` 조회 2026-11-13): `POST /repos/{owner}/{repo}/rulesets`는 새 ruleset을 생성하고 응답의 `id`(Unique identifier of the ruleset)는 **플랫폼이 부여**한다 — 요청 본문에 id 필드가 없으므로 삭제 후 재생성은 필연적으로 새 id를 낸다. `GET /repos/{owner}/{repo}/rulesets`는 "rulesets configured at higher levels that apply to this repository"(`includes_parents` 기본 true)까지 반환하며 org-level(`source_type: Organization`, `source: "Archright"`)과 repo-level(`source_type: Repository`, `source: "Archright/Axiom"`)이 `source` 필드로 구분된다 — §2 readback의 6종 구성과 정합.
- 재생성으로 id가 바뀌어도 **이름("main")·구성(6 contexts × integration_id 15368 · merge_queue MERGE)은 동일**하게 재구성됐음이 실측되었다(§2) — v1.19.0/v1.21.0 이후 이름 해석 fetcher가 무영향인 이유.

## 7. 후속 (out of scope)

- 27097390·27097391이 disabled인 것은 측정 사실로만 기록한다(활성화 여부 판단은 운영자 소관).
- `.github/workflows/diagnostic-authority.yml:185` 주석의 26702792 언급은 historical 주석이다(워크플로 파일은 본 lane 무변경 — 본 rotation lane은 script + 본 문서 2파일).
- 다음 diagnostic-authority canary drill run이 새 앵커로 가드 통과를 실측하면 그 기록이 본 회전의 운영 수용을 완결한다.
