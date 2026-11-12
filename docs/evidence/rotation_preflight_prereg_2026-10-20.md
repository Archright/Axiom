# VS-1 PR-head 회전핀 프리플라이트 사전등록 — verdict·preflight venue의 H2 대조 (2026-10-20)

> **종류**: 사전등록 문서 (pre-registration) — `admission-check` 공유 job의 **verdict stage · PR venue(preflight)** 에 추가되는 VS-1 회전핀 H2 대조 스텝의 입력·판정·실패-폐쇄 매트릭스·수용 기준을 후보 런이 한 번이라도 실행되기 전에 전부 고정한다. 구현 차량은 `.github/workflows/admission-check.yml` (브랜치 `ci/vs1-rotation-preflight-2026-10-20`)이며, 본 문서는 그 계약의 정본이다.
> **권위**: 본 스텝은 **Reporter/adapter**다 — 병합 판정 권위(GitHub ruleset·required checks·merge queue·native MERGE 커밋)를 대체하지 않는다(Authority ≠ Adapter, AGENTS.md §2.3). 착지 판정은 변하지 않는다: landing venue의 `ax merge --dry-run` 조부 스텝(`admission-check.yml:2137` — `[check] Admission predicate evaluation`; 행 번호는 2026-10-20 브랜치 스냅샷 기준)은 본 변경과 무관하게 byte-identical로 유지되며, 회전 admissibility의 정판정 권위는 merge_group venue + org 게이트에 그대로 있다.
> **새 required check 없음**: 본 스텝은 기존 필수 `admission-check` job **내부**의 한 스텝이다 — RequiredChecks 집합에 어떤 이름도 추가·변경하지 않는다. 실패 = 기존 required check RED(기계 집행: 스텝 exit 1 → job failure), 통과 = 여전히 **preflight일 뿐** 착지 증거가 아니다(ADR-0032 (f)).
> **no-peeking**: 본 문서의 모든 기준은 구현 커밋 이전에 고정된다. 관측을 본 뒤의 기준 변경은 새 날짜의 사전등록 문서로만 한다.

---

## 1. 목적 (Purpose)

PR venue(preflight)에서 **회전(rotation) PR이 pin@H와 파생 클로저(derived-H)의 집합 일치(H2)를 깨는 순간 required check를 RED로 만드는** 조기 차단 게이트를 추가한다. 오늘의 PR preflight verdict leg는 policy SSOT + stage-dispatch 구조 대조만 수행하고(`admission-check.yml:1886`), pin↔closure 부정합을 전혀 관측하지 않는다 — 부정합 회전 PR은 merge_group verdict에 도달해야만 적발되며, 그때까지 큐 진입·벽시계·리소스를 소진한다(전형적 상황: `trusted_writer_set.json`을 일반 PR로 편집 → landing ROT 계열 reasonCode로 DENY, 전체 파이프라인 재실행 비용). VS-1은 같은 부정합을 **PR 이벤트 런 안에서** fail-closed 적발한다.

판정 대상(H2): **set/내용(pin@H) vs 파생 클로저(derived-H)** — 구체 비교 규칙의 단일 구현은 `tools/ci/rotation_pin_anchor_check.nim`이 갖는다(§4). 본 워크플로 스텝은 그 오라클을 호출하고 exit 계약을 분류하는 **판정 소비자**일 뿐이다.

## 2. 입력 (Inputs — artifact-only, 단일 공급 경로)

