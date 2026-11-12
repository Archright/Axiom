# Waiver 정본 감사 — 정본 선택 결정 입력 증거 (2026-10-17)

> **종류**: 결정 입력 증거(decision-input evidence)다 — **결정이 아니다**. `config/decision_binding.waiver.toml`(23 entries)과 `config/decision_binding.waiver.json`(259 entries) 중 어느 쪽을 정본으로 할지의 권한은 인간 아키텍트에게 있다. docs/spec/decision_binding_framework.md :172: "두 파일 중 어느 쪽이 정본인지는 **여기서 판정하지 않는다**(아키텍트 제안이 열려 있음)".
> **입력**: 위임 조사 로그 2건 — ① W-AUDIT 정적 감사(브랜치 `fix/judgment-cas-g10e-hermetic-2026-10-17`; 유니온 분류·소비자 맵·비대칭 파급·필드집합·문서 스테일 정정), ② EQ-TEST 실측 보고(`/tmp/waiver-eq-test` @ origin/main `848712413`, 2026-10-17; TOML 삭제 등가성 실측, VERDICT **CONFIRMED**). 본 문서는 두 로그 밖의 사실을 추가하지 않으며, 관측(observed)/코드 도출(code-derived)/사용자 보정 마킹을 그대로 유지한다.
> **감사 기준일**: 2026-10-17 고정 (§1).
> **위치 비고**: 본 문서는 /tmp에만 기록되는 결정 입력이므로 저장소 상대 링크 대신 경로 텍스트로 참조한다. 저장소 기록(착지)은 별개 완료 조건이다(§8).

## §1. 카운트 검증 — 문서 기재 재현 + 감사 기준일 고정

| 파일 | 파싱 결과 | 이상 |
|---|---|---|
| `config/decision_binding.waiver.toml` | `[[grandfather]]` **23개** (정규식 전량 파스, 잔여 비주석 행 0) | 없음 |
| `config/decision_binding.waiver.json` | 루트 키 `grandfather` 1개, JArray **259개** | 없음 |

- docs/spec/decision_binding_framework.md :172의 "TOML 23 / JSON 259" **정확히 재현**.
- 두 파일 모두 `git diff origin/main --` 비어 있음(= main과 동일). 파스 이상(비문자열 필드·불완전 JSON·불인덴트 항목) 0건.
- 필드집합(W-AUDIT (e)): TOML 23/23, JSON 259/259 모두 정확히 `{file, reason, expires}` 3필드 문자열. 추가 필드 0, 누락 0 → 프레임워크 :196-197 "The JSON form mirrors this exactly"는 필드 수준에서 참.

**감사 기준일 고정 — 2026-10-17.** 본 문서의 모든 "활성/만료" 판정은 이 고정일 기준이다. 런타임 규칙은 프레임워크 :192-197 verbatim: "An entry whose `expires < today` is treated as expired: it is excluded from the exempt set and reported as WAIVER EXPIRED" — 세 소비자 모두 ISO 문자열 비교 `expires < today`로 구현 일치(checker :154, gate :114, hermetic_build :1620). 전 항목 만료일이 2026-12-31이므로 소비 프로세스가 **2027년 이후** 실행되면 259건 전체가 `expires < today`로 면제 상실이고, `make check-decision-binding`의 에스컬레이션 문턱(30일)상 **2026-12-01부터** "expiring soon" → WARN이 FAIL로 전환된다(위반 존재 시). 즉 본 감사의 "활성" 판정은 고정일에만 유효하다.

## §2. 유니온 분류 (키 = `file`, 감사 기준일 2026-10-17 고정)

유니온 259개 파일:

| 클래스 | 건수 |
|---|---|
| 활성-공통 (양쪽 존재, 양쪽 비만료) | **23** |
| JSON-전용-활성 | **236** — 그중 **스테일 경로 9건**(파일이 디스크에 없음) |
| 만료(양쪽 동일 만료) | 0 |
| JSON-전용-만료 | 0 |
| TOML-전용-* | **0** (TOML 23개 전체가 JSON의 부분집합) |
| **불확정(격리)** | **0 — 공집합** |

