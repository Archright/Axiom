# Judgment Key v4 경계 관측 통합 기록 — semantic 랜딩 EXECUTED-class 6건·REUSED 표본 3확정+1잠정

> **성격**: 관측 통합 기록 (consolidation record) — 성공 선언이 아니다. 경계 관측과 REUSED 표본 누적을 최종 판정(final adjudication)의 입력 표면으로 고정한다.
> **데이터 SSOT**: `data/ci_optimization/judgment_key_v4_interim_2026-10-19.json` (관측 원장 — 본 문서는 이를 변경하지 않는다)
> **선행 문서**: `judgment_key_v4_boundary_watch_2026-10-19.md` (§2/§8 경계 관측) · `judgment_key_v4_interim_adjudication_2026-10-19.md` (§9/§10 표본 누적) · `mg_reuse_policy_redecision_2026-10-18.md` (재결 — 계약 §5·3지표 측정 계획) · `mg_reuse_cutover_e2e_2026-10-18.md` (REUSED 장소 재결)
> **관측 quirk 정본**: `docs/spec/gh_merge_admission_observation_quirks.md` Q2 (org 필수 워크플로 run의 `gh run view` 404) · `docs/spec/gh_run_observation_quirks.md` Q3 (jobs 로그 ANSI 이스케이프 사전 거부 — `--allow-escape-sequences` 미지정 시 빈 출력+실패)

기록일: 2026-10-19

## 1. 목적

v4 eligible-REUSED-on-MG 장소에서 누적된 관측을 두 축으로 통합한다: (i) semantic 입력 랜딩의 EXECUTED-class 경계 관측 6건, (ii) 비의미(docs-only) 입력 랜딩의 REUSED 표본 3확정+1잠정. 본 문서 자체도 **docs-only PR**(docs/evidence 단일 .md 신규 파일)로서 판정 입력(9성분 클로저)을 변경하지 않는 검증 차량이다 — `mg_reuse_cutover_e2e_2026-10-18.md`의 E2E 차량 관례와 동일하다.

## 2. semantic 입력 랜딩 — EXECUTED-class 경계 관측 6건

전부 실제 개발 착지이며(무합성 프루브 — boundary watch §5 준칙), wall은 runs REST `created_at`/`updated_at` delta 원값이다(Q2 우회 경로). 발화는 전부 EXECUTED-class wall(구세대 밴드 550–737s) 또는 그 초과 원값이다.

| PR | 입력 클래스 (PR files API 실측) | MG 런 (admission-gate, merge_group) | wall | lane 발화 (CAS 라인) |
|---|---|---|---|---|
| #932 | docs/evidence 2건 + `data/ci_optimization` JSON | `39198659706` — success (04:16:39→04:27:49Z) | **670s** | `EXECUTED — no record for the current closure (fresh judgment)` 4주체 — lane-0 job `117887210829`, lane-1 `117887210917` (boundary watch §2a) |
| #935 | src/verification 2건 + tests 3건 | `39203766464` — success (05:17:22→05:29:46Z) | **744s** | EXECUTED 4주체 — lane-0 `117902469086`, lane-1 `117902469124` (boundary watch §8.2) |
| #936 | src 12건 + tests 5건 | `39212037549` — success (06:48:17→06:59:27Z) | **670s** | EXECUTED 4주체 — lane-0 `117927879109`, lane-1 `117927879080` |
| #938 | src/cli/axiom_engine.nim + config/spec 계약 + docs/spec | `39215079947` — success (07:17:53→07:30:06Z) | **733s** | EXECUTED 4주체 — lane-0 `117937405763`, lane-1 `117937405789` |
| #939 | src/verification/cert_promotion.nim + config | `39215742092` — success (07:24:08→07:40:14Z) | **966s** | EXECUTED 4주체 — lane-0 `117940820976`, lane-1 `117940821095` |
| #942 | `data/ci_optimization` JSON + docs/evidence 2건 | `39226469788` — success (08:57:23→09:09:50Z) | **747s** | EXECUTED 4주체 — lane-0 `117974546699`, lane-1 `117974546734` (**본 통합 기록 작성 시점에 lane 로그에서 직접 추출**) |

