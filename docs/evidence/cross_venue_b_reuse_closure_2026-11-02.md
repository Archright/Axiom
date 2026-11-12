# 교차-venue B-build 재사용 종결 — Stage 4 후속 입력 정정·재사용 경로 4계층 증거 분류 (2026-11-02)

> **종류**: 종결·정정 문서 (closure & append-only erratum) — Stage 4 착지 보고서
> (`docs/evidence/node24_merge_group_job_decomposition_2026-11-02.md`)의 후속 입력 ①
> "교차-venue B-build 중복"을 재판정하고, 기존 B-build 캐시 재사용 경로의 증거를
> 4계층(L1–L4)으로 분류해 종결한다. 코드·워크플로·게이트·핀·도구 변경 0건의
> docs-only 문서다.
> **정정 성격**: 이미 착지된 Stage 4 원본 보고서는 **수정하지 않는다** — 본 문서는 그
> 후속 입력에 대한 **append-only 정정**이다. 원본의 측정값(65 s·90 s 등) 자체는
> 유효하며, 정정되는 것은 그 값의 **분류·해석**("이중 빌드")이다.
> **규율**: 모든 관측은 GET-only(`gh api`·`gh pr view`)·`gh` 네이티브 인증(AGENTS.md
> §2.4)이다. 파일 생성은 /tmp뿐 — 저장소 파일·git·캐시·PR·이슈 무변경. 외부 공식
> 문서는 Context7 코퍼스로 인용했다(§6).
> **Date**: 2026-11-02 · **Branch**: docs-only PR(`docs/evidence/` 착지 — 관측 종결 문서 5건 동반: 본 문서·mint tail 분해(`node24_mint_tail_decomposition_2026-11-02.md`)·캐시 회전 관찰(`actions_cache_rotation_observation_2026-11-02.md`)·SLO 상태 스냅샷(`slo_status_snapshot_2026-11-02.md`)·판정창 사전등록(`slo_judgment_window_prereg_2026-11-02.md`)) · **Scope**: `docs/evidence/*.md` 1건 — docs-only
> 비행 → trust surface 아님(정상 merge queue 경로).
> **권위**: 본 문서는 **Reporter**다 — GitHub merge authority(required checks·ruleset·
> merge queue·MERGE commit)를 대체하지 않는다(Authority ≠ Adapter, AGENTS.md §2.3).
> 런·잡·스텝·로그의 존재·타임스탬프·결론 권위는 GitHub Actions API다.
> **측정 기준**: api-second-granularity(±1 s) · step wall = `completed_at − started_at`
> · 시각은 전부 UTC.

---

## §0. 판정 요약

**정정(핵심 문장)**:

> "이전에 중복 비용으로 분류했던 90초는 실제 중복 컴파일 비용이 아니었으며, 이미 실행 중인 캐시 재사용 경로의 복원·검증·업로드 시간이 포함된 job 벽시계 시간이었다."

- **판정 — Stage 4 후속 입력 ① 반박(정정)**: 현세대(게이트 callee 핀 498c5570)에서
  MG venue의 "90초 B-build"는 **재빌드가 아니라 복원+검증+업로드**였다. 배치 3런
  전부에서 MG job1(`attest / build-base-artifacts`)의 컴파일 step은 발화하지 않았다
  (`SUPPLY REUSE — compile skipped`).
- **전달 메커니즘**: GitHub Actions Artifacts가 아니라 **actions/cache(내용 주소 키,
  default-branch 스코프) + ci-cache-publisher 단일 writer**다. PR venue
  (`refs/pull/1214/merge`)와 MG 런(`gh-readonly-queue/main/pr-1214-…`)이 동일 키
  `axiom-b-73dfd535…` exact-hit 복원을 실측했다(§6).
- **중복 지표 재정의**: 중복의 올바른 지표는 job 벽시계가 아니라 **컴파일 step
  발화(실행) 유무**다. 관측: MG에서 compile skipped → **중복 컴파일 없음**(§3).
- **잔여 구조**: 컴파일 gate는 `venue=='landing'`에서만 열린다 → src/ 변경 PR 착지
  시 새 closure digest의 첫 빌드가 landing venue에 1회 발생한다. 이것은 "중복"이
  아니라 **"빌드 시점 이연"**이며, 별세대 관측 과제로 기록만 남긴다(본 문서 범위
  밖, §4).
