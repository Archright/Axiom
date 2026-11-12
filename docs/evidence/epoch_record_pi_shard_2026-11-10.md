# CI Epoch Record — publication-integrity license-scan 2-shard 병렬화 (epoch pi-shard): Freeze / Record / Tombstone

> **성격**: AGENTS.md §2.5(CI Epoch Cutover Protocol) 단계 1–3 — **FREEZE / RECORD / TOMBSTONE** 기록 문서. 변경 = `publication-integrity.yml`의 license-scan 차원을 내부 2-shard 병렬 스캔(`license-scan-shards`, matrix 2-레그) + 단일 병합·판정(`license-scan`) 구조로 개편. 목적은 스캔 wall-time 병렬화뿐이다 — **판정 표면은 전부 불변**(평가기 소스·정책 6종·액션 핀·ruleset required 6 contexts·aggregator 잡·차원 보고서 artifact). 스펙 §8 규칙에 따라 `docs/spec/publication_integrity_gate.md`(v1.0→v1.1) 개정이 본 커밋에 결속된다.
> **작성일**: 2026-11-10.
> **작업 브랜치**: `workstream/pi-license-shard` (clone-first — AGENTS.md §2.7).
> **결정 바인딩**: AGENTS.md §2.5·§2.6 · `docs/spec/publication_integrity_gate.md` v1.1(같은 커밋). 선례 구조: [epoch_record_s5_build_skip_2026-10-09.md](epoch_record_s5_build_skip_2026-10-09.md)(Freeze/Record/Tombstone 템플릿) · [epoch_record_mint_retention_2026-10-29.md](epoch_record_mint_retention_2026-10-29.md).

---

## 1. FREEZE (AGENTS.md §2.5 단계 1)

| 항목 | 값 |
|---|---|
| freeze tag | **`ci-frozen-2026-11-10-pi-shard`** — 원격 push 완료 (`git ls-remote origin refs/tags/ci-frozen-2026-11-10-pi-shard` == `f519fa11…`, 실측) |
| freeze 대상 commit | origin/main == 작업 기준 HEAD == **`f519fa11acf38aa4821fa5895e700a34a8088b96`** |
| 태그↔커밋 일치 | `git rev-parse ci-frozen-2026-11-10-pi-shard^{commit}` == `f519fa11…` — 일치 (실측) |
| frozen workflow blob SHA | **`b7274382cb05841fed695c09213d3cd39ec63283`** (`git rev-parse origin/main:.github/workflows/publication-integrity.yml`) |
| rollback 기준 | 위 blob — 복구 시 정확히 이 내용으로 되돌린다 |

## 2. RECORD (단계 2)

### 2.1 변경 요약 (본문 3파일, 단일 원자 커밋)

| 파일 | 변경 |
|---|---|
| `.github/workflows/publication-integrity.yml` | license-scan 섹션만 개편 (+113/−9, 401→505줄). **신규 `license-scan-shards`**: matrix `shard: [0, 1]`·`fail-fast: false`·timeout 45 — 결정적 round-robin 분할 (`git ls-files \| LC_ALL=C sort \| awk -v s="$SHARD" 'NR%2==s'`), xargs 단일 배치 스캔 (동일 venv 핀·`--license --copyright --processes 4`), per-shard 집합 자기검증 (입력 목록 == 방출 파일 경로 집합, `<workspace-basename>/` 접두어 제거 후 `comm -3` 비교), shard artifact `license-scan-shard-{0,1}` (retention 3일, `publication-report-*` 글로브 비매칭 — aggregator 미소비). **개편 `license-scan`**: `needs: [license-scan-shards]`·`if: !cancelled()` (shard 실패·취소에도 판정 잡이 실결론을 보고 — skipped=UNKNOWN 방지, 스펙 §2) — shard 다운로드 (`pattern: license-scan-shard-*`, artifact별 하위디렉터리) → jq 결정적 병합 (files concat + `sort_by(.path)`, 최상위 `license_detections` identifier별 `detection_count` 재집계, headers shard0 것) + **집합 완전성** (병합 파일 경로 집합 == `git ls-files` 집합·중복 0 — 집합 비교, 개수 비교 아님) → 이후 toolchain·판정·업로드 스텝은 **기존 바이트 그대로** (실측 §2.4). 헤더 POLICY 주석에 shard 구조 1문장 추가. 나머지 잡(secret-scan·dependency-scan·provenance·sbom·publication-integrity)·`on:`·`permissions:`·aggregator `needs` — **무접촉** |
| `docs/spec/publication_integrity_gate.md` | v1.0→v1.1 (같은 커밋 — §8 규칙). §2에 shard 구조 불릿 (판정은 단일 평가기·단일 병합 보고서 유지, "sub-job id = 차원 이름" 규칙은 판정 잡 `license-scan` 담당·shards는 내부 실행 구조), §3.2에 shard 병합 완전성 계약 (집합 동등·2-shard 미만 판정 진행 금지) |
| `docs/evidence/epoch_record_pi_shard_2026-11-10.md` | 본 기록 |

