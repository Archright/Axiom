# B0 — 과거 Apache-2.0 공개 이력 조사 보고서

- **문서**: `B0_historical_license_report.md`
- **작업**: SAL 1.0 공개 준비 — Gate 1-R1 (과거 Apache-2.0 공개 이력 조사 완결)
- **대상 저장소**: `Archright/Axiom` (repo ID **1182104685**, 현재 PRIVATE)
- **조사 기준 시점**: 2026-11-05 (KST)
- **조사 방식**: READ-ONLY — 로컬 clone·GitHub 원격·외부 데이터원 모두 무변경. 산출물은 본 보고서뿐.
- **데이터원**: GitHub REST API(`gh api`, 인증 스코프 admin:org·gist·repo·workflow), GH Archive(`data.gharchive.org`), Wayback Machine CDX API(`web.archive.org`), 로컬 git 객체 DB(읽기 전용 조회)

## 결론 요약

| 판정 | 결정 |
|---|---|
| PUBLIC_APACHE_PUBLICATION_CONFIRMED | **성립** — 2026-03-15 03:28:37Z(Devlog명으로 생성) ~ 최소 2026-03-23 02:31:24Z까지 public 관측, 해당 기간 공개 트리의 LICENSE는 Apache-2.0 |
| EXTERNAL_RECIPIENTS_UNKNOWN | **유지** — 확인 가능한 모든 채널(fork·아카이브·코드 검색)에서 외부 수령 증거 0건이나, 익명 clone 배제 불가 |
| LEGACY_APACHE_RIGHTS_MUST_BE_PRESERVED | **유지** — 창 내 적법 수령자의 Apache-2.0 권리는 2026-03-25 Proprietary 전환으로 소급 박탈되지 않음 |

---

## ① 조사 방법 · 증거 (명령 + 출력 발얬)

### 1.1 관측 환경

| 항목 | 값 |
|---|---|
| 인증 | `gh auth` (스코프: admin:org·gist·repo·workflow) |
| API 잔여(관측 시점) | core 2070/5000, search 30/30 |
| GH Archive 파일 | `2026-03-15-3.json.gz` (39,701,341B, gzip -t OK) · `2026-03-23-2.json.gz` (37,223,749B, gzip -t OK, 최종 재현) · `2026-03-24-0.json.gz` (41,581,368B) |
| 로컬 clone | `main` 브랜치 — commit 3,960개, 읽기 전용 조회만 수행 |
| 다운로드 제약 | 대역폭 ~150KB/s — 03-23 hour 3 이후~03-25 시간대 파일 미스캔(⑤-2의 UNKNOWN 원인) |

### 1.2 핵심 증거

**(a) 저장소 현황 — 2026-11-05 관측**

```console
$ gh api repos/Archright/Axiom --jq '{private, created_at, forks_count, open_issues_count}'
{"created_at":"2026-03-15T03:28:36Z","forks_count":0,"open_issues_count":1,"private":true}
$ gh api repos/Archright/Axiom/releases --jq 'length'       → 0
$ gh api repos/Archright/Axiom/collaborators --jq 'length'  → 1
$ git show HEAD:LICENSE | head -2 ; git show HEAD:LICENSE | wc -l
Copyright (c) 2026 Archright Project. All rights reserved.
6
```

**(b) 공개 생성·초기 push — GH Archive `2026-03-15-3.json.gz`**

```console
$ zcat 2026-03-15-3.json.gz | grep -i archright          # 4 events
{"id":"9410781816","type":"CreateEvent","actor":{…"login":"wintrover"…},
 "repo":{"id":1182104685,"name":"Archright/Devlog","url":"…/Archright/Devlog"},
 "payload":{"ref":"main","ref_type":"branch","master_branch":"main",
   "description":"An engine that captures and visualizes the 'Thought Trajectory' of architects,
    transforming conversation contexts and git histories into high-integrity devlogs."},
 "public":true,"created_at":"2026-03-15T03:28:37Z","org":{"id":268288440,"login":"Archright"}}
{"type":"PushEvent","created_at":"2026-03-15T03:36:52Z","payload":{"before":"47702f0f…","head":"c8678060…"}}
{"type":"PushEvent","created_at":"2026-03-15T03:38:13Z","payload":{"before":"c8678060…","head":"0f02924f…"}}
{"type":"PushEvent","created_at":"2026-03-15T03:39:38Z","payload":{"before":"0f02924f…","head":"c23b3922…"}}
```

