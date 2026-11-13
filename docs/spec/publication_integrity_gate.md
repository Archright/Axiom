# publication-integrity 게이트 — 단일 판정 공개 준비성 계약

**Status**: Normative (v1.3, 2026-11-13 — license-scan shard 3-레그 확장(VS-PI-3) 반영 + self-heal 로컬 감사 스코프 정렬; v1.2 = 2026-11-10 스테이징 단일 루트 스캔 재구성; v1.1 = 2-shard 구조화 도입)
**워크플로**: `.github/workflows/publication-integrity.yml` (required context `publication-integrity`)
**정책 SSOT**:
- `compliance/policy/license-policy.yml` — 허용 라이선스 allowlist + 거부 가족
- `compliance/policy/security-policy.yml` — secret/dependency/sbom 도구 핀 + 판정 시맨틱
- `compliance/policy/provenance-policy.yml` — 기원 클래스 시맨틱
- `compliance/policy/secret-scan-baseline.json` — 감사된 비밀 검출 핑거프린트 baseline
- `compliance/provenance/source-origin.yml` — 전 트랙 파일 경로 기원 선언 (무 catch-all)
- `compliance/provenance/license-attribution.yml` — 감사된 검출 attribution (무 glob catch-all)

**권한 관계**: 본 게이트의 판정 논리 SSOT 전부가 `config/policy/merge_admission.json`
trustSurface에 등록되어 있다 (v1.20.0) — 정책 약화 PR은 자동 병합이 거부된다
(TRUST_SURFACE_MODIFIED → rotation/운영자 경로).

---

## 1. 게이트가 보장하는 것 (Claim)

공개(public) 전환 시점의 저장소 표면에 대해:

1. **비밀**: 공개 표면 스코프(origin/main + HEAD + 서버 PR refs, 전 이력)의 모든
   gitleaks 검출이 감사된 baseline 핑거프린트에 정확히 일치한다. 신규 핑거프린트 = FAIL.
2. **라이선스·저작권**: 모든 ScanCode 검출 라이선스 원자와 저작권 홀더가
   (a) 경로 선언(source-origin.yml) 또는 (b) 감사 attribution 항목으로 회계된다.
   회계 안 된 검출(거부 가족 포함) = FAIL.
3. **의존성 취약점**: OSV 색인 생태계에서 알려진 취약점 0건 (osv-scanner exit-code 판정).
4. **기원**: 트랙된 모든 파일이 정확히 하나의 기원 클래스로 선언되고, THIRD_PARTY는
   출처+허용 라이선스를, ORIGINAL은 자가 라이선스를 만족한다. 미선언·불일치 = FAIL.
5. **SBOM**: SPDX-2.3 산출물이 비공허(≥1 package/file)로 생성·검증되고 sha256이 기록된다.

본 게이트는 **침해 부재의 증명**이 아니다 (rightsVerificationLimit — 자동 분석 통과는
권리 검증이 아니다). 계약은 "정책 SSOT와의 기계적 일치"이며, 정책 SSOT 자체는
감사 문서(`docs/evidence/sal10_publication/B1_third_party_inventory.md`,
`B2_copyright_report.md`)에 근거한다.

## 2. 구조와 판정

```
secret-scan ──────┐  gitleaks 8.30.1 (release pin + sha256 verify)
license-scan ─────┤  scancode-toolkit==32.5.0 + pluggy==1.5.0 (venv pin)
dependency-scan ──┼─→ publication-integrity (종합 job, needs 전부 + if: !cancelled())
provenance ───────┤  tools/ci/publication_provenance_validator.nim
sbom ─────────────┘  syft v1.57.0 → publication_sbom_eval.nim
```

