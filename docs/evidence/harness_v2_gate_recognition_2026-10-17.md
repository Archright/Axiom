# 하니스 v2 게이트 인식 복원 — merge_latency_audit.sh Gap A (2026-10-17)

> **종류**: 측정 하니스 수정 기록 + 검증 산출물. `go_matrix_s3_readjud_post_leverb_2026-10-17.md` §4에 등록된 하니스 갭 중 **Gap A(워크플로 경로 가드)** 만을 해소한다. 측정 정의(E3 §5/§7, A2)·판정 규칙은 한 항목도 변경하지 않는다.
> **권위**: GitHub Actions API(GET-only, api-second-granularity ±1s). 본 도구는 Reporter이며(Authority ≠ Adapter) merge-admission 판정을 대체하지 않는다.
> **소비처**: merge-latency measure→change→measure 루프의 v2 세대(AFTER) 측정. 기계 판독: `data/merge_latency/harness_v2_validation_2026-10-17.{runs.jsonl,summary.json}`.

## 1. 블랙아웃 (수정 전 — 새 세대 측정 완전 두절)

Lever-B(2026-10-16, `g1_leverB_path_rename_2026-10-16.md`)로 org 게이트 워크플로가 `admission-gate.yml` → `admission-gate-v2.yml`으로 개명되면서, `tools/ci/merge_latency_audit.sh`의 4개 가드 사이트가 구경로를 하드핀하여 v2 세대 런을 전부 fail-closed 거부 — 새 세대에 대한 측정 blackout.

수정 전 하니스(origin/main @ 5534c617b)의 재현(2026-10-17, GET-only):

- **런 가드** — v2 런 38925131342 투입 → 거부:

  ```
  [mla] HARD-FAIL: run 38925131342 path '.github/workflows/admission-gate-v2.yml' is not admission-gate.yml — refusing to measure non-admission-gate runs   (EXIT=1)
  ```

- **스캔 창** — 동일 창(2026-10-16T09:00:00Z..2026-10-17T00:00:00Z, 실제로는 v2 런 6건 존재)에서 **0건 발견** → 빈 선택 집합:

  ```
  [mla] HARD-FAIL: no admission-gate success runs selected   (EXIT=1)
  ```

## 2. 수정 — 4개 가드 사이트 (Gap A 한정)

| 사이트 | 위치(수정 후) | 변경 |
|---|---|---|
| 상수 | `tools/ci/merge_latency_audit.sh:108-114` | `GATE_PATH="admission-gate.yml"` → `GATE_PATH_RE='^(.*/)?admission-gate(-v2)?[.]yml$'` + 세대 결합 주석(양 세대 = 동일 게이트, 그 외 fail-closed) |
| measure-path 가드 | `:343-346` (`process_run`) | `!= ` 문자열 비교 → `! [[ =~ $GATE_PATH_RE ]]`, 에러 메시지가 allowlist를 인용 |
| 스캔 창 jq 필터 | `:572` (`scan_window`) | `select(.path \| endswith("admission-gate.yml"))` → `select(.path \| test("<GATE_PATH_RE>"))` — 동일 문자열 보간 스타일 유지 |
| snet-path 가드 | `:787-790` (`emit_snet_side`) | measure 가드와 동일 전환 |

지정 문언 `^admission-gate(-v2)?\.yml$` 대비 2가지 기계적 적응(의미 동등, fail-closed·엄격성 유지):

1. **`[.]`**: `\.`은 jq/gojq 문자열 리터럴에서 부적법 이스케이프(`jq: error: Invalid escape`)라 스캔 필터의 문자열 보간 스타일과 양립 불가. `[.]`는 bash ERE·jq·gojq 어디서든 리터럴 점 하나.
2. **`^(.*/)?`**: 스캔 필터는 basename이 아닌 **전체 등록 경로**(`.github/workflows/<name>`)에 `test()`하므로, `^` 단독 앵커는 전건 불일치(0-run 재발)가 된다. 선택적 경로 접두로 **하나의 정규식**이 basename(가드 2곳)과 전체 경로(스캔) 모두를 정확 매치.