### 2.2 trust binding 불변 선언 (실측 — 본 커밋 변경 대상은 위 3파일뿐, 평가기·정책 0접촉)

| 요소 | 상태 |
|---|---|
| 평가기 `tools/ci/publication_license_eval.nim` | **무변경** (컴파일 sanity §2.4) |
| 정책 6종 (license-policy.yml·security-policy.yml·provenance-policy.yml·secret-scan-baseline.json·source-origin.yml·license-attribution.yml) | **무변경** |
| 액션 핀 | checkout `3d3c42e5…` / upload-artifact `cf430e03…` / download-artifact `9000827c…` — 기존 핀만 재사용, **신규 핀 0건** |
| ruleset required 6 contexts | **무변경** — required context `publication-integrity`는 aggregator 잡이 계속 발화 (잡 id·`needs`·스텝 전체 무접촉) |
| `license-scan` 잡 id·차원 보고서 artifact `publication-report-license-scan` | **존속** — 외부 계약 (스펙 §2·merge_admission RequiredChecks) 불변 |

### 2.3 기준선 실측 (변경 전 — 런 ID 명시)

| 런 | 관측 |
|---|---|
| run **42763362975** / job 129654022349 | 스캔 1149s·toolchain 83s·adjudicate 34s·venv 28s·**잡 wall 1310s** |
| run **42752274862** / job 129618429213 (이전 런) | 스캔 1525s·**잡 wall 1659s** |

스캔 스텝이 잡 wall의 지배 항(~88%)이므로 병렬화의 이론 상한은 `max(shard 스캔 wall) + (venv·toolchain·병합·판정)`이다. round-robin 분할의 실행 시간 균형은 가정하지 않고 acceptance 실측 대상이다 (§4).

### 2.4 로컬 검증 (본문 커밋 전, 워킹트리 실측)

- **평가기 컴파일 sanity**: `nim c --hints:off --warnings:off --path:. --path:src -o:/tmp/vsi_license_eval_check tools/ci/publication_license_eval.nim` — **exit 0** (decision-binding WARN 51건은 본 변경 무관의 기존 경고).
- **YAML 파싱**: `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/publication-integrity.yml'))"` — **OK** (505줄).
- **구조 검증** (파싱 후 프로그램 판독): 잡 id 순서 [secret-scan, license-scan-shards, license-scan, dependency-scan, provenance, sbom, publication-integrity]·`license-scan` `needs: [license-scan-shards]`·`if: ${{ !cancelled() }}`·aggregator `needs` 5차원 불변·`strategy: {fail-fast: false, matrix: {shard: [0, 1]}}` — 전부 계약대로.
- **바이트 동일성** (프로그램 비교): `[adjudicate]`+`[evidence] upload dimension report` 스텝 (판정 잡 tail), `[tool]` venv 스텝 (shards 잡 이식) — origin/main 원본과 **바이트 동일**.
- **분할·xargs 안전성 실측**: 트래킹 경로에 공백·비ASCII·quotepath 대상 0건 → `git ls-files | LC_ALL=C sort | awk NR%2` 분할 + `xargs -a` 단일 배치가 안전. shard 크기 3287/3288 (워킹트리 6575경로 기준).
- **jq 병합 dry-run**: §2.5.

### 2.5 jq 병합 dry-run (live 전체 스캔 보고서 — `/tmp/pi-license-report/scancode.json`)