- sub-job id = 차원 이름 (secret-scan, license-scan, dependency-scan, provenance, sbom).
- license-scan 차원은 내부적으로 `license-scan-shards`(matrix 3-레그 — HEAD 트리
  blob 집합에서 ScanCode 기본 무시 이름(`ignores_VCS`)을 뺀 스캔 표면의 **크기-그리디
  결정적 3-분할**, 각 레그는 자기 파일 집합을 **작업공간 basename과 동일명의 루트
  디렉터리에 스테이징해 그 디렉터리 하나를 스캔** — 단일 디렉터리 인자가 ScanCode가
  올바르게 취급하는 유일한 입력 형태다, §5) + `license-scan`(shard 보고서 병합·판정
  잡)로 실행된다. **판정은 단일 평가기·단일 병합 보고서로 유지된다** —
  "sub-job id = 차원 이름" 규칙은 판정 잡 `license-scan`이 담당하며 shards는 내부
  실행 구조다 (required context·종합 잡 needs·차원 보고서 artifact 표면 불변).
- 종합 job은 `needs.*.result`와 5개 차원 보고서 JSON을 **이중** 검증한다
  (`tools/ci/publication_report.nim`).
- **skipped/cancelled sub-job = UNKNOWN(차단)** — required check의 스킵=성공
  플랫폼 함정을 종합 job이 항상 실결론으로 보고한다. 종합 job 자체는
  `if: !cancelled()`로 절대 스킵되지 않는다.
- 판정·exit: PASS=0, FAIL=1, UNKNOWN=2 (폐쇄 집합). UNKNOWN은 항상 차단이며
  결코 통과로 해석되지 않는다 (fail-closed).
- 보고서·SBOM artifact는 `if: always()`로 업로드된다 (NOT-ADMIT도 증거가 남는다).

## 3. 차원별 판정 시맨틱

### 3.1 secret-scan
- 스코프 = 공개 표면: `origin/main HEAD --glob=refs/remotes/pr/*`
  (security-policy.yml `secretScan.historyScopeLogOpts`) + 현재 트리 dir 스캔.