- **유일 입력**: org 게이트가 PR 런에 발행하는 **같은-런 artifact `derived-closure`**. PR venue 생산자 계약은 **4-파일 집합**이다 — `derived-H.txt`, `derived-B.txt`, `pin-H.json`, `identity.json` (PR venue 생산자는 `derived-M.txt`를 내지 않는다; candidate-delta M leg는 landing-only다). 소비 스텝은 전용 staging dir `.derived-closure-preflight/`에 전용 다운로드로 받으며, landing leg의 5-파일 all-or-none 로더(`admission-check.yml:1827`)는 재사용하지 않는다.
- **생산자 실패 전파**: caller의 verdict job은 `needs: [mint-prepare, closure-deriver, anchor-resolve]` — closure-deriver 실패는 artifact 부재로 전파되고, 소비 스텝이 fail-closed 분류한다(§5).
- **NO local re-derivation fallback (HARD)**: 이 venue에는 in-place 유도 분기가 **존재하지 않는다**. landing leg의 in-place deriver(`bin/derive_checker_closure`) 폴백은 landing-scoped이며 그대로 landing에 남는다. artifact가 없거나 불완전하면 판정하지 않고 RED다 — "아티팩트가 없으니 여기서 유도하자"는 이 게이트의 공급 신뢰 모델을 파괴하는 금지 경로다.
- **판정기 공급**: `tools/ci/rotation_pin_anchor_check.nim`은 **B 워크스페이스(체크아웃 루트 = base.sha)** 에서 컴파일된다 — `nim c --hints:off --skipParentCfg --skipProjCfg --path:src -o:bin/rotation_pin_anchor_check ...` (Gate A: PR tree는 data only; deriver와 동일한 hermetic 레시피). preflight verdict leg는 setup-axiom-toolchain full provisioning(`admission-check.yml:872-877`)으로 nim+jq를 보유한다.

## 3. 식별자 바인딩 (Identity binding)

**판정의 키는 `identity.candidateHeadSha`다 — verdict JSON의 `headSha`가 아니다.** (preflight에는 애초에 verdict JSON이 없다; 규약은 landing leg의 L1과 동일한 키 선택을 강제한다.) 사다리 순서:

1. `identity.json` 파싱 + `candidateHeadSha`/`pinHeadBlobSha` 40-hex 형식 → 위반 시 `NOT_ADMIT_ROT_UNPARSED`.
2. `candidateHeadSha == 이벤트 PR head sha` (순수 등식 — **네트워크 접근 전에** 변조/wrong-run 클로저 주입을 거부한다).
3. 경계 객체 fetch (by-object, depth-1 — landing L1 leg와 동일한 clause-2 object-set 형태; `tools/ci/git_access_scan.sh` 인벤토리 대상) 후 `identity.pinHeadBlobSha == git rev-parse H:config/trusted_writer_set.json` → 불일치 = 변조·stale 생산자 → `NOT_ADMIT_ROT_UNPARSED`.

landing L1이 추가로 묶는 `baseSha`/`runAttempt` 동일성은 이 venue 계약에 포함하지 않는다(범위 폐쇄 — 최소 변경; 착지 정합성은 landing authority가 유지한다).

## 4. 단일 판정 구현 (Single judgment implementation)

H2의 유일 오라클은 `tools/ci/rotation_pin_anchor_check.nim`이다 — 호출: `bin/rotation_pin_anchor_check --derived-H <file> --pin-H <file>` (`--pin-B`는 전달하지 않는다). 체커는 `--pin-B` 미전달 시 cwd 기본 경로 `config/trusted_writer_set.json`(워크플로 스텝의 cwd = 워크스페이스 루트 = B 체크아웃)을 **항상** 읽고, 읽지 못하면 exit 2(입력 계약 위반)로 종료한다 — 따라서 exit 1은 "체커가 pin@B를 읽고 H2가 깨졌다"를 함축하며, 워크플로의 exit-1 분류는 **같은 단일 경로의 같은 파일**을 §5의 술어로 재판독할 뿐이다(이중 공급·2차 판정 아님 — 클래스만 결정). stdout 계약 `H2 <PASS|FAIL> code=<...>` (`H2 PASS code=OK` / `H2 FAIL code=<ROT_NEW_PIN|ROT_GENESIS_INVALID> reason=<...> | missing-from-pin=<paths> | pin-only=<paths>`), exit 계약 `0=pass, 1=H2 fail, 2=input contract violation`. 워크플로는 이 exit 코드와 §5 술어 외에 어떤 판정도 **재구현·재유도하지 않는다** — 집합 비교 로직이 워크플로 셸에 복제되면 단일 구현 원칙이 깨진다.