- `repo.id` 1182104685 = 현재 `Archright/Axiom`의 repo ID → **동일 저장소 확인**. 생성 시 이름은 **`Archright/Devlog`**(이후 Axiom으로 개명, ② 참조).
- 03:39:38Z push head `c23b3922…`는 로컬에 실재하며 트리에 Apache-2.0 포함:

```console
$ git log -1 --format='%H %aI | %s' c23b392248e210778f64f33b24d5fff5072b593d
c23b392248e210778f64f33b24d5fff5072b593d 2026-03-15T12:37:50+09:00 | chore: apply Apache License 2.0 and update nimble metadata
$ git show c23b3922:LICENSE | head -2 ; git show c23b3922:LICENSE | wc -l
                                 Apache License
                           Version 2.0, January 2004
201
$ git cat-file -t 47702f0f… c8678060… 0f02924f…     → 전부 ABSENT(현 clone에 부재)
```

→ **공개 첫날 03:39:38Z 시점 트리에 Apache-2.0 LICENSE(201행 전문) 존재.** push의 `before` 3-SHA가 현 객체 DB에 부재 = head 계보에 포함되지 않음 → 해당 push는 non-fast-forward(강제 이력 교체·import — ⑤-4 참조).

**(c) 마지막 공개 관측 — GH Archive `2026-03-23-2.json.gz` (본 조사 완결 재현, gzip 검증)**

```console
$ zcat 2026-03-23-2.json.gz | grep -i archright          # CI_LINES: 9
PushEvent   2026-03-23T02:01:26Z  repo=Archright/Axiom  before=7a849110e…  head=a644523892…
DeleteEvent 2026-03-23T02:05:40Z  ref_type=tag  ref=v0.1.0
DeleteEvent 2026-03-23T02:07:15Z  ref_type=tag  ref=v0.0.1
DeleteEvent 2026-03-23T02:07:20Z  ref_type=tag  ref=v0.0.4
DeleteEvent 2026-03-23T02:07:21Z  ref_type=tag  ref=v0.0.5
DeleteEvent 2026-03-23T02:07:22Z  ref_type=tag  ref=v0.0.6
DeleteEvent 2026-03-23T02:07:26Z  ref_type=tag  ref=v0.0.8
DeleteEvent 2026-03-23T02:07:28Z  ref_type=tag  ref=v0.0.9
PushEvent   2026-03-23T02:31:24Z  repo=Archright/Axiom  before=a644523892…  head=5bc66fbff…   ← 마지막 관측 이벤트
```

- 이 시점 이벤트의 저장소명이 `Archright/Axiom` → 개명은 [03-15 03:39:38Z, 03-23 02:01:26Z] 구간 내 발생.
- push 연속성(기계 검증): `a644523892 parent=7a849110e`, `5bc66fbff parent=a64452389` — 03-23 두 push 모두 fast-forward. 관측된 push head 4종(`c23b3922`·`7a849110e`·`a644523892`·`5bc66fbff`)은 전부 로컬 git에 실재하며 **태그 계보(윈도 라인) 소속**(1.2-g).
- `2026-03-24-0.json.gz` 전수 grep(대소문자 무시): Archright 관련 이벤트 **0건**.
- 03-23 03시 이후~03-25 시간대 파일은 미스캔(대역폭) → 해당 구간 UNKNOWN(⑤-2).
- 기존 조사 기록 "02:07Z까지 관측"은 본 재현에서 **02:31:24Z로 갱신**(03-23-2 파일 전수 기준).