- **불필요 판정**: 새 writer 도입 = writer 단일성 붕괴(불필요). PR-publisher 순서
  수정도 불필요(+2 s에 불과, §5).
- **서술 규율**: "J1–J4 완전 증명"이라고 쓰지 않는다 — 정확한 표현은 **"현재
  publisher 경로의 불변식과 관측 근거를 명문화했다"**다(§1).

---

## §1. 4계층 증거 분류 — 재사용 경로의 증거 강도 (본 문서의 핵심 구조)

Stage 4 후속 입력이 상정한 "J1-J4 등가 사운드니스 증명"을 평가하기 위해, 재사용
경로에 존재하는 모든 근거를 증거 강도 4계층으로 분류한다. 계층은 근거의 **획득
방식**이며, L1(코드)은 소스 판독으로 항상 확인 가능, L2(런타임)는 실제 실행에서만,
L3(부정 시험)은 적대 입력을 실제로 주입해야만 획득된다. 상위 계층의 부재를 하위
계층의 성취로 서술하지 않는 것이 본 분류의 규율이다.

| 계층 | 의미 | 해당 항목 |
|---|---|---|
| **L1 코드 확인 불변식** | 소스 코드에서 확인 | ① 클로저 digest keygen(키-내용 결속) ② writer 단일성(ci-cache-publisher, single-flight + lookup-only 가드) ③ 소비자 검증(b-verify identity 재유도 + B_PROBE BuildSourceHash 비순환 앵커) ④ fail-closed 폐기 |
| **L2 런타임 관측** | 실제 실행에서 관측 — **happy path만** | 배치 3런(pr-1214 90 s·pr-1215 79 s·pr-1218 119 s, job1 `attest/build-base-artifacts`) 전부 exact-hit=true → b-verify 성공 → B_PROBE OK×5 → `SUPPLY REUSE — compile skipped` |
| **L3 부정 시험 입증** | 위조·변조·출처 불명 입력의 거부를 실증 | **없음** |
| **L4 미검증 조건** | 아직 런타임 검증되지 않은 조건 | 변조 캐시 내용 소비 가능성 — b-verify 재유도가 1차 방어이나 **통과 경로만 관측됨** |

### §1.1 L1 — 코드 확인 불변식 (소스 판독, 4항목)

1. **클로저 digest keygen(키-내용 결속)** — `.github/actions/setup-axiom-toolchain/action.yml`
   keygen step이 `cache-build-source` 트리에서 **컴파일 참여 입력 클로저
   digest(40 hex) + recipe identity**로 b-key를 구성한다(`axiom-b-<클로저
   digest>-<recipe/a_fp>`, action.yml:304-310). 플랫폼(actions/cache)은 키의 의미를
   모른다 — 키와 내용의 결속은 이 keygen 공식이 유일하게 만드는 성질이다.
2. **writer 단일성** — B키의 유일 `actions/cache/save` 주체는 ci-cache-publisher다
   (`.github/workflows/ci-cache-publisher.yml`:483, save 9경로). 트리거 가드(게이트
   conclusion==success ∧ gate-v2 path, :210), 워크플로 단위 직렬화
   `concurrency: ci-cache-publisher-single-flight, cancel-in-progress: false`
   (:196-198), 단일-flight 사전조회 `actions/cache/restore … lookup-only: true`(HIT
   시 save 생략)가 겹막한다. exact-hit 재저장은 플랫폼이 자동 생략한다(saveImpl
   `isExactKeyMatch` — §6 인용 4).