## 5. 실패-폐쇄 매트릭스 (Fail-closed matrix — 전부 기계 판정)

| # | 조건 | 주석(annotation) title | 스텝 exit | 증거 errorClass |
|---|---|---|---|---|
| 1 | artifact 부재 / 4파일 중 누락·0바이트 | `NOT_ADMIT_ROT_UNPARSED` | 1 | `ROT_UNPARSED` |
| 2 | identity.json 파싱 실패 / 필드 형식 위반(40-hex) | `NOT_ADMIT_ROT_UNPARSED` | 1 | `ROT_UNPARSED` |
| 3 | `candidateHeadSha != 이벤트 PR head` | `NOT_ADMIT_ROT_UNPARSED` | 1 | `ROT_UNPARSED` |
| 4 | `pinHeadBlobSha != blob@H` | `NOT_ADMIT_ROT_UNPARSED` | 1 | `ROT_UNPARSED` |
| 5 | 체커 컴파일 실패 (소스 @B 부재 포함) | `NOT_ADMIT_ROT_UNPARSED` | 1 | `ROT_UNPARSED` |
| 6 | 체커 exit 2 / 기타 비(非)0/1 종료 | `NOT_ADMIT_ROT_UNPARSED` | 1 | `ROT_UNPARSED` |
| 7 | 체커 exit 1 ∧ pin@B가 `trustedCheckerTreeClosure` 키 **보유** | `NOT_ADMIT_ROT_NEW_PIN` | 1 | `ROT_NEW_PIN` |
| 8 | 체커 exit 1 ∧ pin@B 파일은 읽히나 키 **부재** (genesis state, ADR-0025 §7) | `NOT_ADMIT_ROT_GENESIS_INVALID` | 1 | `ROT_GENESIS_INVALID` |
| 8b | 체커 exit 1 ∧ 분류 시점에 워크스페이스 pin을 읽을 수 없음/파싱 불가 | `NOT_ADMIT_ROT_UNPARSED` | 1 | `ROT_UNPARSED` |
| 9 | 체커 exit 0 | (주석 없음) `ROTATION-PIN PREFLIGHT PASS` 로그 | 0 | `NONE` (result=PASS) |

- 1–6·8b행은 판정 **입력 계약** 위반이다 — "판정 불가"는 절대 "통과"가 아니며 fail-closed RED다(검증 불가 = fail closed, GUARDIAN).
- 7–8행의 분류자는 **체커와 동일한 pin@B 술어**다(`rotation_closure_facts.nim` `newAnchorVerdict` — 체커는 `--pin-B` 미전달 시 cwd 기본 경로 `config/trusted_writer_set.json`(= 워크스페이스 루트, B 체크아웃)를 항상 읽는다): 읽히는 pin 파일에 closure 키가 **없으면** genesis state(ADR-0025 §7 일회성 genesis 예외 부정립) → `ROT_GENESIS_INVALID`, 키가 **있으면** 회전 신규-pin 주체 → `ROT_NEW_PIN`. 워크플로가 이 술어를 그대로 재적용하므로 주석 클래스와 체커 자체 코드(`H2 FAIL code=<...>`)가 절대 어긋나지 않는다. 파일 부재·JSONC 제거 후에도 파싱 불가는 클래스가 아니라 8b행(UNPARSED)이다 — 체커 exit 1은 체커가 pin-B를 읽었다는 전제를 담으므로, 분류 시점에 같은 파일을 읽지 못하는 것은 상태 불일치이며 결코 추측 분류하지 않는다.
- 모든 실패 주석은 **체커 사유/불일치 경로**(`H2 FAIL code=... reason=... | missing-from-pin=<paths> | pin-only=<paths>`, 900자 한도 인코딩)를 운반하며, `rotation-preflight.json` 증거가 모든 종료 경로에서 기록되고 `always()` 업로드(`if-no-files-found: error`, name `rotation-preflight-<candidate head>-<run_attempt>`)로 보존된다 — RED의 주석이 가리키는 증거가 항상 남는다.
- **스코프 게이팅 금지**: 스텝 조건은 정확히 `inputs.stage == 'verdict' && steps.venue.outputs.venue == 'preflight'`다 — `scope_sl02`/`scope_sl05` 접속사를 **의도적으로 갖지 않는다**. 스코프 접속사는 epoch manifest 누락만으로 회전 대조를 조용히 스킵시킬 수 있고(§0.9 스킵-더-체크 극장), 이는 본 게이트가 존재 이유 그 자체다. 따라서 H2 판정 스텝은 무조건 발화하며, 이 무조건성이 본 문서가 등록하는 계약이다(다운로드 스텝은 이 파일의 모든 artifact 다운로드가 속한 비(非)게이트 provisioning 계층이다).