**격리(불확정) = 공집합 명시 진술**: 미확정 항목은 존재하지 않는다. 236건 델타는 파일만으로 전량 처분 후보로 결정 가능하다 — 근거: (1) 스키마 이상 0(전 필드 문자열+ISO 날짜), (2) 파일 내 중복 0, (3) 교차 만료 충돌 0(전부 2026-12-31), (4) TOML-전용 0("TOML에만 있는 면제의 JSON 손실" 클래스가 원천적으로 없음), (5) 소비자 4곳의 실패 방향까지 확정(§3).

- **중복 0**: TOML 내 0(23 entries → 23 unique files), JSON 내 0(259 entries → 259 unique files), 완전동일 중복 0, 혼합 만료 파일 0.
- **교차 일치/상이**: 23개 겹침 파일 각각 양쪽에 1회씩 존재. **expires 23/23 전부 일치(2026-12-31)**. **reason 텍스트 17/23 상이**(예: TOML "predates" vs JSON "predate", "Violation count (9)" vs "High violation count (9)") — reason은 어느 소비자도 판정에 사용하지 않으므로 **판정 영향 0**이며, 두 파일이 단일 소스에서 생성되지 않고 **독립 편집되어왔다는 증거**다.
- 남는 것은 분류가 아닌 **규범적 편집 판단** 2가지다: ① 스테일 9건의 소재(prune vs 유지 — 어느 쪽이든 분류는 JSON-전용-활성), ② 겹침 17건의 reason 텍스트 중 정본 텍스트 선택(판정 무영향).

**스테일 경로 9건 전문**(JSON-전용-활성의 하위 클래스, 전부 "Grandfathered legacy code - pending rationale extraction" / 2026-12-31):

```
src/core/parsers/nav.nim
src/core/parsers/tree_sitter/cache.nim
src/core/parsers/tree_sitter_extractor.nim
src/core/parsers/tree_sitter_parse.nim
src/core/parsers/tree_sitter_parser.nim
src/core/types/symbolic_types_expr.nim
src/gate/runners/ci_pipeline_health_gate.nim
src/gate/runners/ci_skip_detector_gate.nim
src/gate/runners/private/documentation_first_gate_procs_part1.nim
```

샘플(W-AUDIT (b) 전문 인용) — 활성-공통 샘플 5 (TOML 전문, 전부 expires=2026-12-31):

```
src/core/trusted/architecture_invariants.nim | Pre-existing core invariants predate decision-binding policy
src/gate/static_gate_scanner.nim             | Pre-existing gate scanner predates decision-binding policy
src/gate/runners/debt_scan_gate.nim          | Pre-existing debt gate predates decision-binding policy
src/verification/solver/z3_pool.nim          | Highest violation count (17) — core Z3 solver pool...
src/core/vault/vault_factory.nim             | High violation count (13) — vault factory...
```

JSON-전용-활성 샘플 5 (236건 전부 동일 reason):

```
src/cli/action_output_cli.nim     | Grandfathered legacy code - pending rationale extraction | 2026-12-31
src/cli/action_plan_cli.nim       | Grandfathered legacy code - pending rationale extraction | 2026-12-31
src/cli/cli_io_input.nim          | Grandfathered legacy code - pending rationale extraction | 2026-12-31
src/cli/cli_surface_generated.nim | Grandfathered legacy code - pending rationale extraction | 2026-12-31
src/cli/debug_mode.nim            | Grandfathered legacy code - pending rationale extraction | 2026-12-31
```

## §3. 소비자 영향 — 기술 사실 (정책 후보와 분리된 섹션)

전장 grep으로 확정한 4 소비자와 실패 방향(W-AUDIT (d)):

