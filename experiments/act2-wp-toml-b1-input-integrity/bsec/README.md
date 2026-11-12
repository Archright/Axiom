# bsec/ — B-SEC 판정 기록 + 재현 운용 (campaign record) & 링크 실험 (B-1 follow-up)

**이것은 무엇인가**: `nim-toml-serialization` @ `4aa8e22`의 실행-입증 결함(B-1)에 대해, (결함 × 소비자 × 공격자 모델) 3원조별 보안 영향 판정(NO-GO/UNKNOWN)과 그 판정을 **운용 상태로 고정하는** 오프라인 재현 묶음이다. 판정 본문은 `JUDGMENT.md`, 3원조별 시험 행은 `verdicts.md`.

## 레이아웃

| 경로 | 내용 |
|---|---|
| `JUDGMENT.md` | 판정 기록 본문 (3원조별: 호출부 증거 → 공격자 모델 → 관측+대조 → 판정·범위 조건) |
| `verdicts.md` | 실제 시험된 3원조 행 (nph NO-GO + UNKNOWN 행; 캠페인 번호 체계) |
| `verdicts_recorded.tsv` | 기록된 판정 — 재유도의 **교차 검증 대상**일 뿐, 유도 입력이 아님 |
| `verdict_generations.tsv` | **판정 세대 대장 (append-only)** — 계보(triple)별 세대 이벤트와 대체(supersession) 체인; 현재 판정 = 계보별 최후 유효 세대. 아래 "판정 세대 대장" 절 |
| `rules/rule_table.tsv` | 전함수 규칙 테이블 (R1–R11 + DEFAULT). 미정의 입력 → UNKNOWN, fail-closed |
| `offline/` | 오프라인 증거 묶음: 주체 identity+blob 해시, 의존성 vendor 사본(커밋 SHA+파일 해시), 입력 바이트+sha256, 호출형 결속, 빌드 명령+툴체인 ID, 사례당 원시 관측(선언된 프로젝션), 소비자 기록 관측. `../MANIFEST`가 모든 파일의 sha256을 고정 |
| `snapshot/judgment_snapshot.tsv` | 판정 시점 스냅샷 — freshness 비교 기준선 (무조건 최신 HEAD가 아님): subject + nph + ImThemes + nimbus-eth1 (소비자 master `97d1f982` + vendor 서브모듈 핀 `73529768`) + stickyshell/click (커밋 UNRECORDED — 구조적 fail-closed, 2026-10-12 잔여 결속) |
| `replay.sh` | **단일 프로토콜 (정확히 4 동사)** — `verify`(읽기 전용: 해시+아카이브+주체 blob+세대 대장 체인+참조 무결성) / `run`(번들 빌드+7사례×2 독립 실행+원시·정준 바이트 동일성) / `judge`(순수 재유도+기록·대장 교차 검증+사유 일관성, /tmp에만 출력) / `freshness`(읽기 전용 ∨ 술어) |
| `../MANIFEST` | **유일한 해시 장부 (번들·증거 바이트 도메인)** — offline/ 전체 평문 파일 + 실험 전역 tarball 12개 + 전 멤버의 sha256 (구 manifest.tsv·*.SHA256SUMS·sha256sums.txt 흡수). 기록 파일(verdicts_recorded.tsv, verdict_generations.tsv, rules/, snapshot/, 본 README)은 **git 기록 도메인** — 산출물마다 정확히 하나의 무결성 도메인 |
| `link_a_flavor/` `link_b_consumer/` `capdelta/` `evidence/` | 링크 실험 + 능력-델타 기록 + 호출형/활성화 프로브 (아래 링크 실험 절 참조; JUDGMENT.md가 인용) |

## 재현 방법 (단일 진입점)