**(d) Wayback Machine CDX — 전 5종 조회, 전부 HTTP 200 + 빈 배열 `[]`**

```console
$ curl '…cdx?url=github.com/Archright/Axiom&output=json&from=20260301&to=20260401'   → []
$ curl '…cdx?url=github.com/Archright/Axiom&matchType=prefix&output=json&limit=100'  → []
$ curl '…cdx?url=github.com/Archright/Devlog&output=json&from=20260301&to=20260401'  → []  (2회 실행, 최종 재확인 포함)
$ curl '…cdx?url=github.com/Archright/Devlog&matchType=prefix&output=json&limit=50'  → []
$ curl '…cdx?url=github.com/Archright&matchType=prefix&output=json&limit=100'        → []
```

→ 현재명·**개명 전 이름(Devlog)**·org 경로, 공개 창 포함 전 시기 어떤 URL 형태로도 **아카이브 스냅샷 0건**.

**(e) 외부 코드 검색 — 카나리 `axiomDebt`·`axiomEffect`**

```console
$ gh api 'search/code?q=axiomDebt&per_page=100' -H 'Accept: application/vnd.github.v3.text-match+json'
  → total_count 75 = Archright/Axiom 48건
                + the-omega-institute/trureturing 11파일 (아래 f에서 배제)
                + 만료 도메인명 목록 16건(cirosantilli/expired-domain-names-by-day-*·AdemMlayel/laravel — "AxiomDebt.com" 등 도메인명 나열)
$ gh api 'search/code?q=axiomEffect&per_page=100&page=1..6' …    # 6페이지 전수 × 2회 실행
  → total_count 583(관측 시점별 558→583 — 색인 생동 지표)
   = Archright/Axiom 558건(본 저장소) + 외부 25건(13개 저장소)
```

외부 25건 **전수 분류**(text-match 프래그먼트 대조) — 전부 우연 매칭:

| 분류 | 저장소 | 매치 내용 예 |
|---|---|---|
| PDDL/SAS+ 플래너 C++ 클래스 | `fai-saarland/probfd`, `Zdjinovi/SSAM_probfd` | `class AxiomEffectsProxy; class AxiomEffectConditionsProxy;` |
| 게임·앱 자체 식별자(TS/Rust/C++/JS) | `Oneirical/*`(4개), `TheLitis/AXIOM`, `cdd/bioassay-express`, `aikdna/kdna`, `julianosirtori/ecos-da-crise`, `AptlyClever/vellum` | `export type AxiomEffect = "clarity" \| …`, `pub struct AxiomEffects{…}` |
| 만료 도메인명·채팅 로그 | `cirosantilli/*`, `DanielNorstrom/TwitchChatModerationHelper` | `axiomeffect.com` 등 |

→ **Nim 파일 0건·Axiom 프라그마 구문(`{.axiomEffect: …}`·`{.axiomDebt: …}`) 0건 → Axiom 코드 사본 없음.** (대조 기준: 본 저장소 내 카나리 밀도 — `axiomEffect` 561파일/2,880출현, `axiomDebt` 52파일)

**(f) `the-omega-institute/trureturing` 배제 근거 (axiomDebt 외부 매칭의 실체)**

```console
$ gh api repos/the-omega-institute/trureturing --jq '{created_at, fork, language, owner: .owner.login}'
  → created_at 2026-07-10T18:31:21Z, fork:false, language:"Lean"      # 공개 창 종료 약 3.5개월 후 생성
$ gh api 'repos/the-omega-institute/trureturing/commits?path=D5/X_Assumptions/AxiomDebt.lean'
  → 최초 2026-07-12T15:17:49Z … 2026-08-13T23:38:29Z "remove discharged axiom debt" (이후 파일 제거)
$ gh api 'repos/the-omega-institute/trureturing/git/trees/dev?recursive=1'
  → entries 56,647(truncated) 중 .nim 파일 0개 · AGENTS.md·LICENSE는 자체 내용
$ gh api 'repos/the-omega-institute/trureturing/commits?per_page=8' --jq '.[].commit.author'
  → loning(<third-party-author>·<third-party-author>) 등 — wintrover(Axiom 유일 작성자)와 무관
```