엄격성 실증(정적): `admission-gate-v1.yml`, `landing-integrity.yml`(basename·전체경로), `foo-admission-gate.yml`, `admission-gate-v2.yml.bak` 모두 refuse. 구 `endswith`가 허용하던 접미 오탐(`foo-admission-gate.yml`)이 제거되어 구현보다 엄격.

## 3. 검증 (3종 + 기록 산출물, 전부 GET-only)

| 검증 | 명령 | 결과 |
|---|---|---|
| 양성 | `--runs 38925131342,38913175446,38891209338 --out /tmp/harness_pos` | **exit 0** — 3/3 런 wall/dur_sum/gaps/residual 산출 (아래 표) |
| 음성(대조) | `--runs 38977368334` (landing-integrity) | **HARD-FAIL exit 1** — `[mla] HARD-FAIL: run 38977368334 path '.github/workflows/landing-integrity.yml' is not an admission-gate run (allowlist: ^(.*/)?admission-gate(-v2)?[.]yml$) — refusing to measure non-admission-gate runs` — 가드는 비게이트 런을 계속 거부 |
| 스캔 창 | `--since 2026-10-16T09:00:00Z --until 2026-10-17T00:00:00Z --out /tmp/harness_scan` | **exit 0** — v2 런 **6건** 발견·측정(38885317769, 38885912015, 38891209338, 38913175446, 38925131342, 38977368727) — 구가드 0건 대비 복원 |

양성 런별 성분(초):

| run | workflow_path | wall | dur_sum | gaps | residual | go_step | regime | classification |
|---|---|---:|---:|---:|---:|---|---|---|
| 38925131342 | `.github/workflows/admission-gate-v2.yml` | 734 | 713 | 17 | 4 | null | L | UNKNOWN_LOG |
| 38913175446 | `.github/workflows/admission-gate-v2.yml` | 951 | 929 | 18 | 4 | null | L | UNKNOWN_LOG |
| 38891209338 | `.github/workflows/admission-gate-v2.yml` | 716 | 694 | 17 | 5 | null | H | UNKNOWN_LOG |

관측 보고: `regime`은 사전 예고("unknown 예상")와 달리 **L/H로 해소** — a-restore 마커(`##[end-action id=__self.a-restore …duration_ms=…]`)가 레인 이동 후에도 소비 job(`attest / admission-check`) 로그에 존속. Gap B의 fail-closed 기록 영향은 `go_step=null`·`classification=UNKNOWN_LOG`이며, A2.1.3 분모 규칙상 `stats.executed_only`는 n=0(UNKNOWN_LOG는 EXECUTED 분모에 진입 불가 — 정상 동작). `stats.all_operational`(wall 800.3±130.8, dur_sum 778.7±130.5, gaps 17.3±0.6, residual 4.3±0.6, n=3)은 정상 산출.

본 차량 기록 산출물: `--runs 38925131342,38913175446,38891209338 --out data/merge_latency/harness_v2_validation_2026-10-17` → exit 0, `harness_v2_validation_2026-10-17.runs.jsonl` + `.summary.json` 커밋.

## 4. Gap A / Gap B 분리

- **Gap A(본 차량에서 해소)**: 워크플로 **경로 가드**의 구세대 하드핀 — 측정 정의와 무관한 세대 인식 결함. 4개 사이트 수정으로 복원.
- **Gap B(별도 차량 — 본 PR 미구현)**: GO 스텝이 매트릭스 레인 job으로 이동함에 따른 **lane-aware job 소싱**. `go_step=null`·`UNKNOWN_LOG`는 prereg §10 Q2가 승인한 설계의 대상으로, 해소 전까지 fail-closed로 기록된다. 측정 정의(E3 §5.1 name-rule, A2.1.2 분류)는 그대로이며, 남는 것은 소싱 채널 적응뿐이다.

## 5. §2.5 처분 (비례 차량 근거)