| 소비자 | 읽는 파일 | 실행 시점 | 정본이 틀리면 (실패 방향) |
|---|---|---|---|
| `tools/decision_binding_checker.nim:101` | **JSON 전용** | 로컬 프리빌드 감사(바이너리 `bin/decision_binding_checker`, 게이트 시드 빌드 `tools/build_all_gates.nim:81`) | JSON 부재/불량 → `loaded=false` → **quit(1) fail-closed**(:371-374). 만료 항목은 제외+"WAIVER EXPIRED" |
| `src/gate/runners/decision_binding_gate.nim:89` | **JSON 전용** | 게이트 러너(매니페스트 `src/gate/manifest.d/decision-binding-gate.json`, stage=manual, severity=error) | JSON 부재/파스 실패 → `nil` → 면제 0 → 전수 스캔 → 위반 시 **게이트 FAIL**(면제 상실 방향 fail-closed) |
| `tools/hermetic_build.nim:1607(TOML)+1696(JSON)` | **양쪽 병합**(TOML이 코드상 먼저) | `make check-decision-binding`(Makefile:268-271, threshold 30) → GATES_STATIC(Makefile:39) → `local-verify-static[-full]` | 위반>0 AND `waiverEntries` 비었음 → **FAIL**(:1786); 만료 임박(30일 내) → **FAIL**(:1802); JSON 로드 실패는 **WARNING만**(fail-open, :1714 — TOML이 23건을 계속 공급해 빈집 FAIL은 안 됨); TOML 부재도 WARNING만 |
| `src/verification/evidence_cas.nim:97` | 내용 파스 없음 — **JSON 경로가 `PolicyDigestInputPaths[0]`**(5파일 체인 sha256 → attestation `policyDigest`) | 증명 CAS/attestation 기록 시 | **JSON 바이트 하나만 바뀌어도 policyDigest 변동** → 검증 레코드 identity 변경. TOML은 다이제스트 집합에 없음 → TOML 단독 편집은 CAS identity 중립 |

- 비소비자: `src/generated/decision_registry.nim:93`, `tools/sync_decisions.nim:208` — 양 파일을 결정 메타데이터(ADR-0009)로 **나열만**(내용 미독).
- `.githooks/`는 decision-binding 참조 0. `.github/workflows/`에서 이 파일들을 읽는 단계 없음(`merge-queue-rearm.yml:692`의 `bin/decision_binding_checker`는 TRANSIENT 분류 정규식 토큰일 뿐). **CI는 파일을 직접 소비하지 않음 — 전부 로컬 정적 검증 계층.**

## §4. EQ-TEST 실측 등가성 — "TOML 삭제 = 소비자 등가" CONFIRMED

환경: `/tmp/waiver-eq-test` @ origin/main `848712413` (2026-10-17). 원본 저장소의 `config/`는 미변경(`git status --porcelain -- config/` 비어 있음, 파일 타임스탬프 불변). 삭제 대상 TOML은 `/tmp/waiver-eq-toml-preserved.toml`(4153 bytes)에 보존. 사전 확인: JSON 259 entries(전부 `expires=2026-12-31`, 259 unique files), TOML 23 entries(전부 JSON의 엄격 부분집합, 만료일 동일).

| 항목 | baseline | TOML 삭제 후 |
|---|---|---|
| `make check-decision-binding` 종료코드 | **0** (cold run 1 / run 2 노이즈 플로어 모두) | **0** |
| `bin/decision_binding_checker --audit-mode` 종료코드 | 0 | 0 |
| checker 위반 수 | 41 | 41 (동일) |
| hermetic_build 위반 수 | 55 | 55 (동일) |
| 면제 수 (관측 가능 위치 전부) | 259 | 259 (동일) |
| checker 출력 diff (`baseline-checker.log` vs `after-checker.log`) | — | **0줄** |
| CAS `collectPolicyDigest` | `5578d62d52fffb23…` | **byte 동일** |

(41 vs 55 비대칭은 checker와 hermetic_build 간 **기존 스캐너 로직 차이**로, 양 실행에서 byte 동일 — TOML과 무관.)

warm-to-warm diff(`baseline2.log` vs `after.log`)는 정확히 2줄:

```diff
204a205
> [decision-binding] WARNING: waiver file not found: /tmp/waiver-eq-test/config/decision_binding.waiver.toml
463c464
< MAKE2_EXIT_CODE=0
---
> MAKE_EXIT_CODE=0
```

hermetic_build 구간 baseline→after: "Starting decision binding check..."(양쪽) → WARNING 1줄(after만, hermetic_build.nim:1688 else-branch) → "Found 55 violation(s)"(양쪽 동일) → "WARN: 55 function(s) missing {.axiomDecision.} pragma — escalation threshold 30 days not yet reached"(양쪽).

**EQ-TEST의 명시적 정정(기록 유지)**: 기대했던 "double-echo 소멸"은 실제로 존재하지 않았다 — `Loaded N active waiver(s)` 에코는 `tools/decision_binding_checker.nim:162-163`(JSON 전용) 소속으로 before/after 동일 출력이며, `hermetic_build.checkDecisionBindings`에는 그런 에코가 없다. 259는 관측 가능한 모든 위치에서 확인된다(checker 에코; hermetic_build의 `exemptFiles` — dedup :1599-1605).

