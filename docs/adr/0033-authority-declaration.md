# ADR-0033: Authority 선언 — 결정권자·writer·device 3분리와 관측→차단 승격 규칙

## Status

**Accepted (2026-10-09, owner ratification — 본 계획 승인)** — "Authority 선언 +
관측 모드 게이트" 슬라이스의 **Slice 0(권한 선언)** 이다. 본 ADR은 새 장치를
만들지 않는다 — 기존 장치(Owner 결정 기록, repository-surface 정책, GitHub
ruleset, blob-sha 핀)로의 **등록**이 전부다.

**효력 개시 = 워크플로 배선 슬라이스 착지** — 본 ADR의 승격 규칙·관측 표시·
기록 계약 조항은 관측 러너의 호출자가 배선되는 후속 슬라이스에서 발화한다.
그 전까지 이 조항들은 **선언(dormant)**이며, 호출자 없이 발화하지 않는다.

## Context

관측 모드 게이트(관측 먼저 → 증거 누적 후 차단 승격) 계획에 필요한 권위 답변은
저장소에 산재해 있었다:

- merge authority는 GitHub이다(AGENTS.md §2.3, `docs/spec/repository_surface_contract.md`
  §판정 계층) — 판정 계층은 verdict를 낼 뿐 권한이 없다(Authority ≠ Adapter).
- Owner 결정 #12가 3축 control-plane 위임(생성·실행·실행내용)을, #13(2)이 merge
  authority 현행 유지를, #13(6)이 "새 검증 workflow는 새 authority surface가
  된다"를 각각 확정했다.
- ADR-0028이 authority·writer·device 3분리와 판정 단일성 규칙을 선언했다.
- 관측 오라클(manifest-consistency-gate, `src/gate/runners/manifest_consistency_gate.nim`)
  은 이미 존재하지만, 그 관측 결과가 어떤 권위 체계에 속하고 어떤 조건으로
  차단으로 승격되는지를 선언한 문서는 없었다.

이 공백에서 "관측 도구가 사실상 판정자가 되는" 극장(§0.9)이 재도입될 수 있다.
Slice 0은 관측 구현에 선행하여 권위 체계를 기존 장치로 고정한다.

## Decision

**세 가지를 혼합하지 않는다** (ADR-0028 3분리 재적용):