```bash
cd experiments/act2-wp-toml-b1-input-integrity/bsec
bash replay.sh verify     # 읽기 전용: MANIFEST 전수(평문+아카이브+멤버) + 주체 blob
                          #   + 판정 세대 대장(스키마·append-only 체인·계보 헤드·참조 무결성)
                          #   — 하나라도 불일치 → 실패, 진행 없음, 아무것도 쓰지 않음
bash replay.sh run        # 검증 → 주체/툴체인 신원 → 번들 vendor만으로 빌드(~/.nimble/pkgs2 불사)
                          #   → 7 사례를 두 번(A/B) 독립 실행 → (1) 사례당 원시 출력 = projection.sha256,
                          #   (2) 정준 증거 해시 A==B (canonicalProjectionHash — 실행 메타데이터는 권위 목록이 제외)
bash replay.sh judge      # 기록된 관측에서 규칙 테이블로 **순수 재유도**(파생 표는 /tmp에만 기록)
                          #   → verdicts_recorded.tsv + 세대 대장 헤드와 교차 검증
                          #   (불일치 = 기록 파손; 사유 셀이 자기 판정과 모숭되어도 실패; 절대 자동 수정 없음)
bash replay.sh freshness  # 판정 시점 스냅샷 대비 ∨(OR) 술어 → FRESH / RE-EVALUATE REQUIRED
                          #   (읽기 전용 — 평가 로그를 쓰지 않고 fresh_as_of 같은 필드도 어디에도 없음)
```

- `run`과 `judge`의 분리: `run`은 **라이브 세계가 기록된 프로젝션을 여전히 재현하는지**(원시 바이트)와
  **같은 고정 입력 위의 두 독립 실행이 정준 증거에서 동일한지**(결정론)를 입증하고, `judge`는
  **검증된 관측에서 규칙 테이블의 전함수로 판정이 재유도되는지**를 입증한다. 세 게이트가 함께
  기록의 운용 상태를 재확정한다.
- 바이너리·캐시·정준 어댑터·파생 표는 `/tmp`에만 생긴다. 주체 저장소는 읽기 전용이며 실행 후에도 바이트-클린이다.
- `verify`·`judge`·`freshness`는 실험 트리에 아무것도 쓰지 않는다 (verify의 아카이브 멤버 해싱 /tmp 스크래치는 사용 후 제거).
- 종료 코드: `0` PASS/FRESH, `2` 프로젝션·정준 발산(발산 관측으로 판정 유도 안 함 — run 한정), `1` 환경 INVALID 또는 재유도≠기록·대장(fail-closed).

## 신뢰 모델 — 신뢰된 검사기 + 후보 트리 데이터 (`AXIOM_TARGET_TREE`)

`replay.sh`는 항상 **자기 자신의 위치**(신뢰된 복사본)에서 실행되고, 검증 대상 트리는
`AXIOM_TARGET_TREE`로 정해진다(미설정 시 스크립트 자신의 저장소 루트 — 기존 동작과 바이트 동일).
설정되면 검사기는 **후보 트리를 데이터로만** 검증한다 — MANIFEST·offline 번들·규칙·기록 판정·스냅샷·
세대 대장(그 git 기록 도메인 포함)의 모든 검증 경로는 후보 트리에서 읽기만 하고 후보 트리의 코드는
실행하지 않는다 (대장 게이트 Gate A/B는 후보 트리의 git 기록에 결속되며, 사용 가능한 git worktree가
없는 후보는 fail-closed). `run`은 코드를 실행하는 유일한 동사이므로 외부 대상 트리를 거부한다 —
**CI는 `verify`/`judge`만 실행하며, `run`은 후보 트리의 코드를 절대 실행하지 않는다.**

## 판정 세대 대장 (`verdict_generations.tsv`)

스키마 (탭 구분, 헤더 행 고정):

```
event_id	triple_id	event_kind	at	actor	evidence_ref	supersedes	payload
```

- `event_kind`은 항상 `verdict_generation` — 이 대장은 **판정 세대 이벤트만** 지원한다 (결정/액션/외부관측 대장, 일반 관계 테이블, 라이프사이클 프레임워크 없음 — P0-4 최소 구조).
- `payload` = 한 줄 JSON, **정확히 8개 키**: `verdict`, `tuple`, `rule_id`, `rule_hash`, `input_ref`, `snapshot_ref`, `reason`, `evidence_refs`.
  - `verdict` ∈ {GO, NO-GO, N/A, UNKNOWN}
  - `tuple` = `defect_live|consumer_path|valid_contrast|boundary|artifact` 정규형 (defect_live는 yes→present, no→absent 정규화)
  - `rule_hash` = 매치된 규칙 테이블 행 1줄(끝 개행 제외)의 sha256 — `judge`가 재계산해 대조한다 (규칙 기준이 바뀌면 재유도 불일치 = fail-closed)
  - `evidence_refs` = 비어있지 않은 문자열 배열