→ 제3자 Lean 프로젝트(2026-07-10 생성). "AxiomDebt"는 자체 개념(미증명 고전 공리 가계부 — 자체 AGENTS.md 2회 언급, 중국어 자체 서술). **Axiom(Nim) 코드 사본 없음 → 외부 수령자 아님.** 용어 수렴 원인은 UNKNOWN(⑤-6).

**(g) 이력 forensics — 이중 계보 관측 (공개 창 이력 ≠ 현 main 이력)**

```console
$ git rev-list --max-parents=0 v0.1.2        # 윈도 라인 루트
b3d081b1a… A:2026-02-06T19:45:57+09:00 C:2026-02-23T23:43:46+09:00 | init: initial commit with language-neutral guidelines
$ git rev-list --max-parents=0 HEAD           # 현 main 루트(1개)
5ddd11b23… A:2026-02-06T19:45:57+09:00 C:2026-02-23T23:43:46+09:00 | chore(init): bootstrap project with language-neutral guidelines
$ git merge-base v0.1.2 HEAD                 # (출력 없음 — 공통 조상 0: 두 계보는 완전히 별개)
$ git merge-base --is-ancestor <sha> HEAD / v0.1.2
  c23b3922(03-15 push head)       → in_main=NO   in_window_line=YES
  4bd49ffc(현 main Apache 적용)   → in_main=YES  in_window_line=NO
  5a95c149f(현 main Proprietary)  → in_main=YES  in_window_line=NO
  7a849110e·a644523892·5bc66fbff(03-23 push heads) → in_main=NO  in_window_line=YES
$ git log --format='%aI' v0.1.2 | sort | sed -n '1p;$p'
  2026-02-06T19:45:57+09:00 … 2026-03-25T22:15:30+09:00     # 윈도 라인 98커밋 전부 02-06~03-25 author date
$ git log --format='%aI' | awk '$0 < "2026-03-26"' | wc -l   → 31   # 현 main의 03-26 이전 author date 커밋
```

**관측된 사실(해석 배제)**:

1. 공개 창에서 관측된 push head 전부가 태그 계보(`v0.0.1`~`v0.1.2`가 가리키는 라인) 소속 — 현 `main`에는 어느 것도 속하지 않음.
2. 두 계보의 루트는 **동일한 author/committer 시각**(2026-02-06T19:45:57+09:00 / 2026-02-23T23:43:46+09:00)을 가진 별개 커밋.
3. 주요 마일스톤이 동일 시각에 별개 SHA로 양 계보에 존재 — Apache 적용(`c23b3922` 03-15 03:37:50Z ↔ `4bd49ffc` 03-15 06:36:44Z)·Devlog→Axiom 개명(`e80a8f82e` ↔ `02c54d069` 03-21 13:59:45Z)·Proprietary 전환(`18810d855`+`7436bae60` 03-25 11:28:40Z/11:34:00Z ↔ `5a95c149f` 03-25 11:34:00Z).
4. 현 main의 2026-03-26 이전 author date 커밋은 31개뿐(나머지 3,929개는 03-26 이후).

→ **현 main 이력은 공개 창 이력(태그 계보)과 별개로 재구성된 계보이며, 공개 창 원본 이력은 태그 refs(v0.0.1~v0.1.2)를 통해서만 도달 가능.** 추가 관측: 태그 `v0.0.7`·`v0.1.3`~`v0.4.11`·`v0.4.13`~`v0.5.1`(2026-03-26~08-27 태깅)은 main도 윈도 라인도 아닌 별개 중간 계보 — 반복적 이력 재구성 흔적. 기존 기록 "창 내 163커밋"에 정확히 일치하는 ref는 관측되지 않음(윈도 라인 v0.1.2=98, v0.1.4=159[03-31], v0.2.0=167[04-01]) → ⑤-5.