3. **소비자 검증** — (i) **b-verify**: 복원 payload를 save-time manifest와 identity
   재유도(closure+recipe+a_fp — 페이로드 밖 신뢰 입력에서 재계산)로 대조 + 파일별
   sha256, 부분 페이로드는 폐기. (ii) **B_PROBE**: 복원된 ci-compile 바이너리의
   내장 BuildSourceHash를 신뢰 트리와 대조(J3 §3.3 **비순환 앵커** — "provenance
   re-derived outside the payload").
4. **fail-closed 폐기** — A-layer 지문 불일치 폐기, publisher base 경로의 앵커
   불일치 skip(manifest build_sha vs 플랫폼 진실 base.sha — 정확 일치 시에만 진행),
   b-verify 부분 엔트리 DISCARD. 캐시는 가속일 뿐 증거가 아님(J3) — miss는 실패가
   아니라 cold build로 퇴화한다.

**서술 규율(엄수)**: 위 4항목을 "J1–J4 완전 증명"이라고 쓰지 않는다. 정확한
표현: **"현재 publisher 경로의 불변식과 관측 근거를 명문화했다."** Stage 4 후속
입력이 상정한 "새 전달 계약(J1-J4 등가 증명 + CAS 도메인 확장)"은 §5에서 불필요
판정을 받는다 — 위 성질들은 이미 코드+관측으로 존재하며, 새 계약을 선언하면
이중 계약(제2 writer 포함)이 된다.

**초안 정정(내부 계보)**: 본 문서의 원초 초안이 "fail-closed 폐기 3런 관측"이라고
쓴 것은 **과대 주장**이었다 — 배치 3런은 happy path(복원→검증 통과→재사용)만
관측했고, 어떤 fail-closed 분기도 런타임에서 발화하지 않았다. fail-closed 폐기는
**L1(코드 확인) 계층으로 강등**한다 — 코드로 확인된 불변식이지 런타임 거부
실증(L3)이 아니다.

### §1.2 L2 — 런타임 관측 (happy path: MG 3런 + PR venue)

MG job1(`attest / build-base-artifacts`) 실측 — 관측창 2026-11-02, 전부
run_attempt=1:

| 런 | MG 배치 | base | job1 구간(UTC) | job1 wall | B-restore | b-verify | B_PROBE | s5 판정 |
|---|---|---|---|---|---|---|---|---|
| 41414648142 | pr-1214 | 8c46c4ea | 08:39:24→08:40:54 | **90 s** | exact-hit=true (08:40:31) | OK 5/5 (577 ms) | OK×5 | **SUPPLY REUSE — compile skipped** (08:40:39) |
| 41416443711 | pr-1215 | 9381cb3a | 08:54:27→08:55:46 | **79 s** | exact-hit=true (08:55:17, 동일 키) | 성공 | OK×5 | SUPPLY REUSE (08:55:28) |
| 41421620938 | pr-1218 | 4c19fa9b | 09:33:24→09:35:23 | **119 s** | exact-hit=true (09:34:46, 동일 키) | 성공 | OK×5 | SUPPLY REUSE (09:35:02) |

- 세 런 모두 b-identity = `73dfd535e2fe36919e194f6a31b9534aff239811`(문서/.
  github-only PR 연쇄로 클로저 digest 불변), b-key 바이트 동일:
  `axiom-b-73dfd535e2fe36919e194f6a31b9534aff239811-41ae9d00a404ca743cd4050a788817ecfec503b1cd6570e7737ce3968b7e9d62`.
  Stage 4 표기 "동일 B=8c46c4ea"는 base 커밋 표기이며, 캐시 키 identity는 클로저
  digest `73dfd535…`다 — 같은 대상의 두 표기다.
- verbatim 로그 라인(MG pr-1214 job1 — 로그 원본 `/tmp/xv_org_wf/mg_job1.log` 보존,
  재인출은 §8):
  - `AXIOM_CACHE_B_RESTORE: exact-hit=true requested-key=axiom-b-73dfd535… primary-key=axiom-b-73dfd535… matched-key=axiom-b-73dfd535…` (requested = primary = matched)
  - `AXIOM_CACHE_B_VERIFY: RESULT OK — 5/5 entries digest-verified, identity=73dfd535e2fe re-derived from trusted inputs (closure+recipe+a_fp), key exact-hit`
  - `SUPPLY REUSE — verified payload restored; compile skipped (ADR-0032/J3 §3.1)`
  - B_PROBE OK×5 = ci-compile 바이너리 4개(bin/ax·gate_hook·precompile_gates·
    install_ax_cas) 내장 BuildSourceHash 일치 + proofs/.lake/build/bin/ircheck
    존재·실행 가능(digest는 b-verify files map으로 결속).
- **PR venue**(런 41413475503, run_number 815, PR #1214, ref
  `refs/pull/1214/merge`): job1 `08:30:06→08:31:11 = 65 s` — setup-axiom-toolchain
  56 s 내에서 **08:30:54 exact-hit=true**, b-verify 303 ms, B_PROBE OK. 컴파일·
  업로드 step은 preflight 조건 미충족으로 미실행 — **복원(관측)만 수행**. job2
  (`attest / admission-check`) 85 s — 체크아웃+identity 재유도+static contrast,
  빌드 없음. Stage 4가 보고한 65 s는 그 값 그대로 재현됐다(측정은 유효).
- **L2의 한계(명시)**: 위 관측은 **전부 happy path다** — "복원 시도→HIT→검증
  통과→재사용"의 통과 경로만 샘플에 있다. 거부 경로(miss→cold build, 검증
  실패→폐기)의 런타임 발화는 이번 샘플에 없다.

