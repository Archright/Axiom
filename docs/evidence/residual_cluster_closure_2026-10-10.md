# 잔류 정리 클러스터 처분 기록 — #663/#664 · org admission-gate blob · branch.main 다중값

- **Date**: 2026-10-10
- **Scope**: 문서 전용(추적 대상 소스 무변경). 3항목: (1) 음성 실측 PR #663/#664 처분, (2) org admission-gate blob ↔ ruleset 워크플로 핀 대응 확인, (3) Axiom3 clone `branch.main` 다중값 경고 정정(로컬 git config — tracked 파일 무변경).
- **관측 시점**: 2026-10-10 (모든 GitHub 값은 `gh api` live 응답; git 값은 로컬 clone 실측)

---

## §1. PR #663/#664 처분 — **CLOSE** (판정 근거 포함)

### 1.1 대상

| PR | 제목 | 성격 |
|---|---|---|
| #663 | test(S3-2): NO_CERT negative — in-scope target without vault certificate | 음성 실측 브랜치, "절대 병합 금지" |
| #664 | test(S3-3): SUBJECT_MISMATCH negative — tampered vault cert irHash | 음성 실측 브랜치, "절대 병합 금지" |

양 PR 본문 명시: manifest@H는 `c14243cd…` 바인딩 유지, Pass 2.96b 음성 경로 기대, "자동 탈락 정상".

### 1.2 정본 캡처 — 이미 존재하며 원문 검증됨 (재관측 불요)

두 PR은 merge queue 진입 → `admission-gate`(merge_group)에서 기대 음성 판정으로 자동 탈락했다. 판정 JSON은 런 로그에 원문으로 영속 캡처되어 있다(2026-10-10 잡 로그 직접 다운로드로 원문 대조 완료):

- **run 37966661077** (2026-10-09T17:29:41Z, `merge_group`, `gh-readonly-queue/main/pr-663-88b52abe…`, conclusion **failure**) — `verdict / admission-check` 잡 로그:
  `{"prNumber":663, ..., "verdict":{"result":"mergeAborted","reasonCode":"NO_CERT","reason":"Pass 2.96b: no vault certificate for in-scope kernel symbol src/core/orchestrator/orchestrator_api.nim::normalizeMaxWorkers (manifest irHash c14243cdc6d5 — proof-required admission requires one (re-attest)"}, ...}`
- **run 37969124445** (2026-10-09T17:50:42Z, `merge_group`, `gh-readonly-queue/main/pr-664-999327ab…`, conclusion **failure**) — 동일 잡 로그:
  `{"prNumber":664, ..., "verdict":{"result":"mergeAborted","reasonCode":"SUBJECT_MISMATCH","reason":"Pass 2.96b: vault certificate identity mismatch for src/core/orchestrator/orchestrator_api.nim::normalizeMaxWorkers — content irHash != manifest irHash c14243cdc6d5 ..."}, ...}`

양 런 모두 최종 `admission-check` 잡에서 fail-closed("Every needed job must be success (skipped -> FAILURE, never green)")로 큐 탈락 — 반대경로(no-cert·subject-mismatch) CI 행이 기대대로 확정됐다.

### 1.3 처분 판정: CLOSE — 유지(canary 보존) 기각 근거