---

## ② 공개 창 타임라인

| 시각(UTC) | 사건 | 근거 |
|---|---|---|
| 2026-02-06T10:45:57Z | 양 계보 루트의 author date 원점(저장소 생성을 5주+ 선행) — 이력 import | `git rev-list --max-parents=0` (b3d081b1a·5ddd11b23) |
| 2026-03-15T03:14:00Z | `Archright` Organization 생성 | `gh api users/Archright` |
| 2026-03-15T03:28:36Z | 저장소 생성(API created_at) — 당시 이름 **`Archright/Devlog`** | `gh api repos/Archright/Axiom` |
| 2026-03-15T03:28:37Z | **CreateEvent(public)** — 설명 "Thought Trajectory 엔진… high-integrity devlogs" | GH Archive 03-15-3 (재현, repo ID 교차) |
| 2026-03-15T03:36~03:39Z | PushEvent 3건(public, Devlog명). **03:39:38Z head `c23b3922` 트리에 Apache-2.0 LICENSE(201행) 포함**(커밋 03:37:50Z). 해당 push는 non-fast-forward(이력 import) | GH Archive + `git show c23b3922:LICENSE` |
| 2026-03-15T05:42:24Z | org에 `.github` 저장소 생성(현재 public — 창 내 가시성 UNKNOWN) | `gh api orgs/Archright/repos` |
| 2026-03-15T06:36:44Z | (현 main 계보) `4bd49ffc` "apply Apache license and polish community documentation" — LICENSE 201행 추가 | `git log --follow HEAD -- LICENSE` |
| 2026-03-21T13:59:45Z | **Devlog→Axiom 개명**(코드 내 커밋: 윈도 라인 `e80a8f82e` / 현 main 미러 `02c54d069` — 동일 시각). GitHub 저장소 개명의 정확 시각은 UNKNOWN | git + GH Archive 이름 전환 관측 [03-15 03:39Z=Devlog, 03-23 02:01Z=Axiom] |
| 2026-03-23T02:01:26Z | PushEvent(public) — head `a644523892`(=현 v0.0.1 tip, fast-forward) | GH Archive 03-23-2 |
| 2026-03-23T02:05:40Z~02:07:28Z | **공개 태그 7종 삭제**(v0.1.0·v0.0.1·v0.0.4·v0.0.5·v0.0.6·v0.0.8·v0.0.9) — DeleteEvent ×7 | GH Archive 03-23-2 |
| **2026-03-23T02:31:24Z** | **마지막 외부 관측 이벤트**(PushEvent, `Archright/Axiom`, head `5bc66fbff`, fast-forward) | GH Archive 03-23-2 (본 조사 최종 재현·gzip 검증) |
| 2026-03-24T00:00Z~ | 03-24 hour 0 파일에서 Archright 이벤트 0건(이후 시간대 미스캔) | GH Archive 03-24-0 |
| 2026-03-25T11:28:40Z | (윈도 라인) `18810d855` "change license from Apache-2.0 to Proprietary" — **LICENSE Apache→Proprietary 전환**(v0.0.9 트리부터 Proprietary 확인) | `git log --follow v0.1.2 -- LICENSE` + 태그 트리 대조 |
| 2026-03-25T11:34:00Z | (현 main 미러) `5a95c149f` "migrate license from Apache-2.0 to Proprietary and rename to Archright Project"(LICENSE 201행→5행 + axiom.nimble) / (윈도 라인) `7436bae60` LICENSE 내 프로젝트명 변경 | `git show 5a95c149f --stat` |
| 2026-03-25T13:15:30Z | (윈도 라인) v0.1.2 tip(`8ebd9489`) — 라인 98커밋 전부 author date ≤ 2026-03-25 | git |
| 2026-03-25경 | **비공개 전환 확정**(기존 조사 기록). 정확 시각 UNKNOWN — 관측 bracket [03-23T02:31:24Z, 03-25T11:28:40Z 전후] | 종합 |
| 2026-03-26~ | 중간 계보 태그들(v0.1.3~v0.4.11 등, 03-26~08-27) — 반복적 이력 재구성 관측 | `git for-each-ref refs/tags` |
| 현재(2026-11-05) | private:true · forks 0 · releases 0 · collaborators 1 · LICENSE = Proprietary("Archright Project", 6행) | `gh api` + `git show HEAD:LICENSE` |

