# E5 — PR Refs Exposure Scan Report (Gate 2-E5, Pre-Rewrite)

**스캔 일시**: 2026-11-05. **방법**: `git clone --mirror <원본 로컬 경로> /tmp/ax_prrefs.git`(하드링크 클론 — 원본 무변경) → `git fetch origin '+refs/pull/*/head:refs/remotes/pull/*' '+refs/pull/*/merge:refs/remotes/prm/*'`(fetch 10초, mirror 144MB). gitleaks 8.30.1 자체 설치(/tmp/gitleaks_pr). **READ-ONLY 준수 — 원본·원격 무변경**(종료 시 porcelain 빈 출력·HEAD `73e1a792e` 불변·ref 714개·PR refs 0개).

## 1. PR refs 확보 결과

- `refs/pull/*/head` **1,265** + `refs/pull/*/merge` **1**(PR #1274 — 열린 PR 1개만 merge ref 존재, GitHub는 닫힌 PR의 merge ref 삭제). merge-queue 5 refs는 현재 원격 부재(일시적 refs). 인증 실패 없음.
- 태그 ls-remote 139라인 = 실질 89(annotated peel 라인 포함)·브랜치 110 — 누락 0(E1 측정과 결론 일치).

## 2. PR 전용 커밋 성격

- 집합: PR refs 도달 커밋 A=5,227 ∩ 원본 `--all` B=13,595 → 공통 4,951, **PR 전용 276개**(78개 PR 분산).
- 시기 2026-08-04 ~ 2026-11-05(PR flow 전 기간). 저자: wintrover 173 / Axiom Agent 90 / dependabot[bot] 7 / Suhyok Yoon 6.
- 상위 PR: #3(39) #50(38) #7(30) #8(15) #4(11) #23(10) #22(10) #10(8) — 상위 15 중 14는 `closed merged=true`(**squash/rebase-merge 잔여** — 커밋이 main에 없음), #25·#1280은 `closed merged=false`(폐기). PR #1280이 PR 전용 최신 커밋.
- 파일 규모: diff 경로 574종(nim 522·json 218·md 161·yml 96), 신규 blob 1,095개 — **전수 매직 검사 전부 텍스트, 바이너리 0**. PR #2(폐기 359패치) head 총 1,059커밋은 전부 로컬 refs 보유(비-PR전용).

## 3. 비밀 스캔 결과 — 사중 독립 검증

`gitleaks git --log-opts="--all"`(12,333 비머지 커밋·505MB·30초) — **총 findings 4,882**(generic-api-key 4,875 + jwt 7):

- **PR 전용 한정 실자격증형 0건·합성 0건** — 276개 PR 전용 커밋에서 findings 전혀 없음.
- findings 4,882 전부는 로컬 refs 공유분(3,085개 커밋): CI 산출 sha256 증거키 4,875 + `data/golden/admission_landing/jwt.*.txt` 골든 픽스처 7(kid=`axiom-admission-test-01`) — 전부 비자격증형/합성. E1 스캔과 규모 동일·독립 재현(bytes 상이).
- **삼중 보강**: (a) PR #1280 조상 전체 타겟 재스캔(199MB, findings 1,164)도 PR 전용 0건 (b) PR 전용 신규 blob 1,095개 자체 정규식 스캔(`ghp_`·`github_pat_`·`AKIA`·`PRIVATE KEY`·`sk-`·`xox`·`AIza`·`/home/`·`Axiom_Enterprise`) **0 hit** (c) A−B 집합 차분상 PR ref 도달 커밋은 B 또는 276에 전속 — PR-ref 전용 비밀 존재 불가 구조.
- **음성컨트롤 판정**: PR #1280 head `4eb4ca29`("nc: root violation probe (P7 admission negative control)", 2026-11-05)는 `debug_real.nims` 1줄 텍스트 — P7 admission 정책 게이트용 픽스처, 비밀 주입 아님. gitleaks 0건은 정상 동작(극장 아님). probe/s3 4요건 분류 대상 중 PR 측 발생 0건.

## 4. 공개금지 자료 잔존 — 재작성 커버리지 검증

**PR 전용 커밋이 새로 추가한 금지자료: 0** (PDF/ELF/ZIP/바이너리 blob 0, 경로노출 패턴 0, 신규 JSON 2개 `config/policy/epoch_manifest.json`·`data/feature_manifest.json` 내용 검사 clean).

PR refs 계열 잔존(blob 도달성 전수 차분 — 카탈로그 197종):

| 계열 | PDF 실체 17 | ELF 23 | ZIP 1 | JSON(버전) |
|---|---|---|---|---|
| PR refs 도달 | 16 | 14 | 1 | 143(type_registry 137 포함) |
| 로컬 refs 도달 | 17 | 23 | 1 | 156 |
| **PR-exclusive** | **0** | **0** | **0** | **0** |

- PDF 21 경로(기지 사실과 일치): main HEAD 18경로(**PR 전용 276 트리 전부에 LFS 포인터 131~133B로 존재 — 실 내용 없음**) + 삭제 3경로(콜론 변체 2·dempster_shafer). 실체 blob 16종은 공유 main 이력 경유로 PR refs 도달 가능(예외 1: `propositions-as-types.pdf` 실체는 로컬 전용).
- ELF 23·session ZIP: PR 전용 트리에 경로 0(2026-08 이전 삭제). blob은 14·1종이 PR refs 이력 도달 가능(나머지 ELF 9·JSON 13버전·PDF 1은 로컬 전용).
- JSON 침소 후보 8 blob: PR 전용 트리의 JSON blob은 전부 카탈로그 기존 버전(신규 버전 0). 경로별 잔존: `type_registry_metadata.json` 276/276, act2-wp3c manifest 164/276, attribution×2 9·8, rearm 2, runs.jsonl 2. h2 실험 JSON 4종은 로컬 전용.
- **커버리지 판정**: PR refs에서 발견된 금지자료 경로는 전부 기존 invert-paths/replace-text 목록(PDF 21+ELF 23+JSON 8+ZIP 1·kimi-export 2)과 일치 — **PR 전용 때문에 추가해야 할 경로·blob 없음**.

## 5. 판정 — PR refs의 재작성 편입 필요성 (측정 근거)

**로컬만 재작성(force-push) 시 `refs/pull/*/head` 1,265가 174종 금지 blob(PDF·ELF·ZIP·JSON 계열)을 계속 보존·fetch 가능 상태로 유지한다.** 실제 접근 차단은 PR refs의 Support dereference("cached views and references… in pull requests" — GitHub 공식 문서 명시 항목) 또는 저장소 삭제·재생성이 전제된다. 본 스캔이 §4(잔존 접근 경로 처리) Support 티켓의 정량 근거(174종 blob·PR ref 수)를 제공한다.

## 6. UNKNOWN·한계

- (a) gitleaks 스캔 커밋 수 12,333 vs 비머지 12,532(Δ199 — 빈 diff 커밋 추정, 전 blob 내용 스캔으로 보정) (b) JSON 8의 blob-수준 SSOT 파일 미발견(경로·blob 기준 검증으로 우회 — 결론 불변) (c) 78개 PR 중 16개만 상태 샘플링 (d) mirror refspec 이중 착지(분석 무영향).

## 7. 신뢰도·산출물

**신뢰도**: PR 전용 비밀 0·신규 금지자료 0·PR-exclusive 금지 blob 0 = **HIGH**(독립 스캔 + 타겟 재스캔 + 전 blob 정규식 스캔 + blob 도달성 전수 차분의 사중 검증). PDF 21경로·ELF 23 카탈로그는 사전 단계 산출물과 OID 단위 교차 확인.

**분석 산출물(사적 보관)**: PR 전용 커밋 목록(276)·PR별 분포(78)·트리 히트 TSV·PR refs 도달 금지 blob 목록(174)·로컬 도달 목록(197)·금지 경로 목록(43)·PR refs gitleaks 재스캔 JSON(4,882).
