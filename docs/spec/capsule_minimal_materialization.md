# 최소 오프라인 증명 캡슐 Materialization 사전계약 (1d)

> **Status**: Normative pre-contract (v1, 2026-11-08) — 최소 오프라인 증명 캡슐 재건(1d)
> 실험 단위(materialization M)의 사전등록. 본 문서는 계약 사전등록이며 M의 실제
> 조립·선택·격리 실행·관측 기록은 별도 작업이다(§15).
> **Created**: 2026-11-08
> **Registered at**: branch `workstream/1d-minimal-materialization-contract`
> (base main `5e740d7e4c7884ad44060daa1179cb9f16d540e7`)
> **Position**: [aeneas_generation_contract.md](aeneas_generation_contract.md) (이하 "1a") ·
> [mathlib_hermetic_boundary.md](mathlib_hermetic_boundary.md) (이하 "1c")를
> **개정하지 않는다** — 세대 identity(1a §5)와 격리 실행 경계(1c §4)를 준용·위임받는
> 신규 사전계약이다. 1c §2는 "캡슐 축소 실험의 설계·실행·판정"을 1c의 범위 밖으로
> 예견했다(1c §3.4 — 공식 수단의 참조만). 본 계약이 그 예견된 범위를 정의한다.
> **근거 증거**: [docs/evidence/b2_hermetic_proof_capsule_2026-11-04.md](../evidence/b2_hermetic_proof_capsule_2026-11-04.md)
> (이하 "capsule") · [docs/evidence/b2_capsule_detached_acceptance_2026-11-04.md](../evidence/b2_capsule_detached_acceptance_2026-11-04.md)
> (이하 "detached") · [docs/evidence/b1_gate_a_minimal_proof_2026-11-04.md](../evidence/b1_gate_a_minimal_proof_2026-11-04.md)
> (이하 "Gate A")
> **원칙**: 세대 identity는 결속 기록의 순수 함수다 — 물리 캡슐의 inventory는 세대
> identity 요소가 아니다(1a §5). 미측정·불확실·불일치는 fail-closed(UNKNOWN)이며
> 무음 PASS는 존재하지 않는다(1a §5.6·§9, 1c §9 준용).

---

## §1. 목적 — 세대 identity와 materialization identity의 계약상 분리 (P0 해소)

B-2 원본 캡슐(180,040파일·11,353,320,247B — capsule §2·§4.1)은 소실됐다(2026-11-08
캠페인 관측 — 6경로 전수 확인, 등록). 이 소실이 드러낸 계약상 충돌(P0)을 본 계약이
해소한다:

- **세대 측**: 세대 G의 identity는 1a §5 결속 요소의 순수 함수다 — 원본 캡슐의 물리
  inventory는 §5 요소가 아니므로, 캡슐 소실은 세대 G의 identity·capsule·detached에
  착지된 증거 기록에 아무 영향을 주지 않는다(1a §6.4 append-only).
- **실행 측**: 그러나 세대 G의 **재실행**은 Stage B 실행 입력(1a §4.1 1~3행)을 담은
  물리 집합을 요구한다. 1c §3.2는 원본 Stage A 산출물(.ltar 인벤토리 9,031항목)을
  generation에 결속했고 1c §9.1은 인벤토리 불일치 시 진행을 금지한다 — 원본 정의
  그대로면, 소실된 원본 캡슐을 대체하는 어떤 물리 집합도 원본 인벤토리와 불일치하므로
  재실행의 계약 근거가 없다.

**해소**: 재실행의 단위를 "원본 Stage B의 반복"이 아니라
**"세대 G(1a §5 불변)의 재실행 + 신규 materialization M(본 계약 §4의 실험 단위)"**로
정밀화한다. M은 1c의 원본 Stage A/B 계약 아래의 실행이 아니라 본 계약 아래의 신규
실험이며, 원본 캡슐과의 인벤토리 차이(축소)는 1c 위반이 아니라 본 계약 §7이 정의하는
최소성 실험의 대상이다. 1c §2·§3.4의 위임을 이렇게 수용한다.

원본 `generation.json`(sha256
`efdced76b105cc4843aad99cbe2f4eedab039439742870c34d85107e5d1b5133`)과
`sha256(inventory.json)`
(`742ec2c0f78c3490621d42c67e6f88698f5588422f95b1fcf612a5af9f1d781e` — capsule
§4.1·§5.1)은 1a §6.4에 따라 **append-only 불변**이다 — 재실행·축소·회복의 어떤
결과도 이 기록을 소급 수정·삭제·대체하지 않는다. 모든 신규 관측은 새 기록으로
추가된다.

## §2. 적용 범위

**범위 안**: materialization M의 실험 단위 정의(§4)·인벤토리 결속(§4.2), G 동일성
기계 조건(§5), 실행 기반 identity 판정 규칙(§6), 최소성 정의(§7), olean digest
불일치 판정(§8), 회복 실행의 지위(§9), 격리 규정 준용(§10), acceptance 4축(§11),
mutation 증거 상속 조건(§12), Non-claims(§13), 비준수 판정(§14).

**범위 밖 (non-goals)**:

- 1a·1c의 개정 — 본 계약은 준용·위임만 하며 두 계약의 어느 조항도 변경하지 않는다.
- 신세대 채택 절차(1a §8.2) — 본 계약이 대체하지 않는다. §5 관문 불일치 시의
  경로는 §5.4가 규정한다.
- mutation(변이) 음성 대조의 재실행 — 본 계약은 상속 조건만 계약화한다(§12).
- rustc·charon·aeneas의 격리 실행 — 회복 실행의 지위만 규정한다(§9). M의 격리
  실행(§10)은 1a §4.2 A안 경계를 그대로 준용한다.