**공개 창 확정 구간**: 생성 **2026-03-15T03:28:37Z**(Devlog명) — 마지막 관측 **2026-03-23T02:31:24Z**.
**확실하게 공개+Apache-2.0이었던 기간: 2026-03-15T03:37:50Z ~ 2026-03-23T02:31:24Z**(트리·태그 트리·LICENSE 이력으로 기계 확인). 03-23 02:31:24Z~03-25 11:28:40Z 사이의 공개 지속 여부는 UNKNOWN(⑤-2) — 어떤 시나리오에서도 창 내 공개 콘텐츠의 라이선스는 전 기간 Apache-2.0이었음(Proprietary 전환은 03-25 11:28:40Z).

---

## ③ 외부 수령 증거

| 채널 | 관측 | 해석 |
|---|---|---|
| Fork | `forks_count = 0` (현재) | 포크 경유 수령 흔적 없음 — 단, **수령 부재의 증거 아님**(포크 없이 clone 가능) |
| Wayback | 5종 URL 변형(현재명·Devlog명·org prefix·기간 한정·전체) 전부 빈 배열 | 외부 아카이브 경유 증거 없음 |
| 코드 검색 | `axiomDebt` 75건·`axiomEffect` 583건 전수 분류 — 외부 매칭 전부 우연(도메인명·PDDL·게임 식별자), **Nim/Axiom 프라그마 사본 0건** | 확인된 외부 수령자 0 |
| trureturing | 제3자(작성자 loning)·2026-07-10 생성(창 종료 후 3.5개월)·Lean·`.nim` 0개·AxiomDebt.lean 2026-07-12~08-13 존재 후 제거 | **Axiom 코드 수령자 아님**(용어 수렴만 존재) |
| Collaborator | 1명(소유자 본인) — 창 시점 소급 검증 불가 | 조사 기간 협업 증거 없음 |
| (맥락) org 공개 저장소 | `.github`(2026-03-15 05:42Z 생성, 현재 public), `nim-libp2p`(2026-11-03, public fork) — Axiom 코드와 무관 | org 공개면 기록(가시성 이력 UNKNOWN) |

**결론**: 확인 가능한 모든 채널에서 외부 수령 증거 **0건**. 그러나 익명 clone은 원천적으로 관측 불가하므로 수령 부재를 주장할 수 없음 → **EXTERNAL_RECIPIENTS_UNKNOWN** 유지.

---

## ④ 판정 (3종)

### 1. PUBLIC_APACHE_PUBLICATION_CONFIRMED — 성립

- **공개 상태**: GH Archive public 이벤트 관측(CreateEvent 2026-03-15T03:28:37Z[Devlog명] + PushEvent 연쇄 + 마지막 관측 2026-03-23T02:31:24Z[Axiom명]) — 공개 이벤트는 비공개 저장소에서 발생 불가.
- **Apache-2.0 적용**: 공개 push 트리(`c23b3922`, 2026-03-15T03:37:50Z, LICENSE 201행 전문)·태그 트리(v0.0.1·v0.0.8 = Apache-2.0)·LICENSE 변경 이력(Apache 적용 03-15 → Proprietary 전환 03-25 11:28:40Z) — **창 내 공개 콘텐츠 전 기간 Apache-2.0**.

### 2. EXTERNAL_RECIPIENTS_UNKNOWN — 유지 (갱신 없음)