**관측 3델타**(EQ-TEST (f) 그대로):

| # | 성격 | 내용 |
|---|---|---|
| 1 | 코스메틱 (관측) | `WARNING: waiver file not found` 1줄 추가 (hermetic_build.nim:1688) |
| 2 | 시맨틱·잠재 (코드 도출, 오늘 결과 중립) | `waiverEntries` 282→259 — TOML+JSON 겹침은 `waiverEntries`에선 디듑되지 않고 `exemptFiles`만 디듑. 오늘 중립인 이유: :1786은 emptiness만 검사, `anyExpiringSoon`은 bool. **2026-12-01부터** `WAIVER EXPIRING SOON` 에코가 겹침 23파일을 삭제 전 2회/삭제 후 1회 출력(이중 에코 소멸) — 종료코드는 여전히 동일 |
| 3 | 시맨틱·경계 (문서화) | JSON 로드 실패 시 fail-open 쿠션 제거 → hermetic_build **fail-closed 전환**(:1786), checker 계약과 정렬(decision_binding_checker.nim:370-374: `if not waiverLoad.loaded: FAIL ... quit(1)`). 이 경계에서 삭제는 **엄격히 더 안전** |

델타 3의 경계 상세(코드 도출, 트리거는 안 함; hermetic_build.nim:1696-1717): 삭제 전에는 JSON 로드 실패 시 TOML 로더(:1607-1686, 23 entries)가 `waiverEntries`를 유지 → :1786 가드(`if waiverEntries.len == 0: FAIL ... return 1`) 미발화 → 감사는 WARN/exit 0으로 진행하되 `exemptFiles`가 23으로 축소 → JSON-전용 면제 236건이 전수 스캔됨 — 위반 수가 급증하는데도 게이트 통과(under-grading, fail-open). 삭제 후에는 JSON 실패 → `waiverEntries = @[]`, `exemptFiles = @[]` → :1786-1788 `FAIL: ... no active waivers; return 1` — **fail-closed**.

**CAS digest 중립 — 증명됨**: `PolicyDigestInputPaths`(evidence_cas.nim:96-101)는 정확히 5파일이며 JSON이 `[0]`, TOML은 부재:

```
config/decision_binding.waiver.json
config/policy/epoch_manifest.json
config/policy/landing_required_gateway_tests.json
config/policy/merge_admission.json
config/trusted_writer_set.json
```

`collectChainedFileDigest`(:365-382 — 멤버별 `content.add(rel & ":" & bytes & "\n")` 후 단일 `sha256Hex`)를 미러링한 `policy_digest.py` 재계산 결과, 5개 per-file sha256과 체인 다이제스트 모두 before/after **byte 동일** — `collectPolicyDigest = 5578d62d52fffb23144e4d4f2c3b6de0d2c133fcb4ca307498a8095bc7e90956` 양쪽(`policy_digest_before.txt` ≡ `policy_digest_after.txt`).

**검증 요구의 충족**: "TOML⊂JSON이므로 삭제가 등가"라는 **집합 추론만으로는 불충분했다**는 검증 요구가 — 종료코드 0/0/0·위반 수 41/55 동일·checker diff 0·CAS digest byte 동일이라는 **실측으로 충족**되었다(VERDICT: CONFIRMED).

범위 한계(EQ-TEST caveats 유지): 본 실측 스코프는 라이브 main @848712413(2026-10-17)의 감사 경로(`make check-decision-binding`)다. 향후 저장소 전체 삭제 시의 스코프 밖 참조 2곳 — `tools/sync_decisions.nim:208`, `src/generated/decision_registry.nim:93`(ADR-0009 메타데이터 나열, 로더 아님). `src/gate/runners/decision_binding_gate.nim:89`는 JSON 전용으로 예상대로. 산출물: `/tmp/waiver-eq-test/`에 로그 전체(`baseline.log`, `baseline2.log`, `baseline-checker.log`, `after.log`, `after-checker.log`) + digest 증명. 클론은 변형 상태로 남아 있음(TOML 부재 — 필요 시 보존본 `/tmp/waiver-eq-toml-preserved.toml`으로 복원).

## §5. 비대칭 파급 — 기술 사실 (결정 권한의 대행 아님)