- 캡슐 추가 축소(§7의 S 이하 추가 최소화)·Aeneas 정식 채택(DEFER)·타 머신
  재현·이식형 hermetic(§13)·Rust 지원 범위 확장·추가 함수 5개·fixture-6·
  업스트림 게시(별도 승인 전 금지).
- 제품 계약(v1 CLI·레인·게이트·인증서)의 어떤 동작·범위 주장도 하지 않는다
  (AGENTS.md §0.12 — 본 계약은 제품 주장을 넓히지 않는다).

## §3. 용어 정의

| 용어 | 정의 |
|---|---|
| **세대 G** | 1a §5 결속 요소 전체로 고정된 세대 — generationId `aeneas-gen/nightly-2026.11.03-ab34bd2+charon-0.1.304+lean-v4.35.0`(1a §5.0). "G 동일"은 §5 관문의 기계 조건을 통과했음을 뜻한다 — 주장이 아니라 재실측 대조다. |
| **원본 Stage A** | B-2의 프로비저닝 단계(capsule §4.1) — 1c §3.2 산출물(.ltar 인벤토리 9,031항목·manifest 전체 SHA-256)을 generation에 결속한 원본 기록. |
| **materialization M** | 본 계약 §4가 정의하는, 세대 G의 재실행을 목적으로 조립되는 신규 물리 집합. 원본 캡슐과는 별개의 실험 단위다. |
| **최소 집합 S** | 공식 Mathlib 캐시 선택 수단(`lake exe cache get-`, 루트 5모듈 지정)이 산출하는 전이 import 폐쇄 .ltar 집합(§7·부록 A). |
| **Run₁′·Run₂′** | M에서 §10 격리 하에 수행하는 2회의 독립 실행. 원본 run1·run2(capsule §4.3·§5.3·§5.4)·run3(detached §4.3·§5.1)과 구분된다. |
| **회복 실행** | §9 — artifact 회복 목적의 rustc→charon→aeneas 재실행(프로비저닝 기록). |
| **원본 기록값** | capsule §5.2(generation.json 전문)·§5.5(판정·olean digest 기준)·detached §5.1~§5.4에 착지된 관측 원문. |
| **근거 (anchor)** | 각 값이 측정·기록된 위치. 착지된 증거 문서의 경로+절, 또는 "측정(등록)" — 본 계약이 등록 위치인 값(1a §6.2 표기 규칙 준용). |

## §4. 실험 단위 — materialization M

### 4.1 정의

M은 세대 G의 Stage B 실행 입력(1a §4.1 표 1~3행)을 담는 신규 물리 집합이며,
다음으로 구성된다:

| 구성 | 내용 | 결속 |
|---|---|---|
| 캐시 | 최소 .ltar 집합 S(§7) | §4.2 인벤토리 |
| 증명 입력 | leanproj 코어 9파일(stage_b_inputs.core_files — §5.2 표와 동일 내용) | §5 재실측 |
| 증명 도구 | toolchain bin 4종 + lib 5종(§5.3) | §5 재실측 |
| 실행 스크립트 | stage_b.sh 재구성본(원문 비내장 — capsule §8 Repro Block의 동일 내부 경로·절차로 재구성) | §5.5 |

M은 원본 캡슐의 복제·복구가 아니다 — M의 정의 자체가 최소성 실험(§7)이다. 원본
캡슐은 복구 대상이 아니다(§13).

### 4.2 M의 인벤토리 결속 — 1c §3.2 양식 준용, 별개 판정

M의 `.ltar` 인벤토리(파일 **개수·이름·크기·SHA-256 목록** + **manifest 전체
SHA-256**)는 M의 실험 기록에 결속된다. 이 결속은 1c §3.2 양식의 준용이며, 원본
Stage A 산출물 결속(capsule §5.2가 기록한 원본 인벤토리)과는 **별개 판정**이다:

- M의 인벤토리가 원본 인벤토리(9,031항목)와 다른 것(축소)은 원본 Stage A 위반이
  아니다 — 1c §9.1의 진행 금지는 원본 Stage B 실행(run1·run2·run3)에 적용되는
  조항이며, M은 본 계약의 실험 단위다(§1).
- 대신 M의 인벤토리는 다음 **부분집합·동일성 조건**을 만족해야 한다: (a) M의
  `.ltar` 전수는 원본 인벤토리 항목의 **부분집합**(이름 기준)이며, (b) 대응하는
  각 파일의 SHA-256·크기는 원본 인벤토리 기록값과 **동일**이다. 원본 인벤토리에
  없는 `.ltar`의 존재, 대응 항목의 digest 불일치 → fail-closed(§14). 이 조건이
  M을 원본 Stage A 산출물과 계약상 연결한다.
- 부록 A의 폐쇄 산출이 네트워크에서 새로 확보한 파일이면 그것은 원본 Stage A가
  아니다 — §10 격리 하 선택(unshare-net)이므로 다운로드는 원천 불가능하며,
  `get-` exit 1(로컬 불완비)의 관측 자체가 fail-closed 관측이다(부록 A).

### 4.3 원본 기록의 불변

§1의 두 digest(`efdced76…`·`742ec2c0…`)는 capsule §5.1·§5.2 전문이 결속하는
원본 세대 정본이다. M 실험의 모든 산출(인벤토리·실행 기록·판정)은 **새 문서·새
파일**로 기록되며 원본 기록에 병합·수정되지 않는다(1a §6.4).

## §5. G 동일성 기계 조건 (실행 전 관문 — MUST)

