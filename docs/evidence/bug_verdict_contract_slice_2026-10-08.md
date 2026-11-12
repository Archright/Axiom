# Bug Verdict Contract Slice Record — S1 subject · S2 property(P2 판정) · S3 semantic 충분성

> **Status**: Execution evidence record — S1–S3 of the nim-stew `BUG_FOUND`/`NO_BUG_PROVED` 운영 판정 milestone, contract slice S0–S3
> **Created**: 2026-10-08
> **Terminology**: [docs/spec/bug_verdict_glossary.md](../spec/bug_verdict_glossary.md) (S0)
> **Axiom revision**: branch `feat/bug-verdict-contract` cut from `origin/main` = `3d0ad4a70` (worktree `wt-ms-f-contract`)
> **Reporting contract**: external verification workspace AGENTS.md §14

## Question

운영 판정 보고 어휘(`BUG_FOUND`/`NO_BUG_PROVED`)가 적용될 subject·property·semantic 모델을 계약 수준에서 고정할 수 있는가? 특히 P2(sizing soundness)는 normative 근거가 있어 채택 가능한가?

## Context

- Subject: status-im/nim-stew clone at `<workspace>/nim-stew` — **읽기 전용** (Zero-Footprint Integrity)
- Axiom configuration: 로컬 게이트(pre-commit/pre-push), `make build` — CI=0 표면
- Toolchain: Nim 2.2.10 (`~/.choosenim/toolchains/nim-2.2.10`)
- Experiment ID: `bug-verdict-contract-slice-2026-10-08`

## S1 — Subject 고정 (measured, not labeled)

버전 라벨이 아니라 **exact commit + exact file bytes**로 바인딩한다. 실측 일시 2026-10-08:

| 항목 | 값 | 명령 |
|---|---|---|
| nim-stew HEAD | `1853f20bdfeda61331a0b7e02f7aace0e88a0dfe` | `git -C <nim-stew> rev-parse HEAD` |
| HEAD 메타 | `2026-10-06 07:54:03 +0000` — "Drop Clang 20 check (#286)" | `git log -1` |
| `git describe --tags` | `v0.6.0-1-g1853f20` | `git describe --tags` |
| `stew/base36.nim` blob sha256 | `b8a42a6ac6d1057fca0be079aac5750463729fdad771823f1be53b8723a5e0a8` | `sha256sum` |
| `stew/base36.nim` 최근 변경 커밋 | `1f8a5ad7612afebfa5b724b36baefdc85f43b3e8` | `git log -1 -- stew/base36.nim` |
| `v0.5.2..HEAD` base36.nim diff | **empty** (`git diff --stat v0.5.2 HEAD -- stew/base36.nim` 출력 없음) → 기존 계약(`base36_sizing_binding_contract.md` §1, v0.5.2 기준)의 주체 바이트가 HEAD에서도 동일 | `git diff` |
| porcelain 상태 | **empty** (읽기 전용 유지 — 캠페인 상시 불변식) | `git status --porcelain` |

계약적 의미: `BUG_FOUND`/`NO_BUG_PROVED` 보고는 위 HEAD 해시 + blob sha256 조합에 한해 유효하다. 주체가 이동하면 이 기록은 자동 만료다(glossary §4).

## S2 — Property 고정과 P2 판정

### P_rel — 재확인 (변경 없음)

캠페인 property `P_rel`은 커밋된 계약 [docs/spec/base36_sizing_binding_contract.md:25-33](../spec/base36_sizing_binding_contract.md)의 정의를 **그대로** 사용한다(재확인 완료):

```
∀ n : Int,  0 ≤ n ∧ n ≤ 33297371974204966 →
    decodedLength (encodedLength n) = n          -- equality, exact (not ≥)
  ∧ encodedLength n ≥ 1
  ∧ ¬ overflowAt encodedLength n
  ∧ ¬ overflowAt decodedLength (encodedLength n)
```

경계 `33297371974204966 = high(int) div 277`(64-bit)는 정확히 tight하다(동 문서 §1 근거 유지).

### P2 — **비채택** (결정 + 근거)

`P2 := decodedLength(m) ≥ ⌈m·log₂36/8⌉`(sizing soundness)에 대한 §0.12 결정: **채택하지 않는다**. property는 계약이어야 하며 발명될 수 없고(§0.12), normative 근거가 존재하지 않기 때문이다. 조사한 세 근거 원천 전부에서 근거 부재를 확인했다:

1. **multibase Base36 RFC — sizing 규정 없음.** nim-stew 소스 코멘트가 정확히 핀한 리비전 `f378d3427fe125057facdbac936c4215cc777920`(`stew/base36.nim:13`)와 `master` 리비전(2026-10-08 기준 fetch, 내용 동일)을 모두 실측: 문서는 인코딩/디코딩 **알고리즘**(leading-zero 카운트, big-endian 정수 변환, `k`/`K` prefix)과 예제 테이블만 담고, 버퍼 크기·상계·`MUST`류 sizing 규범 문장이 **존재하지 않는다**.
2. **nim-stew docstring — 명시적 "estimated" (규범 아님).** `encodedLength`/`decodedLength` 둘 다 "Return **estimated** length …"(`stew/base36.nim:52-60`). 추정 함수에 soundness 의무를 부과하는 것은 주체가 선언하지 않은 계약의 발명이다.
3. **주체 내부 조합 의존 없음 (실측).** `decode`는 `decodedLength`를 소비하지 않는다 — `binsz = payload.len + 4`로 **과다 프로비전**하고, 부족 시 쓰기 전에 `Base36Status.Overrun`으로 fail-closed 반환한다(`stew/base36.nim` decode 전반부, 측정). 즉 `decodedLength`의 under-estimation이 주체 자신의 경로에서 메모리 안전 위반을 만들지 않는다.

**추가 기술 사유 (비채택과 정합)**: `179/277 = 0.646209…  <  log₂36/8 = 0.646241…` — `decodedLength`의 유리 계수는 참 상계의 **아래**에 있어 체계적 under-estimation이 수학적으로 필연이다. 또한 `⌈m·log₂36/8⌉`은 무리수 계수를 포함해 기존 LIA/`omega` 결정 절차로 직접 표현 불가능하다 — 채택한다면 유리 대리항 핀 + 계약 개정(§0.12)이 선행 요구된다.

### P2 관련 실측 관찰 (계약 아님 — 기록 목적)

주체 외부(/tmp)에서 컴파일한 읽기 전용 프로브(nim 2.2.10, `--path:<nim-stew>`)의 관측:

| 관측 | 값 |
|---|---|
| `Base36Lc.decodedLength(4)` | `2` |
| `decode("kzzzz")` (충분 버퍼) | `Success`, `outlen = 3`, bytes `19 A0 FF` (`N = 35·(36³+36²+36+1) = 1_679_615`, 21 bits → 3 bytes) |
| `encode(0x19,0xA0,0xFF)` | `"kzzzz"` (roundtrip 일치) |
| `decode("kzzzz")` **decodedLength 크기(2B) 버퍼** | `Overrun`, `outlen = 8`(요구량 `payload.len+4`) — fail-closed, 메모리 불안전 없음 |

즉 유효한 multibase 입력 `'kzzzz'`에 대해 `decodedLength`는 실제 디코딩 크기(3)를 2로 **under-estimate**하며, 이 크기로 할당한 호출자는 `Overrun`을 받는다. **그러나 이 관찰은 본 슬라이스에서 subject `BUG_FOUND`를 구성하지 않는다**: 주체의 자기 계약이 "estimate"이고(위 근거 2), normative sizing 의무가 어디에도 없기 때문이다(glossary §2.2 — 위반 서술은 "위반된 계약"을 요구한다). 이 입력은 **미래에 sizing-soundness 계약이 먼저 커밋되는 경우의 결정적 테스트 벡터**로 기록된다(§0.12 절차: 계약 개정 → 그때 BUG_FOUND 판정).

## S3 — Semantic 충분성 노트 (coincidence-domain 모델)

`P_rel`의 Lean 인코딩이 사용하는 coincidence-domain 모델은 **P_rel 판정에 충분**하다:

- **div/rem**: `div=lean-floor/nim-trunc` — Nim `div`(truncation)와 Lean `/`(floor)는 `0 ≤ n` domain에서 일치하고, 그 일치는 커널 검증 경로에서 사용되는 대응(`Int.tdiv_eq_ediv_of_nonneg` 사용부 `proofs/IR/Denotation.lean:382-417`; denotation scoping 기록 `proofs/IR/Denotation.lean:30-39`; identity segment `canonical_verification.nim:117`). `P_rel`의 domain이 `0 ≤ n`으로 한정되므로(§2 P_rel 전제 — discharged hypothesis), floor/truncation 분기는 P_rel 위에서 도달 불가능하다. rem도 동일 구조다(`rem=lean-emod/nim-mod/coincident-nonneg-dividend-domain`, `canonical_verification.nim:123`; `Int.tmod_eq_emod_of_nonneg`).
- **overflow**: `no-overflow-obligations/coincident-checked-wrap-domain` — `¬ overflowAt …` conjunct가 overflow 도달성을 discharge하므로 checked(`OverflowDefect`)와 wrapping 산술이 **검증 domain 안에서** 일치한다(`base36_sizing_binding_contract.md` §4.1 coincidence wording).
- **경계 tightness**: `n = 33297371974204966`에서 `277·n ≤ high(int)`(headroom 225), `n+1`에서 overflow — domain 상계가 모델 내부에서 자명하다(동 계약 §1).

**DEBT#494 — open 유지 (비blocker)**: `SemanticProfileV1`의 명목 모드(spDivTruncTowardZero·spOverflowBounded)와 실제 coincidence-domain 인코딩의 간극은 실재하며 추적 중이다(`data/debt_registry.json` DEBT#494). 본 슬라이스는 이를 **조용히 패치하지 않는다**(§0.9a). **P_rel은 음수/경계 확장을 요구하지 않는다** — `P_rel` 자체가 `0 ≤ n` 한정이므로 확장 요구는 없다. `P2`도 도메인은 nonneg(`m`은 문자열 길이)이므로 음수 확장을 요구하지 않았으며, 비채택 결정으로 확장 논점 자체가 닫혔다. 만약 P2가 채택되었다면: 무리수 상계의 유리 대리항 핀 + `⌈·⌉` 경계 모델링이라는 **별도 계약 개정**(§0.12)이 선행되어야 했을 것이고, 그 사실을 이 기록으로 명시한다.

## Result

- S0: `docs/spec/bug_verdict_glossary.md` 신규 커밋 — 순수 projection 별칭 계약.
- S1: subject exact binding 실측 완료(위 표) — `BUG_FOUND`/`NO_BUG_PROVED` 보고 유효성의 주체 조건.
- S2: `P_rel` 재확인(변경 없음), **P2 비채택** 확정 — 근거 원천 3건 모두 normative 부재 실측.
- S3: coincidence-domain 모델의 P_rel 충분성 확인, DEBT#494 open 유지, 확장 요구 없음.

## Evidence

- nim-stew 해시·태그·diff·porcelain: 본 문서 S1 표의 명령 재실행으로 재현 가능.
- P2 근거 원천: multibase RFC 리비전 `f378d342` 본문(알고리즘+예제뿐), `master` 동일, `stew/base36.nim:52-60` docstring, `decode` 버퍼 경로 소스.
- base36 프로브: `/tmp/b36probe.nim` (nim 2.2.10, `--path`로 주체 모듈만 참조 — 주체 트리 무변경), 위 S2 관측 표.

## Classification

`Verified` — 계약·문서 슬라이스의 수행 기록으로서(코드 판정 아님). subject에 대한 `NO_BUG_PROVED`/`BUG_FOUND` 판정 자체는 이 문서의 범위가 아니다(semantic binding 트랙의 후속 슬라이스).

## Non-Conclusions

- 이 기록은 nim-stew가 옳다고 주장하지 않는다 — `decodedLength` under-estimation 관찰(§P2 실측)은 유효한 미해결 관찰이다.
- P2 비채택은 under-estimation이 "안전"을 의미하지 않는다 — glossary §3(반례 미발견 ≠ 안전)대로, sizing-soundness 계약이 커밋되기 전까지 그 방향의 판정은 존재하지 않는다(Unknown).
- S1 해시는 nim-stew HEAD 이동 시 만료된다.

## Next Experiment

semantic binding 트랙: `P_rel`을 실제 canonical 경계(renderLeanForFuncDef → Lean → kernel)로 집행하여 `vrPass ∧ vdVerified ∧ clProved` (= `NO_BUG_PROVED(P_rel, D)`) 성립 여부를 산출한다. 이때 subject 바인딩은 본 기록 S1 값을 소비한다.