입력: live 보고서 (files 엔트리 7217 = file 6567 + directory 650, 경로 접두어 `Axiom/`, license_detections 108종·detection_count 합 171, 식별자 중복 0). files 배열을 3608+3609로 절반 분할한 **모의 shard 2개**를 생성했다 — license_detections는 identifier 정렬 후 짝수 인덱스 54종을 양 shard에 `detection_count` floor/ceil 분할 배치(재집계 group_by+합산 경로를 실제로 통과시키기 위함)하고 홀수 인덱스 54종을 27+27로 단독 배치했다. 이후 **워크플로의 병합 jq 식을 그대로** 실행:

| 검증 | 결과 |
|---|---|
| files 수 | 병합 7217 == 원본 7217 — **일치** |
| 경로 집합 | 원본과 **동일** (LC_ALL=C sort 비교 diff 0) |
| 중복 경로 | **0** |
| 파일 엔트리 deep-equal | 원본 `sort_by(.path)` 정규형과 sha256 **동일** — 병합이 엔트리를 불변 |
| headers | shard0 것 보존 == 원본 |
| license_detections | 식별자 **108종**·detection_count 합 **171** — 원본과 동일; (identifier, detection_count) 쌍 전수 일치; 엔트리 deep-equal |
| 공유 식별자 산술 스팟체크 | orig 1 = shard0 0 + shard1 1 = merged 1 — `group_by(.identifier)`+합산 경로 실증 |
| 결정론 | 병합 2회 실행 출력 sha256 **동일** |

모의 shard의 files 절반 분할은 모의일 뿐이며 실 shard 분할(round-robin)은 잡 안의 `git ls-files` 분할과 동일 논리로 결정론적이다. 최상위 `license_detections`의 `reference_matches`는 shard0 엔트리 것을 보존한다(합산되지 않음) — 이 키는 평가기가 소비하지 않는다(실측 — 평가기는 파일 엔트리의 인라인 검출 필드만 읽음)·형태 보존 목적. 명시적 파일 인자 스캔의 경로 방출 형식 등 **실측 퀴크의 확정은 J1(§4)이 담당**한다.

### 2.6 재구성 커밋 (2026-11-10 — rollback 대신 재구성, 판정 표면 불침범)