M의 격리 실행(Run₁′·Run₂′) **개시 전에** 아래 전 항목을 재실측·대조한다.
**하나라도 불일치·미측정이면 실험을 즉시 중단하고 UNKNOWN으로 보고한다** —
조용한 PASS·관문 생략·사후 승인은 금지된다.

### 5.1 1a §5 전 항목 재실측

1a §5.0~§5.6의 결속 필드를, 생존하는 물리 원본(서브젝트 체크아웃·LLBC·생성
Lean·elan toolchain·`.ltar` 캐시·aeneas/charon 로컬 바이너리)에서 재실측해
기록값과 대조한다. 1a §5.5·§5.6의 전 sha256·버전·지문이 대상이며, 그 중 M의
실행 입력이 되는 항목은 다음 표가 기계 대조 목록이다:

| 항목 | 기록값 (sha256) | 근거 |
|---|---|---|
| lean (toolchain bin) | `bf8d54e4714cc4b03d3f6bb34c83b7202b87e49c8bfcbff6895c085bb90ceb38` | 1a §5.3·capsule §5.2 |
| lake (toolchain bin) | `8ba83c98f76562d03b8dbc33f1057151ba6cbb121679dde76b2260ccc90495e1` | 1a §5.3·capsule §5.2 |
| leantar (toolchain bin) | `06d613dffd2a6fd996b095bfd835c2bb720886f9eb7e13ed2adddd7df4507bf3` | 1a §5.3·capsule §5.2 |
| clang (toolchain bin) | `df2e7d9b9e23822587cf04ac28f206a1ddaac5053312a4c875acf5608701b9d2` | 1a §5.3·capsule §5.2 |
| toolchain lib 5종 | `libInit_shared.so`·`libLake_shared.so`·`libleanshared.so`·`libleanshared_1.so`·`libleanshared_2.so` 전문 | capsule §5.2 stage_b_inputs.toolchain_libs |
| lake-manifest.json | `fd3d5b0ebd1063cceb318f9efc1e7346a7f53a742cb8602d62cb99b57fa44bd7` | 1a §5.3·capsule §5.2 |
| 서브젝트 serde_json HEAD | `8c535a260ce561eaab4111aafc29038eb9f77ff3` (READ-ONLY 불변) | 1a §5.5·Gate A §4.1 |
| 잠금 Cargo.lock | `1bc62b1a4645e18c7856073376f0601348f874d47a854e55261955381061b2e4` | 1a §5.5·Gate A §4.3 |
| LLBC (input of record) | `cfa5a04f99d55a54ebe098b30256712078c6ff271791ab8b6200de311a5e3dfc` (287,322 B) | 1a §5.5·Gate A §4.3 |
| 생성 `Types.lean` | `229ec1768d814171269674227bfebc75c96950516ffbf4a7c96cb63002914f60` (1,729 B) | 1a §5.5·Gate A §5.3 |
| 생성 `Funs.lean` (원본) | `e0fec2a836a12ffd6588f501218522ceb2895f8d16b866f9b727d9e841951b32` (1,306 B) | 1a §5.5·§7·Gate A §5.3 |
| 프로젝트 `Funs.lean` (1토큰 수정본) | `abaca6f68ab304c935f2d87564c5f19be6e80ba8aac4ddd0a2db724807e1e0e8` (1,313 B) | 1a §5.5·§7·Gate A §5.3 |
| 생성 `TypesExternal_Template.lean` | `514fbfd947d7cb617d81046e60e874b59301b766a52a4b16af4bd72cccfef485` (1,134 B) | 1a §5.5·Gate A §5.3 |
| aeneas 실행 바이너리 | `12e6042cfb00aba8ea8b6ef2811f55867e4fc8bf56bcc96c5a7d52ab9fd53a9c` | 1a §5.1·Gate A §4.1 |
| charon 실행 바이너리 | `4226741660099a31be54bde273e9193dd5a44154df7eb203c3c333d83b32a59c` | 1a §5.1·Gate A §4.1 |
| `.ltar` 캐시 전수 | 9,031파일·455,355,304 B(파일별 digest는 원본 인벤토리 — §4.2) | capsule §5.2 stage_a_stats · 2026-11-08 재실측 일치(등록) |

재실측 불능 항목(물리 원본이 회복 전 부재)은 **미측정**이다 — 미측정도 불일치와
동등하게 관문 FAIL이다(§14). 회복 실행(§9)은 미측정 항목을 digest 일치로 채우는
유일한 경로다.

### 5.2 stage_b_inputs 코어 9파일 대조

capsule §5.2 `generation.json`의 `stage_b_inputs.core_files` 9파일을 전수 대조한다:

| 파일 | sha256 |
|---|---|
| `inputs/leanproj/lakefile.lean` | `8a435a42eda30704adec48469951ad86fa7d7f6b5569e9cdd24fe6924a80dcb9` |
| `inputs/leanproj/lean-toolchain` | `ca5f1f601d34c49079e38d7e7041eb0f2a9c227fbc1df0f404820069a052330c` |
| `inputs/leanproj/lake-manifest.json` | `fd3d5b0ebd1063cceb318f9efc1e7346a7f53a742cb8602d62cb99b57fa44bd7` |
| `inputs/leanproj/PrintAxioms.lean` | `73bb45f72693448aeff6f1b96dbe1c8f18d4bd5252288629b04d1ff616746b50` |
| `inputs/leanproj/AsBool.lean` | `a57ea4165520f3af03e05aed2d97f0b6c768820b8d9bebba0dbd771365d84934` |
| `inputs/leanproj/AsBool/Funs.lean` | `abaca6f68ab304c935f2d87564c5f19be6e80ba8aac4ddd0a2db724807e1e0e8` |
| `inputs/leanproj/AsBool/Spec.lean` | `c072867f5db02c7ff7b06a6e7da2045266611ea081b3182a2360f4fe455e7e17` |
| `inputs/leanproj/AsBool/Types.lean` | `229ec1768d814171269674227bfebc75c96950516ffbf4a7c96cb63002914f60` |
| `inputs/leanproj/AsBool/TypesExternal.lean` | `646ebd427928385ab89ce1b96dff0fb80cb5ae978eec0856168edfdce8196bf4` |