- `supersedes` = **같은 계보(같은 triple_id)의 파일상 앞선 행**의 event_id 또는 빈 값(계보 뿌리). 교차 계보 대체·역방향 참조·포크(한 부모를 2개 이벤트가 대체)는 하드 실패.
- 계보의 **현재 판정** = 대체되지 않은 헤드 세대 — 계보당 정확히 1개 (2개 이상 = 모호, fail-closed).
- `at`은 **기록 시점에 고정** — 재생(replay)이 재생성하거나 현재 시각과 비교하지 않는다 (형식 검사만). 과거 행은 불변(append-only); 지연(staleness)은 과거 행 수정으로 표현하지 않는다. 체인 순서 불변식 + git 이력이 이를 강제한다.
- 참조 무결성: `evidence_ref`, `input_ref`, `snapshot_ref`, `evidence_refs[*]`는 실험 루트 또는 bsec 기준 상대경로로 **기존 파일**에 해석되어야 한다 (`#` 앵커는 해석 시 제거).
- 사유 일관성 (`judge`): payload/recorded의 사유 셀이 자기 판정과 모순되면 하드 실패 (예: verdict NO-GO인데 사유가 "NOT a NO-GO"). 사유가 규칙 id를 인용하면, 실제 판정을 산출한 규칙이 그 인용에 포함되어야 한다. **judge는 절대 자동 수정하지 않는다.**
- 사유 바이트동일성 (`judge`): `verdicts_recorded.tsv`의 사유 셀은 계보 헤드 `payload.reason`의 **사영(projection)**이다 — 양쪽의 바이트동일성이 구속 불변식이고, 불일치는 "projection divergence" 하드 실패다 (기록 TSV를 대장과 무관하게 고치는 것을 차단). 사유 일관성 검사(모순·규칙 인용)와 이 바이트동일성 검사는 별개의 검사다 — 둘 다 요구된다.
- git 기록 도메인 게이트 (`verify` 6단계): 대장은 MANIFEST가 아니라 **git이 기록**한다. Test A — **항상 fail-closed**: 대장은 커밋돼 있고 HEAD와 바이트동일해야 한다. `git diff HEAD`는 untracked를 보고하지 않으므로 인덱스 멤버십을 먼저 탐색한다 — 완전 untracked 대장은 "untracked record file"로 보고되어 첫 착지 커밋까지 실패하고, 이후 무커밋·스테이지 변경도 실패한다 (append + commit = **하나의 coherent generation**). Test B — 과거 세대 불변성: 신뢰 베이스(`AXIOM_LEDGER_BASE` env, 없으면 `git merge-base HEAD origin/main`) 시점의 바이트 접두사가 정확히 보존되어야 한다 (append만 허용; 접두사 내 편집·삽입·삭제·파일 축소 = "append-only violation"). 베이스는 대장을 마지막으로 만진 커밋에서 절대 유도하지 않는다 (그 커밋이 변조 커밋일 수 있음). **부트스트랩 진공 통과**: 베이스에 이전 대장이 없거나(신규 대장은 보호할 과거 세대가 없다) 신뢰 베이스 자체가 없으면 Test B는 vacuous pass — 접두사 구속은 첫 착지에서 시작되므로 대장을 도입하는 첫 PR은 항상 착지할 수 있다. 단, 명시적으로 설정된 `AXIOM_LEDGER_BASE`가 해석 불가능하면 연산자 오류이므로 fail-closed. 착지 강제 권위는 이 동사를 돌리는 PR/merge-queue 필체크이고, 로컬 실행은 같은 위반을 조기에 노출한다.

## 결정론 분리 (정준 증거 vs 실행 메타데이터)