J1 iteration-1 FAIL(§4.6)을 받은 메인 에이전트 판정: 결함 1(다중 파일 인자 include
변환)·결함 2(`ignores_VCS` 미방출)은 **구현 메커니즘 단계 결함**이고 판정 표면(평가기
소스·정책·ruleset required 6 contexts·aggregator·차원 artifact·adjudicate 스텝)은
무손상이다 — §5 ROLLBACK(단일 revert)이 아니라 샤드 **실행 메커니즘 재구성**으로
착지한다. freeze 태그·tombstone은 무효화되지 않는다(폐기 대상은 "license-scan 차원의
내부 실행 구조"로 동일하며 재구성 후에도 단일 잡 직렬 스캔 토폴로지는 폐기 상태다).
PR 착지 전 workstream 내 반복은 §2.5 CI Epoch Cutover 절차의 내부 반복이다(활성
merge 경계 착지 전). 결함 3(본 문서 GPL-3.0-only 검출)은 평가기가 규정한 정공법인
attribution 회계로 해소한다(아래 표).

| 파일 | 변경 |
|---|---|
| `.github/workflows/publication-integrity.yml` | shard `[scan]` 스텝: round-robin `git ls-files` 분할 + xargs 파일 목록 스캔 → **SHA 결속 크기-그리디 2-분할**(`git ls-tree -r -l HEAD` blob − ScanCode `ignores_VCS` 평문 이름) + **스테이징 단일 루트 스캔**(PFX 명명 루트에 tar 스테이징 후 그 디렉터리 하나를 인자로 스캔 — 방출 `<PFX>/<rel>`이 frozen 단일 스캔과 동일 형식). merge `[merge]` 스텝: files 병합식에 경로 dedup(`group_by(.path)`) 추가(디렉터리 중복 제거)·완전성 기대집합을 동일 E 유도로 교체. per-shard 자기검증(comm -3)·duplicate 검사·SHARD_COUNT==2·adjudicate·venv 스텝·artifact 이름 — **불변** |
| `docs/spec/publication_integrity_gate.md` | v1.1→v1.2 (같은 커밋 — §8 규칙): §2 shard 구조 서술 갱신·§3.2 완전성 계약의 기대집합 정정(현행 `git ls-files` 집합 기술은 항상 FAIL인 기술 오류)·§5 퀴크 4건 추가(단일 디렉터리 인자 루트 의미론·`ignores_VCS` 정확한 이름 목록·스테이징 경로 방출 동일 형식·디렉터리 dedup/부재) |
| `docs/evidence/epoch_record_pi_shard_2026-11-10.md` | §2.6(본 절)·§4.7(iteration-2 기록 — 결과 확정 후 추가) |
| `compliance/provenance/license-attribution.yml` | 본 문서(§4 검증 계획이 GPL-3.0 전문 파일을 음성 제어 입력으로 언급 — §4.6 결함 3의 gpl-3.0-only 검출 매칭)에 대한 documentary-mention 회계 **additive 엔트리** 추가. §2.2의 "정책 6종 무변경"은 8ab6b83b 시점의 역사 기록으로 유효하다 — 본 재구성 커밋이 attribution을 additive 변경함을 명시한다(평가기 nim·license-policy.yml·source-origin.yml은 여전히 무변경) |

재구성 후에도 §3 TOMBSTONE의 fail-closed 불변식은 전부 유효하다: shard 보고서
2건 미만 판정 진행 금지·집합 완전성(기대집합은 스캔 가능 집합으로 정정)·중복 파일
경로·per-shard 표면 자기검증 — 전부 FAIL 경로로 존속한다.

## 3. TOMBSTONE (단계 3)

폐기되는 동작: **단일 잡 license-scan topology** — 한 잡이 전체 트리(`.`)를 직렬 스캔하고 그 자리에서 판정하던 구조. 폐기 범위는 license-scan 차원의 내부 실행 구조 정확히 하나다.

1. 본 Tombstone은 **required-check 제거가 아니다** — required context는 `publication-integrity`(aggregator)이며 그대로 발화한다. 판정 잡 id `license-scan`도 존속한다 (스펙 §2 "sub-job id = 차원 이름" 규칙 — 판정 잡 담당).
2. 본 Tombstone은 **게이트 우회(break-glass)가 아니다** — shard 보고서 수 ≠ 2·집합 불일치·중복 경로·per-shard 표면 불일치는 전부 FAIL(fail-closed)이며 조용한 부분 통과 경로가 없다. shard 중간물 artifact는 `publication-report-*` 글로브에 매칭되지 않아 aggregator가 소비하지 않는다.
3. 본 Tombstone은 **면제(waiver)가 아니다** — `config/decision_binding.waiver.*` 등록 없음 (본 변경 관련 면제 0건).
4. 본 Tombstone은 **검증 면제를 의미하지 않는다** — 병합·집합 완전성 검사가 오히려 도입되었으며 판정은 여전히 단일 평가기·fail-closed.
5. Tombstone은 역사적 폐기 기록이며 실행·검증 권한을 갖지 않는다 (AGENTS.md §2.5 Mandatory Invariants).

## 4. 검증 계획 (착지 판정 — J1·acceptance)

1. **J1 패리티**: 로컬에서 실 shard 스캔 2-레그 실행 → 병합 보고서 vs live 전체 스캔 보고서로 `tools/ci/tcb_judgments.nim` `--judgment parity --baseline <live> --candidate <merged>` 기계 판정 (exit 0=PASS / 2=JUDGMENT-FAIL).
2. **집합 완전성**: 병합 files 경로 집합 == `git ls-files` 집합·중복 0 — dry-run과 동일 검사를 실 shard 산출물에 적용.
3. **음성 제어**: GPL-3.0 전문 파일 첨가 → license-scan FAIL·게이트 차단 관측 (기존 음성 제어 규칙과 동일 — shard 구조가 차단 회귀를 만들지 않는지).
4. **production acceptance**: `workflow_dispatch` 전체 게이트 재실행 + 다음 merge_group에서 required 6 contexts 관측 — shard 2-레그 병렬 실행·병합·판정 통과·wall 개선 실측.
5. **측정 기록 위치**: `data/ci_optimization/` — J1 에이전트가 후속 커밋으로 생성·push (본 커밋 미포함).

### 4.6 J1 실측 결과 (2026-11-10, 로컬 기계 실측) — **FAIL**

같은 트리(`git archive HEAD` export, 트래킹 6576파일)에서 전체 스캔(`.`)과
워크플로와 동일한 shard 스캔 2-레그(round-robin 3288/3288, xargs 단일 배치 의도)를
실행하고, 워크플로 merge jq 식 그대로 병합해 §4.1·§4.2를 기계 판정했다.
증거 전문: `data/ci_optimization/pi_shard_j1_2026-11-10/`(summary.json·평가기 출력
2종·투영 맵 2종·completeness.txt).

| 판정 | 결과 |
|---|---|
| evaluator (full.json) | **FAIL** (exit 1) — `docs/evidence/epoch_record_pi_shard_2026-11-10.md`의 gpl-3.0-only 검출이 denied family·무회계 (본 문서 라인 89 "GPL-3.0 전문 파일" 음성 제어 언급이 매칭) |
| evaluator (merged.json) | PASS (exit 0) — **공허**: 병합 보고서가 파일 3개뿐인 스캔 표면 (아래 결함 1). 실 워크플로에서는 merge 스텝 완전성 검사가 판정 전 exit 1 |
| tcb_judgments parity | **exit 2** (6565 심볼 "missing in candidate" / 0 "new") |
| tcb_judgments selftest | **exit 0** (12/12 — 모든 판정 FAIL 경로 생존) |
| 집합 완전성 (merged vs `git ls-files`) | **FAIL** — 6573 파일 누락 (병합 파일 엔트리 3), 중복 0, 예외 0 |
| 집합 완전성 (full vs `git ls-files`) | **FAIL** — 8 파일 누락 (`.gitignore`×7·`.gitattributes`×1 — ScanCode `ignores_VCS` 기본 무시; live 전체 스캔 보고서도 동일 갭, 샤딩 이전부터 존재) |

타이밍(실측): 전체 스캔 wall 8m25.4s(7218엔트리·오류 0) · shard0 41.1s · shard1 41.5s —
단 shard wall은 병렬화 효과 측정이 **아니다**: shard 스캔이 입력의 ~99.9%를 누락한
근접 빈 스캔이므로(결함 1), 유효 처리량 측정은 전체 스캔뿐이다.

**결함 1 — shard 파일 목록 스캔의 의미론 결함 (워크플로 shard 토폴로지가 통과 불가)**:
① shard 1건 분량 파일 목록(~162KB)이 xargs 기본 명령 버퍼(131,072바이트)를 초과해
scancode가 2회 실행되고 후속 실행의 `--json-pp`가 이전 출력을 덮어쓴다(관측 분할
2515+773 / 2510+778 인자). ② ScanCode 32.5.0은 다중(≥2) 파일 인자 목록을 "공통접두어
루트(`.`) + 인자를 `--include` 패턴으로 변환"으로 처리하며(cli.py:616-649), include
매칭(fileset.py:101-148)에서 슬래시 없는 패턴(루트 파일명)은 경로 세그먼트에 매칭,
슬래시 있는 패턴(서브디렉터리 경로)은 전체 경로 `<cwd-basename>/<path>`에 매칭 —
접두어 불일치로 **서브디렉터리 파일 인자가 전부 조용히 탈락한다(exit 0)**. 결과:
shard0/shard1이 3288 인자 중 파일 2/1개만 스캔(각 디렉터리 650 전체 방출, 병합 시
650 중복). include 매칭 시뮬레이션이 실행당 스캔 파일 수·경로를 정확 예측(33+2 /
13+1)해 메커니즘을 확정했다. **CI 영향**: per-shard 자기검증(comm -3)이 즉시
FAIL → license-scan-shards 잡 red — fail-closed 안전망은 유효하나(조용한 부분 통과
없음) 샤딩 구현 자체가 통과 불가다.

**결함 2 — 본 브랜치 신규 문서가 denied family 검출을 유발 (샤딩과 무관한 독립 블로커)**:
본 epoch_record(라인 89)가 gpl-3.0-only 검출을 일으키며 선언·attribution 어느 쪽에도
없다 → 전체 스캔 evaluator FAIL. 다른 변경 2파일(spec·workflow)의 검출은 변경 전
live 보고서에도 존재하던 기존 회계 완료 검출이다. 즉 샤딩을 올바르 고쳐도 이 브랜치
커밋 상태로는 license-scan 차원이 FAIL이며, 구(단일 스캔) 토폴로지로도 동일하게
FAIL이다 (attribution entry 추가 vs 문서 재작성 vs rollback은 재구성 판단 — 메인
에이전트 소관; J1은 데이터를 고치지 않고 FAIL을 기록했다).

provenance(워크플로와 동일 호출): `publication_provenance_validator` — **PASS**,
tracked 6576파일 전수 커버, 위반 0.

§5 ROLLBACK의 "shard 구조 결함 (CI red·J1 패리티 FAIL)" 조건이 **실측으로
트리거되었다** — rollback(단일 revert PR) 여부는 메인 에이전트 판단이다. §4.3(음성
제어)·§4.4(production acceptance)는 J1 FAIL로 도달하지 못했다(미실행·미측정).

### 4.7 J1 iteration 2 (2026-11-10, 재구성 커밋 `8a6b8b9388` — 로컬 기계 실측) — **PASS**

재구성(§2.6)된 트리에서 §4.1·§4.2를 재판정했다: 전체 스캔(`.`) 기준선과, 워크플로와
동일한 **크기-그리디 2-분할 + 스테이징 단일 루트 스캔** 2-레그(레그별 독립
스테이징 — 워크플로 matrix 잡의 러너 격리 미러링)를 실행하고, 수정된 병합 jq(경로
dedup 포함)를 그대로 적용해 병합했다. 결과 상세·명령 전문·sha256:
`data/ci_optimization/pi_shard_j1_2026-11-10/summary_iteration2.json` (후속 증거
커밋).

| 판정 | 결과 |
|---|---|
| evaluator (full.json) | **PASS** (exit 0) |
| evaluator (merged.json) | **PASS** (exit 0) — 양쪽 verdict·검출 카운트 일치(엔트리 7226·라이선스 검출 파일 58·저작권 검출 파일 43) |
| tcb_judgments parity | **exit 0** — 6574 심볼 투영 완전 동일(full 대비 missing 0·new 0) |
| tcb_judgments selftest | **exit 0** (12/12 — 판정 FAIL 경로 전부 생존) |
| 집합 완전성 (merged vs E) | **PASS** — 파일 6574 전부, comm 잡것 0, 중복 파일 경로 0 (E = HEAD 트리 blob 6582 − ScanCode `ignores_VCS` 8) |
| 집합 완전성 (full vs E) | **PASS** — 파일 6574, 잡것 0 (결함 2 해소: 기대집합을 스캔 가능 집합으로 정정) |
| provenance (워크플로 동일 호출) | **PASS** — 6582파일 전수 커버, 위반 0 |

결함 해소 실측: **결함 1** — 다중 파일 인자 include 변환·xargs 버퍼 분할 경로가
스테이징 단일 루트 스캔으로 원천 제거됐다(각 레그 방출 파일 == 입력 목록, per-shard
자기검증 comm -3 diff 0·양 레그 합 6574파일 전부 방출). **결함 2** — 완전성
기대집합을 "HEAD 트리 blob − `ignores_VCS` 이름"으로 정정해 스캔 표면과 기대집합이
정확히 일치한다(full·merged 양쪽 E 동일). **결함 3** — 평가기가 규정한 attribution
회계로 해소: 구현 커밋에서 epoch_record 본문(§4 음성 제어 GPL-3.0 전문 파일 언급),
본 커밋에서 J1 iteration-1 증거 3종(`summary.json`·`report_license_full.json`·
`parity_baseline.json`)과 스펙 §5 퀴크 문단이 인용한 측정 예시의 원자를
documentary-mention으로 additive 회계했다 — 평가기가 실제로 지적한 원자·홀더만
정확히 회계했고 선제 추가는 없다(denied family 원자가 포함된 파일은 REVIEW RULE에
따라 전부 documentary-mention).

타이밍(실측): 전체 스캔 wall **8m43.2s**(엔트리 7226·오류 0) · shard0 레그 wall
**285.4s**(파일 3250) · shard1 레그 wall **312.6s**(파일 3324, 2레그 병렬 실행 —
동일 16코어 호스트에서 코어 공유 조건) · 레그 바이트 균형 42,819,930 vs 42,819,929
(**1바이트 차**) · 병합: 파일 6574·디렉터리 652(dedup 후 — dedup 전 디렉터리 방출
1067에서 양 레그 공유 디렉터리 415중복 제거; 전체 스캔의 652와 동일 형태) · 병합
결정론: 동일 입력 재실행 출력 sha256 동일. 로컬 2레그 병렬 wall(312.6s)은 동일
호스트 코어 공유 조건의 측정이며 CI에서는 레그가 별도 러너에서 실행된다 — CI wall
개선 실측은 §4.4 production acceptance의 몫이다(§6 갱신).

### 4.8 production acceptance (2026-11-10, main 착지 후 실측) — **PASS**

PR #68이 merge queue(ALLGREEN, max_entries_to_merge=1)를 통해 GitHub 네이티브
MERGE로 main에 착지했다 — merge commit `bf96c07d5523b0b62c806e35025ba59e168e45d2`,
2026-11-10T12:06:25Z. 착지 검증: main의 워크플로 blob이 브랜치 헤드와 바이트 동일
(diff 0줄, blob sha256 `41d4f315…`), freeze 태그 `ci-frozen-2026-11-10-pi-shard`
무결(`f519fa11…`). 착지 후 main에서 `workflow_dispatch`로 production acceptance
런(run `42813670912`, conclusion **success**)을 실행했다. 전체 실측치·원시 데이터:
`data/ci_optimization/pi_shard_acceptance_2026-11-10/acceptance.json`.

| 런 (이벤트) | 레그·병합·집계 잡 초 | 차원 wall | 판정 |
|---|---|---|---|
| PR 헤드 (run 42804169994) | 757 / 550 / 98 | **855s** | PASS (files=7234 licenseDetections=61 copyrightDetections=46) |
| merge_group (run 42811156530) | 522 / 523 / 91 / 113 | **614s** | PASS (동일 수치) |
| main dispatch (run 42813670912) | 623 / 556 / 96 / 118 | **719s** (전체 843s) | PASS (동일 수치) |

- **개선 실측** (기준선 단일 잡 wall 1310s): PR 헤드 **−34.7%** · merge_group
  **−53.1%** · main dispatch **−45.1%** (2차 기준선 1659s 대비 −48.5/−63.0/−56.7%).
- **판정 결정론**: 세 이벤트 모두 verdict·검출 카운트가 수치까지 동일 — 동일
  입력(동일 트리)에 대해 분할 실행이 판정을 흔들지 않았다.
- **레그 균형**: merge_group 522:523 (1.00x) — 크기-그리디 분할은 러너 조건이
  균등하면 wall 균형을 달성한다(§4.7 로컬 관측의 CI 확인). PR 헤드 757:550
  (1.38x)는 러너 경합 관측이며 content-aware 분할 Follow-up의 근거다.
- **아티팩트 검증**: run 42813670912의 publication-report-license-scan 아티팩트를
  다운로드해 검증 — report verdict PASS, 위반 0/0, 병합 scancode.json 엔트리
  7234(파일 6582·디렉터리 652·중복 경로 0).
- **음성 제어 (§4.3 이행 실측)**: PR #69(미병합 close·원격 브랜치 삭제)에서
  denied-family 파일 첨가 시 관측 체인 — 레그 PASS(샤딩 회귀 없음) → 병합 집합
  완전성 PASS(파일 존재) → 평가기 FAIL(미회계 원자·홀더) → publication-integrity
  **BLOCKED** (mergeStateStatus BLOCKED). 판정 라인 files=7236 licenseDetections=62
  copyrightDetections=47 — 슬라이스 런 대비 정확히 +1 파일·+1 디렉터리·+1/+1 검출
  (증분이 정확하다). run 42807009493, job 129805554290, 차원 러너 초 1795.
- **runner-분·비용 실측**: 차원 러너 초 — PR 헤드 1405s(+7%, 경합) · merge_group
  1136s (**−13%** vs 단일 잡 1310s) · main 1275s (−3%). hosted Linux 단가 기준
  차원 비용 ~$0.08–0.14/런 — 병렬화가 wall을 45–53% 줄이면서 계산량은 대체로
  중립이다(경합 하 변동 ±). 과금 판독(2026-11-10T12:15:20Z): 당월 총액
  $289.85 / 포함 $300 (잔여 $10.15), Axiom Linux 11,127분(당일 3,884분) —
  포함량 압박의 주원인은 전체 CI 트래픽이고 슬라이스 몫은 반올림 오차 수준이다.
- **SLO (운영 목표, MUST 아님)**: merge_group 큐→병합 wall 750s > 480s — **미달**.
  이 슬라이스는 license-scan 병목(차원 wall 614s)을 제거했다. 잔여 지배 경로는
  admission-gate 등 타 필수 워크플로(이번 착지에서 ~13분)다. 480s 달성은 별도
  Follow-up 범위이며, 본 기록은 측정된 개선분만 주장한다.

§5 ROLLBACK 조건은 실측상 미트리거(구조 결함 없음·판정 동일·필수 검사 전부
정상 보고). 원복 경로는 여전히 단일 revert — freeze blob `b7274382…` 앵커.

## 5. ROLLBACK

| 상태 | 행위 |
|---|---|
| shard 구조 결함 (CI red·J1 패리티 FAIL) | **단일 revert PR** — 본 커밋(워크플로+스펙+기록)을 한 번에 되돌린다. freeze 태그가 원본 blob `b7274382…`를 보존하므로 복구 기준은 명시적이다 |
| 판정 불가 상태 | rollback을 선언하지 않고 조사한다 — 어느 경우도 게이트 우회 수단을 만들지 않는다 |

## 6. 잔여 / 후속

- **스펙 §5 실측 퀴크 — 완결 (2026-11-10 J1 후속 커밋)**: 경로 방출 3종 실측(`.`/다중 파일 인자는 `<cwd-basename>/<rel>`·디렉터리 650 방출, 단일 파일 인자는 裸 basename, 디렉터리 인자는 인자 문자열 루트)·include 변환 결함(cli.py:616-649 + fileset.py:101-148)·xargs 버퍼 분할(131,072바이트 초과)·`ignores_VCS` 8파일 무시를 스펙 §5에 추가했다(§4.6 참조).
- shard 실행 시간 균형·병렬화 효과 정량화 — **J1 실측 불가 상태**: shard 스캔이 결함 1(§4.6)로 입력의 ~99.9%를 누락해 wall 41s가 무의미하다. 결함 수정 전에는 병렬화 wall 측정이 존재하지 않는다(미측정 항목은 기록하지 않는다 — summary.json timing 참조). → **iteration 2에서 측정 성립 (§4.7)**: 로컬 레그 wall 285.4s/312.6s(병렬·코어 공유 조건, 3250/3324파일)이 유효 측정이다. CI 레그 wall(별도 러너)과 전체 잡 wall 개선 실측은 §4.4 production acceptance의 몫이다.
- J1 에이전트가 증거를 합류한 뒤 메인 에이전트가 PR을 생성한다 — 본 커밋은 브랜치 commit+push까지만 (PR 생성 없음). **단 J1 판정이 FAIL(§4.6)이므로** PR 생성 전 §5 ROLLBACK(단일 revert) 또는 재구성 결정이 선행해야 한다 — 결함 1(워크플로 shard 의미론)·결함 2(epoch_record GPL-3.0-only 검출)은 각각 독립 블로커다. → **재구성 결정이 집행됐다 (§2.6·§4.7)**: 메인 에이전트 판정으로 rollback 대신 메커니즘 재구성을 착지했고 iteration-2 판정이 전부 PASS다 — PR 생성 전제조건이 해소됐다(나머지는 §4.3 음성 제어·§4.4 acceptance).
- **§4.3 음성 제어·§4.4 production acceptance — 완결 (2026-11-10, §4.8)**: 음성 제어는 PR #69로 차단 실증(BLOCKED·미병합 close), production acceptance는 PR #68 main 착지(`bf96c07d…`) 후 main dispatch run 42813670912 success로 wall·판정·아티팩트·과금 전부 실측 완료. 슬라이스의 Terminal Outcome은 종결 — 남은 것은 운영 Follow-up 3건: (1) admission-gate 등 타 필수 워크플로가 admission-wall의 잔여 지배 경로다(480s SLO 범위, 별도 슬라이스) (2) 러너 경합 하 잔여 레그 불균형(757:550)에 대한 content-aware(scan-time 가중) 분할 (3) 과금 포함 잔여 $10.15(12:15Z 기준)의 월말 감시 — 압박 원인은 전체 트래픽이다.