근거: capsule §5.2(전문)·capsule §4.1. 1a §5.4의 손모델·§7의 1토큰 수정 규칙은
이 파일들의 내용 결속으로 이미 반영된다 — 본 표의 대조가 그 규칙의 기계 검증이다.

### 5.3 실행 도구·환경

§5.1 표의 toolchain bin 4종·lib 5종은 M에 봉입될 물리 바이너리 자체의 재실측이다.
elan 경유 설치본(`~/.elan/toolchains/leanprover--lean4---v4.35.0`)이 재실측
원본이다(1a §5.3 등록값과 대조). 실행 기반(OS·kernel·glibc·bwrap)의 판정은 §6가
규정한다.

### 5.4 불일치 판정

- 불일치·미측정 **1건** → 실험 즉시 중단·UNKNOWN 보고. 중단 후 재시도는 새 관문
  수행을 요구한다(부분 관문 통과의 재사용 금지).
- 불일치의 해소가 세대 구성요소의 재생성(신세대 요건 — 1a §8.2 전부)을 요구하면
  그것은 **별도 작업**이다 — 본 실험의 실패를 신세대 채택 요건 충족으로 우회하는
  것을 금지한다(1a §8.1: 업데이트라는 개념은 존재하지 않는다).

### 5.5 stage_b.sh 재구성본

원본 `stage_b.sh`의 원문은 기록에 내장되어 있지 않다(sha256만 결속 —
`9197a0f02f829455b62660f9f8894bfa04430a1060b4ee731c0ee52d3fd54e39` — capsule §4.3·
§5.2 `execution_base.stage_b_sh_sha256`).
M의 stage_b.sh는 capsule §8 Repro Block의 내부 경로·절차([0]~[7])로 재구성하며,
재구성본의 digest를 기록한다. 재구성본 digest가 원본 기록값과 **불일치해도** 그
diff를 기록하고 진행 가능하다(원본은 "run1 최종본"·관측 코드 수정 이력 포함 —
capsule §7 Deviations 1) — 단 diff는 전수 기록되고, 판정축·재현축(§11)은 diff의
영향을 받지 않는 동일 산출로 측정된다. 재구성 불능·Repro Block과의 대응 불능은
fail-closed다.

## §6. 실행 기반 identity 판정 규칙 (수정안①)

1a §5.6은 "실행 기반의 상이 판정 규칙은 B-2 캡슐 계약이 정의한다"고 위임했다.
본 §6가 1d 실험(M)에 적용할 그 규칙이다. 판정 항목은 **아래 두 목록에 전부
열거된다 — 목록 밖의 실행 환경 차이를 판정하는 규칙은 존재하지 않는다**(§6.3).

### 6.1 MUST 일치 (불일치 → 즉시 중단·UNKNOWN)

| 항목 | 기준값 | 근거 |
|---|---|---|
| elan toolchain 바이너리 4종 sha256 (lean·lake·leantar·clang) | §5.1 표 값 | 1a §5.3·§5.6 |
| lake-manifest.json sha256 | `fd3d5b0e…44bd7`(§5.1 표) | 1a §5.3·§5.6 |

이 5개 digest가 identity 심판의 최종 기준이다(1a §5.6 원문 준용). M 실행에
봉입되는 바이너리·manifest의 재실측값이 이와 불일치하면 그 세대(G)로의 산출물
발행은 금지된다(1a §9·§14).

### 6.2 기록·대조 항목 (불일치 → 원인 규명 전 UNKNOWN)

M의 실험 기록은 실행 기반을 아래와 같이 기록하고 원본 기준값(1a §5.6·1c §8)과
대조한다:

| 항목 | 원본 기준값 | M 기록 |
|---|---|---|
| OS 배포 | Linux Mint 22.3 `[noble]` · x86_64 | 관측값 기록·대조 |
| kernel | `6.17.0-42-generic` | 관측값 기록·대조 |
| glibc | `2.39-0ubuntu8.9` | 관측값 기록·대조 |
| bwrap | 버전 `0.9.0` + 바이너리 sha256 `e318903862396f96de3df57264e0158682b952fd3fb53ac23d876413e7b30f71` | 관측값 기록·버전·sha256 대조 |

근거: 1a §5.6·1c §8·capsule §5.2 `execution_base`(os·arch·kernel·glibc·
bwrap_version·bwrap_binary_sha256)·capsule §5.7 F2. `execution_base`의 나머지
원본 기록(glibc_ldd_line·libc6_package·ldd closure 전문·resolved file
identities — capsule §5.2)도 M의 실험 기록이 동일 관측을 수행·대조 기록한다.

불일치 시 자동 PASS 사유가 될 수 없다 — 차이를 기록하고 원인·증명 의미 영향을
규명하기 전까지 해당 실행은 UNKNOWN이다(§14). bwrap은 kernel/glibc를 가상화하지
않는다 — 샌드박스 내 관측값은 호스트 값 그대로다(6.2 대조는 호스트 관측으로
수행한다).

### 6.3 목록 밖 차이 = UNKNOWN (무음 PASS 금지)