1. **캡처 완결**: §1.2의 정식 verdict JSON(reasonCode 포함, prNumber 결속)이 런 로그에 원문 존재. 음성 경로의 관측 목적은 소진됐다.
2. **결정론 경로·독립 커버**: NO_CERT/SUBJECT_MISMATCH는 `merge_cli` Pass 2.96b의 결정론 분기이며 유닛 회귀로 고정돼 있다(`cert_ledger_fact_minimization_acceptance_2026-10-06.md`: test_merge_cli 65/65 — NO_CERT/SUBJECT_MISMATCH/POLICY·SCOPE/CERT_INVALID fail-closed 전부 green). 병합된 epoch gate(#669, 2026-10-09)는 #663 실측을 authority 입증 근거로 인용하며 자체 5행 기계 검증(T1–T5)을 갖는다.
3. **병렬 canary 수요 부재 (2026-10-10 실측)**: open 이슈 0건; open PR은 #657/#652/#650/#628/#627(docs-evidence)과 #663/#664 자신뿐. 활성 trust-root 재베이스 워크스트림(S0'–S4', #670/#671/#673/#674 머지 완료)은 음성 canary로 **자체 픽스처**(C1 fence-note 문서, C2 `src/cli/version.nim` 주석 프로브, 기대 `ROT_NEW_PIN`)를 정의해 #663/#664를 재사용하지 않는다. 또한 §2에서 org pairing(blob ↔ ruleset 핀)이 **오늘 일치**로 확인됐다 — "org pairing 수정 후 재사용"의 전제(수정 필요성)가 현재 성립하지 않는다.
4. **상시 비용**: 병합 금지 PR의 잔류는 PR 목록 오염과 재큐 진입 시 CI 소모만 남는다.

단, **브랜치는 보존된다**(close ≠ branch 삭제). 향후 인증서 흐름 회전 시 음성 경로 재관측이 필요해지면 의도적 재지정(re-point + 재바인딩)으로 부활 가능하며, 그 경우 새 관측이다 — 본 캡처의 재관측이 아니다.

---

## §2. org admission-gate blob ↔ ruleset 워크플로 핀 대응 — **일치 (확인 보고, debt 불요)**

jq 파싱 체인(2026-10-10, `gh api`):

```text
/orgs/Archright/rulesets/24233738                      → name: axiom-admission-gate, enforcement: active
  .rules[] | select(.type=="workflows") | .parameters  → {path: ".github/workflows/admission-gate.yml",
                                                          ref: "main", repository_id: 1182157951}
/repositories/1182157951                               → full_name: Archright/.github (default main)
/repositories/1182157951/contents/.github/workflows/
  admission-gate.yml?ref=main                          → sha: 786e809bb51a8b03901c063a34658dbb1535e40c
                                                          size: 37684
```

- **대응 판정**: ruleset 핀(path + ref + repository_id)의 해석 결과가 보고된 org admission-gate blob `786e809bb`(37,684B)와 **정확히 일치** — SHA-1 blob `786e809bb51a8b03901c063a34658dbb1535e40c`, 37,684바이트.
- **실행 경로 일치**: 실제 merge_group 런(§1.2 양 런)의 workflow path가 `.github/workflows/admission-gate.yml`로 핀 경로와 동일. Axiom 저장소 자체에는 `admission-gate.yml`이 없음(`git ls-files` 실측 — org 중앙 소스 단일성 확인).
- **역사 정합**: 10-04 handoff 기록(`org_gate_handoff_2026-10-04.md`) 시점 blob은 `14b26ba3`(16,812B, 255행) — 이후 org 측 회전이 있었으나 핀이 **ref 기반**(`ref: main`)이라 저장소 측 조치 없이 자동 추종한다. 이는 drift가 아니라 설계된 대응이다.
- **판정**: 불일치 요인 없음 → debt 등록 **하지 않음**(일치 상황의 debt 등록은 극장이 된다). 본 절을 확인 보고로 대신한다.

---

## §3. Axiom3 clone `branch.main` 다중값 경고 — **정정 완료 (로컬 git config, tracked 무변경)**

### 3.1 사전 실측 (원인)

`.git/config`에 `[branch "main"]` 섹션이 **2개** 존재:

```text
git config --local --get-all branch.main.remote → origin, origin            (2개)
git config --local --get-all branch.main.merge  → refs/heads/main,
                                                  refs/heads/chore/final-hetzner-line-edits,
                                                  refs/heads/main, refs/heads/main, refs/heads/main  (5개)
grep -c '^\[branch "main"\]' .git/config         → 2
```

- **원인 기전**(공식 문서 대조 — git-scm `git-config`, Context7 경유 2026-10-10): 다중값 키에서 `get`은 "emits the last value", `set`은 "refuses to write multi-valued config options" 기본, `--append`만 무조건 추가, `--all`만 전체 대체. 섹션 중복이 한번 생긴 뒤 set-upstream 류 쓰기가 모호성 아래에서 append로 동작한 누적 패턴과 일치(첫 값 `refs/heads/main`은 최초 섹션, 두 번째 섹션 선두 `refs/heads/chore/final-hetzner-line-edits`는 과거 upstream 지정 흔적).
- **유효 의미는 무손상**: 마지막 값 규칙으로 upstream 해석은 `origin/main`으로 정상(`git rev-parse --abbrev-ref main@{upstream}` → origin/main, `git status -sb` → `## main...origin/main`). 결함은 모호성·경고이지 추적 드리프트가 아니다.

### 3.2 수리 (git 2.43.0, 옵션형)

```text
git config --local --remove-section branch.main   # 중복 섹션 전체 제거
git config --local branch.main.remote origin
git config --local branch.main.merge refs/heads/main
```

(비고: 최초 시도한 서브커맨드형 `git config --local remove-section …`은 git 2.43에서 "key does not contain a section" 오류로 미반영 — 옵션형 `--remove-section`으로 성공. 변경 없는 실패였음을 사후 상태 동일로 확인.)

### 3.3 사후 실측

```text
--get-all branch.main.remote → origin            (1개)
--get-all branch.main.merge  → refs/heads/main   (1개)
[branch "main"] 섹션 수       → 1
upstream                     → origin/main
```

**재발 방지 트리거 재시험**: 수리 후 `git branch --set-upstream-to=origin/main main` 재적용 → 값 **대체** 확인(여전히 각 1개, 섹션 1) — 경고 0건, 누적 재발 없음. 누적을 유발하던 동일 연산이 이제 안전하다.

---

## §4. 기계 검증 색인

| # | 검증 | 방법 | 결과 |
|---|---|---|---|
| V1 | 음성 판정 원문 캡처 | 잡 로그 다운로드(`actions/jobs/*/logs`) 후 grep | NO_CERT(prNumber 663)·SUBJECT_MISMATCH(prNumber 664) verdict JSON 원문 확인 |
| V2 | ruleset 핀 해석 | `gh api` 3단계 + jq | blob `786e809bb51a8b0…`·37,684B 일치 |
| V3 | Axiom 측 admission-gate 부재 | `git ls-files \| grep admission-gate` | 0건(org 소스 단일성) |
| V4 | config 수리 | `--get-all`·`grep -c`·set-upstream 재시험 | 다중값 2·5 → 1·1, 섹션 2 → 1, 재발 없음 |
| V5 | 병렬 canary 수요 부재 | `gh issue list`(0건)·`gh pr list`(open 7건 전수)·머지 PR 제목 전수 | 재사용 계획 없음 — §1.3-3 |