| 층 | 결정 |
|---|---|
| **(a) authority — 결정권** | **wintrover(인간 아키텍트)**. 에이전트는 기록·집행만 담당하며 승인권이 없다. 에이전트 임시키 서명은 접근 제어가 아니라 사후 감사 흔적이다(`tools/agent_bypass_sign.nim` 보안 모델 선례 — "cryptographic audit trail, not access control"). |
| **(b) writer — 기록 권한** | 결정 기록 = `docs/spec/repository_surface_contract.md` §Owner 결정 기록(본 건 = 결정 #19). 관측 스위치 정책 값 = `config/policy/observation_gates.json`(**후속 워크플로 배선 슬라이스에서 생성** — 본 착지에서는 경로 선등록만). 표면 등재 = `config/repository_surface.json`(v72). |
| **(c) device — 집행 수단** | GitHub main ruleset 20303214(required check `admission-check` strict + `update`/`creation` 규칙 + merge queue) + blob-sha 핀(`config/executor_authority.json` — mint-domain TrustedExecutorSet, `config/trusted_writer_set.json` — `trustedAdmissionWorkflowSha`·`trustedCheckerTreeClosure`). |

### 신뢰 뿌리 고정

신뢰 뿌리(trust root)는 위 (c)의 플랫폼 권위 + 콘텐츠 주소 핀으로 **고정**된다.
관측 오라클·관측 스위치 정책이 새로운 신뢰 뿌리가 되는 것을 금지한다 — 관측은
입력이지 권위가 아니며, merge에 결합되는 강제는 GitHub의 몫이다(§판정 계층).
정책 값 소비는 slice-engine의 policy@B 패턴을 따른다 — B 체크아웃에서 읽는다
(`src/gate/slice_catalog.nim`의 `config/policy/epoch_manifest.json` 선례).

### 승격 규칙(관측 → 차단)

관측 모드 게이트의 차단 승격은 다음 3조건을 **모두** 만족할 때 Owner만 발동한다.

1. **증거 = N=3회 연속(순차) merge-group(MG) 라운드** — 동일 판정이 3회 **연속**
   관측되어야 한다. **라운드 = merge_group `checks_requested` 이벤트 1건(서로
   다른 group head SHA)**이다. dedup은 판정 폐쇄 identity(동일 predicated 판정)
   기준이며, 카운트 단위는 **런당 1개 positive 라인 × 서로 다른 head SHA**로
   고정한다. 미관측·에러(OBSERVER-FAULT) 라운드는 계수하지 않으며 **연속을
   단절**한다(UNKNOWN은 링크가 아니다 — AGENTS.md §2.3·§4 fail-closed). **취소
   (conclusion=cancelled)·미발화(startup_failure·이벤트 미전달·타임아웃) 라운드는
   OBSERVER-FAULT로 분류**한다 — 계수하지 않으며 연속을 단절한다. 동일 G의 재평가
   중복 발화는 별개 라운드가 아니라 동일 라운드의 재관측이며 카운트 단위가 이를
   흡수한다. N회 positive는 **WOULD-BLOCK 배출 부재(증거 클래스 E-A — 저장소-상태
   클레임)**만 증명하고, 탐지력은 **음성 주입 시험(증거 클래스 E-B)**이 담당한다 —
   승격 증거는 두 클래스가 모두 충족된 경우에만 인정된다. **E-B는 두 층으로
   나뉜다: E-B-min(관측 슬라이스 = 탐지력의 존재 증명: PASS 대조군·위반 1종·
   내부결함 1종 fixture 3종)과 E-B-full(위반 클래스별 주입의 전 클래스 완료).
   E-B-full은 차단 승격의 필수 선행 조건이다** — E-A만으로는 N회 positive가
   저장소-상태 클레임에 불과하므로(탐지력 없는 게이트의 침묵과 구별 불가) 전
   클래스 E-B 없는 승격은 인정되지 않는다. **위반 클래스 유니버스는 관측 대상
   게이트의 검사 목록에서 기계적으로 유도**하며(수치 고정 논쟁 금지), **E-B
   fixture 디렉터리가 유일 원천**이다 — 본 ADR은 이름 목록을 참조만 하고,
   1:1 정합은 기계 대조(`_index.json` 패턴 선례)가 강제한다.
2. **wintrover의 명시 승인** — 에이전트의 승인 주장은 권위 행위가 아니다((a)).
3. **γ=STOP 재의결 조건** — WOULD-BLOCK이 관측되면 **Owner가 오탐/진양성을
   판정**한다. **미판정 상태의 기본값은 승격 불가(fail-closed)**다. 오탐으로
   판정되면 승격을 중단하고 재의결한다(γ=STOP) — 단순 계수 리셋이 아니라
   승격 절차 자체의 중단이다. 위반·비결정 관측도 동일하게 γ=STOP을 발동한다.
   γ 조건은 승격의 부정 조건이지 자동 승격 트리거가 아니다.

**관측기 생존 표시(개정 2026-10-10 — 계수 보유처 이전)**: 워크플로는 런마다
무상태이므로 연속 계수를 러너가 수행하지 않는다. 관측 러너는 자기 라운드의
OBSERVER-FAULT를 비필수 빨간 체크와 payload로 배출할 뿐이다. **연속 K=3 판정은
집계 명령(GET-only — 승격 증거 집계와 동일한 명령 1개)이 아티팩트·런
메타데이터만으로 계산하며, 그 출력의 고정 라인(`FAULT streak=3 owner-display:
required`)이 마커다.** **감시 주체: 자동 신호는 비필수 빨간 체크뿐이며, 계수
경보의 책임은 집계 명령을 실행·기록하는 자에게 있다 — 승격 판단 시 Owner가
반드시 실행하고, 그 외 시점의 재실행은 누구나 임의로 가능하다.** 명령은 비필수
관측이며 어떤 merge도 막지 않는다.

**관측 신원(재유도 — 사전 등록 없음)**: 판정 payload는 B·H·event를 기록하고,
계수 시 `H:.github/workflows/observation.yml == B:.github/workflows/observation.yml`
(PR이 관측기를 바꾸지 않음)과 `gateSourceBlobOid`(B에서 재유도)만 단언한다.
고정 등록값을 두지 않는다 — 등록은 소비 시점 재유도와 같은 보증을 유지비 없이
제공하지 못한다(바이너리 해시 등록 기각과 동일 논거).

**결손 원인 분류(2계층)**: 결손은 허용하되 **모든 결손에 원인이 기록되고 원인
불명은 0건**이어야 한다. 계층1(payload 내장 `fault_cause`): `timeout`(래퍼
타임아웃 — SLA 상수 공유)·`gate`(게이트 크래시/자기진단 결함)·`toolchain`
(빌드·설치 실패). 계층2(run-level, payload 부재): 런 부재=platform /
`jobs==0`=platform(기동 실패 — conclusion 무관) / cancelled=platform /
부재 ∧ 경과 ≥ 상한=timeout / 그 외=platform. 집계 창은 증거 수명(artifact
retention) 이내로 한정하고, 집계기 자신의 REST 장애는 메타 OBSERVER-FAULT로
기록한다.

**증거 수명**: artifact retention(기본 30일, 전송용 `subject-certificate`는 3일)·
run URL 로그 90일은 만료 포인터다. 승격
증거의 영속은 **승격 PR이 N회 각 라운드의 판정 payload 전문 + sha256 + identity
(gate|B|H, run_id, verdict)를 `docs/evidence/`에 커밋**하는 것으로만 성립한다
(ADR-0022 D1 선례 — 살아있는 포인터를 믿지 않고 재계산 불가 사실을 기록화).
run URL은 편의 참조로 격하한다.

### #13(6) 처분 — 관측 오라클의 authority 부인

manifest-consistency 관측 오라클은 authority를 주장하지 않는다(advisory 성격).
관측 스위치 정책(`config/policy/observation_gates.json`)은 관측 모드의 기록이지
새 authority surface가 아니며, 관측 결과는 merge 권한을 부여·거부하지 않는다.
이는 결정 #13(6)("정기 재검증 automation은 미신설 — 새 검증 workflow는 새
authority surface가 된다")의 유지이지 그 개정이 아니다.

## 갱신 문서 목록 (본 착지가 함께 갱신하는 문서)

| 경로 | 변경 | 등급 |
|---|---|---|
| `docs/spec/repository_surface_contract.md` | Owner 결정 #19 추가(동기 개정 포함) | CONTROLLED |
| `docs/adr/0033-authority-declaration.md` | 신규 (본 ADR) | PRODUCT |
| `config/policy/observation_gates.json` | 선등록만 — 본문은 후속 워크플로 배선 슬라이스에서 생성 | CONTROLLED (v72 등재) |
| `config/repository_surface.json` | policyVersion 71 → 72 + CONTROLLED 선등록 | FROZEN (정책 PR 자신 — §18(c) 수용 리스크 경로) |

## Consequences

**긍정:** 관측 모드 게이트의 권위 체계가 구현에 선행하여 고정된다. 관측 도구가
사실상 판정자가 되는 경로(§0.9 극장)를 결정 차원에서 봉쇄한다. 승격 요구 증거
형태(N=3회 연속 MG 라운드 — E-A/E-B 증거 클래스)와 승격 주체(Owner)가
문서화되어 후속 slice의 acceptance criteria가 정해진다.

**부정/유지:** 결정 #1(플랜 미승급·`--no-verify` 수용 리스크)·#13(2)(merge
authority 현행 유지)·#13(6)(정기 재검증 automation 미신설)은 모두 유지된다.
본 ADR은 이들 중 어느 것도 supersede하지 않는다.