§6.1·§6.2 목록에 **정의되지 않은** 실행 환경 차이(호스트명·CPU·마운트 옵션·환경
변수·시간 등)는 자동 PASS 사유가 될 수 없다. 관측된 차이는 기록하고, 판정은
원인 규명 전까지 UNKNOWN을 유지한다(1a §5.6·§9 무음 PASS 금지 준용). 미관측을
"차이 없음"으로 해석하지 않는다 — 관측되지 않은 축은 미측정이다.

## §7. 최소성 정의 (수정안②) — 제약 최적화

M의 "최소성"은 다음 제약 최적화 문제로 정의된다:

```
min |M|  s.t.  ProofGeneration(M) = G          (§5 관문 통과 — 세대 G identity)
              ∧ Acceptance(M) = PASS           (§11 4축 전부)
              ∧ NetworkAccess(M) = DENIED       (§10 격리 관측)
              ∧ Run₁′(M) = Run₂′(M) = Original  (§11.2 재현축 — 원본 기록값)
```

- **"최소"의 기준**: 공식 Mathlib 캐시 선택 수단의 **전이 import 폐쇄** — 루트
  5모듈(AsBool·AsBool/Funs·AsBool/Spec·AsBool/Types·AsBool/TypesExternal)에 대한
  `lake exe cache get- <인자>`가 산출하는 `.ltar` 집합 S(부록 A 공식 의미론 —
  1c §3.4·Cache/README.md §Arguments). 이 폐쇄는 Mathlib 캐시의 공식 선택
  프로토콜이 정의하는 단위(cached-packages 필터, 하류 프로젝트 공식 지원)이며
  **전역 최소 주장이 아니다** — 다른 정당한 최소성 축(olean 단위 의존성·바이트
  단위 필요집합)이 존재할 수 있고 본 계약은 그 최소성을 주장하지 않는다.
- **|M|의 측정**: 파일 수와 bytes는 **별도 측정·별도 보고**한다 — 파일 수 비율
  (|S| / 9,031)과 bytes 비율(bytes(S) / 455,355,304 B)을 단일 지표로 병합하지
  않는다(두 비율은 서로 다른 사실이다).
- **폐쇄 상한 대조**: 사전 측정(capsule_min_measure — 실측 2026-11-05·계약 등록
  2026-11-08) 폐쇄 상한은 **1,795**다(원천 주석 — 원본 B-2 run 로그의 빌드 플랜
  관측에서 첫 루트 컴파일 이전 완료 up-to-date 작업 수 1,801−5−1로 유도된 느슨한
  상한이며 .ltar 외 사전 빌드·비모듈 집계 작업을 포함한다. 2026-11-09 erratum
  정정: [docs/evidence/b2m_1d_s2_provenance_2026-11-09.md](../evidence/b2m_1d_s2_provenance_2026-11-09.md).
  종전 표기는 상한 수치에 ".ltar" 단위를 결합한 형태였다). S의 관측 크기는 이 상한과
  대조 기록하며, 상한을 초과하면 사전 측정과의 불일치로 원인 귀명 전까지
  진행 금지(UNKNOWN)다.
- **폐쇄 교차검증**: S의 열거는 `get-` 폐쇄 산출에 더해 `lake exe cache lookup`
  열거 및 `lean --deps-json` 폐쇄로 교차검증한다. 단 세 경로의 폐쇄 계산은
  `parseImports'` 파서를 공유한다(부록 A) — 이 교차검증은 **완전 독립 검증이
  아니라 부분 독립 교차검증**으로 정직하게 기록한다.

## §8. olean digest 불일치 판정 (수정안③)

커널 판정축(§11.1)이 성공해도, 재현축(§11.2)의 **olean digest 5종·실행 간
동일성**에 불일치가 있으면 **원인 규명 전까지 전체 acceptance는 PASS가 될 수
없다**:

- 불일치를 이례 기록(anomaly log) 수준으로만 남기고 종료하는 것은 금지한다 —
  무음 PASS다(1a §5.6·§9, AGENTS.md §0.9 극장 금지).
- 원본 B-2의 "판정 기준은 커널 판정이며 digest 불일치 시 원인을 기록한다"(capsule
  §4.3·§5.5 — 원본 실행에서는 5종 전부 동일해 논점 미발생)는 **원본 실행의**
  기준이다. M의 목적은 산출물 identity 재현을 포함하므로(§7 제약식), M의
  acceptance는 본 §8의 더 엄격한 규칙을 따른다 — 이는 capsule §4.3의 개정이
  아니라, M이라는 별개 실험 단위(§1)에 적용되는 신규 판정 규칙이다.
- 원인 규명 후 불일치가 판정·증명 의미에 무영향임을 기계적으로·증거로 입증하지
  못하면 acceptance는 UNKNOWN으로 종결한다(§14).

## §9. 회복 실행의 지위

rustc→charon→aeneas 재실행(캠페인 Stage A′ — 프로비저닝·회복)은 **artifact 회복
수단**이며, 세대 G의 증명 활동으로 기록되지 않는다:

- 1a §4.2 — identity-only 결속 요소(rustc·charon·aeneas·Rust 원본·LLBC)를
  같은 세대의 증명 활동으로 기록하는 것은 금지된다. 1a §6.1 — 기록은 실행을
  의미하지 않는다. 회복 실행은 §5.1 재실측을 위한 **물리 원본의 재생산**일 뿐이다.
- **수용 기준(회복 산출물)**: 회복 산출물(LLBC·생성 Lean 3종·번들)의 digest가
  1a §5.5 등록값(LLBC `cfa5a04f…`·`Types.lean 229ec176…`·`Funs.lean 원본
  e0fec2a8…`·`TypesExternal_Template.lean 514fbfd9…`)과 **일치**할 때만 §5.1
  재실측 대상으로 수용한다. 도구 재취득(aeneas 번들·charon·rustc)은 Gate A §4.1·
  §8 기록 sha와 대조한다.
