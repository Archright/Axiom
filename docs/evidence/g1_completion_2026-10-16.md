# G1 완결 기록 (Completion Record) — 2026-10-16

> **성격**: G1(이벤트 전달 사망 → 경로 리네임 복구) 슬라이스의 **종결 레코드**다. 구성 실험 문서 — [g1_cache_supply_experiment_2026-10-16.md](g1_cache_supply_experiment_2026-10-16.md)(PUT 단계), [g1_leverA_create_experiment_2026-10-16.md](g1_leverA_create_experiment_2026-10-16.md)(DELETE+CREATE 단계), [g1_leverB_path_rename_2026-10-16.md](g1_leverB_path_rename_2026-10-16.md)(경로 리네임 단계), [g1_leverB_final_observation_2026-10-16.md](g1_leverB_final_observation_2026-10-16.md)(갱신 가드 첫 발행 관측), [g1_support_ticket_package_2026-10-16.md](g1_support_ticket_package_2026-10-16.md)(지원 티켓 패키지) — 의 판정을 한 곳에 모아 **여정·근원 판정·해소 사슬·잔여**를 확정한다. 본 문서가 개별 실험 문서를 대체하지 않는다(측정 원문은 각 문서에 유지).
> **실측 시점**: 본 문서의 GitHub API 라이브 재검증값은 2026-10-16T09:1x–09:3xZ 판독이다(런 ID·시각·merge commit 전부 재판독).
> **롤백 앵커**: 각 단계 문서의 기준 스냅샷(이동하는 main이 아님).

## 1. 여정 요약

