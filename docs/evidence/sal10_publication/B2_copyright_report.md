# B2 — Copyright & Development History Report (SAL 1.0 Publication Readiness, Gate 1-R3)

**기준**: 로컬 클론 HEAD `73e1a792e`(2026-11-04), tracked 파일 전수. 조사 중 원격 진행 관측(origin/main → `201ac6c54`, PR #1281) — 수치는 측정 시점·기준 ref 고정. READ-ONLY(저장소 무변경).
**갱신(2026-11-05)**: fetch 후 `rev-list --all` 13,572→13,595(+23: 인간+4·AI+7·CI+12, 신규 identity 없음). 본 보고서 수치는 `73e1a792e` 기준 고정값.

## 1. 저작권 표기 전수 목록

방법: `git grep -n -i 'copyright'`·`'all rights reserved'`·`'©'`(`-E '\(c\)'`은 CI 주석 노이즈 수천 건으로 비권장). NOTICE/AUTHORS/COPYING 파일 없음(`LICENSE`, `vendor/ed25519/ed25519/license.txt`만 존재).

**자사 표기 — "Archright Project" 문자열은 정확히 3곳**:

| 위치 | 문구 | 비고 |
|---|---|---|
| LICENSE:1 | `Copyright (c) 2026 Archright Project. All rights reserved.` | 저작권 행 |
| LICENSE:3 | `...proprietary property of the Archright Project.` | 권리자 단정 행 |
| README.md:80 | `Copyright (c) 2026 Archright Project. All rights reserved.` | 저작권 행 |

연관 행: LICENSE:4 전면 복제 금지 조항, LICENSE:6 면책("THE AUTHORS OR COPYRIGHT HOLDERS"), README.md:81-82 금지 문구, `axiom.nimble:2` `author = "Archright"`, `:3` description(브랜드), `:4` `license = "Proprietary"`.

**제3자 표기 — 변경 제외, 원래 권리자 유지 (10곳 + PDF 21종 + tarball)**:

| 위치 | 권리자·문구 |
|---|---|
| `vendor/ed25519/ed25519/license.txt:1` | Orson Peters 2015 (zlib — 조항 3: notice 제거·변경 금지) |
| `vendor/ed25519/ed25519.nimble:4,6` | nim 바인딩 author "niv"·MIT |
| `tests/fixtures/bug_verdict_scope/base36_pinned_subject.nim:1-7` | Status Research & Development GmbH 2025, Apache-2.0 OR MIT |
| `tests/unit/test_libp2p_bytesview_binding.nim:55` | Status Research 헤더 리터럴(기대 헤더 검증용) |
| `experiments/nim-libp2p-bytesview-slice-e2e/discovery/04_c2_fact_reverification.md:7,95` | Status Research 헤더 인용 |
| `experiments/act2-wpi-structural-ingress/canonical/signature_corpus{,_run1,_run2}.json:1` | "Nim Authors 2017 / Status Research 2019" 헤더 스니펫 |
| `experiments/.../canonical/corpus_README.md:31` | "Nim copyright header" 기술 언급 |
| `experiments/act2-wp-toml-b1-input-integrity/env/toolchain.md:12`, `observations/raw/env.txt:14` | Andreas Rumpf "2006-2026"(Nim 툴체인 배너 캡처) |
| `docs/spec/*.pdf` 21종 | 제3자 논문(판정은 B1 §1-D) |
| `experiments/act2-wp-toml-b1-input-integrity/bsec/offline/deps.tar.gz` | status-im 3패키지(faststreams·serialization·stew) |

src/·tools/·config/·bin/에 저작권 헤더 없음(LICENSE 단일 집중형 구조).

## 2. "© 2026 Suhyok Yoon" 통일 변경 계획 (L1·L3 입력)

| 지점 | 현행 | 변경 |
|---|---|---|
| LICENSE:1 | `Copyright (c) 2026 Archright Project. All rights reserved.` | `Copyright (c) 2026 Suhyok Yoon. All rights reserved.` |
| LICENSE:3 | `...property of the Archright Project.` | `...property of Suhyok Yoon.` (라인 1과 동시 변경 필수 — 아니면 내부 모순) |
| README.md:80 | Archright Project 판 | `Copyright (c) 2026 Suhyok Yoon. All rights reserved.` |
| axiom.nimble:2 | `author = "Archright"` | `author = "Suhyok Yoon"` (:3 브랜드 유지 여부는 §8.5 연동) |

연도: 전 이력 2026-02-06~현재 → "2026" 단일 연도 충분. 제3자 10곳 표기·zlib notice·status-im 헤더는 불변. 부속: README.md:84 잔여 `# Short-circuit test marker` H1(라이선스 섹션 아래 노출) 공개 전 제거 검토.

## 3. 기여자 분류 명세 + 수치 재현 (기준 ref `73e1a792e`, --all 13,572)

총 13,572 = 5,706 + 3,863 + 3,993 + 10 (항등 검증 완료).

| 분류 | 기준 | identity 수 | 계 |
|---|---|---|---|
| 인간 | name ∈ {wintrover, Wintrover, Suhyok Yoon} AND email ∈ {wintrover@gmail.com, *+wintrover@users.noreply.github.com, wintrover@users.noreply.github.com, ∅} | 7 | **5,706** (3,135+1,292+1,208+54+12+4+1) |
| AI | name ∈ {Axiom Agent, Agent User, Diag Agent, Axiom Assistant, axiom-core-sentinel} AND 도메인 axiom.*/archright.*/test | 8 | **3,863** (2,236+996+555+42+26+4+3+1) |
| CI | GitHub App `[bot]` 접미 | 3 | **3,993** (github-actions[bot] 3,987 + axiom-ci-elastic[bot] 5 + dependabot[bot] 1) |
| 애매 | 이름-이메일 패턴 상충 | 2 | **10** |

**애매 10건 특정**: ① `wintrover <axiom@axiom.dev>` 9건(2026-10-22~23, dependabot automerge/rearm 슬라이스 — `1473e7449`·`1406ffa76`·`1ef2559ba`·`d38bc3898`·`244ec55dc`·`4c924eed2`·`884563954`·`881e007de`·`52962b806`) — 인간 이름 + "Axiom Agent" 대표 이메일 조합, 로컬 git identity 오설정 추정(메시지는 에이전트형 업무라 단정 불가). ② `Axiom CI Bot <wintrover@users.noreply.github.com>` 1건(`6a1841509`, 2026-09-25, sha-pin-validate probe) — 봇 이름 + 인간 이메일.

커밋 작성자 메타데이터와 저작권 귀속은 별개 사실 — §4 원칙(한정 허여)이 이 혼합을 흡수한다.

## 4. SAL §4.4 보증 문구 정합 판정 — 모순 없음(확인) + 보완 4건

- **정합**: 제3자 인벤토리가 실재하므로 "자신이 소유하거나 적법하게 허여할 권한을 보유한 범위" 한정 허여는 필수 조항. AI 3,863/인간 5,706 혼합 — "AI 부분 무보증 + AI 사용만으로 인간 기여 불제외"는 과잉·과소 보증 없이 사실과 정합.
- **보완**: (a) LICENSE:3-4 전면 금지 문구가 vendored zlib(재배포 허용+notice 보존 의무)·Apache-2.0 OR MIT 컴포넌트와 충돌 → L1 개정 + THIRD-PARTY-NOTICES 병행으로 해소 (b) Licensor 정의를 자연인 Suhyok Yoon으로 고정(Archright는 비법인 org명) (c) **2026-03-15~25 Apache-2.0 창 존재**(`4bd49ffc9` 도입 → `5a95c149f` "Apache-2.0→Proprietary, Archright Project" 전환; 그 이전 LICENSE 부재) — 당시 27파일 vs 현재 6,761파일(`git diff --stat` 6,779 files, +1,880,570/−2,744)로 실질 중첩 미미하나, 공개 이력상 Apache 허여 스냅샷 존재를 §4.4·§4.5(판정 3종)에 기술 (d) PDF 21종 재배포 권리 → B1 §1-D 판정표로 확정(KEEP 2·REMOVE 18·#19 자격).

## 5. 개발 기록 보존 판정 — 별도 보존 조치 3건 (E2 cutover 입력)

1. **가지치기**: filter-repo 기본 `--prune-empty=auto`는 제거 경로만 수정한 커밋 통째 삭제 → 전량 보존엔 `--prune-empty=never` 명시. 로컬 경로·자격증명 침소는 `--replace-text`(커밋 0건 제거, author·메시지 불변, SHA만 변경) 적합.
2. **사전 아카이빙**: 전 SHA 변경으로 docs/evidence 189파일·data의 SHA 인용 무효화 + GitHub merge 커밋 PGP 서명(verification "valid") 무효 → 재작성 직전 `git bundle --all` 원본 스냅샷 + SHA 매핑 문서(§2.5 coherent-generation 전환).
3. **실행 전제**: 현 클론은 shallow(`.git/shallow` 2항목) + 로컬 main이 origin 대비 11커밋 지연 → filter-repo는 shallow 클론 거부 → **fresh full clone에서 실행 필수**. `git-filter-repo` 미설치(설치 선행).

## 6. "Archright" 사용처 개요 — 총 494 파일 (§8.5 연동)

- **조직 식별자**: `@Archright/architect` CODEOWNERS(44+ 경로), org 워크플로 참조 `Archright/.github`(workflows 5파일·config/policy), 기본 리포 `Archright/Axiom`(src 6곳: `admission_cli.nim:33`·`cert_cli.nim:422`·`merge_cli.nim:142,165`·`admission_artifact.nim:45,72`·`evidence_ledger.nim:67`)
- **제품 브랜드**: `report_layout.nim:18-21` "ARCHRIGHT AXIOM ENGINE [Enterprise Alpha]"·"Archright Integrity Certificate", `axiom.nimble:3`
- **저작권자 명의**: 정확히 3곳(§1) — §2 변경 대상과 일치
- **생성 감사 데이터**(330+): docs/evidence 189·data/promotions 75+·data/ci_* — GitHub API 캡처의 org URL(역사 기록, 비변경)
- **문서·정책**: docs/spec 21·docs/adr 9·docs/agents 3·tools 26. bin/ 0건.
- §8.5 연결: Archright(GitHub org·브랜드) / Axiom(제품·CLI명) / Suhyok Yoon(저작권자·Licensor) 3중 구조 — 상표 조항은 이 관계와 "명칭 사용은 식별 목적" 진술 필요.

## 7. UNKNOWN (판정 관련 해소 완료)

1. ~~PDF 21종 vs 실측 18종 불일치~~ → **해소**: 21 = 현행 18 + 이력 전용 3(dempster_shafer·콜론명 2종 — R2a 경로·최초 커밋 확정).
2. §4.4·§8.5 전문이 저장소에 없음(외부 계획서) — 인용 문구만 대조함.
3. ~~PDF 18종 재배포 권리~~ → **해소**: B1 §1-D 판정표(2026-11-05).
4. Archright 상표 등록 여부 — 네트워크 확인 불가(상표 등록은 본 공개 작업 범위 외 — 사용자 판정).
5. 애매 9건의 실제 주체(인간 오설정 vs 에이전트 위장) — 메타데이터만으로 단정 불가(§3 기록으로 족함).
6. live drift — 수치 고정 기준 ref 명시로 해소(본 보고서는 `73e1a792e` 고정).
7. git-filter-repo 미설치 — cutover 전 설치(E2 실행 전제).
8. 2026-03-15 이전 무라이선스 상태(LICENSE 부재) — 공개 이력 노출 사실로 기록(§4-(c)).

## 8. 신뢰도·사용 명령 (read-only)

**신뢰도**: 수치 재현·저작권 표기 목록·Apache 이력 = 높음(전수 실측). 애매 10건 특정 = 높음(커밋 나열 확인). §4.4 = 사실 대조 높음(법률 해석은 원고·법률 검토 영역). filter-repo 거동 = 문서 지식 기반(미설치 실측 불가, 중간). Archright 494파일 = 디렉터리 분포+대표 샘플 기반(중간-높음).

**사용 명령**: `git shortlog -sne --all` · `git log --all --format='%an <%ae>' | sort | uniq -c | sort -rn` · `git rev-list --count --all` · `git grep -n -i 'copyright'` · `git grep -l 'Archright' | wc -l` · `git log --follow -- LICENSE` · `git show 4bd49ffc9:LICENSE | head -4` · `git diff --stat 4bd49ffc9 HEAD | tail -1` · `wc -l < .git/shallow`