### §1.3 L3 — 부정 시험 입증: **없음**

위조·변조·출처 불명 입력이 실제 거부되는 장면(검증 실패→폐기 발화)을 관측하지
못했다. §1.1-4의 폐기 코드 경로가 소스에 존재한다는 것(L1)과 그것이 런타임에서
작동하는 것을 입증하는 것(L3)은 다른 증거 강도다. 본 문서는 L3가 **비어 있음**을
그대로 기록한다 — 이를 채우려는 재구성(인위적 변조 주입 등)은 본 문서 범위 밖이며
별도 계약의 과제다.

### §1.4 L4 — 미검증 조건: 변조 캐시 내용 소비 가능성

**플랫폼 사실(공식 문서·소스 확인 — Context7 /actions/cache, restoreImpl·dist
소스, 2026-11-02)**:

- restore는 **내용 무결성 검증 없이 key 매칭만 수행**한다 — 복원 payload가 그 키의
  빌드인지는 플랫폼이 판정하지 않는다.
- restore 실패·오류는 **기본 warning 처리**다 — 캐시 miss로 취급하고 빌드를
  계속한다. `CacheReadDeniedError`조차 warn 후 `undefined`를 반환한다(소비자
  체인이 깨지지 않는다).
- 결론: **플랫폼은 변조된 캐시 내용을 검증해주지 않는다.** 키가 맞으면 내용이
  무엇이든 복원된다.

이 사실에서 재사용 경로의 안전성은 전적으로 **소비자 측 검증(b-verify identity
재유도 + B_PROBE 비순환 앵커 — §1.1-3)이 1차 방어**라는 구조가 된다. 이번 관측
(§1.2)은 그 방어선의 **통과 경로만** 포함하므로, "변조 payload가 방어선에서
거부된다"는 명제는 L1(코드)까지만 확정이고 런타임 입증은 미검증(L4)으로 남는다.

---

## §2. 90초 정정 (append-only)

### §2.1 정정 대상 (원본 보고서 인용 — 본문은 수정하지 않는다)

`node24_merge_group_job_decomposition_2026-11-02.md` §5의 두 문구:

- 후보 표: "실측: 동일 B=8c46c4ea가 PR venue 65 s(런 41413475503, run_number 815)
  + MG venue 90 s(런 816) 이중 빌드 — MG 크리티컬 패스 17.6%"
- 후속 입력 ①: "교차-venue B-build 중복(동일 B 65+90 s 이중 빌드 실측 — J1-J4
  등가 사운드니스 증명 + CAS 도메인 확장 계약 전제)"

같은 보고서 §4.3의 "유일한 측정된 교차 실행 반복은 build-base-artifacts의 venue
간 재실행" 진술도 같은 해석(재실행=재빌드)에 의존하며 함께 정정된다.

### §2.2 정정 문장 (verbatim)

> "이전에 중복 비용으로 분류했던 90초는 실제 중복 컴파일 비용이 아니었으며, 이미 실행 중인 캐시 재사용 경로의 복원·검증·업로드 시간이 포함된 job 벽시계 시간이었다."

### §2.3 append-only 성격

이미 착지된 원본 보고서는 수정하지 않는다 — 본 문서가 후속 입력에 대한 **후속
판정 기록**이다. 원본의 65 s·90 s 타임스탬프 측정은 그대로 유효하며(§1.2가 PR
65 s를 그 값 그대로 재현), 정정되는 것은 **분류("이중 빌드")와 그 파생(새 계약
전제)**뿐이다. 변경은 새 날짜 문서로만 한다는 기존 등록 규율
(`slo_official_measurement_prereg_2026-11-01.md` §10 준용)을 따른다.