- `forks 0`은 수령 부재의 증거가 아님(익명 clone 배제 불가 — 구조적 한계).
- 코드 검색에서 실재 사본 0건 확인(외부 매칭 전수 배제) — "확인된 수령자 없음"은 관측 사실이나 "수령자 없음"의 증거가 될 수 없음.

### 3. LEGACY_APACHE_RIGHTS_MUST_BE_PRESERVED — 유지

- 창 내 적법 수령자가 존재했다면 그 시점의 Apache-2.0 권리(라이선스 고지·NOTICE·수정 여부 고지·§4 조건부 특허 대항 등)는 2026-03-25의 Proprietary 전환(`18810d855`/`5a95c149f`)으로 **소급 박탈되지 않음**.
- **설계 전제(SAL 1.0 공개 시)**: (a) 과거 Apache-2.0 수령 권리를 침해하지 않는 범위에서 권리 보존, (b) "2026-03-15~03-25 공개 창 콘텐츠 = Apache-2.0 / 이후 = Proprietary(현 라이선스)" 경계를 공개 문서에 명시, (c) 제3자가 창 내 코드를 Apache-2.0 하에 재배포하는 시나리오에 대한 대응 절차(판정 근거 본 보고서 인용) 확보.

---

## ⑤ UNKNOWN 목록 (확정 불가 항목 — 명시적 기록)

1. **익명 clone 수령자의 존재·수** — 구조적으로 관측 불가 (EXTERNAL_RECIPIENTS_UNKNOWN의 직접 원인).
2. **비공개 전환의 정확한 시각** — 관측 bracket [2026-03-23T02:31:24Z, 2026-03-25T11:28:40Z 전후]. 03-23 hour 3~03-25 GH Archive 파일 미스캔(대역폭 제약). 태그 재생성(현 v0.0.2 tagger 03-23T03:34:26Z 등)이 공개 상태에서 이루어졌는지도 미관측.
3. **GitHub 저장소 개명(Devlog→Axiom)의 정확한 시각** — bracket [2026-03-15T03:39:38Z, 2026-03-23T02:01:26Z]. 개명은 GH Archive 이벤트를 발생시키지 않음. 코드 내 개명 커밋은 2026-03-21T13:59:45Z.
4. **2026-03-15 03:36:52Z/03:38:13Z 첫 2회 push 트리의 LICENSE 존재 여부** — 커밋 객체(`47702f0f`·`c8678060`·`0f02924f`)가 현 clone에 부재(03:39:38Z non-fast-forward push로 교체). 확정 가능한 것은 03:39:38Z head(`c23b3922`)부터 LICENSE 존재.
5. **기존 기록 "창 내 163커밋"의 산출 기준** — 현 관측: 윈도 라인 v0.1.2=98커밋(전부 author date ≤ 2026-03-25)·v0.1.4=159(03-31)·v0.2.0=167(04-01). 163에 정확히 일치하는 ref 미관측.
6. **trureturing의 "AxiomDebt" 용어 수렴 원인** — 우연/독립 발명/간접 영향 판별 불가(코드 사본 없음은 확인).
7. **코드 검색의 색인 한계** — fork·비기본 브랜치·미색인 저장소·비공개 저장소는 검색 불가 → "무매칭"이 수령 부재의 증거가 아님.
8. **`.github`·`Landing_Page` 저장소의 창 내 가시성 이력** — org 산하 별도 저장소(본 조사 범위 외).
9. **2026-03-23T02:31:24Z 이후~LICENSE 전환(03-25 11:28:40Z) 사이의 push 공개 여부** — 해당 구간 이벤트 미관측.
10. **collaborator 이력의 소급 검증** — 현재 1명(소유자) 관측만 가능, 창 시점 협업자 존재 여부 UNKNOWN.

---

## ⑥ 신뢰도