- 정체성 계산의 **단일 권위**는 `src/core/utils/canonical_projection.nim::canonicalProjectionHash`다 — 트리 전체에서 volatile 키(`timestamp, startedAtMs, endedAtMs, elapsedMs, solverElapsedMs, parallelOverheadMs, activeNodeCount, availableMemoryBytes, cpuLoadRatio, recommendedWorkerCount, totalWallTimeMs, hotspotElapsedMs, hotspotLabel, runId, generatedAt, processId, timedOut, timeout, timeoutCount, timeoutNodes, timeoutImpactNodes, timeoutHotspots, timeoutComplexityWeight, wallElapsedMs`)와 최상위 `runtimeMeta`를 재귀 제거한 뒤 키 정렬 직렬화의 SHA-256 (`docs/spec/productization_contract.md` §6). **이 프로토콜은 제외 목록을 다시 정의하지 않는다.**
- `run`은 7 사례를 두 번(A/B) 독립 실행하고: (1) 원시 사례당 출력 = `offline/observations/projection.sha256`와 바이트 대조 (기록 권위), (2) 정준 증거 해시 A == B + 무휘발 정준 아티팩트 바이트 동일. 실행 메타데이터(stamp, date, subject head, batch 마커)는 `runtimeMeta` 봉투와 `/tmp` run_dir의 `metadata.txt`로 분리되며, 제외는 **권위 함수가** 수행한다 (제2의 목록 없음).
- 정준 어댑터(canonical_hash)는 /tmp에서만 생성·컴파일·실행된다 (pinned nim 2.2.10 + nimble.lock-pinned checksums 0.2.2; 권위 모듈을 import할 뿐 재구현하지 않는다).

## MANIFEST 재생성 (기록 행위 — 연산자 전용, replay 동사 아님)

MANIFEST 도메인 파일(offline/ 묶음, inputs/, 고정 followup 입력, closure 기록)의 내용이 바뀌었을 때만, 그 파일들의 해시를 갱신한다. 기록 파일(TSV/MD 대장)은 git 도메인이므로 MANIFEST에 없다 — **산출물마다 정확히 하나의 생성 권위와 하나의 무결성 도메인**. 재생성은 연산자가 직접 실행하는 결정론적 파이프라인이며 replay.sh 동사에 포함되지 않는다:

```bash
cd experiments/act2-wp-toml-b1-input-integrity
# 1) file + archive 자기 해시 행: 기재된 경로 위에서 결정론적으로 재계산 (projection 생성과 동일한
#    정렬된 sha256sum 기법)
while IFS=$'\t' read -r kind rel want; do
  case "$kind" in
    '#'*)    printf '%s\n' "$kind" ;;
    file)    printf 'file\t%s\t%s\n' "$rel" "$(sha256sum "$rel" | cut -d' ' -f1)" ;;
    archive) printf 'archive\t%s\t%s\n' "$rel" "$(sha256sum "$rel" | cut -d' ' -f1)" ;;
    *)       printf '%s\t%s\t%s\n' "$kind" "$rel" "$want" ;;  # member 행은 2)에서만 재생성
  esac
done < MANIFEST > MANIFEST.new && mv MANIFEST.new MANIFEST
# 2) member 행: 바이트가 바뀐 아카이브에 대해서만 — 임시 디렉터리에 추출해 전 멤버를 재해시하고
#    해당 아카이브의 member 행 블록을 정렬해 교체한다
#    (예: a=bsec/evidence/raw.tar.gz; tmpd=$(mktemp -d); tar -xzf "$a" -C "$tmpd" &&
#     (cd "$tmpd" && find . -type f | LC_ALL=C sort | sed "s|^\./|$a::|") | while IFS= read -r m; do
#        printf 'member\t%s\t%s\n' "$m" "$(sha256sum "$tmpd/${m#*::}" | cut -d' ' -f1)"; done)
# 3) 게이트: bash bsec/replay.sh verify  ← 이 기록 행위의 기계적 증명
```