### §2.4 90 s 성분 분해 (pr-1214 MG job1 — step 분해)

- setup-axiom-toolchain **70 s**(08:39:29→08:40:39) — 그 안에 B-restore exact-hit
  (08:40:31, 복원 자체 ~1 s)·b-verify 577 ms·B_PROBE OK×5.
- 이하: s5 공급 판정 <1 s + deriver 컴파일 2 s + jq <1 s + manifest <1 s + base
  artifacts 업로드 5 s + nimcache 업로드 4 s.
- **"[build] Build bin/ax + harness from B" step은 실행 목록에 부재** — 조건
  `venue=='landing' && mode=='build'` 미충족(mode=skip).
- PR 65 s vs MG 90 s의 **Δ≈25 s는 landing 전용 s5 판정+업로드** 성분이다 —
  컴파일이 아니다.
- MG venue의 다른 B 소비 경로에도 빌드는 없다: `go-critical-lane (0)`
  (08:41:00→08:44:05) = 같은-런 아티팩트 다운로드 → manifest 검증 → 테스트
  배터리 → nimcache 업로드. 컴파일 step 없음.

### §2.5 타이밍 — 키는 사이클 이전부터 존재했다

| 시각(UTC) | 주체 | 사건 |
|---|---|---|
| ≤08:29 이전 | 과거 사이클 publisher | 키 `axiom-b-73dfd535…41ae9d00…`가 default-branch 스코프에 존재(논리 증명: 08:30:54 exact-hit이 사이클 첫 publisher보다 앞섬) |
| 08:29:43–08:35:00 | PR 게이트 41413475503(#815, PR #1214) | job1 65 s — **exact-hit 복원(08:30:54)**, 컴파일 0 |
| 08:35:02–08:35:16 | publisher #11218(41414132699) | PR 게이트 완료 **+2 s** 발화. lane skip(ci-bootstrap-artifacts absent)·base skip — **발행 0**, 14 s |
| 08:39:20–08:47:52 | MG 게이트 41414648142(pr-1214) | job1 90 s — **exact-hit(08:40:31)**, SUPPLY REUSE, 업로드만. go-critical lanes 3 min(아티팩트 소비+테스트) |
| 08:47:54–08:49:47 | publisher #11219(41415676453) | MG 완료 +2 s 발화. lane skip. base 경로 keygen(동일 키)→A-seed 실행, lookup-only save 가드 동작 |
| 08:50:42–08:51:03 | publisher #11220(41416006223) | (별도 게이트 완료 트리거) lane keygen 동일 키 — 존재 키라 save 생략 경로 |
| 08:54:19 | MG 게이트 41416443711(pr-1215) | job1 79 s — exact-hit(동일 키), SUPPLY REUSE |
| 09:33:20 | MG 게이트 41421620938(pr-1218) | job1 119 s — exact-hit(동일 키), SUPPLY REUSE |

- PR 복원(08:30:54)이 사이클 첫 publisher #11218(08:35:02)보다 **4분 이상 선행**한
  exact-hit — **키는 이전 사이클부터 존재했다**. 원인: 직전 PR(#1213)이 .github만
  변경해 closure digest가 현세대와 동일했다(**docs-only 연쇄라 closure digest
  불변**).
- publisher 발화 지연 실측: 게이트 완료→publisher 생성 **+2 s**
  (08:35:00→08:35:02, 08:47:52→08:47:54) — workflow_run 트리거는 즉시다.
- 원인 선택지 소거(측정 대조): (b) "MG가 restore를 시도조차 안 함" — 거짓(B-restore는
  `keygen-only != true`면 venue 무관 무조건 실행, 3/3 시도+exact HIT). (c)
  "recipe/identity 불일치로 miss" — 거짓(양 venue keygen이 같은
  `cache-build-source` 8c46c4ea에서 바이트 동일 키 산출). (a) "publisher 발화가
  늦음" — 이번 샘플에서는 원인이 아니다(§2.5 첫 행).

---

## §3. 중복 지표 재정의

- **중복의 올바른 지표 = 컴파일 step 발화(실행) 유무**다 — job1 step 목록에서
  "[build] Build bin/ax + harness from B"의 실행 여부(s5 판정의 mode=build vs
  skip)가 관측점이다.
- job 벽시계는 복원·검증·업로드·툴체인 setup을 모두 포함하는 **혼합 성분**이므로
  중복 판정 지표로 부적합하다. Stage 4가 65 s+90 s를 "이중 빌드"로 분류한 것은
  지표 선택 오류(벽시계 지표)가 원인이다.
- 관측: MG 3/3 compile skipped, PR venue는 preflight라 애초 컴파일 step이 없음 →
  **중복 컴파일 0회**.
- 이 지표로 §2의 정정과 §4의 잔여가 하나의 관측점에서 일관되게 읽힌다 — 90 s는
  "중복 비용"이 아니라 재사용 경로의 운영 비용(복원·검증·업로드)이고, 컴파일
  발화는 0회다.

---

## §4. 잔여 구조 — "중복"이 아니라 "빌드 시점 이연"

- 컴파일 gate는 `venue=='landing'`(∧ `mode=='build'`)에서만 열린다 — PR(preflight)
  venue는 컴파일하지 않는다.
- src/ 등 컴파일 입력을 바꾸는 PR이 착지하면 새 closure digest 키는 어디에도
  존재하지 않고, **landing(MG) job1이 mode=build로 새 base 트리의 첫 빌드를 1회
  지불**한다.
- PR venue는 애초 컴파일하지 않으므로 이것은 "같은 빌드를 두 venue가 반복"하는
  중복이 아니라 **"빌드가 착지 시점으로 이연"**된 것이다.
- 본 배치(문서/.github-only 3건)에서는 이 잔여가 0회 발생했다 — src-변경 PR
  샘플은 미관측(**UNKNOWN**, §7).
- **처분: 별세대 관측 과제로 기록만 남긴다(본 문서 범위 밖).** PR venue로 빌드를
  앞당기는 설계는 PR venue job1이 복원 전용으로 설계되어 작업 크기가 크고, 현
  관측(0회 발생)에서 유지·관측이 최소 변경이다.

---

## §5. 불필요 판정

| 후보 | 판정 | 이유 |
|---|---|---|
| 새 writer 도입(Artifacts 기반 cross-run 전달 계약 등) | **불필요 — writer 단일성 붕괴** | B키 writer는 ci-cache-publisher 단일이어야 한다(§1.1-2). 제2 writer는 단일성 불변식을 깬다. cross-run 전달에서 아티팩트는 캐시보다 만기·비용·스코프 전환 측면에서 열세다 |
| PR-publisher 순서 수정(발화 앞당기기) | **불필요 — +2 s에 불과** | 발화 지연 실측 **+2 s**(§2.5). MG 소비는 default-branch 스코프 캐시만 보므로 publisher 경유가 유일 통로인데 그 통로가 3/3 exact-hit으로 이미 작동한다 |
| "J1-J4 새 전달 계약" 서술 | **불필요 — 명문화로 흡수** | J-성질은 이미 코드+관측으로 존재한다(§1). 새 계약 선언은 이중 계약 위험이다. 올바른 서술: **"현재 publisher 경로의 불변식과 관측 근거를 명문화했다"** |

---

## §6. venue·전달 메커니즘 사실

- **전달 수단**: actions/cache — B의 교차-런·교차-venue 전달은 Artifacts가 아니라
  캐시다. 유일 writer는 ci-cache-publisher(`actions/cache/save` 9경로)이며,
  publisher는 workflow_run 실행(default branch ref)이므로 save가
  **default-branch(main) 스코프**에 착지한다(별도 스코프 승격 API 없음 — 이것이
  publisher 스코프 위임 패턴의 근거).
- **동일 키 교차-venue 복원 실측**: PR venue(`refs/pull/1214/merge`) 런
  41413475503(08:30:54)과 MG 런(`gh-readonly-queue/main/pr-1214-<sha>`)
  41414648142(08:40:31)가 **동일 키 `axiom-b-73dfd535…` exact-hit 복원**을 실측했다.
- **merge-queue ref의 스코프 함의**: `gh-readonly-queue/main/pr-N-<sha>`는 PR
  브랜치도 default branch도 아니므로 복원 가능한 것은 default-branch 스코프 캐시뿐
  — **publisher 경유가 MG 소비의 구조적 유일 통로**다. Artifacts의 실제 역할은
  (i) 같은-런 job↔job 전달(derived-closure, admission-check-base-*,
  go-critical-lane 입력)과 (ii) publisher의 입력 소재(재발행 전 다운로드)다.
- 외부 공식 문서 인용(Context7 코퍼스 — 2026-11-02 확인):
  1. actions/cache 스코프: "The cache is scoped to the key, version, and branch.
     The default branch cache is available to other branches."
  2. GitHub Docs 복원 접근 제한: "Workflow runs can restore caches created in
     either the current branch or the default branch… If a workflow run is
     triggered for a pull request, it can also restore caches created in the base
     branch." / "Workflow runs cannot restore caches created for child branches or
     sibling branches." / PR 트리거로 만든 캐시는 merge ref(`refs/pull/.../merge`)
     스코프로 갇혀 재런 외 복원 불가.
  3. 키 매칭 순서: exact key → restore-keys 접두 → default branch 재시도(스코프
     제한은 검색 내내 적용). 본 경로는 restore-keys 금지·exact만 사용
     (action.yml:395-413).
  4. exact 일치 시 save 생략: `saveImpl.ts` `isExactKeyMatch` — "Cache hit occurred
     on the primary key …, not saving cache." (`lookup-only` 입력도 공식 제공 —
     publisher 단일-flight 사전조회가 공식 패턴).
  5. actions/download-artifact: 타 런 다운로드(`github-token` actions:read +
     `repository` + `run-id`)와 서버 제공 digest 대조(`digest-mismatch`
     ignore/info/warn/error, 기본 error) — 같은-런 전달·publisher 입력의 무결성은
     이 층이 담당.
  6. restore의 내용 무결성 미검증·실패 시 warning 처리(§1.4 — L4 근거):
     restoreImpl·dist 소스 확인.

---

## §7. 측정 사실 vs 원인 판정 · UNKNOWN 명시

| 구분 | 내용 |
|---|---|
| **측정 사실**(관측 — §8 명령으로 재현 가능) | 런·잡·step 타임스탬프와 wall, step 목록·conclusion; `exact-hit=true`와 전체 키 문자열(requested=primary=matched); b-verify OK 5/5(identity 재유도); B_PROBE OK×5; `SUPPLY REUSE — compile skipped` 로그 라인; publisher 발화 +2 s; PR job1 65 s·MG job1 90/79/119 s |
| **원인·구조 판정**(위 사실 위의 해석) | "키는 이전 사이클부터 존재"(exact-hit이 사이클 첫 publisher에 선행 → 전제-존재의 논리 귀결); "90 s는 재빌드가 아님"(build step 부재 + 성분 분해); "중복이 아니라 빌드 이연"(venue gate 코드 + 관측 조합); "전달 수단은 캐시"(복원 경로 코드 + 스코프 문서 + 교차-venue 동일 키 실측 조합) |

**UNKNOWN 명시**:

1. 키의 최초 시더 publisher 개별 동정 — 미수행(후보 38개). 단, 사이클 첫 publisher
   이전 exact-hit이 키의 전제-존재를 논리적으로 증명하므로 본 판정에는 영향 없다.
2. src-변경 PR 착지 시 landing 첫 빌드 발생 — `venue=='landing' && mode=='build'`
   코드 조건에서 도출된 구조적 사실이나, 본 배치(문서/.github-only 3건)에서는
   미발생. **src-변경 PR 샘플은 미관측.**
3. 변조·위조·출처 불명 입력의 런타임 거부 실증 — **L3 부재**(§1.3). fail-closed
   분기는 L1까지만 확인.
4. 위 라인 참조의 핀 기준 한계 — org required workflow(admission-gate-v2)의
   enforcement 대상은 핀 sha 7eaa9624 버전이므로 원초 조사의 org 파일 라인 참조는
   main 버전(0ef1a441) 기준이다. 실제 callee 핀 498c5570은 런 로그로 독립 확인됐다
   (§8).

---

## §8. 재현 명령 (GET-only — 초안 verbatim 보존)

```
gh api "repos/Archright/.github/contents/.github/workflows?ref=main"
for f in admission-gate-v2.yml landing-integrity.yml parse-probe.yml pin-promotion-gate.yml; do
  gh api "repos/Archright/.github/contents/.github/workflows/$f?ref=main" --jq '.content' | base64 -d > "/tmp/xv_org_wf/$f"; done
ls -la .github/workflows/                                    # 로컬 clone (읽기)
git log --oneline -1 498c55704552291da926fae6eb34bc5c0c04ec1b
git diff --stat 498c55704552291da926fae6eb34bc5c0c04ec1b -- .github/workflows/admission-check.yml .github/actions/setup-axiom-toolchain   # (빈 결과 = byte 동일)
for id in 41414648142 41416443711 41421620938 41413475503; do gh api "repos/Archright/Axiom/actions/runs/$id" --jq '<요약 jq>'; done
gh api "repos/Archright/Axiom/actions/runs?event=workflow_run&per_page=15" --jq '.workflow_runs[] | <요약 jq>'
gh api "repos/Archright/Axiom/actions/runs?event=workflow_run&created=2026-11-02T08:25:00Z..2026-11-02T09:46:00Z&per_page=100" --jq '<publisher 필터>'
gh api "repos/Archright/Axiom/actions/runs?event=workflow_run&created=2026-11-02T07:40:00Z..2026-11-02T08:36:00Z&per_page=100" --jq '<count>'
gh pr view 1214 --repo Archright/Axiom --json number,title,headRefOid,baseRefOid,mergeCommit,state,mergedAt
git log --oneline -2 8c46c4ea8a635dc468248470732e1084c08863a7; git rev-parse 8c46c4ea8a6…^1 8c46c4ea8a6…^2
gh api "repos/Archright/Axiom/actions/runs/<run>/jobs?per_page=100" --jq '.jobs[] | <요약 jq>'        # 41413475503, 41414648142
gh api "repos/Archright/Axiom/actions/jobs/<job_id>" --jq '.steps[] | select(.conclusion != "skipped") | <타이밍 jq>'
  # 125171764972(PR job1), 125175442148(MG job1), 125172240299(PR job2), 125176039316(MG lane0)
gh api "repos/Archright/Axiom/actions/jobs/<job_id>/logs" --allow-escape-sequences                     # job 로그 GET
gh api "repos/Archright/Axiom/rulesets/25218071" --jq '<parameters jq>'; gh api "repos/Archright/Axiom/rulesets/23943917" --jq '<parameters jq>'
gh api "repos/Archright/Axiom/actions/runs/41413475503" --jq '.run_number'                            # 815
gh api "repos/Archright/Axiom/actions/runs?created=2026-11-02T07:55:00Z..2026-11-02T08:31:00Z&per_page=100" --jq '<merge_group gate 필터>'  # (0건)
Context7: resolve(/actions/cache, /actions/download-artifact, /websites/github_en_actions) + query-docs  # §6 인용·§1.4 L4 근거(restoreImpl·dist 소스) 경로
FetchURL docs.github.com/en/actions/writing-workflows/choosing-what-your-workflow-does/caching-dependencies-to-speed-up-your-workflow  # 404 — URL 폐기됨, Context7 코퍼스로 대체 인용(§6)
grep/sed/wc — 로컬 파일·/tmp 로그 파싱만
```

로그 원본 보존: `/tmp/xv_org_wf/{mg_job1.log, pr_job1.log}`(+ org 워크플로 디코딩본
4개) — 세션 로컬 보존이며, 착지 이후에는 위 §8 명령으로 동일 값을 재인출한다.

---

*본 문서는 Stage 4 보고서(`node24_merge_group_job_decomposition_2026-11-02.md`)
후속 입력 ①을 종결한다 — "교차-venue B-build 중복"은 반박되어 "복원·검증·업로드의
job 벽시계"로 정정되며, 잔여는 "빌드 시점 이연"(별세대 관측 과제)으로 재분류된다.
측정의 원본은 GitHub Actions API·런 로그이며 본 문서는 그 투영이다. 재사용 경로의
증거는 §1의 4계층 분류로만 인용되어야 한다 — L1(코드 불변식)과 L2(happy path
런타임 관측)는 확정, L3(부정 시험)은 부재, L4(변조 내용 소비 가능성)는 미검증으로
남는다.*