| 증거 | 신뢰도 | 근거 |
|---|---|---|
| 공개 창 존재(CreateEvent/PushEvent/DeleteEvent) | **HIGH** | GH Archive 파일 `gzip -t` 검증 + repo ID 교차(1182104685) + 로컬 git SHA 교차(`c23b3922`·`7a849110e`·`a644523892`·`5bc66fbff` 전부 실재·계보 일치) |
| 창 내 Apache-2.0 적용 | **HIGH** | 커밋 트리 LICENSE 전문(201행) + 태그별 트리 대조(v0.0.1/v0.0.8=Apache, v0.0.9+=Proprietary) + LICENSE 변경 이력 추적 |
| 마지막 외부 관측 2026-03-23T02:31:24Z | **HIGH(스캔 범위 내)** | 03-23-2 파일 전수 grep(9 이벤트, 2회 실행 일치). 범위 밖(03-23 h3+)은 UNKNOWN |
| 외부 코드 사본 부재(확인된 수령자 0) | **MEDIUM-HIGH** | 카나리 2종 총 658건 전수 분류(프래그먼트 대조) — 색인 한계 존재(⑤-7) |
| Wayback 무스냅샷 | **HIGH** | 5종 URL 변형 조회 전부 HTTP 200 + 빈 배열(Devlog명 포함) |
| 이력 재구성(현 main ≠ 공개 창 계보) | **HIGH** | merge-base 부재 + 동일 시각 루트 쌍 + push-head 계보 소속 + 3 SHA 부재 + 마일스톤 미러 |
| 비공개 전환 정확 시각 | **LOW** | bracket만 확보 |
| 기존 기록 "163커밋"치 | **LOW** | 재현 실패(관측치 98/159/167) |

---

## 부록 A: 사용 명령 전체 목록 (본 조사 — 전부 읽기 전용)

**원격 (gh api / curl)**
1. `gh api repos/Archright/Axiom --jq '{private, created_at, forks_count, open_issues_count}'`
2. `gh api repos/Archright/Axiom/releases --jq 'length'` / `gh api repos/Archright/Axiom/collaborators --jq 'length'`
3. `gh api rate_limit --jq '.resources | {core, search}'`
4. `gh api 'search/code?q=axiomDebt&per_page=100' -H 'Accept: application/vnd.github.v3.text-match+json'`
5. `gh api 'search/code?q=axiomEffect&per_page=100&page=1..6' -H 'Accept: application/vnd.github.v3.text-match+json'` (6페이지 × 2회)
6. `gh api repos/the-omega-institute/trureturing` / `users/the-omega-institute` / `user` / `users/Archright` / `orgs/Archright/repos`
7. `gh api 'repos/the-omega-institute/trureturing/commits?path=D5/X_Assumptions/AxiomDebt.lean'` / `commits?per_page=8` / `git/trees/dev?recursive=1` / `contents/AGENTS.md` / `contents/LICENSE`
8. `curl 'http://web.archive.org/cdx/search/cdx?url=github.com/Archright/{Axiom|Devlog|}&…'` (5종 변형, Devlog 기간 한정 2회)
9. `curl -I/-o 'https://data.gharchive.org/2026-03-{15,23,24}-<hour>.json.gz'` (HEAD·다운로드·이어받기)

**로컬 git (읽기 전용)**
10. `git log --reverse/--follow/--format` / `git rev-list --count [--before] [--max-parents=0]` / `git merge-base [--is-ancestor]` / `git cat-file -t` / `git ls-tree` / `git show <rev>:LICENSE` / `git for-each-ref refs/tags` / `git tag -l` / `git grep -l axiomEffect` / `git show <sha> --stat`

## 부록 B: 증거 원본 보존

- GH Archive 원본·매치 추출물: `/tmp/b0_gha/` (`2026-03-15-3.json.gz`·`2026-03-23-2.json.gz`·`2026-03-24-0.json.gz` + `.ci` 매치 파일) — 세션 한시적. 본 보고서의 명령+출력 발췌가 증거 기록의 정본 역할.
- 본 조사는 READ-ONLY로 수행됨: 로컬 저장소·원격 저장소·org 설정 무변경, 커밋·브랜치·파일 변경 없음.
