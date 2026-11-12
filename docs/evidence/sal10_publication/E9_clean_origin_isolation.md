# E9 — Clean-Origin Isolation 기계 audit 기록

**실행일**: 2026-11-09 · **판정**: CLEAN_ORIGIN_ISOLATED (관측 가능 표면 7조건 전부 PASS — 범위 선언·관측 불가 목록은 §하단)

## Ultimate Purpose

현행 `Archright/Axiom` (id **1448376585**)이 구 정본 `Archright/Axiom-archive` (id **1182104685**)로부터
독립적인 clean-origin 세대임을, 각 조건의 **증명 범위(관측 사실/추론/API 불가)**를 구분해 기계 audit로 확정한다.

## audit 환경·경계

- 실행 클론: `Axiom2` (main `70d1b66f`, 클린) → 격리 worktree `Axiom2-wt-vsc` (branch `workstream/vs-c-clean-origin-isolation`)
- **아카이브 조작 전부 읽기**: `git fetch`(객체 읽기)·`gh api` GET·ls-remote·smudge-skip 클론만 수행, mutation 0회
- 아카이브 refs 취득: `git fetch --no-tags https://github.com/Archright/Axiom-archive.git '+refs/heads/*:refs/remotes/archive/heads/*' '+refs/tags/*:refs/remotes/archive/tags/*' '+refs/pull/*/head:refs/remotes/archive/pull/*'`
  → **1,471 refs** (heads 112 · tags 85 · pull 1,274) · main tip `b4c08e94e1128cc6ae886289b56969b552fcaae6` (2026-11-06, "Merge pull request #1290 … work/e2-cutover-record")