- **wall 원값 주의 (보정 없음)**: #935 744s는 구세대 밴드 상단(737s)을 7s 초과한 원값, #939 966s는 #938 MG 런(→07:30:06Z)과의 병행 실행으로 대기 포함 가능성이 있는 원값 — adjudication §10.4와 동일하게 원값 그대로 기록한다.
- **발화 원인 단정 유보**: #932/#942는 `data/ci_optimization` JSON 동반 착지다. T7 실측(재결 정오표)은 `data/*.json` 일반이 키 전진 멤버임을 증명하지만, #928은 같은 경로의 JSON 동반 착지에서 **REUSED**였다. 본 문서는 발화를 files API 분류+관측 basis로만 기록하며 메커니즘 단정(경계 이동 vs 세대 전환 vs 개별 성분 효과)은 후속 과제로 유보한다 — boundary watch §2a의 해석 유보를 계승한다.
- **관측 목록 범위**: 본 표는 통합 대상 6건만 담는다. 전체 착지 census(#929/#930/#931 docs·src·Makefile 경계 3건, #937 713s EXECUTED 포함)는 원장 `observations`와 boundary watch §2/§8이 권위다.
- **권리 보존**: 본 표의 "semantic 입력" 분류는 files API 실측 파일 목록과 발화 결과에 근거한 **관측 분류**다 — 클로저 성분의 내부 구조 주장으로 확대되지 않는다.

### 2a. CAS 라인 추적 상태 — lane-log API 갭과 해소 경로

wall+파일 분류가 먼저 관측되고 CAS 라인 추출은 뒤따랐던 이유는 문서화된 두 겹의 API 갭이다:

1. **org 필수 워크플로 run 404** (Q2) — admission-gate는 `Archright/.github` 원천의 org required workflow라 `gh run view <id>`·`--log`가 404. run 메타·wall은 runs REST(`repos/Archright/Axiom/actions/runs/{id}`)로 정상 조회된다.
2. **jobs 로그 ANSI 이스케이프 사전 거부** (Q3) — `gh api …/actions/jobs/{id}/logs`는 이스케이프 포함 응답을 거부하며 미지정 시 **빈 출력+실패**. 정규 경로는 `--allow-escape-sequences` + sed 탈출이다.

위 표의 6건 전부에 대해 이 정규 경로로 lane 발화 추출이 **완료**됐다(#932/#935–#939는 boundary watch §2/§8, #942는 본 문서 §7 명령으로 직접 확인). 더 이상 "추출 지연" 항목은 없다 — 본 절은 그 지연이 왜 발생했는지의 문서적 기록으로 남는다.

## 3. REUSED 표본 — 3확정 + 1잠정 (docs-only 클래스)

| 착지 | 입력 클래스 (files API 실측) | MG 런 | wall | 밴드 401–550s | 상태 |
|---|---|---|---|---|---|
| #926 | docs/evidence 1건 | `39134186961` — success (14:02:16→14:09:33Z) | **437s** | ✓ | **확정** — lane REUSED 4주체 (adjudication §9/§10) |
| #927 | docs/evidence·data/ci_optimization | `39135473401` — success (14:19:31→14:26:25Z) | **414s** | ✓ | **확정** — 동일 |
| #928 | docs+data (interim 원장) | `39186429925` — success (01:40:31→01:47:50Z) | **439s** | ✓ | **확정** — 동일 |
| #934 | docs/evidence 1건 | `39200840559` — success (04:42:42→04:49:42Z) | **420s** | ✓ | **잠정** — lane REUSED 4주체 관측됨(boundary watch §8.1). 단, 세대 2 첫 docs-only 표본으로서 본 통합 문서는 최종 판정(J1–J4) 확정 전까지 잠정 등재로 표기한다 |

- **상태**: **n=3 확정 / n=4 잠정** (docs-only 클래스). 최종 판정 문서가 J1–J4 증거 맵으로 상태를 확정한다.
- **클래스 경계 주석 (정직 기록)**: 원장은 세대 2 표본으로 #933(rust-lane 경로, 404s, REUSED 4주체)을 추가로 기록해 관측 n=5로 집계한다. #933은 docs-only 클래스가 아니므로 본 통합 문서의 표본 표에서 제외하며, 최종 판정이 클래스 기준을 명시한다.
- **세대 주석**: #926–#928은 세대 1(eba3e79cea75…), #934는 세대 2(a3f14dbb8cc2 / d6dd58e95612 / 069929f3ce7e / 71aff5818ab4)를 재검증했다 — record ID 세대 교체는 adjudication §10.2가 권위다.

## 4. 무사후 게이트 변경 원칙 (no-post-hoc-gate-change rule)

1. **기준 고정**: 밴드(401–550s), 표본 수 기준, 클래스 정의(docs-only vs semantic), 완결 증거 4요소(venue·wall·lane 발화·files API)는 재결 `mg_reuse_policy_redecision_2026-10-18.md` §4와 원장 사전등록에 **고정**된다.
2. **관측 후 기준 변경 금지**: 착지 관측(wall·발화)을 본 뒤 임계·밴드·eligibility를 사후 조정하지 않는다. 기대와 어긋난 관측(#932 전환 EXECUTED, #935 744s·#939 966s 원값 등)은 **원값 그대로** 기록한다.
3. **변경 경로**: 기준 변경이 필요하면 관측 창 종료 후 **별도 재결 문서**로만 한다 — 역추적 보간·기준 재조정·표본 재분류 금지 (adjudication 사전등록 준칙: 표본은 관측으로만 확정).
4. **데이터 무접촉**: 본 문서를 포함한 관측 기록 문서는 `data/*.json`(semantic 데이터)을 변경하지 않는다 — 원장 갱신은 별도 권한 절차를 따른다.

## 5. 본 착지의 위치 (self-vehicle)

본 PR의 MG 런은 §3 절차에 따라 docs-only 클래스 표본 후보로 관측 대상이며, 그 발화·wall 기록은 최종 판정 준비 문서 계보(J1–J4 증거 맵)가 수행한다. 본 문서는 착지 전 선측값을 선언하지 않는다 — 관측은 GitHub(run·queue·MERGE 커밋)가 권위다(AGENTS.md §2.3).

## 6. 재현 명령

```bash
# 1) 경계 6건 wall·venue·conclusion — 670/744/670/733/966/747s
for r in 39198659706 39203766464 39212037549 39215079947 39215742092 39226469788; do
  gh api repos/Archright/Axiom/actions/runs/$r --jq '[.id,.created_at,.updated_at,.conclusion]'
done

# 2) REUSED 표본 wall — 437/414/439/420s
for r in 39134186961 39135473401 39186429925 39200840559; do
  gh api repos/Archright/Axiom/actions/runs/$r --jq '[.id,.created_at,.updated_at,.conclusion]'
done

# 3) #942 lane 발화 (quirk Q3 — --allow-escape-sequences 필수, 미지정 시 빈 출력+실패)
gh api --allow-escape-sequences repos/Archright/Axiom/actions/jobs/117974546699/logs 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -E "REUSED — record|EXECUTED — no record"  # lane-0 → EXECUTED
gh api --allow-escape-sequences repos/Archright/Axiom/actions/jobs/117974546734/logs 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -c "EXECUTED — no record"               # lane-1 → 3 (4주체 확인)

# 4) 입력 클래스 실측 (제목·추측 기반 분류 금지 — boundary watch §4.4)
gh api repos/Archright/Axiom/pulls/942/files --jq '.[].filename'
gh api repos/Archright/Axiom/pulls/932/files --jq '.[].filename'
```
