# CI Epoch Record — publisher lane identity 게이트 재범위화 (R10 재판정): Freeze / Record / Tombstone

> **성격**: AGENTS.md §2.5(CI Epoch Cutover Protocol) 단계 1–3 — **FREEZE / RECORD / TOMBSTONE** 기록 문서. 변경 = `.github/workflows/ci-cache-publisher.yml` lane verify 게이트를 executed-subject identity로 재범위화 (ahead-invariant freshness 판정 제거).
> **작성일**: 2026-10-08.
> **작업 브랜치**: `workstream/ci-memo-reanchor-slice1`.
> **결정 바인딩**: `docs/adr/0025-gateway-landing-authority.md` **Amendment D** — R10 게이트 재범위화의 "별도 결정 바인딩"은 그 Amendment 본문이다.
> **기록 관례**: `docs/evidence/epoch_record_base_artifact_2026-10-01.md`(Freeze/Record/Tombstone 템플릿) 준용.
> **변경 범위 판정**: publisher 전용 변경 — `admission-check.yml` blob 무변경 ⇒ 3파일 pin 유닛(`trustedAdmissionWorkflowSha`·`productionExecutionPin`) · org callee 핀 회전 · trustSurface 변경 **전부 불요** (publisher는 workflow_call callee도 required check도 아님).

---

## §0. 표면(surface) 판정 — 본 문서의 등록 의존 없음 (실측)

- base 정책 = `config/repository_surface.json` **policyVersion 67** (실측): `defaultClass: PRODUCT`, FROZEN은 열거 glob 15개뿐(`docs/**` glob 없음 — v51에서 default-FROZEN 폐지, "미등록 = 일반 코드"). ⇒ 신규 `docs/evidence/*.md` = **PRODUCT, ADD: PASS**.
- 편집 대상 3경로 실측: `.github/workflows/ci-cache-publisher.yml` → **CONTROLLED**(v57 재승인), `docs/spec/github_delegation_residuals.md` → **CONTROLLED**(v27 선례), `docs/adr/0025-gateway-landing-authority.md` → **CONTROLLED**(v17 선례). rules: CONTROLLED MODIFY=PASS.
- 결론: **본 문서·본문 편집 모두 base 정책에서 PASS** — surface 정책 선행 PR(PR-1) 불요. `make check-repository-surface`는 base(merge-base) 정책 × branch diff를 판정하며, 위 실측과 정합(§2.3 게이트 실행에서 확인).

## 1. Freeze (AGENTS.md §2.5 단계 1)

| 항목 | 값 |
|---|---|
| freeze tag | **`ci-frozen-2026-10-08`** (annotated) |
| 태그 타입 | annotated — `git cat-file -t ci-frozen-2026-10-08` = `tag` ✓ |
| freeze 대상 | origin/main == 작업 기준 HEAD == **`5dc62ebbadbc899251f63f2de903029d8e15017a`** |
| 실측 검증 | `git rev-parse ci-frozen-2026-10-08^{commit}` == `5dc62ebba` — 일치 ✓ |
| push | **아니오 — 로컬 전용** (기존 `ci-frozen-*` 시리즈 동일 관례) |

## 2. Record (AGENTS.md §2.5 단계 2)

### 2.1 변경 요약 (본문 3파일 + 본 기록)

| 파일 | 변경 |
|---|---|
| `.github/workflows/ci-cache-publisher.yml` | (a) lane verify: `tree(build_sha) != tree(head_sha)` → **실행 주제 identity** 판정(`build_sha == head_sha` ∨ `head_sha ∈ parents(build_sha)`)으로 교체, "not landable as tested" 문구·판정 삭제 (b) `build_sha` 트리로 detach checkout 후 keygen — 레시피/script 키 바이트 동일성 보장 전이 (c) 헤더 items 4/6 + 잔여 주석 정합(R6 오기→R10) |
| `docs/spec/github_delegation_residuals.md` | R10 재판정 기록 — P2-3(a) 충족 + 재범위화 선언, ahead-invariant 분류 해소 |
| `docs/adr/0025-gateway-landing-authority.md` | **Amendment D** — 결정 바인딩("freshness = 플랫폼, identity = Axiom") |
| `docs/evidence/epoch_record_memo_reanchor_2026-10-08.md` | 본 기록 |

### 2.2 authority 전이 정의 (§2.6 필수 4요소)

- **authority**: 착지 가능성(landable/ahead) 판정 = **GitHub ruleset + merge queue** (기존 권한 — 이전까지 publisher가 흉내 내던 것을 반환). 내용 identity 결속 = publisher (기존 유지).
- **state transition**: `TREE_BUILD != TREE_HEAD → publish-skip` (ahead-invariant) → `build_sha ∉ {head_sha} ∪ parents(head_sha) → publish-skip` (identity 미결속). 이외 경로는 전이 없음.
- **failure semantics**: fail-closed skip 불변 (검증 실패 = 기록 생략, red run 없음, J3 fail-open 가속 포기). 새 skip 문구 = "content identity not bound to executed subject".
- **proof**: 본 기록 §3 + acceptance 실측(`docs/evidence/memo_reanchor_acceptance_2026-10-08.md`, 후속 사이클).

### 2.3 변경 전 검증 (본문 커밋 전 워킹트리 실측)

- `python3 -c "import yaml; yaml.safe_load(...)"` → YAML OK
- 전체 run 블록 추출 `bash -n` → SHELL SYNTAX OK
- `make check-repository-surface` / `check-workflow-shell-syntax` → 본문 PR의 기계 게이트 출력에 기록 (§2.4)

### 2.4 기계 게이트 실행 (본문 PR에서)

`check-workflow-shell-syntax`(bash -n 전수), `check-repository-surface`(base 정책 판정), push-admissibility 정적 게이트군 — 실행 결과는 PR의 검증 블록에 원문 기록한다.

## 3. Tombstone (AGENTS.md §2.5 단계 3)

1. 본 Tombstone은 **게이트 우회(break-glass)가 아니다** — N/A(폐기 대상 없음). 실행 권한·검증 의무 제거 없음: verdict 체인(`admission-check` required check, org gate, mint) 무변경.
2. 본 Tombstone은 **면제(waiver)가 아니다** — N/A. `config/decision_binding.waiver.*` 등록 없음(본 변경 관련 면제 0건).
3. 본 Tombstone은 **required-check 제거가 아니다** — N/A. `admission-check`(ruleset 20303214)·org required workflow·verdict 체인 무변경 유지.
4. 본 Tombstone은 **검증 면제를 의미하지 않는다** — N/A. 검증 의미 변경 없음 — 제거되는 것은 publisher의 freshness **흉내** 판정뿐이며, 그 판정의 진짜 authority(GitHub ruleset/merge queue)는 그대로 발효.
5. Tombstone은 역사적 폐기 기록이며 실행·검증 권한을 갖지 않는다(AGENTS.md §2.5 Mandatory Invariants) — N/A이면서 이 원칙 자체는 본 기록에 준용된다.

## 4. 연결 (결정 바인딩 · 잔여)

- 결정 바인딩: `docs/adr/0025-gateway-landing-authority.md` **Amendment D** (R10 제거 조건의 "별도 결정 바인딩").
- 잔여 불변: R4(fork)·R5(교차 타이밍)·R6(mode=none)·R9(c)(a_fp 이미지 롤)·J3 바닥(HIT에서도 warm 재컴파일 — S5 build-skip 별도 슬라이스).
- 후속 증거: acceptance 실측 기록(계획 Completion Evidence 1–7)은 후속 PR에서 `docs/evidence/`에 착지한다.