- 로컬 감사(`tools/ci/publication_self_heal.sh --audit-refs`)도 동일 선언 스코프를
  소비한다(동일 history pass — 격리 클론의 working tree가 HEAD 트리와 동일하므로 별도
  dir leg는 중복이다). 로컬 감사와 CI가 같은 커밋 집합을 스캔한다 (판정 결정성).
  구 폐쇄-PR 정보 lane(`--glob=refs/remotes/pr/* --not ...`)은 폐지한다:
  refs/pull/*/head가 선언 스코프의 positive revision이므로 두 번째 lane은 같은
  커밋 집합을 재계산할 뿐이다 (duplicated-lane anti-pattern — 워크플로의 2026-11-13
  폐지 결정과 동일). `--support-bundle`의 PR-only 열거(`--not` 제외 포함)는
  dereference 티켓 의미론상 유지하며 게이트 판정 lane이 아니다. baseline
  `_meta.historyScope`는 이 선언 스코프를 기록한다.
- 회계 단위 = gitleaks 핑거프린트(`Commit:File:Rule:Line` / `File:Rule:Line`) —
  경로가 아니라 정확한 튜플로 baseline이 고정되므로 baseline에 숨은 경로 안에서
  실제 비밀이 새 핑거프린트로 잡힌다.
- 신규 핑거프린트 = FAIL; 검출이 baseline보다 적으면 정보성(표면 축소).
- baseline 분류는 폐쇄 집합: `synthetic-hash-or-cas-key` / `synthetic-test-fixture` /
  `identifier-false-positive`.

### 3.2 license-scan
- ScanCode 32.5 스키마(`license_detections[].license_expression_spdx`,
  파일별 `detected_license_expression_spdx`)에서 원자를 추출한다
  (AND/OR 복합식 분해, LicenseRef 포함).
- 회계: 원자 ∈ 선언 라이선스 집합(source-origin) **또는** (파일, 원자) attribution.
- 저작권: 검출 홀더의 유의 토큰(≥4자, stopword 제외)이 선언 저작권 필드 또는
  attribution 홀더 문자열과 중첩. 유의 토큰 0개 검출("(c) inc"류)은 noise로
  보고되고 위반이 아니다(회계할 홀더가 없다).
- attribution 분류 폐쇄 집합: `self-license-text` / `documentary-mention` /
  `subject-manifest-record` / `upstream-header` / `spurious-scanner-match`.
  거부 가족(GPL/AGPL/LGPL/CC-BY-NC/CC-BY-ND/SSPL/BUSL/Proprietary) 원자의
  attribution은 `documentary-mention`이어야 한다 (텍스트 언급이지 부여가 아님을
  명시적으로 주장).
- 신규 검출에 attribution 항목이 없으면 FAIL (fail-closed; 항목 추가는 리뷰되는
  가시적 행위다 — 극장 금지 §0.9).
- **shard 병합 완전성 계약**: 병합 보고서의 파일 경로 **집합** == **기대 스캔
  가능 집합**(`git ls-tree -r -l HEAD` blob 집합에서 ScanCode `ignores_VCS` 이름을
  뺀 집합 — shard 분할과 동일 유도, 중복 없음). 누락·중복·예상 밖 파일 전부
  FAIL이다. 집합 비교이지 개수 비교가 아니며, shard 보고서가 정확히 3개가 아니면
  판정 자체를 진행하지 않는다 (부분 스캔 표면 위 판정 금지 — fail-closed).
  (v1.1까지의 "`git ls-files` 집합" 기술은 오류였다 — ScanCode가
  `.gitignore`·`.gitattributes`를 어떤 토폴로지에서도 방출하지 않으므로(§5) 그
  기대집합으로는 검사가 항상 FAIL한다.)

### 3.3 dependency-scan
- osv-scanner exit-code 판정 (security-policy.yml `exitCodeAdjudication`):
  0=보고서 파싱(발견→FAIL) / 100=FAIL / 128="No package sources found"=
  완료된 스캔 — PASS with **선언된** 한계(Nim·Lean 생태계는 OSV 색인 없음;
  매 보고서에 기록) / 기타=UNKNOWN 차단.
- ORT Reporter 대체 기록: hosted runner에 JVM이 없어 syft(SBOM)+license-scan이
  동일 역할을 수행한다 — 판정 시맨틱 동일, 문서화된 대체, 검사 영역 삭제 아님.

### 3.4 provenance
- `git ls-files` 전수를 source-origin.yml 선언과 대조:
  커버리지(무 catch-all — 미선언 경로=FAIL) / 다중 일치 규칙 (origin,license)
  전체 일치 / 클래스 시맨틱(THIRD_PARTY: source+허용 라이선스, ORIGINAL: 자가
  라이선스) / `exclude`는 정확 경로만 — 제외 후 재선언 없는 파일은 여전히 구멍=FAIL.

### 3.5 sbom
- syft SPDX-2.3 JSON: 스키마 필드 존재 + 비공허 + 산출물 sha256 기록
  (재현성 주장 — ADR-0037 §5와 동일 의미론).
- **선언된 한계**: syft에 Nim 카탈로거가 없어 nimble.lock 의존성은 파일 항목으로만
  나타난다 (매 보고서에 기록).

## 4. 기존 required checks와의 직교성 (공백·중복 매트릭스)

| 검사 | 담당 | publication-integrity와의 중복 |
|---|---|---|
| admission-check | 인증 연속성·주체 무결성 (Pass 2.9x) | 0 — 판정 대상이 증거 체인이지 공개 표면 콘텐츠가 아님 |
| bsec-integrity | 외부 subject 저장소 빌드 무결성 재현 | 0 — 대상이 status-im subject지 본 저장소 트리가 아님 |
| debt-registry-gate | 극장 레지스트리 계약 (data/debt_registry.json) | 0 — 등록부 스키마 강제, 콘텐츠 라이선스/비밀 무관 |
| generation-acceptance | 정책·검증 세대 승격 (GPA L1-L4) | 0 — 세대 적합성이지 게이트 산출물이 아님 |
| axiom-operational-slice | 제품 수직 슬라이스 종단 (prove + Lean 재생) | 0 — 검증 파이프라인 동작성, 배포 콘텐츠 무결성 아님 |
| **publication-integrity** | **공개 준비성: 비밀·라이선스·기원·의존성·SBOM** | 신규 — 위 5검사 어디에서도 판정하지 않는 영역 |

공백 실증: 2026-11-09 로컬 전수 측정에서 본 게이트 도입 전 상태로는
(비밀) 1,978개 검출의 감사 baseline 부재, (라이선스) 45파일 검출 무회계,
(기원) 6,548파일 무선언, (SBOM) 산출물 부재 — 어느 기존 검사도 이를 차단하지
못했다. 본 게이트의 5차원이 이 공백을 닫는다.

## 5. 도구 능력 매트릭스와 선언된 한계

| 도구 | 핀 | 능력 | 선언된 한계 |
|---|---|---|---|
| gitleaks | 8.30.1 (tarball sha256 검증) | 전 이력+트리 정규식 탐지, 핑거프린트 | 정규식 탐지의 본질적 한계 — baseline 분류는 감사 근거(B2) |
| ScanCode | 32.5.0 + pluggy 1.5.0 (venv) | 라이선스 텍스트·저작권 행 탐지 | 텍스트 패턴 매칭 — 언급/부여 구분 불가 → attribution 기록이 감사 결론의 SSOT |
| osv-scanner | v2.7.1 (binary sha256 검증) | OSV 색인 생태계 취약점 | Nim/Lean 색인 부재 (매 보고서 기록) |
| syft | v1.57.0 (tarball sha256 검증) | SPDX-2.3 SBOM 생성 | Nim 카탈로거 부재 (매 보고서 기록) |
| publication_* 평가기 | 동일 커밋 소스 (trustSurface 보호) | 판정은 전부 Nim 평가기가 수행 (워크플로 bash는 판정하지 않는다) | — |

툴체인 quirk 기록 (측정 2026-11-09): pluggy 1.7이 ScanCode 32.5의 플러그인
로더를 깨뜨린다(동반 핀 필수); ScanCode 32.5는 legacy `licenses` 키가 없는
신스키마를 출력한다; gitleaks `--log-opts` 문자열은 셸 전개 없이 git log에
전달된다(`--glob=refs/remotes/pr/*` 사용); syft는 `-o spdx-json=<path>`/stdout
리다이렉션으로 쓴다(`--output-file` 미지원). GitHub Actions `run:` 스텝은 기본
`bash -e`로 실행된다 — 스텝 내 `set -uo pipefail`은 상속된 errexit을 끄지
못하므로, 0이 아닌 exit code를 **판정 입력으로 캡처**하는 스텝은 `|| code=$?`
형태로만 캡처할 수 있다(裸 커맨드 라인 + `code=$?`는 캡처 전에 스텝 자체가
실패한다 — osv-scanner exit 128 실패 재현, PR #45 첫 CI 라운드 2026-11-09).
`actions/download-artifact`의 `pattern`은 **artifact명**만 매칭한다 — SBOM 차원은
Capsule 입력 묶음 artifact `publication-sbom-spdx-json`(sbom.json + report_sbom.json)에
보고서를 실어 올리므로 `publication-report-*` 글로브에 매칭되지 않는다. 명시적
name 지정 다운로드 없이는 종합 잡이 report_sbom.json을 MISSING으로 읽어 verdict가
UNKNOWN(fail-closed)으로 강등된다 (run 42602859044 job 129124683461, 2026-11-09
실측). 종합 잡은 `publication-sbom-spdx-json`을 별도 스텝으로 명시 다운로드하며,
`continue-on-error`로 차원 잡이 업로드 전 실패한 경우에도 MISSING→UNKNOWN 의미론을
유지한다.

툴체인 quirk 기록 (J1 실측 2026-11-10, 로컬 — pi-shard epoch, `workstream/pi-license-shard`
HEAD 8ab6b83b, scancode 32.5.0+pluggy 1.5.0; 전문 측정:
`data/ci_optimization/pi_shard_j1_2026-11-10/`): ScanCode의 **경로 방출은 입력 형태에
따라 3종**이다 — `.`-스캔과 **다중(≥2) 파일 인자 목록** 스캔은 모두
`<cwd-basename>/<repo-rel>` 경로를 방출하며, 다중 파일 인자 목록 스캔은 `.`-스캔과
동일하게 **디렉터리 인벤토리 전체**(실측 650엔트리)를 방출한다(단일 파일 인자는 裸
basename `MIT.txt` 방출·디렉터리 0, 디렉터리 인자는 인자 문자열을 루트로 방출 — 예:
`LICENSES/` → `LICENSES/<rel>`). `filesScanned`(=`files.len`, publication_license_eval.nim:396)
는 디렉터리 엔트리를 포함하나 판정 루프는 `type=="file"`만 소비한다(라인 310-312) —
메트릭 차이는 판정 입력이 아니다. 단, 각 shard 보고서가 디렉터리 인벤토리 전체를
방출하므로 jq concat 병합은 디렉터리 엔트리를 **중복**시킨다(실측 650×2).
다중(≥2) 파일 인자 목록은 내부적으로 "공통접두어 루트(`.`)+인자를 `--include` 패턴으로
변환"으로 처리된다(scancode-toolkit 32.5.0 `scancode/cli.py:616-649`): include 매칭
(`commoncode/fileset.py:101-148`)에서 슬래시 없는 패턴(루트 레벨 파일명)은 경로
**세그먼트**에 fnmatch 매칭되어 임의 깊이의 동일 basename에 적중하고(실측: `README.md`
인자가 트리 내 13개 README.md에 적중), 슬래시 있는 패턴(서브디렉터리 경로)은 전체
리소스 경로 `<cwd-basename>/<path>`에 매칭되어 **접두어 불일치로 전부 조용히
탈락한다(exit 0)** — 실측: 서브디렉터리 파일 인자 4개 → 0파일 스캔. shard 1건 분량의
파일 목록(~162KB)은 xargs 기본 명령 버퍼(131,072바이트)를 초과해 scancode를 2회
실행하며(커널 ARG_MAX 2,097,152바이트와 무관), 후속 실행의 `--json-pp` 출력이 이전
실행을 덮어쓴다(실측 분할 2515+773 / 2510+778 인자, 실행당 스캔 파일 33+2 / 13+1 —
include 매칭 시뮬레이션 예측과 정확 일치). `commoncode/ignore.py`의 `ignores_VCS`가
`.gitignore`·`.gitattributes`를 기본 무시한다("Git config artifact") — 어떤 스캔
토폴로지에서도 파일 엔트리로 방출되지 않는다(실측: tracked 6576 중 8개, `.`-스캔과
live 전체 스캔 보고서 동일 갭). 이 퀴크들의 파생 결과(shard 집합 완전성 FAIL·J1
판정)는 [epoch_record_pi_shard_2026-11-10.md](../evidence/epoch_record_pi_shard_2026-11-10.md)
§4.6에 기록한다.

스테이징 단일 루트 스캔 토폴로지 근거 (재구성 실측 2026-11-10,
[epoch_record_pi_shard_2026-11-10.md](../evidence/epoch_record_pi_shard_2026-11-10.md)
§2.6·§4.7): ① **단일 디렉터리 인자 스캔은 인자 문자열이 루트가 된다** — 루트
레벨·서브디렉터리 파일 전부가 `<인자>/<rel>`로 방출된다(실측). 위 다중 파일 인자
include 변환 결함을 우회하는 유일한 올바른 입력 형태여서, 각 shard는 자기 파일
집합을 **작업공간 basename(PFX)과 동일명의 루트 디렉터리에 스테이징**하고 그
디렉터리 하나를 스캔한다 — 방출 경로 `<PFX>/<rel>`이 frozen 단일 스캔(`.` →
`<cwd-basename>/<rel>`)과 **동일 형식**이므로 접두어 제거·병합·판정이 그대로
성립한다. ② `ignores_VCS` 정확한 이름 목록(commoncode/ignore.py 157-175행,
Codebase walk의 skip_ignored가 적용): 평문 이름 `.bzr` `.bzrignore` `.git`
`.gitignore` `.gitattributes` `.hg` `.hgignore` `.repo` `.svn` `.svnignore`
`.tfignore` `vssver.scc` `CVS` `.cvsignore`(임의 깊이의 basename에 소문자 비교
매칭)와 경로 패턴 `*/_MTN` `*/_darcs` `*/{arch}`(VCS 메타데이터 디렉터리용).
shard 분할·완전성 기대집합 유도는 평문 이름을 미러링한다(경로 패턴은 본 트리에
해당 경로 0건 — 실측). ③ 스테이징 토폴로지에서 각 shard 보고서는 **자기 스테이징
트리의 디렉터리만** 방출한다(전체 인벤토리가 아님) — 양 레그가 공유하는 디렉터리가
각각 방출되므로 병합 jq는 경로 기준 dedup(`sort_by(.path)` 뒤 `group_by(.path) |
map(.[0])`)으로 단일 스캔의 유니크 형태를 복원한다. 파일 엔트리는 분할상 disjoint라
dedup 대상이 아니며, 병합 후 파일 중복 경로 검사는 여전히 fail-closed다.
④ "VCS 이름 파일만 담긴 디렉터리"(예: `.gitignore`만 트래킹된 디렉터리)는 스테이징에
부재할 수 있다(그 파일은 분할에서 이미 제외됨) — 완전성 검사는 **파일 집합**
기준이므로 무영향이다(디렉터리 엔트리 수는 판정 입력이 아니다).

## 6. UNKNOWN 규칙 (폐쇄)

UNKNOWN은 "아직 판정되지 않음"이며 항상 차단이다: 도구 다운로드/설치/실행 실패,
보고서 부재·파손, 파싱 불가 정책, 매핑 안 된 exit code, 스킵/취소된 sub-job,
missing artifact. 종합 verdict는 `unresolvedUnknownCount > 0`이면 PASS일 수 없다.

## 7. 활성화·착지 기록

1. **본 PR** (워크플로+평가기+정책+미러, merge_admission v1.20.0): trustSurface
   hit → rotation/운영자 수동 병합 경로 (v1.16.0 bootstrap 조항).
2. **ruleset PUT** (활성화): 큐 비움 확인 → ruleset "main" required_status_checks에
   `publication-integrity` context 추가 → readback 6 contexts × integration_id 15368 →
   드리프트 모니터 GREEN. 정책↔ruleset 사이의 일시적 드리프트 창은 같은 UTC 일
   내에 닫는다 (activation manifest에 기록).
3. **workflowIdObservation 등록**: 착지 후 `gh api .../actions/workflows` readback으로
   follow-up 커밋에서 채운다 (v1.7.0/v1.16.1 관례; merge_cli는 이미 (job, path)로 유효).
4. **음성 제어** (별도 브랜치·PR, 미병합 close): ①무효 가짜 secret ②GPL-3.0 전문
   파일 ③source-origin 규칙 밖 신규 파일 — 각각 publication-integrity FAILURE +
   mergeStateStatus BLOCKED 관측.
5. **실운영 병합**: 유효 소변경 PR이 6/6 required checks 통과 후 GitHub native MERGE.
6. **Capsule**: workflow_dispatch 전체 게이트 재실행 — 공개 대상 SHA == 검증 SHA
   강제, SBOM+sha256·차원별 보고서·종합 보고서 묶음 artifact.

## 8. 개정 규칙

- 정책 파일(allowlist/baseline/attribution)의 모든 변경은 PR 리뷰를 타며
  trustSurface에 의해 자동 병합이 거부된다. "스캔을 통과시키기 위한" 규칙 약화는
  극장(§0.9)으로 등록 대상이며 작업 실패다.
- 도구 핀·판정 시맨틱 변경은 본 스펙 개정과 같은 커밋에서 일어난다.