링크 실험 (소비자 경로 — nph 클론 필요했던 실측): 결과 바이트는 `link_a_flavor/raw.tar.gz`·
`link_b_consumer/raw.tar.gz` + `observed/` + `capdelta/`로 고정되어 있다 (`verify`가 전 멤버 해시를
검증한다). 구 `run.sh` 드라이버는 재생성 스크립트라서 삭제되었고 — 재생성은 기록을 제자리에서
덮어쓰므로 불변식이 아니라 위험이었다. 방법 서술은 `link_b_consumer/report.md`와
`link_a_flavor/compare_v100.md`가 보존한다.

## 판정 값의 의미 (2026-10-11 정정 — rule_table.tsv 헤더가 구속 부호다)

| 값 | 의미 |
|---|---|
| **GO** | 진술된 공격자 모델 하 + 실제 소비자 경로에서 보안 영향이 재현됨 |
| **NO-GO** | 진술된 경로·영향 가설의 **범위가 시험되었고** 관측 결과가 보안 영향 주장을 뒷받침하지 않음 — **"영향이 없다"가 아니라 범위화된 판정**이다. 타 소비자·타 모델·타 리비전으로 이전되지 않는다 |
| **N/A** | 증거가 이 정확한 소비자 AND 버전에서 경로 도달 불가를 확인함 — **호출부 조사 아티팩트 필수**, 없으면 UNKNOWN |
| **UNKNOWN** | 도달 가능성·공격자 통제·영향이 불충분하게 확립됨 — **미결정**이지 "안전"이 아님. 유효 대조 입력 1건 + fail-closed 관측으로는 시험 범위 밖의 영향을 배제하지 못한다 (범위 밖은 전부 UNKNOWN) |

## 통합 정리 (2026-10-11 — 산출물 수가 신뢰를 만들지 않는다)

하나의 프로토콜(`replay.sh` 4 동사) + 하나의 해시 장부(`../MANIFEST`)로 흡수·삭제된 것:

| 흡수/삭제 | 이유 |
|---|---|
| `run.sh` + `verify_hashes.sh` + `freshness.sh` | `replay.sh`의 `run`·`verify`·`freshness`로 흡수 — 동일 게이트, 동일 종료 코드, 3개 진입점이 1개로 |
| `offline/manifest.tsv` (42 entries) + `deps.SHA256SUMS` + 8개 트랙 `*.SHA256SUMS` + 5개 내부 `sha256sums.txt` | `../MANIFEST`로 흡수 (kind=file/archive/member 3열) — 기존 `*.SHA256SUMS`가 놓친 "미기록 멤버"까지 전수 강제 |
| `observations/repro.sh` + `followup/*/{repro.sh}` 6개 + `link_a_flavor/run.sh` + `link_b_consumer/run.sh` | 삭제 — 재생성 드라이버는 기록 디렉터리를 제자리에서 덮어쓴다(귀속 파괴). 그 바이트는 tarball로 고정되어 `verify`가 검증하고, 7사례 재현 불변식은 `run`이, 방법 서술은 각 report.md가 보존한다. 유일한 예외였던 pkgs2 소비(`observations/repro.sh`)도 `run`은 번들 vendor만 쓰므로 제거됐다 |

유지된 읽을 기록: `JUDGMENT.md`(루트·bsec), `verdicts.md`, `verdicts_recorded.tsv`, `rules/rule_table.tsv`,
`snapshot/judgment_snapshot.tsv`, `offline/subject/`(blob 해시), 각 트랙 `report.md`/`*.tsv`, `env/`, `oracle/`,
`observations/`(원기록), `followup/exposure/`. 지연 항목은 `../DEFERRED.md`가 별도 트랙으로 적는다
(본 기록의 P0 판정과 상호 간섭 없음 — 실행하지 않음).

## 이 기록이 말하지 않는 것