## 6. 사유 코드 (Reason codes)

- `NOT_ADMIT_ROT_NEW_PIN` — H2 불일치 + pin@B가 closure 키 보유. 일반 PR 경로로는 회전 신규 pin을 착지시킬 수 없다(회전 절차/allowlist 경로가 유일 승격 경로).
- `NOT_ADMIT_ROT_GENESIS_INVALID` — H2 불일치 + pin@B에 closure 키 부재(genesis state). 일회성 genesis 예외(ADR-0025 §7)가 부정립되는 H2 불일치다.
- `NOT_ADMIT_ROT_UNPARSED` — 입력 계약 위반(artifact·identity·체커 계약·분류 시점 pin 판독 불가). PR의 회전 적합성에 대한 판단이 아니라 "판정 불가"의 fail-closed 표현이다.

## 7. 부정/대조 픽스처 (Negative / control fixtures)

구현 검증은 아래 픽스처의 기계 관측으로 한다(스텁 하니스 + 실체 체커 바이너리 스모크 + 착지 후 실런). 브랜치 상태에서 (a) 스텝 run body를 실제 YAML에서 추출해 실행한 결과와 (b) 실체 `rotation_pin_anchor_check` 바이너리(Nim 2.2.10, 문서화 레시피 컴파일 1.6s) 스모크 결과를 괄호로 기록한다 — 전부 통과 (2026-10-20).

| 픽스처 | 구성 | 기대 (HARD) | 검증 |
|---|---|---|---|
| F-NEG-1 신규 회전 | pin@H ∉ closure(derived-H), pin@B에 closure 키 보유 | `NOT_ADMIT_ROT_NEW_PIN` RED, 체커 사유·불일치 경로 주석 | (PASS — 하니스 exit=1; 실바이너리 `code=ROT_NEW_PIN` 일치) |
| F-NEG-1b JSONC pin | 위와 동일 + pin@B가 JSONC 주석 포함 | 동일 — 주석 제거 후 키 판별 | (PASS) |
| F-NEG-2 genesis 무효 | pin@H 불일치, pin@B는 읽히나 closure 키 **부재** | `NOT_ADMIT_ROT_GENESIS_INVALID` RED | (PASS; 실바이너리 `code=ROT_GENESIS_INVALID` 일치) |
| F-NEG-2b pin 파일 부재 | pin@B 파일 없음 | 체커가 cwd 기본 pin-B를 읽지 못해 **exit 2** → `NOT_ADMIT_ROT_UNPARSED` RED (genesis 아님 — 판정 불가는 fail-closed) | (PASS) |
| F-NEG-3 wrong-run 클로저 | identity.candidateHeadSha ≠ 이벤트 head | `NOT_ADMIT_ROT_UNPARSED` RED (네트워크 전 거부) | (PASS) |
| F-NEG-4 pin 변조 | pinHeadBlobSha ≠ blob@H | `NOT_ADMIT_ROT_UNPARSED` RED | (PASS) |
| F-NEG-5 artifact 부재 | 다운로드 실패/부분/0바이트 | `NOT_ADMIT_ROT_UNPARSED` RED — 재유도 폴백 없음 | (PASS) |
| F-NEG-6 체커 계약 위반 | 체커 exit 2 | `NOT_ADMIT_ROT_UNPARSED` RED | (PASS) |
| F-CTRL-1 일반 PR | pin@H == pin@B(키 보유), 클로저 불변 | 체커 exit 0 → PASS, job GREEN, 증거 result=PASS | (PASS; 실바이너리 `H2 PASS code=OK`) |
| F-CTRL-2 정당 회전 | pin@H == closure set(derived-H) | PASS (GREEN) — 단, 착지 admissibility는 여전히 merge_group 권위 | (PASS) |