- 아카이브 Actions: `{"enabled":false,…}` (동결) · 과거 runs 34,956건 [관측]
- 현행 PR refs 취득: origin에서 `refs/pull/*/head` → 41 refs (`refs/remotes/origin-pull/*`) — PR 번호 공간 1–8·10–42 (#9 부재)
- 참조 자료(사적 캐시, 읽기 전용): E7 `commit-map`(168행)·`pathspec-final.txt`(24항목), E2 pre-cutover bundle
  `Axiom_pre_cutover_20261106T024648Z.bundle` sha256 `4d50bfb636c97416dd227690032af17c1611e113f02570742a6df7f94313e849`
  (기록값과 재검증 일치) → `refs/pre-cutover/*` (112 heads + 85 tags, 13,228 commits)

## 7조건 판정표

| # | 조건 | 핵심 명령 | 관측 | 증명 범위 | 판정 |
|---|---|---|---|---|---|
| 1 | Repository ID 상이 | `gh api /repos/Archright/Axiom --jq .id` | **1448376585** ≠ 아카이브 **1182104685** (양쪽 GET 실측) | 관측 | **PASS** |
| 2 | 승인 트리만 | `git log --diff-filter=A` (E2-117 재구성·E7-24) | 활성 브랜치 refs 이력·tip 잔존 **0** (E2-117은 현행 전체 refs에서도 **0**) | 관측+추론 | **PASS** (잔존 1건: §조건2 — 아카이브 무관) |
| 3 | 이력 독립 (3단계) | `comm -12 <(rev-list …)` | **S_main=0 · S_all=0 · S_pull=0 · S_total=0** | 관측 | **PASS** |
| 4 | 브랜치·태그 승인 목록 | `git ls-remote …/Axiom.git` | 브랜치 3(main·axiom/certificates·axiom/evidence-cas) · **태그 0** · PR refs 41 | 관측 | **PASS** |
| 5 | 비계승 (a–e 분리) | 아래 상세 | 5a–5e 각각 관측 PASS | 관측 (5a는 제한 명시) | **PASS** |
| 6 | 구 저장소 실행 의존성 부재 | `rg -l "Axiom-archive"` 실행 표면 | 실행 의존성 **0** (hit 1건 = 정책 산문 기록) | 관측 | **PASS** |
| 7 | 비공개·권한 경계 | `gh api` (rulesets·secrets·keys·hooks·org) | private · main bypass `[]` · secrets 0 · keys 0 · hooks 0 · org 기본 권한 read | 관측 | **PASS** |

## 조건별 상세

### 1. Repository ID 상이 [관측]

현행 `{"id":1448376585,"fork":false,"private":true,"default_branch":"main","created_at":"2026-11-06T14:42:31Z"}`,
아카이브 `{"id":1182104685,"private":true,"default_branch":"main"}` — 서로 다른 저장소 자원.

### 2. 승인 트리만 [관측+추론]

- **E2 매니페스트 원본 부재(정직 기록)**: E2 기록 매니페스트 `invert_paths_final.txt` (117행, sha256 `c5a5786f…`)는
  디스크에서 발견되지 않음(파일명 find + 내용 grep → E2/E6 문서 참조뿐).
- **117 경로 기계 재구성**: P_pre(pre-cutover bundle 13,228 commits에서 추가된 경로 23,677종) −
  P_post(아카이브 heads+tags 13,240 commits에서 추가된 경로 23,567종) = **정확히 117종** — E2 문서 행수와 일치.
  재구성 집합은 filter-repo가 세대에서 제거한 경로의 상위집합(정당 삭제 커밋은 양쪽에 모두 등장해 차집합에서 제외됨).
- **잔존 재스캔**: 현행 전체 refs(main·ledger 2·PR refs 41, 추가 경로 6,899종) ∩ E2-117 = **0**.
  E7 `pathspec-final.txt` 24항목(디렉터리 9 + 파일 15)은 **활성 브랜치 refs 이력 0 · main/ledger tip 트리 0**.
- **잔존 1건(재실측)**: `refs/pull/*` 경유로 **현행 저장소 자체의 E7 이전(pre-E7) 세대**가 도달 가능 —
  루트 `938a49e0…`("Axiom clean-origin root commit", 2026-11-06)은 main 미도달·pull/24 도달, 트리에 E7 제거 24항목 전부 존재.
  E7 문서 "잔여: refs/pull/*/head 구세대 잔존 = Support 티켓(Lane B2)"의 재실측 확인. 해당 세대는 아카이브 객체와
  무공유(S_total=0)이며 GitHub PR refs는 사용자가 삭제 불가 — 활성 표면(branches)이 아니므로 조건 2 판정은 PASS.
- **E7 검증 기록 대조**: E7 2차 재검증 (a) 제거 경로 0 (b) KEEP 존재 (c) 패턴 0 (d) 침소 0 + 신원·메시지 불변(161→161)
  중 (a)를 활성 refs에서 독립 재실시 — 0으로 정합. KEEP(§5e) 존재 정합.
- **[추론] 트리==E7 승인 세대**: 현행 main 루트 `6104b249…` = E7 commit-map 신규 루트 매핑(`938a49e→6104b249`) 일치 +
  E7 재작성 main tip `df378f60…`가 현행 main의 조상 + 잔존 0 → 현행 활성 트리는 E7 승인 세대의 직계.

### 3. 이력 독립 — 3단계 판정 [관측]

정의 — 현행 집합 C = rev-list(main 97 ∪ axiom/certificates 19, 루트 `23d99260` ∪ axiom/evidence-cas 59, 루트 `be75175e` ∪ PR refs 41) = **235 commits**.
아카이브 집합: A_main(archive/heads/main) 3,992 · A_all(heads 112+tags 85) 13,240 · A_pull(pull 1,274) 9,164 · A_total(전 refs 합집합) 18,413.

| 검사 | 교집합 | 실측 | 판정 |
|---|---|---|---|
| S_main (현행 main ∩ E2세대 main) | `comm -12 C_main A_main` (97∩3,992) | **0** | PASS |
| S_all (현행 전체 refs ∩ A_all) | 235 ∩ 13,240 | **0** | PASS |
| S_pull (현행 전체 refs ∩ A_pull — 구 세대 공유 tier-1 후보) | 235 ∩ 9,164 | **0** | tier-1 미성립 → PASS |
| S_total (현행 전체 refs ∩ A_total) | 235 ∩ 18,413 | **0** | tier-3(E7 전면 재작성→공유 0 기대) 일치 → PASS |

- tier-1 (S_pull≠∅ → 조상 계승 후보·SHA별 경위 조사): **성립하지 않음**(0) — 경위 조사 대상 없음.
- tier-2 (S_main/S_all≠∅ → E2 위생 세대 여부 확인): **성립하지 않음**(0) — "동일 객체 존재" 기록 대상 없음.
- 보강: tip-SHA 교집합(현행 41 ∩ 아카이브 1,274) = **0** · 현행 핵심 SHA 5종(pre-E7 루트 `938a49e`·pre-E7 PR #24 tip
  `8058d18f`·현행 PR #25 tip `032a0e64`·현행 루트 `6104b249`·현행 main tip `70d1b66f`)의
  아카이브 서버측 commits API 프로브 전부 **404**.

### 4. 브랜치·태그 승인 목록 [관측]

`ls-remote`: `HEAD`+`refs/heads/main 70d1b66f`·`axiom/certificates 56f3186c`·`axiom/evidence-cas 8428f63d` 3종,
`refs/tags/` **0건**, `refs/pull/*/head` 41건. (아카이브 태그: ls-remote 139라인 = 실 ref 85 + peeled `^{}` 54.)

### 5. 비계승 — a~e 분리 [관측]

- **5a isFork=false**: `fork:false`·`forks_count:0`·`parent:null`·`source:null`·`mirror_url:null`.
  **범위 한계 명시**: 이것은 'GitHub fork가 아님'만 증명한다 — 연결 부재(객체·실행·참조 전반)의 증명은 아니다.
  연결 부재는 조건 3·5b–5e·6의 독립 검사로 별개 입증된다.
- **5b 현행 PR 41 refs 전부 현행 커밋**: API `pulls?state=closed` 41건(PR #9 부재, open 0건)의 `head.sha` 전수에 대해
  `git cat-file -e <sha>^{commit}` → **missing 0**. 전부 현행 객체 공간 소속.
- **5c 구 PR 참조 비계승**: 현행 41 tip ∩ 아카이브 1,274 tip = **0** (객체 상호 배타). 번호 공간은 1–42 구간이 겹치나
  현행 번호 체계는 재생성 후 신규 발번(E6: "Gate 3 PR부터 신규 번호 체계") — 아카이브 PR #≤1290 참조와 무관.
- **5d Actions 비계승**: runs **636건 전수**(페이지네이션 완주) `html_url` 전부 `https://github.com/Archright/Axiom/` 경로,
  타 저장소 경로 **0건**.
- **5e LFS 독립**: 신규 클론 `/tmp/vsc-current-clone`에서 `git lfs pull` 성공 — LFS 파일 1종
  `docs/spec/SVF-SVC_Software_Verification_Using_SVF.pdf` (OID `8c744d79…61eaa`, 10,076,526B, 작업파일 sha256=OID 정합,
  `.git/lfs/objects/8c/74/…` 객체 실재). **현행 저장소 단독으로 해소됨.**
  아카이브 main에 동일 경로·동일 OID 포인터가 존재하나 이는 동일 CC-BY 콘텐츠의 내용 주소화 결과(E6 기록: 과거 실체
  blob도 동일 콘텐츠)이며 해소 경로가 아카이브 경유가 아님은 신규 클론 다운로드로 입증. 서버측 저장소 내부 공유 여부는 관측 불가(§하단).

### 6. 구 저장소 실행 의존성 부재 [관측]

`rg -l "Axiom-archive"` 실행 표면(`.github/ config/ tools/ src/ bin/ ci/ Makefile`) → **hit 1건**:

| 경로 | 분류 | 근거 |
|---|---|---|
| `config/policy/merge_admission.json` | **(ii) 문서·증거 기록** — 허용 | hit 위치가 `description`(v1.19.0)·`reRegistrationNote` 산문: 구 워크플로 id들이 아카이브에서만 해소된다는 **관측 기록**. 빌드·런타임·CI 입력 경로에 아카이브 참조 없음 — 라이브 fetcher는 이름 해석("main")·현행 id만 사용 |
| `docs/evidence/…` 3건(E6·b2m_1d_s2_provenance 2) | (ii) 증거 기록 — 허용 | 감사·증거 문서의 관측 서술 |

**실행 의존성 (i) = 0건** → PASS.

### 7. 비공개·권한 경계 [관측]

`private:true` · repo ruleset 6종 전 active, **main(26702792) `bypass_actors: []`** · org rulesets 2종
(axiom-admission-gate 25218071·landing-integrity 23943917) **bypass 0** · secrets **repo 0 · org 0** ·
deploy keys **0** · webhooks **0** · org `default_repository_permission: "read"`.

## 관측 불가(API) 목록 — 격리 주장의 범위 선언

아래 항목은 GitHub API/표면으로 관측할 수 없으므로 본 audit의 주장 범위 밖이다:

1. **서버 내부 캐시·객체 저장소의 unreachable 객체** — refs 기반 rev-list와 commits API는 refs 도달 객체 중심;
   서버측 도달 불가 객체의 존재 여부(스팟 프로브 5종 404로 부분 보강)
2. **cross-repo 내부 참조** — GitHub 내부 조인·백링크 상태
3. **fork 네트워크 내부 상태** — `isFork`·`parent`·`source` null 이외의 네트워크 그래프 내부 데이터
4. **LFS 서버측 저장소 간 중복 제거** — 동일 OID의 서버측 물리 저장 공유 여부(현행 단독 해소는 입증됨)

**격리 주장은 위 관측 가능 표면에 한정된다.**

## 최종 판정

```
CLEAN_ORIGIN_ISOLATED
```

- 7조건 전부 관측 PASS (조건 2·5는 분리 검사 a–e 및 활성/PR refs 표면 구분 포함).
- 잔존 기록(판정 무관·추적): (1) 현행 `refs/pull/*`의 pre-E7 세대 잔존 — E7 문서의 Support 티켓(Lane B2) 대기 항목
  재실측, 아카이브 무공유. (2) E2 매니페스트 원본 파일 부재 — bundle 대조 재구성으로 행수 117 정합 확인.

## Completion Evidence (명령 → 관측 → 판정)

| 명령 | 기대 | 실측 |
|---|---|---|
| `gh api /repos/Archright/Axiom --jq .id` | 1448376585 | 1448376585 |
| `comm -12 C_main A_main \| wc -l` | 0 | 0 |
| `comm -12 C_full A_total \| wc -l` (S_total) | 0 | 0 |
| 현행 PR head `cat-file -e` missing | 0 | 0 |
| `rg -l "Axiom-archive"` 실행 의존성 | 0 | 0 (산문 기록 1건 별도 분류) |
| Actions runs 타 경로 URL | 0 | 0 (636/636 현행 경로) |
| 신규 클론 `git lfs pull` + sha256=OID | 일치 | 일치 (8c744d79…61eaa) |

관측 시각(UTC): 2026-11-09T05:20–05:55 · 관측 도구: gh api(GET)·git(fetch/ls-remote/rev-list/cat-file/ls-tree)·git-lfs 3.4.1