| 시나리오 | checker | gate | hermetic_build | CAS policyDigest |
|---|---|---|---|---|
| **JSON 정본 + TOML 삭제** | 무영향(실측 0/0) | 무영향 | 실측 등가(§4) | **byte 동일(중립)** — 추가로 JSON 로드 실패 경계가 fail-closed로 안전화 |
| **TOML 정본 + JSON 삭제** | **하드 실패(exit 1)** | **면제 236건 상실** → 위반 시 게이트 FAIL | — | **변동** (JSON이 `PolicyDigestInputPaths[0]`) |

- JSON 정본 방향: 면제 집합 손실 0(TOML⊂JSON), checker·gate·CAS 다이제스트 무영향 — §4 실측으로 확인. 운영 하중은 전적으로 JSON에 있다.
- TOML 정본 방향(W-AUDIT (g)4): checker 하드 실패(exit 1), gate 면제 236건 상실, CAS policyDigest 변동.
- **단, 이 절은 기술적 파급에 관한 판단이지 정본 선택 권한의 대행이 아니다.** 어느 쪽을 정본으로 할지는 아키텍트의 결정 사항이다(프레임워크 :172 "아키텍트 제안이 열려 있음").

### 정정 — 정본 문서 자체의 스테일 기술 (W-AUDIT (g), 기록 유지)

1. 프레임워크 :160/:172 "checker가 JSON 먼저, TOML 폴백(:162)" — **스테일**. 현재 checker에 TOML 경로가 존재하지 않음(파일 내 "toml"은 `axiom.toml` 루트탐지 :25뿐). 헤더 :73-78 "the only format... deliberately no second format and no partial fallback". :162는 이제 "Loaded N active waiver(s)" 에코다. DEBT#479 종료 이후 재작된 것으로 보임(`data/debt_registry.json` 해당 항목 Closed).
2. "JSON을 먼저 읽는다"는 순서도, 유일한 양파일 소비자인 hermetic_build에서는 **반대**다 — 코드상 TOML(:1607)이 JSON(:1696)보다 먼저.
3. 프레임워크 :160 전제 오류: 같은 문장이 "runtime이 소비하는 waiver는 zero active"라고 서술하면서 괄호로 259 entries를 인용 — 감사일 기준 활성은 **259**다(전부 미만료). "zero active"는 전환 목표 상태가 현재형으로 쓰인 오기.
4. 프레임워크 :451/:460/:470 예시 로그 `"...from decision_binding.waiver.toml"` — **스테일 포맷**. 실제 출력은 `"...from decision_binding.waiver.json"`(예: `experiments/act3-o1-verified-warm-protocol/results/warm_build_output.txt:50` "Loaded 259 active waiver(s) from decision_binding.waiver.json").

## §6. 시한과 미결정 처리 (사용자 보정 — 위임 지시에 따른 필수 절)

- **만료 전 상태**: 259건 전부 `expires=2026-12-31`(감사 기준일 2026-10-17 기준 전부 활성).
- **에스컬레이션**: **2026-12-01부터** 30일 문턱 진입 → "expiring soon" WARN→FAIL 전환(위반 존재 시; hermetic_build :1802, `make check-decision-binding` threshold 30).
- **전면 만료**: 2026-12-31 경과 후 소비 프로세스 실행 시점부터 런타임 규칙 `expires < today`에 의해 259건 전체 면제 상실(WAIVER EXPIRED).
- **결정 시한 제안: 2026-11-30 이전**(에스컬레이션 개시 전). — 본 문서가 제안하는 것일 뿐 결정이 아니다.
- **미결정 시 처리: 현상 병존 유지.** 런타임 소비는 이미 JSON 우선이다(checker JSON 전용·gate JSON 전용·hermetic_build 양파일 병합 — §3) — 운영 연속성·정합성 문제가 없다. TOML 삭제조차 실측 등가인 이상(§4), 병존 유지는 그보다 더 보수적인 상태다.
- **지연의 자연적 결과**: 12-01 에스컬레이션과 12-31 전면 만료는 **결정 지연의 자연적 결과**다 — 자동 폐기/부활 절차가 아니다. 면제 연장·정리가 필요해지는 경우 별도 prereg가 필요하다.

## §7. 재현 명령 집합

카운트:

```bash
# TOML [[grandfather]] 항목 수 (정규식 전량 파스)
grep -c '^\[\[grandfather\]\]' config/decision_binding.waiver.toml   # → 23
# JSON grandfather 배열 길이
python3 -c "import json;print(len(json.load(open('config/decision_binding.waiver.json'))['grandfather']))"   # → 259
# main 동일성 확인
git diff origin/main -- config/decision_binding.waiver.toml config/decision_binding.waiver.json   # → 비어 있음
```

만료 판정(감사 기준일 고정): 모든 entry에 대해 ISO 문자열 비교 `expires < <감사 기준일>` — 런타임과 동일 구현(checker :154, gate :114, hermetic_build :1620).

EQ-TEST 재실행 절차 요약:

```bash
# 1) 격리 클론 @ 848712413
git clone <origin> /tmp/waiver-eq-test && git -C /tmp/waiver-eq-test checkout 848712413
# 2) baseline: 2회 실행(cold + 노이즈 플로어) + checker 감사 모드
make -C /tmp/waiver-eq-test check-decision-binding              # exit 0
make -C /tmp/waiver-eq-test check-decision-binding              # exit 0
/tmp/waiver-eq-test/bin/decision_binding_checker --audit-mode   # exit 0
# 3) TOML 보존 후 삭제
cp /tmp/waiver-eq-test/config/decision_binding.waiver.toml /tmp/waiver-eq-toml-preserved.toml
rm /tmp/waiver-eq-test/config/decision_binding.waiver.toml
# 4) after: 동일 실행 → warm-to-warm diff 2줄 + checker diff 0 확인
make -C /tmp/waiver-eq-test check-decision-binding              # exit 0
diff baseline2.log after.log                                    # → WARNING 1줄 + MAKE*EXIT_CODE 라벨
diff baseline-checker.log after-checker.log                     # → 0줄
# 5) 원본 저장소 config/ 미변경 확인 + 종료 후 클론 상태 회수
git status --porcelain -- config/                               # → 비어 있음
```

digest 계산:

```bash
# evidence_cas.nim collectChainedFileDigest(:365-382) 미러링:
# PolicyDigestInputPaths 순서로 각 멤버를 "rel:bytes\n"로 연결 후 sha256 단일 해시
python3 - <<'EOF'
import hashlib, pathlib
root = pathlib.Path("/tmp/waiver-eq-test")
paths = ["config/decision_binding.waiver.json","config/policy/epoch_manifest.json",
         "config/policy/landing_required_gateway_tests.json","config/policy/merge_admission.json",
         "config/trusted_writer_set.json"]
content = "".join(f"{p}:{(root/p).read_bytes()}\n" for p in paths)
print(hashlib.sha256(content.encode()).hexdigest())
# 기대값(삭제 전후 동일): 5578d62d52fffb23144e4d4f2c3b6de0d2c133fcb4ca307498a8095bc7e90956
EOF
```

기존 실측 산출물: `/tmp/waiver-eq-test/{baseline,baseline2,baseline-checker,after,after-checker}.log`, `policy_digest_{before,after}.txt`, `policy_digest.py`.

## §8. 결정 요청

- **요청 대상·사항**: 인간 아키텍트에게 waiver 정본 선택을 요청한다 — (안 1) JSON 단일 정본 + TOML 삭제, (안 2) TOML 정본 + JSON 삭제, (기타). 판정 재료는 §3(소비자 실패 방향)·§4(실측 등가성)·§5(비대칭 파급)다. 기술 증거 요약: JSON 정본 방향은 실측 등가·CAS 중립·경계 안전화이며, 역방향은 checker exit 1·면제 236건 상실·CAS policyDigest 변동을 수반한다. 처분 가능성: 격리 공집합(§2) — 미확정 항목 없음.
- **결정 시한 제안**: 2026-11-30 이전(§6 — 에스컬레이션 개시 전).
- **미결정 시**: 현상 병존 유지(§6).
- **결정 후**: 마이그레이션 계획은 **별도로 수립**된다 — 정본 선택(결정)과 본 감사 문서의 착지는 **별개 완료 조건**이다. 마이그레이션 계획 수립 시의 기록된 입력은 §2의 규범적 편집 판단 2건(스테일 9건 소재, 겹침 17건 reason 텍스트 정본)과 §5 정정(정본 문서 자체의 스테일 기술)이다.