## 8. 수용 (Acceptance — 타임라인/스냅샷 기준)

- **수용 판정은 실행 타임라인/스냅샷으로 한다**: F-NEG-x 구성의 PR-event(preflight) 런에서 required check `admission-check`가 RED이고, 그 런의 체크-런 타임라인에 §5의 주석 title이 존재하며, `rotation-preflight-<head>-<attempt>` artifact의 `errorClass`가 매트릭스와 일치한다. F-CTRL-x는 같은 관찰 체계에서 GREEN + result=PASS 증거.
- **merge_group 부재만으로 수용하지 않는다**: 큐 진입은 여전히 발생할 수 있고(ALLGREEN 역사) dequeue될 수 있다 — "큐에 안 들어갔다"는 본 게이트의 증거가 아니다. 수용의 정본 관찰 단위는 PR-head 이벤트 런의 체크-런 결과 스냅샷이다.
- **완료는 기계 검증**: `make check-workflow-shell-syntax` (2026-10-20 기준: run blocks checked=185, failures=0, lane-guard=0) + §7 픽스처 하니스 + YAML 파싱. "구현했다"는 주장은 위 관측 없이 완료가 아니다.
- **세대 경계**: 본 워크플로 변경이 활성화되려면 `tools/ci/rotation_pin_anchor_check.nim`이 B(=main)에 존재해야 한다 — 체커 없이 본 파일만 착지하면 모든 PR preflight verdict가 F-NEG-5(컴파일 실패 → `NOT_ADMIT_ROT_UNPARSED`)로 RED다. 통합(parent)은 두 파일을 일관 세대로 착지시킨다(§2.5 — in-place 혼합 상태 금지).

## 9. 범위 밖 (Out of scope)

- **NO_CERT** — 인증서 요구 판정(certRequired)은 landing verdict/org 게이트 권위다. 본 프리플라이트는 인증서를 소비하거나 요구하지 않는다.
- **ROT_ALLOWLIST** — 회전 allowlist 개정(PR-α)·TWS pin ceremony의 승인 판정은 org 게이트 권위다. 본 게이트는 그 경로의 유일성을 대체하지 않고, **일반 PR 경로에서의 우회**만 차단한다.
- **UNPARSED(착지 계열)** — landing verdict의 run-level err 클래스(`NOT_ADMIT_UNPARSED`)와 본 게이트의 `NOT_ADMIT_ROT_UNPARSED`는 별개다. 후자는 입력 계약 가드일 뿐 PR에 대한 verdict가 아니며, 착지 판정 권위를 예고·대체하지 않는다.
- **landing predicate 판정 변경** — `ax merge --dry-run`의 판정과 required-check 의미는 불변이다. 같은 세대에 포함되는 `src/cli/merge_cli.nim` 변경은 §4의 단일 판정 추출(`newAnchorVerdict`로의 위임)뿐이며, 코드·사유 문자열이 byte-identical함을 기존 `test_merge_cli` 스위트가 그대로 고정한다(동작 변경 0).
- 본 작업 범위 밖: 새 required check 등록, merge_group venue 동작 변경, `ROT_ALLOWLIST`/`NO_CERT` 판정 개정 — 전부 금지이며, 위반 시 본 등록 무효. `config/trusted_writer_set.json`의 pin 갱신은 판정 변경이 아니라 회전 자체의 산출물(§8 세대 경계)이다.