- **AGENTS.md §2.5 전문**(`docs/agents/ci_epoch_cutover.md`)의 CI 변경 정의 목록 항목 (verbatim): "CI를 검증하거나 CI의 trust boundary에 영향을 주는 스크립트·설정 변경" — 본 하니스는 CI를 검증하는 측정 스크립트이므로 §2.5 차량이 적용된다.
- **prereg §10 Q2 경계 문언**(`go_matrix_parallelization_prereg_2026-10-16.md` §10, verbatim): "도구 구현 변경은 별도 차량에서 수행하며, 본 문서는 판정만 등록한다(Reporter — Authority ≠ Adapter 유지)." — 하니스 구현 변경의 별도 차량을 사전 승인.
- **근거**: 사용자 명시 허가 (2026-10-17, "권한이 필요한 부분은 전면 허가한다").
- **비례 절차**: epoch-record형 본 증거 기록 + 표적 검증(§3) + 일반 큐 PR 착지. 본 변경은 활성 실행 경계(게이트·워크플로·required-check)를 일절 변경하지 않는 읽기 전용 리포터의 세대 인식 복원이므로 coherent-generation 전환 의식은 불요이며, 상태 혼합이 아니라 관측 정합화다.

**[정정 — 2026-10-17, 근거 검증 후]** 위 두 서술을 근거 원문(`go_matrix_parallelization_prereg_2026-10-16.md` §10, Q2 항)과 대조 검증한 결과 다음과 같이 정정한다. 원문은 감사 추적을 위해 그대로 보존된다.

1. **prereg §10 승인 범위 정정**: 위 인용 문언("도구 구현 변경은 별도 차량에서 수행하며, 본 문서는 판정만 등록한다(Reporter — Authority ≠ Adapter 유지).")은 verbatim으로 정확하나, 그 직후의 해석("하니스 구현 변경의 별도 차량을 사전 승인")은 부정확하다. 원문 대조 결과, prereg §10 Q2의 승인 범위는 **레인-어웨어 job 소싱에 한정된다**(D4 추출기 + audit steps-matcher — §10 Q2의 "범위 포함 (audit steps-matcher)" 항까지). **본 차량이 실제 수행한 워크플로 경로 가드 수정(Gap A)은 prereg §10 어디에도 언급되지 않으며, §10의 승인 범위에 포함되지 않는다.** §10의 "별도 차량" 문언은 Q2가 승인한 소싱 변경의 구현 차량 지정일 뿐, 가드 수정을 포함한 일반 하니스 변경에 대한 일반 사전 승인이 아니다. 가드 수정의 차량 근거는 **오직** (a) AGENTS.md §2.5의 권한 조항("권한은 사용자 명시에만 있다")과 (b) 사용자 명시 허가(2026-10-17, "권한이 필요한 부분은 전면 허가한다") 뿐이다.
2. **처분 문언 정정**: 위 마지막 문장("…coherent-generation 전환 의식은 불요이며…")은 §2.5가 사용자 명시 권한에 유보한 판단("「작은 변경」이라는 독자 판단으로 절차·검증을 축약·생략하지 않는다 — 권한은 사용자 명시에만 있다")을 차량 수행자가 내린 것으로 읽힌다. 정정된 처분: 위 비례 절차(epoch-record형 본 증거 기록 + 표적 검증(§3) + 일반 큐 PR 착지)는 변경의 경미성에 대한 수행자 판정 때문에 적용된 것이 아니라, **AGENTS.md §2.5의 권한 조항에 따른 사용자 명시 허가(2026-10-17, "권한이 필요한 부분은 전면 허가한다") 아래에서 적용된 것이다**.

## 6. 재현

```bash
# 양성
bash tools/ci/merge_latency_audit.sh --runs 38925131342,38913175446,38891209338 --out /tmp/harness_pos
# 음성 (exit 1 필수)
bash tools/ci/merge_latency_audit.sh --runs 38977368334 --out /tmp/harness_neg
# 스캔 창
bash tools/ci/merge_latency_audit.sh --since 2026-10-16T09:00:00Z --until 2026-10-17T00:00:00Z --out /tmp/harness_scan
```