- 회복 산출물이 불일치 → 그것은 신세대 문제다(1a §8) — 본 실험 범위 밖,
  중단·UNKNOWN(§5.4).
- 회복 실행 자체를 "세대 G의 실행"으로 보고하는 것, 회복 로그를 capsule·detached의
  원본 관측과 동일 취급하는 것은 극장이다(1a §4.2·§9, AGENTS.md §0.9).

## §10. 격리 규정 (1c §4.2·§4.3 전항 준용)

M의 선택(§7)과 격리 실행(Run₁′·Run₂′)은 1c §4.2·§4.3을 **전항 준용**한다:

| 구성 | 요구사항 | 근거 |
|---|---|---|
| 네트워크 | 외부 네트워크 통신 불가능 — `bwrap --unshare-net`(관측 보조축: curl exit 6 — 시도 부재의 증명은 아니다, capsule §5.5 준용) | 1c §4.2 |
| 파일시스템 | 최소 노출 — `/usr` 읽기 전용 + M의 캡슐 경로만 ro-bind(/toolchain·/cache — §4.2 인벤토리 범위) + workspace rw + `--tmpfs /tmp` | 1c §4.2 |
| 환경변수 | `LAKE_NO_CACHE=true` **프로세스 환경 전체** | 1c §4.2 |
| 고정 환경 | `--clearenv` 후 고정: PATH·HOME·LANG·TMPDIR·LAKE_NO_CACHE·MATHLIB_CACHE_DIR + `--die-with-parent` | capsule §4.3·§5.2 sandbox_config 준용 |
| 캐시 조작 | **`lake exe cache unpack` 만** — 다운로드 경로가 없는 순수 로컬 복원 | 1c §4.2·§4.3.2 |
| 재컴파일 강제 | 루트 `.lake/build` 삭제 후 빌드 | 1c §6·capsule §4.3 [2] |

**금지 목록(1c §4.3 전항 준용)**:

1. `--try-cache` CLI 플래그 병용 금지(1c §4.3.1 — env 전체 적용 무력화).
2. **다운로드 경로가 있는 캐시 명령** — `lake exe cache get` 계열 금지. 격리
   실행에서 허용되는 캐시 조작은 `unpack`뿐이다(1c §4.3.2). 원본 B-2 Stage B도
   unpack만 사용했다(관측 `Already decompressed 9031 file(s)` — capsule §5.3).
3. §4.2 격리 구성의 생략·약화 금지(1c §4.3.3 — 그런 실행은 격리 실행이 아니다).
4. 원본 Stage A 외 캐시 소스 혼입 금지(1c §4.3.4) — M의 `.ltar`는 §4.2
   부분집합·동일성 조건을 만족하는 파일만(다른 경로·다른 namespace 금지).

**선택 단계(§7)의 격리**: S 산출도 동일한 bwrap 격리(unshare-net) 하에서
수행한다 — 로컬 완비 시 `get-`는 curl을 실행하지 않고 exit 0이다(부록 A 실측).
`get-` exit 1(로컬 불완비) 관측 → fail-closed(네트워크 차단 하에서는 다운로드가
불가능하므로 그 실행은 폐쇄·완비 실패의 증거다). 선택 단계의 전제는 부록 A
(bwrap 내 curl ≥ 7.84·git·leantar·lake 접근).

## §11. Acceptance 4축 정의

M의 acceptance는 아래 4축으로 판정한다. **4축 전부 충족 + §5 관문 통과 + §6 판정
통과**일 때만 `Acceptance(M) = PASS`다(§7 제약식).

### 11.1 판정축 (MUST — Lean 커널 판정)

- `#print axioms` 2행이 원문과 **바이트 동일**(capsule §5.5):
  - `'AsBool.Spec.as_bool_bool_some' depends on axioms: [propext, Quot.sound]`
  - `'AsBool.Spec.as_bool_non_bool_none' depends on axioms: [propext, Quot.sound]`
- **sorryAx 0** — 허용 가정 집합 `[propext, Quot.sound]` 외 sorry 부재(1c §7
  결속 항목 6·Gate A §4.8).
- **Built 5 실재 재컴파일** — 루트 5모듈(AsBool·Funs·Spec·Types·TypesExternal)이
  `.lake/build` 삭제 후 실제로 새 컴파일됐음(1c §6 — 캐시 hit ≠ 성공).

### 11.2 재현축 (MUST — 산출물 identity 재현)

- **olean digest 5종** — Run₁′·Run₂′ 각각의 산출이 원본 기록값(capsule §5.5)과
  동일:

  | olean | sha256 (capsule §5.5) |
  |---|---|
  | `AsBool.olean` | `e5b1ef421f5ebccb6aa35ebeff066db35dd944e97dbfcace61362c8d43340d58` |
  | `AsBool/Funs.olean` | `bdf7f0ff6dfc84804d36a640348e9a5af6fe9f1d7e8c8a63b41ce099a6133ad9` |
  | `AsBool/Spec.olean` | `5f604d403600172d402091048aebdba1e646c39a30fbe19ff095dfec6601f816` |
  | `AsBool/Types.olean` | `d66574f5f531a479d158654351aef301446b61ab7da47684526360a2fd396db8` |
  | `AsBool/TypesExternal.olean` | `a41a0bed960f683f4134dddd3edb72da8cd067f369ea66c5d516404ff8bd09b8` |

- **Run₁′ = Run₂′ = Original** — 실행 간 동일성(타임스탬프·wall 제외 정규화
  diff — capsule §5.5 절차 준용) 및 원본 관측(capsule §5.3·§5.4·detached §5.1)과
  판정축·재현축 동일. 불일치 시 §8이 적용된다.