| 단계 | 내용 | 판정 |
|---|---|---|
| **사망** (2026-10-12T12:41:49Z) | org ruleset 24233738의 enforcement `active→evaluate→active` 사이클(12:25:32Z→12:41:49Z, 16분 17초 — 문서화된 긴급 정비 창) 직후, `admission-gate` 완결의 `workflow_run` 이벤트 전달 사망. 첫 미전달 완결 = 게이트 런 **38249840104**(12:42:52Z — 재-active 63초 뒤). 초기 추산 **160+** 누적; 전수 스캔으로 **239건(176 성공)** 측정(10-16T05:00Z 기준, 지원 패키지 §4.3). 게이트 자체는 정상 실행·필수 체크 강제 유지 — **순수 이벤트 전달 결함** | 전달 사망 |
| **조사** | 정체성 조사(agent-t1lqj0kj): 가설 3건(H-A 레거시 고아·H-B 레지스트리 부재 대칭·H-C) **전부 반박** — 최선 설명은 10/12 evaluate 토글 창에서 **(repository_id + path) 단위 required-workflow 이벤트 바인딩 사멸**(플랫폼 측), 8+회 PUT 무효. 소비자 측 반쪽(이름 필터 무음 미일치)은 PR **#846**(10-15T13:22Z)의 퍼미시브 glob + 인잡 path 가드 프루브로 우회 | 가설 반박 + **evaluate-창 상관** 식별 |
| **PUT 실험** | 1단 멱등 PUT(readback diff 빈 파일·updated_at 무갱신 = 서버 완전 no-op) + 2단 룰 제거→재등록(11초 detach/attach 창, mq 동결 하) — **양단 무발화**. post-stage-2 게이트 완결 3건 전수(38844756746·38846646087·38847179520) admission-gate 바인딩 0. 양성 대조: observation.yml 완결 03:50:32Z → publisher 런 38847525643 **+2초** — 발화 회로 자체는 생존 | **NO FIRE** |
| **Lever-A (DELETE+CREATE)** | 04:50–04:52Z 창: ruleset 24233738 DELETE → verbatim POST → **신규 id 25218071**, 본문 diff 공란(완전 동일 명세). 관측차량 PR #875 게이트 완결 05:28:02Z 후 admission-gate 바인딩 0 | **NO FIRE** |
| **Lever-B (경로 리네임)** | `admission-gate.yml` → `admission-gate-v2.yml` (컨트롤러 PR #226 — R100 바이트 동일, `name: admission-gate` 유지) + ruleset 25218071 path·sha 재핀(h6) + 선행 PR #877(오케스트레이터 런 정체성 검증 v2 경로 리타겟). **MG 게이트 완결 07:46:58Z → +2초 뒤 publisher 런 38869397558 생성(07:47:00Z)** — 가드 로그가 트리거 런 path를 `admission-gate-v2.yml`로 귀속 = **이벤트가 신규 등록 객체에 도달** | **FIRE** |

## 2. 근원 판정 (Root Cause Determination)

**결함의 소재는 ruleset 바인딩이 아니라 대상 리포지터리의 워크플로 객체 정체성**(구 객체 **367727531**, `.github/workflows/admission-gate.yml`)의 발화 측 상태였다. 4개 등록-표면(registration-surface) 레버가 이를 교차 확인했다:

| 레버 | 조작 층 | 결과 |
|---|---|---|
| 멱등 PUT | ruleset (24233738) | 무발화 — 서버 완전 no-op |
| 룰 제거→재등록 | ruleset (24233738) | 무발화 — 새 updated_at 발급에도 |
| ruleset DELETE+CREATE | ruleset (24233738 → 25218071, 동일 명세) | 무발화 |
| **파일 경로 리네임** | **워크플로 등록 자체** (yml 경로 → v2 = 진짜 NEW 등록 강제) | **FIRE** |

- ruleset 수준 조작 3종 전부 실패 + 경로 변경(유일하게 새 워크플로 등록을 강제하는 조작)만 성공 → 바인딩 키 `(repository_id, path)` 중 **path가 바뀌는 순간만 고착 정체성과 구조적으로 충돌 불가**.
- 신규 등록의 직접 증거: PR-이벤트 런 **38866640608**의 **run_number=1**(워크플로 id **386419787**) — 러너 넘버가 1부터 재시작.
- 유의(비대칭의 정확한 위치): 구·신 양 객체 모두 대상 리포의 Actions 워크플로 레지스트리에 부재(404)다. 구 객체는 **런 생성·실행은 정상이면서 이벤트 발화 측만 사망**했고, 신 객체는 발화까지 정상 — 레지스트리 부재 자체가 결함이 아니라 **객체 정체성의 발화 측 상태**가 결함이었다.
- **evaluate-창 상관은 여전히 가장 강한 가설**이다: 사망 순간이 evaluate→active 전환 63초 뒤라는 상관과 "모든 UPDATE 계열 무효·CREATE(신규 등록)만 유효"라는 실험 패턴은 정합한다. 그러나 **상관 ≠ 인과** — 근원 인과 주장은 GitHub 측 확인(지원 티켓)을 필요로 하며, 본 기록은 이를 미증명 가설로 유지한다.

## 3. 해소 증거 사슬 (Resolution Evidence Chain)

| # | 단계 | 커밋/런 | 시각 (UTC) |
|---|---|---|---|
| 1 | **PR #877** (Axiom) — certificate-mint 오케스트레이터 런 정체성 검증 리타겟(r_path 3곳 step 0/1/P0 + `GATE_PATH` 상수 step 2a → v2, 결합 주석 4곳) | MERGE `9aaee76f09748837ecf0c04779b8d2bdbc9a71c3` | 06:53:12Z |
| 2 | **PR #226** (Archright/.github) — `git mv` admission-gate.yml → admission-gate-v2.yml(R100 바이트 동일·이름 유지) + certificate-mint 핀 7072f9382→9aaee76f(2곳) | MERGE = **H_v2 `5bfc911448a56d3e600aa06552291fb405898a46`** | 06:56:09Z |
| 3 | **ruleset 재핀 (h6)** — 25218071(org 소유 → `/orgs/` 엔드포인트): path → v2 + sha → H_v2, 빈-큐 창·mq 동결(2→0→2, ~2분). 태그 `admission-gen-h6-20261016`. readback `{path: .github/workflows/admission-gate-v2.yml, repository_id: 1182157951, sha: 5bfc9114…}` — **본 기록 작성 시점 라이브 재판독으로 동일 상태 확인**(enforcement active) | ruleset PUT | 10-16 (h6 창) |
| 4 | **PR #881** (Axiom) — publisher path 가드 v2(guard가 `admission-gate-v2.yml` 추적) | MERGE `0fe0697d387c3b9ba2a3e88a4862a50eed9426e0` | 08:23:16Z |
| 5 | **PR #882** (Axiom) — 갱신 가드 첫 발행 관측 차량(docs) | MERGE `fa46147d77d2b25eb4a3ccdf085d95a48a0a5608` | 08:50:38Z |
| 6 | **publisher 런 38876343879** — event=`workflow_run`, conclusion=success. 트리거 게이트 = MG 런 **38874492382**(pr-882, success — run updated_at 08:50:11Z, 필수 체크 잡 admission-check 완결 08:50:10Z) → **publisher 생성 08:50:13Z(+2초)**. 가드 로그: **path 게이트 PASS**(트리거 런 path가 `admission-gate-v2.yml`로 해석·통과 — path-gate skip 라인 런타임 미발행, 후속 단계 실행), skip 사유 = `[publish-skip] ci-bootstrap-artifacts absent (mode=none gate — nothing built, nothing to publish; residuals R6)` = **docs 전용 PR의 정상 mode=none 동작** | 런 38876343879 | 08:50:13Z |

### 3.1 발화 전수 (admission-gate-v2 등록 이후 — 6런 전부 success, 라이브 전수 스캔)

| 런 | 이벤트 | 완결 (UTC) | 비고 |
|---|---|---|---|
| 38866640608 | pull_request (#880 차량) | 07:30:42Z | **run_number=1**, workflow_id 386419787 — 신규 등록 직접 증거 |
| 38867729895 | merge_group (pr-880) | 07:46:58Z | **FIRE 순간**: +2초 뒤 publisher 38869397558(07:47:00Z) — 가드가 런 path=v2 귀속(구경로 하드코딩 skip — 사전 예고된 1차 발견). #880 무인 착지 07:47:23Z |
| 38870782878 | pull_request (#881 차량) | 08:05:22Z | +3초 뒤 publisher 38871366061(08:05:25Z) — v2 바인딩 실증(구 가드 skip) |
| 38871419937 | merge_group (pr-881) | 08:22:52Z | #881 착지 08:23:16Z — 이후 완결부터 갱신 가드(v2) 적용 |
| 38873841509 | pull_request (#882 차량) | 08:32:43Z | — |
| 38874492382 | merge_group (pr-882) | 08:50:11Z | 위 표 #6 — **갱신 가드 path PASS + mode=none skip**(docs PR 정상) |

`workflow_run` 이벤트 전달은 신규 등록 객체에서 **완전 복원**됐다 — 6회 게이트 완결 각각에 publisher 발화(또는 정상 mode=none skip)가 +2~3초 내 관측됐다.

## 4. S3 상태 (캐시 공급·재사용)

**S3(공급 → 후속 재사용)의 실측은 다음 코드 변경 PR에서 자동 성립한다.** docs PR은 게이트가 아무것도 빌드하지 않는 mode=none으로 올바르게 스킵된다(위 §3 런 38876343879의 skip 사유가 그 증거). 다음 코드 변경 PR의 게이트 완결 시 publisher가 실제 공급(publish 잡 실수행)을 수행하고, 후속 게이트가 동일 키를 restore(재사용)하는 것이 관측될 것이다 — **수동 절차가 아니라 자동**이다. 메뉴얼 개입 요구는 없다.

## 5. 지원 티켓 (Support Ticket)

- 증거 패키지 착지: **PR #874**(MERGE `df535f6e55cd6621ad17039a291e41d498420b0d`, 05:13:22Z) → [g1_support_ticket_package_2026-10-16.md](g1_support_ticket_package_2026-10-16.md).
- 패키지는 자가 완결형이다: A/B 재현(동일 리포지터리·동일 sha 핀의 구조적 쌍둥이 ruleset에서 **landing-integrity는 전달 정상**(46회 바인딩 관측)·**admission-gate는 0회**) + 전 재현 명령(`gh api` 판독형) + 239건 누적 측정 + 16회 PUT 이력(GitHub 자체 ruleset history가 감사 추적으로 존재).
- **티켓 제기는 인간(사용자) 행동이며 패키지는 준비 완료**다. GitHub 측 확인이 있어야 evaluate-창 인과 가설이 근원 판정으로 승격된다(§2).

## 6. 레버 분류학 (Lever Taxonomy — 향후 참조)

required-workflow 이벤트 바인딩 사멸 시 등록-표면 레버의 효과 분류:

| 레버 | 조작 | 효과 |
|---|---|---|
| PUT | 멱등 재등록 / sha 회전 / 룰 제거→재등록 포함 | **무효** — (repository_id, path) 키가 재사용되어 고착 정체성과 충돌 |
| ruleset DELETE+CREATE | 신규 ruleset id 발급(동일 path) | **무효** — 새 바인딩이 **같은 path로** 기존 객체 정체성에 재부착 시도 → 충돌 |
| **워크플로 파일 경로 리네임** | yml 경로 변경 + ruleset path 필드 갱신 | **유효** — 진짜 NEW 등록을 강제. 바인딩 키가 `(repository_id, path)`이므로 **경로 변경은 고착된 정체성과 충돌이 구조적으로 불가능한 유일한 조작**이다 |

**불변식으로 기록**: 바인딩 키 = `(repository_id, path)`. ruleset 층의 모든 조작은 키의 path 성분을 보존하므로(= 충돌 재시도) 회복력이 없다; path 성분을 바꾸는 것만이 새 키를 발급한다.

## 7. 종결 판정 및 잔여

- **G1 종결**: 이벤트 전달 복원(FIRE 전수 관측) + publisher 사슬 정상화(가드 v2 path PASS, mode=none 정상 skip) — **완료**.
- **잔여 (자동)**: S3 공급·재사용 실측 — 다음 코드 변경 PR에서 자동 성립(§4). 수동 개입 없음.
- **잔여 (인간)**: GitHub 지원 티켓 제기 — 패키지 준비 완료(§5). 티켓 결과에 따라 evaluate-창 인과 가설 승격/유지.
- **잔여 (위임)**: `admission-check.yml` 내 비기능 문서 주석 1곳(구경로 참조) — admission-check blob sha 변동을 수반하므로 다음 epoch 승격 주기에 정리(Lever-B 문서의 사전 기록 유지). `certificate-mint.yml` 역사 실측 주석(367694978 ≠ 367727531)은 역사 기록으로 보존.

## 8. 재현 명령 (판독 전용)

```bash
# ruleset 현재 상태 (path=v2 · sha=H_v2)
gh api orgs/Archright/rulesets/25218071 --jq '{enforcement, w: .rules[0].parameters.workflows[0]}'
# → {"enforcement":"active","w":{"path":".github/workflows/admission-gate-v2.yml","repository_id":1182157951,"sha":"5bfc911448a56d3e600aa06552291fb405898a46"}}

# 해소 사슬 머지 커밋
gh pr view 877 --repo Archright/Axiom --json mergeCommit,mergedAt
gh pr view 226 --repo Archright/.github --json mergeCommit,mergedAt
gh pr view 881 --repo Archright/Axiom --json mergeCommit,mergedAt
gh pr view 882 --repo Archright/Axiom --json mergeCommit,mergedAt   # → fa46147d77d2…

# FIRE: 게이트 완결 → publisher +2초
gh api repos/Archright/Axiom/actions/runs/38874492382 --jq '{path,event,updated_at,conclusion}'
gh api repos/Archright/Axiom/actions/runs/38876343879 --jq '{name,event,created_at,conclusion}'

# 가드 로그: path 게이트 PASS + mode=none skip 사유 원문
gh api repos/Archright/Axiom/actions/runs/38876343879/logs > /tmp/pub.zip && unzip -p /tmp/pub.zip \
  | grep -a "^\[publish-skip\]"
# → [publish-skip] ci-bootstrap-artifacts absent (mode=none gate — nothing built, nothing to publish; residuals R6)
```
