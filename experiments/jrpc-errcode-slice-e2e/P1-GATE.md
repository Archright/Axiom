# P1 — 바인딩 형상 실증 (게이트 판정 기록)

> FREEZE.md §13의 3게이트에 대한 실증 결과. 판정: **전부 통과 — 구현 착수.**

## 게이트 1 — of-매트릭스 관찰: **PASS (13/13)**

실행: `/tmp/jrpc-probe/probe_errclass_matrix.nim` — Nim 2.2.10, 핀 dep 5종(nimble pkgs2:
json_serialization-0.2.9-4062dc79 / serialization-0.2.6-26deca68 / stew-0.5.0-db229429 /
faststreams-0.3.0-ec2d9279 / results-0.5.1-a9c011f7) + 피검험체 status-im/nim-json-rpc
READ-ONLY 체크아웃 @ debf33cabf7be009a2e905d4c7921b85eb7ca6dd.
빌드: `nim c -r --noNimblePath -p:<5종> -p:<json-rpc root>` (agent-7 프루브와 동일 구성).

관측 (13 인스턴스 × 8 판별자 = 리프 7 + 베이스 1):

| 관측 항목 | 결과 |
|---|---|
| 베이스 참 = 1 (전 인스턴스) | ✅ (도메인 사전조건 — 정적 폴딩 CondTrue로 확인, 런타임 판별 아님을 기록) |
| 리프 참 ≤ 1 (모호성 0) | ✅ leafCount ∈ {0, 1}만 관측 |
| leafCount=0 ∧ base → RpcResponseError (제네릭) | ✅ -32768, -32100 |
| observed == expected (13/13) | ✅ 전부 일치 — FREEZE §6 표와 정확히 동일 |
| fail-closed 조건 ①~④ 위반 | **0건** |

수정 불변식(리프 ≤ 1 ∧ 베이스 = 1)이 관찰의 완전성·배타성을 실증 수준에서 성립시킴.
FREEZE §6 경계값 13개의 기대 분류가 원본 실행과 전부 일치.

## 게이트 2 — 채택 파일 경로·routing 범용성: **PASS (판정: 새 lane 경로)**

소스 실증 (worktree @ 09b42c5):

1. **registry 스캔은 범용**: `loadRegistry`가 `walkDir(specDir)`로 config/spec 하위 전체를
   스캔 (external_subject_registry.nim:797-811) — 새 오버레이 JSON 추가 시 자동 발견.
   "Same input directory ⇒ identical registry" (:782) — 결정론적.
2. **routing은 module+symbol 키의 정확 일치**: `overlayDeclaresSidecarSubject` =
   `modulePath == domain.modulePath and fnName == domain.symbol` (axiom_engine.nim:2342-2347)
   — nim-stew 하드코딩 아님. subject 겹침 시 registry가 거부 (:848).
3. **sidecar 파일 위치 = Axiom 측 config/spec/** (AXIOM_ROOT anchor walk, :57-63) —
   피검험체 tree 무수정 유지 (Zero-Footprint 정합).
4. **판정 — sidecar 레인(capBodyCarry) 직접 재사용은 불가**: D2가 "원본 바디를
   materialize해 통째로 운반"하는 body-carry 전제 (sidecar 계약 §4 D2). 우리 피검험체
   바디는 template+obj-constr+move+`in` (subset 밖 — Axiom #119)이므로 loss-free
   materialize 불가.
   **FREEZE §2의 형상(bytesview = 채택 모델 + 관찰)이 이미 이 판단을 반영 중이므로
   재동결 불필요** — 채택 파일의 "구조"(2단 hash-bound 검증·SpecID 재계산·subject 핀)는
   그대로, **capability는 capConstructedGate 계열의 신규 lane**으로 구현한다.
5. **문법 확장 필요 확정**: `sidecarPrimary`가 음수 리터럴을 명시적으로 거부
   (axiom_engine.nim:2366-2401 "no negative literals") — FREEZE §7의 신규 버전 핀
   문법 `nim-jrpc-errclass-v1`(음수 포함)이 유일한 경로. "새 문법은 새 엔진 버전" —
   v0.7.0 출하와 정합.

## 게이트 3 — 엔진 추가점 실존: **PASS (전부 실존 확인)**

| 추가점 | 위치 | 상태 |
|---|---|---|
| 폐쇄 템플릿 디스패치 (신규 id 추가점) | external_subject_registry.nim:225-235 | 실존 — case문 + fail-closed else |
| d2 형상 post 생성기 (형상 전례) | counterexample_replay.nim:1407-1422 | 실존 — shape 검증·fail-closed |
| stamped-template 재생 브랜치 | counterexample_replay.nim:1475-1496 | 실존 — generic 형상 (현재 d2 명명) |
| CapabilityAdapter 프레임 (신규 lane 등록점) | axiom_engine.nim:4406-4453 | 실존 — d2·sidecar·cout 어댑터 전례 |
| registry walkDir 발견 | external_subject_registry.nim:797-811 | 실존 — 위 게이트 2 |
| typedesc 캐리어 토큰 전례 | sidecar 계약 §5 | 실존 — `decodedLength(Base36Types, <lit>)` 형상 |

## P2 구현 설계 확정 (게이트 통과의 귀결)

- **신규 lane** `jrpc-errclass` (capConstructedGate 계열): validate(FREEZE §7의 2단
  hash-bound + 폐쇄 문법 nim-jrpc-errclass-v1) · declares(module+symbol 키) ·
  synthesize(모델 캐리어 = 채택 매핑의 irIf 사슬 + post 생성 + 재생 템플릿 스탬프)
- **폐쇄 레지스트리 템플릿** `errors-class-v1`: 원본 모듈 include → `new(code,…)` 실행 →
  8판별 매트릭스 → 관찰 클래스 산출(FREEZE §8) → BEGIN/END 마커 echo — expected는
  채택 파일 파싱 결과에서 주입(하드코딩 금지)
- 기존 EA·문법·인증 subset 테스트 전량 회귀 (무손상 확인 — 인증 subset·Denotation.lean·EA 불변)