- LLBC 경로-내장 필드 동등성(Gate A §4.11)·`stage_b.sh` diff(§5.5)는 재현축
  판정에 앞서 기록·정규화 대조한다.

### 11.3 §5 재실측축 (MUST — G 동일성)

§5.1·§5.2 전 항목 재실측 일치 + §6.1 MUST 일치. 실행 **전** 관문이며, 실행 후
M 불변성(사전→사후 재실측 — capsule §5.6 절차 준용)도 본 축의 종결 조건이다.

### 11.4 기록축 (기록 — 변동 허용, 값 기록)

아래 값은 **변동이 허용되며** 변동값을 그대로 기록한다(원본 기록값과의 차이는
M이 최소 집합 S로 실행된다는 사실의 자연한 결과다 — 축소의 직접 관측):

| 항목 | 원본 기록값 | M 기록 |
|---|---|---|
| decompressed 파일 수 | `Already decompressed 9031 file(s)`(capsule §5.5) | Run₁′·Run₂′ 관측값 |
| lake build jobs | `Build completed successfully (1801 jobs)`(capsule §5.5) | Run₁′·Run₂′ 관측값 |
| bytes | `.ltar` 전체 455,355,304 B(capsule §5.2 stage_a_stats) | bytes(S) 관측값 |

기록축 값·변동은 판정축·재현축·재실측축을 **대체하지 않는다**. 실행 과정에서
부가 관측 가능한 값(예: mathlib 패키지 빌드 cache 실행파일 sha256
`a8b0bf258ad991ba40561bffcbcadc88ad429eef6e4ac2cd8ae99b229590d624` — capsule
§5.7 F4)도 기록축으로 기록한다(원본과의 불일치는 관측으로 기록 — 판정축이
아니다).

## §12. mutation 상속 조건

B-1 mutation 음성 대조(Gate A §4.10 — clause 1 킬·clause 2 생존, §7 Deviations 4)의
증거는 다음 조건에서만 M의 실험 기록으로 **상속**된다:

- **상속 조건(전부)**: §5 전 항목 재실측 일치(§5.1·§5.2 — G 동일성) **및**
  stage_b_inputs 9파일 대조 일치. 즉 §5 관문 통과 그 자체다.
- **상속 거부**: 불일치·미측정 항목이 하나라도 있으면 상속하지 않는다 — M의
  결과는 mutation 음성 대조와 무관한 신규 관측으로만 보고한다.
- mutation 재실행은 본 계약 범위 밖이다(§2) — 본 §는 상속 조건만 계약화한다.
  상속된 증거는 "B-1에서 실행·기록된 관측의 인용"이지 M의 실행이 아니다(1a
  §4.2 인용 규칙 준용).

## §13. Non-claims

본 계약과 M 실험이 **주장하지 않는** 것:

- **offline ≠ 이식형 hermetic** — M의 격리는 본 호스트·본 실행 기반(§6.2)의
  관측이다. 타 머신 이식성·범용 hermetic 재현을 주장하지 않는다.
- **캐시 hit ≠ 성공** — `unpack` 성공·`.olean` 존재·캐시 hit는 acceptance가
  아니다(1c §6 준용).
- **전역 최소 아님** — "최소"는 공식 `get-` 전이 import 폐쇄 기준이다(§7).
  파일 수·bytes 최소성의 다른 축에 대한 주장이 아니다.
- **G 재실행 ≠ Aeneas 정식 채택** — 본 실험은 Aeneas/Charon의 Axiom 지원
  채택 판정(DEFER)이 아니다(1a §8.3 — 상류 지원 범위의 자동 편입 금지 준용).
- M의 PASS는 제품 계약의 범위·준비성 주장이 아니다(AGENTS.md §0.12 — 제품
  계약이 정의하지 않은 지표·산출물·주장을 본 실험이 발행하지 않는다).
- 원본 캡슐 소실의 원인 규명·복구, 그리고 소실이 capsule·detached 증거의
  유효성에 미치는 영향 판정 — 본 계약의 범위가 아니다(원본 증거는 착지된
  MERGE_SHA에 결속되어 있다).
- §6.2 항목의 일치 관측은 "실행 기반이 모든 면에서 동일하다"는 주장이 아니다 —
  열거된 항목의 대조 결과일 뿐이다(§6.3).

## §14. 비준수 시 fail-closed

| 위반 | 결과 |
|---|---|
| §5 관문 불일치·미측정 1건 | 실험 즉시 중단 — **UNKNOWN**(조용한 PASS 금지) |
| §5 관문 생략·사후 승인·부분 관문 재사용 | M의 acceptance 전체 기각 |
| §6.1 MUST 불일치 | 즉시 중단·UNKNOWN — 세대 G 산출물 발행 금지(1a §9 준용) |
| §6.2 불일치·§6.3 목록 밖 차이의 자동 PASS화 | UNKNOWN — 원인 규명 전 수용 금지 |
| §7 상한 초과·폐쇄 산출 불일치(get- exit 1 포함) | fail-closed — 진행 금지·UNKNOWN |
| §8 digest 불일치를 이례 기록으로만 종료 | **acceptance PASS 발행 금지** — 무음 PASS(극장, AGENTS.md §0.9) |
| §9 회복 실행의 증명 활동 기록화 | 세대 무효(1a §4.2·§9 준용) — 그 기록 전체 기각 |
| §10 격리 생략·약화·금지 목록 위반 실행 | 그 실행은 격리 실행이 아니다 — 산출물 기각(1c §4.3.3·§10 준용) |
| §4.2 부분집합·동일성 조건 위반(원본 인벤토리 밖 `.ltar`·digest 불일치) | M 기각 — 원본 Stage A 외 소스 혼입(1c §4.3.4 준용) |
| §12 상속 조건 미충족 상태의 mutation 증거 인용 | 그 인용 기각 |
| required checks 0건 | **UNKNOWN / NOT READY** — SUCCESS로 해석하지 않는다(AGENTS.md §2.3) |
| 검증 불가·오래된 증거 | fail-closed(UNKNOWN — AGENTS.md §4) |