- **심각도·CVSS·CVE 없음.** upstream 제출 없음.
- **NO-GO의 확산 금지**: "nph에서 능력 증가 0"은 다른 소비자·다른 공격자 모델로 이전되지 않는다.
- 소비자 집합(2곳)은 **전수 조사가 아니다** — 미발견 소비자의 3원조는 미생성 상태다.
- UNKNOWN은 결함 부정이 아니다. B-SEC-02·03은 열거된 집합에서 닫히지 않았다.
- **잔여 조건 (residue condition)**: *"The defect remains live at consumer pin `73529768ced17720f78fb5b57191e863f8d8a9c1` (nimbus-eth1 `vendor/nim-toml-serialization` submodule, `TomlHexEscape` default-active); upstream remediation is a human decision and is NOT part of this record's completion."* 이 기록의 완결(병합·게이트 통과)은 결함 제거가 아니라 **증거 고정**이다 — 시정은 이 기록 밖의 인간 결정이다.

## 권위의 성격 (중요)

**main 병합 = 이 기록의 운영적 완결이지, 외부 세계에 대한 진실성 보장이 아니다** — *"main merge is the operational completeness of the record, not truth about the external world."* 정본(canonical)은 **증거를 보존하는 권위**다 — 증거가 무엇을 입증하는지는 별도의 검토 대상이다. 판정은 관측+규칙의 함수로 언제든 재유도할 수 있으며, 세계가 움직이면(`replay.sh freshness` 발화) 기존 판정은 역사 기록으로만 남는다.

---

## 링크 실험 산출물 (병행 태스크 기록)

`link_a_flavor/`, `link_b_consumer/`, `capdelta/`, `evidence/`, `verdicts.md`는 소비자
경로 실측을 담는다:

- **Link (a) — flavor 전이**: 바이트 고정된 B-1 입력을 기본 `Toml` flavor(un-keyed
  `Toml.decode(input, Obj)`)로 실행 — **전 사례 Toml_v100 결과와 바이트 동일**
  (`assert_result.txt` = `OK`; 분석 `compare_v100.md`).
- **Link (b) — 소비자 경로**: nph `2cacf6cc` 소스 빌드, 실제 `.nph.toml` 경로
  (`Toml.loadFile`, `src/nph.nim:103`)를 결함/유효/기준선 설정으로 구동 —
  **양 B-1 결함 모두 실제 nph 동작에 도달**, 관측 효과는 전부 유효 설정이 재현
  (`report.md`; C0–C12 바이트 기록).
- **능력-델타**: 결함/유효/기준선 3자 대조 + dead-code 재검증(`matchesFilters` 미평가) +
  보호 경계(nph-action@v1) + 구조적(리비전 불변) 동치 진술 — `capdelta/capdelta.md`.
- **호출형/활성화 프로브**: nph·ImThemes의 실제 호출형에서 `TomlHexEscape` 동적 확인
  (해석 리비전 `b5b387e6`에서 REJECTED; 반사실 `4aa8e22`에서 OK —
  `evidence/probes/` + `evidence/raw/`).

### 바이트 동일성 스코프 관례 (캠페인 전체)

바이트 동일성 주장은 **사례당 관측 출력**에만 적용된다. 런 메타데이터 — 타임스탬프,
HEAD, 툴체인 신원, 절대 입력 경로, `decode_call=` flavor 명명 — 는 `run_meta.txt` /
`run_dir` 메타데이터 파일에 있으며 모든 비교에서 **제외**된다.

### 제약 준수

- 프로브는 `# nim-check: skip` + out-of-tree import 근거 주석으로 시작
  (관례: `experiments/bug-verdict-e2e/cout_probe.nim`).
- 바이너리는 `/tmp`만 사용; 주체 저장소 무손상(실행 후 검증).
- 심각도/CVSS 평가 없음; upstream 이슈 제출 없음.

## 전임 산출물과의 관계

- `../JUDGMENT.md` — B-1 결함 2건의 실행 입증 (본 기록의 기반; 재증명 없음)
- `../followup/{defects3,writer,utf8,extend}/` — 후속 확정 발견 (B-SEC-02·03 메커니즘)
- `../env/` — 의존성 출처 strace 입증 (번들 vendor 사본의 근거)
- 캠페인 계획 — 기록된 계획 참조 `rocket-white-tiger-black-widow.md`는 이 저장소에 존재하지 않음 (recorded plan reference not present in repo); 능력-델타 확립 기록은 `capdelta/capdelta.md`