## Residual Limits (해소되지 않은 잔여)

1. **판정 논리 미정의** — 본 ADR은 관측 게이트의 판정 논리·구현·배선을 정의하지
   않는다(후속 slice). "관측 모드"의 실행 의미는 그 slice가 자신의 계약으로
   정의한다.
2. **선언과 강제의 분리** — 승격 규칙의 N=3·γ 조건은 본 ADR의 선언이며, 강제는
   GitHub(required check·merge queue)과 후속 slice 구현이 담당한다. 본 ADR 자체는
   어떤 merge도 막지 못한다(§판정 계층). 위 **효력 개시 마커**가 그 분리의
   명시적 표현이다.
3. **정책 파일 자기 진화** — `config/policy/observation_gates.json`의 진화는
   CONTROLLED 등록(v72)으로 통제되며, 그 수정이 승격을 스스로 선언하는
   루프홀은 base-policy binding이 차단한다 — 정책 변경은 main 착지 후에만
   효력을 갖는다.
4. **γ 판정 주체** — γ=STOP 재의결 조건의 판정 주체는 Owner다. 에이전트는 γ
   조건의 관측을 보고할 수 있으나 재의결을 개시하거나 종결할 수 없다. WOULD-BLOCK
   의 오탐/진양성 판정도 같은 주체·같은 한계를 따른다.

## References

- `docs/spec/repository_surface_contract.md` — Owner 결정 #19(본 건)·#1·#12·#13·
  §18(c) 수용 리스크 경로·§판정 계층
- `docs/adr/0028-hook-installation-authority.md` — authority·writer·device 3분리
  원형 + 판정 단일성 규칙
- `docs/adr/0022-admission-artifact-authority.md` — 증거 수명/영속(D1 assertion 기록화)
- `tools/agent_bypass_sign.nim` — 임시키 서명 = 감사 흔적 선례
- `config/executor_authority.json` · `config/trusted_writer_set.json` — blob-sha 핀
- `src/gate/slice_catalog.nim` — policy@B 소비 패턴 선례(`config/policy/epoch_manifest.json`)
- `config/policy/observation_gates.json` — 관측 스위치 정책(선등록 — 본문은 후속 배선 슬라이스)

---

*작성일: 2026-10-09. 개정: 2026-10-10(효력 개시 마커·E-A/E-B·판정 주체·증거 수명
명문화). Accepted — Slice 0 권한 선언. Residual Limits ①~④는 해소된 것으로
취급하지 않는다.*