UNKNOWN은 본 계약의 fail-closed 판정값이다(productization_contract.md 상태
어휘 준용 — 부재·무효·상충 증거는 PASS로 해석되지 않는다). 본 계약(및 그 개정)의
착지 authority는 GitHub 네이티브 MERGE 커밋이다(AGENTS.md §2 — merge authority는
GitHub다).

## §15. 본 계약의 위치 (범위 명시)

이 착지는 **계약 사전등록**이다. M의 실제 조립·선택·격리 실행·관측·기록은 1d
캠페인의 별도 작업(선택 단계 → Stage B′ → 증거 PR)이며, 본 문서는 "M이
검증됐다"·"최소 캡슐이 재현됐다"·"hermetic이 달성됐다"는 주장을 포함하지
않는다. §10·§14를 위반한 실행의 결과물은 격리 실행 산출물이 아니며, 그런 실행을
"격리 실행이었다"고 기록하는 것은 극장이다(AGENTS.md §0.9 — 발견 시
`data/debt_registry.json` 등록 대상).

## §16. 참조

**준용 계약**:

- [docs/spec/aeneas_generation_contract.md](aeneas_generation_contract.md) (1a) —
  §4.1 경계 표(A안)·§4.2 미실행 단계 실행 기록 금지·§5 세대 요소·§5.6 실행 기반
  위임·§6.1~§6.4 기록·계보 규칙·§7 1토큰 수정본·§8 세대 갱신·§9 fail-closed
- [docs/spec/mathlib_hermetic_boundary.md](mathlib_hermetic_boundary.md) (1c) —
  §2 범위(축소 실험 예견)·§3.2 Stage A 결속·§3.4 공식 선택 수단 참조·§4.2 격리
  구성·§4.3 금지 목록·§5 해시 범위·§6 캐시 hit ≠ 성공·§7 증거 identity 분리·§9
  fail-closed

**근거 증거 (측정 원문)**:

- [docs/evidence/b2_hermetic_proof_capsule_2026-11-04.md](../evidence/b2_hermetic_proof_capsule_2026-11-04.md) —
  §4.1 Stage A 조립·§4.3 Stage B 경계·stage_b.sh·§5.1 정본 digest·§5.2
  generation.json 전문(stage_b_inputs·sandbox_config·stage_a_stats)·§5.3/§5.4
  run1·run2 관측·§5.5 판정·olean digest 기준·§5.6 캡슐 불변성·§5.7 F1~F4·§8
  Repro Block
- [docs/evidence/b2_capsule_detached_acceptance_2026-11-04.md](../evidence/b2_capsule_detached_acceptance_2026-11-04.md) —
  §4.3 run3·§5.1~§5.4 detached 재현·수용 판정
- [docs/evidence/b1_gate_a_minimal_proof_2026-11-04.md](../evidence/b1_gate_a_minimal_proof_2026-11-04.md) —
  §4.1 도구 identity·§4.3 LLBC·lock·§4.6 mathlib 핀·캐시·§4.8 명제·공리·§4.10
  mutation·§4.11 cold 재현·§5.3 해시 인벤토리·§8 재현 명령열

**관련 계약**: [productization_contract.md](productization_contract.md) — 상태
어휘(PASS/FAIL/UNKNOWN, fail-closed)·제품 범위 주장 경계(AGENTS.md §0.12)

**부록 A** — Mathlib 캐시 CLI 공식 의미론 실측(§7·§10의 근거).

---

## 부록 A. Mathlib 캐시 CLI 공식 의미론 실측 (agent-124, 2026-11-08)

소스 코드 + 공식 문서(Cache/README.md·Cache/SECURITY.md — 핀 커밋
`56a005855ea17e0b0958f73ec801ae140b0a1679`) 검증으로 확정한 실측(agent-124
측정(등록) — 1a §6.2 표기 규칙 준용: 본 계약이 등록 위치다):

| 항목 | 실측 의미론 |
|---|---|
| `get- <args>` 실재 | 다운로드만 수행 — 압축해제 없음 |
| 인자 지정 시 | 지정 파일과 **전이 import 의존성만** 다운로드(1c §3.4 인용 원문) — 하류 프로젝트에서 공식 지원되는 선택 단위(cached-packages 필터) |
| 로컬 완비 시 | **curl 미실행·exit 0** — 네트워크 접근 없이 폐쇄 산출 |
| 부족 시 | **exit 1** — 폐쇄·완비 실패의 기계 신호(§10 격리 하에서 fail-closed 관측) |
| 루트 모듈 404 miss | exit 0 + 경고 — 무해(§7 루트 5모듈 지정에는 비발생 클래스) |
| 폐쇄 계산 | `parseImports'` — `lean --deps-json`과 **파서 공유** → §7 교차검증은 완전 독립이 아닌 **부분 독립 교차검증**으로 기록 |
| 전제 | bwrap 내 접근: curl(≥ 7.84 — 로컬 8.5.0 확인)·git·leantar·lake |

측정 세션 전문은 캠페인 기록(1d workstream)에 보존한다. 본 부록의 값은 의미론
기록이지 실행 관측이 아니다 — M의 선택 단계(§7·§10)가 이 의미론을 관측으로
확인한다.
