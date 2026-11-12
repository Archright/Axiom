# Base36 C_out Buffer-Sizing Binding — Product Contract (S0)

> **Status**: Committed product contract — S0 of the `feat/base36-cout-contract` slice (계약 개정 선착, §0.12)
> **Created**: 2026-10-10
> **AGENTS.md 참조**: §0.12 (제품 계약 선행), §0.9 (극장 금지), §0.3 (신뢰 경계), §2.6 (변경 불변조건), §4 (GUARDIAN)
> **Related**: [base36_sizing_binding_contract.md](./base36_sizing_binding_contract.md) (P_rel — 채택 완료 선례), [bug_verdict_glossary.md](./bug_verdict_glossary.md) (§2.2 4요소 · §2.4 BUG_SUSPECTED), [counterexample_replay_adapter.md](./counterexample_replay_adapter.md), [obligation_semantics.md](./obligation_semantics.md), [authority_contract.md](./authority_contract.md)
> **Spec registry**: `SPEC-B36-COUT` (docs/spec/spec_registry.json)

---

## 1. Scope

**Subject**: `stew/base36.nim` of an **unmodified** clone of status-im/nim-stew @ full OID `1853f20bdfeda61331a0b7e02f7aace0e88a0dfe` (READ-ONLY; `git -C <nim-stew> status --porcelain` must remain empty — Zero-Footprint Integrity). Blob sha256 of `stew/base36.nim`: `b8a42a6ac6d1057fca0be079aac5750463729fdad771823f1be53b8723a5e0a8`. Symbols: `decodedLength` (`:57-60`), `decode` (`:123-210`). Pinned toolchain: Nim 2.2.10, `int` = 64-bit.

**Claim under verification** — an output-sizing bound (C_out, Axiom-owned strengthening contract):

```
∀ s ∈ AcceptLanguage :  decode(s, buf, outlen) = Success  ∧  buf.len ≥ len(s)+3  →  decodedLength(len(s)) ≥ outlen
```

- `AcceptLanguage` = strings with `s[0] == 'k'` (lowercase literal — the gate at `base36.nim:130` is `'k'` even for `Base36Uc`) and `s[1..^1] ∈ B36LcAlphabet`; `btype` = `Base36` / `Base36Lc`. Domain membership is **decidable**: `decode` returning `Success` is the mechanical membership witness.
- `L = len(s)` = **full encoding length including the `'k'` prefix** (the docstring "encoded value of length `length`", `base36.nim:58-59`).
- Buffer condition is **exact**: `binsz = payload.len + 4 = len(s) + 3` (`base36.nim:135`); the string wrapper's `len(s)+4` allocation (`:217`) is one byte of slack, not the contract.
- Actual length = `outlen` on `Success` (magnitude bytes + base58-style leading-zero preservation `zcount`).
- Domain bound: `L ≥ 3` (measured: no violation at L ≤ 2) and `L*179` non-overflow (`L ≤ high(int) div 179`).

**What a violation establishes (defect meaning)**: a public sizing helper under-reports the decoded size for valid input — a caller sizing its buffer with `decodedLength` gets a spurious `Overrun` on input the subject itself accepts. It does **NOT** establish memory-unsafety (`decode` fail-closes with `Overrun` before any write, `base36.nim:136-138`), and it does **NOT** establish violation of an upstream promise (the docstring says "estimated" — an affirmative disclaimer of any bound; README and the pinned multibase RFC have no sizing norm).

**Hard constraint**: the judgment closes with EXISTING machinery. No new verifier, no new gate, no new required check, no new verdict enum.

## 2. Evidence chain — 보편 ↔ 단일 반례 연결 (필수)

단일 반례는 보편 C_out 반증에 **충분**하다 — 전제: ① C_out이 보편 명제로 채택되고 ② 아래 사슬이 증거에 포함된다. `result ≥ K` 거짓만으로는 불충분하다.

| 링크 | 내용 | 소재 |
|---|---|---|
| 1 | 보편 계약 C_out(채택, 양해 구간 고정) | 본 계약 + overlay(`soExplicit`) |
| 2 | 구체 입력 `s = "kzz"`, `L = 3` | 기계: `input.L = 3`(solver 모델) · 문자열 `s` = overlay 결정 벡터 + 증거 문서 |
| 3 | 독립 관측: `decode("kzz", buf≥6) == Success`, `outlen = 2` | 외부 프로브(cmd + 출력을 증거 문서에 기록 — 파이프라인 사실 아님) |
| 4 | 실제 반환식 평가: `decodedLength(3) = 1` (`(3*179) div 277`, 나머지 260) | **2다리**: solver(스플라이스된 실 body 유도) + replay(실제 컴파일 실행) |
| 5 | `s` ∈ C_out 적용 도메인 | 기계: P4 pre 재검증(리터럴 도메인 핀 + `Success` 조건) + accept 언어 논증(증거 문서) |

**의무 렌더링 (닫힌 명제 금지)**: 닫힌 산술 명제는 자유 변수가 없어 solver 모델 바인딩이 없고, exact-input 게이트와 P4 `pre ∧ ¬post` 재검증이 아사한다. 의무는 **열린 형태**로 렌더링한다 — 파라미터 `L`, 리터럴 pre `3 ≤ L ∧ L ≤ 3`(도메인 핀 — `obligation_semantics.md` 리터럴 고정 선례), post `result ≥ K`(`K = 2` 클레임 상수, overlay data). SAT 모델이 `L = 3`을 바인딩 → exact-input 게이트 통과 → replay → P4 재검증.

## 3. K 출처 보존 + rvAgree 경계

> **K 근원 계층 (보고서·인증서 공통 기재)**: `K = 2`는 **외부 관측값**이다 — 주체 트리 외부 프로브(nim 2.2.10, `--path:<nim-stew>`, 주체 무변경)의 `decode("kzz") → Success, outlen = 2` 실측. 이는 파이프라인이 생성·검증한 사실이 아니며, 채택된 계약 C_out의 K-핀 조건에 따라 **클레임 상수로 핀**된다(`soExplicit` — 근원 기록은 본 계약이 담는다). `decodedLength(3) = 1`은 **주체 반환식의 평가**이며 2다리(solver 유도 + replay 실행)로 일치한다. C_out 위반 판정은 (a) K 상수에 대한 파이프라인 반증(`clDisproved` — replay는 판정을 강등할 수 있어도 클레임을 생성·변경하지 않는다) ∧ (b) K의 외부 관측 근원 기록의 **보고 결합**이다. **(b)가 결측이면 BUG_FOUND로 보고할 수 없다**(glossary §2.2 fail-closed 원칙 준용).

> **비클레임**: `rvAgree`는 `decode` 실행 정확성을 검증하지 **않는다** — 어댑터 Authority = 0이며, 동의의 정의는 관측 결과 위에서 위반된 postcondition을 콘크리트 평가한 결과가 `propertyHolds == false`인 것(`counterexample_replay_adapter.md` §3.6). rvAgree가 진술하는 것은 캐리어 산술(`decodedLength(3) = 1`)의 실측 재현뿐이고, `decode("kzz")`의 `outlen = 2` 관측 자체의 정확성은 이 체인이 보장하지 않는다. 이 구분은 보고서와 인증서 양쪽에 보존된다.

- "결합"은 **보고 투영**으로만 수행한다 — 새 판정 값·producer·gate를 만들지 않는다(glossary §1, adapter §1).
- 4요소 중 ③④의 명령·관측 출력은 증거 문서로 완성한다(뮤턴트 선례). 선택적 payload 문자열 추가는 필드≠enum이나, 최소 변경 원칙상 기본은 증거 문서 경로다.

## 4. 스윕 서술 규율

> **∃-형 전용 필수 서술**: "모든 길이 L ≥ 3에 대해 C_out 위반 입력이 적어도 하나 존재한다(`∃s : decodedLength(s.len) < outlen(s)`)" — **"해당 길이의 모든 입력이 위반한다"는 ∀-형 주장을 하지 않는다**(실측상 `L = 5`의 `'kzzzz'`는 등호 사례 `decodedLength(5) = 3 = outlen = 3`이므로 ∀-형은 거짓이다). 부가 관측(비클레임, 범위 밖): 대형 L에서는 전 입력 위반 길이가 존재한다(관측상 최초 `L = 9,630`, `L ≥ 41,274`에서 영구) — 무조건적 "일부만 위반" 주장도 금지한다.

> **1,076 방법론 (미기록 수치 보고 금지 — authority_contract.md:167-169)**: (도메인) `D₃ = 'k' ∔ Σ²`, `Σ = "0123456789abcdefghijklmnopqrstuvwxyz"`(`B36LcAlphabet`), `|D₃| = 1,296` — payload에 `'k'`(숫자 20) 포함. (유효성) 주체 자체 accept 언어 — `decode(s, buf ≥ len(s)+3) == Success` — 전건 Success. (집계) `|{s ∈ D₃ : outlen(s) > (3*179) div 277 = 1}| = 1,076`(zcount 분해: 0 → 1,040 / 1 → 35 / 2 → `'k00'` 1건), 비위반 220(경계 `'k73'`(255 → 1B) vs `'k74'`(256 → 2B)). 실측: `/tmp/b36slice/c_out_probe.nim` (S0, 2026-10-10).

## 5. 2계층 provenance — 계약 계층 vs upstream 계층

| 계층 | 상태 | 근거 |
|---|---|---|
| 계약 계층 (Axiom-owned C_out) | 채택 전 `Unknown`/`clNoSpecification` → 채택 후 **PROPOSITION_DISPROVED(C_out)** | 본 계약 + 4요소 + §2 사슬 |
| upstream (nim-stew base36) | **BUG_SUSPECTED** (귀속 라벨 — glossary §2.4) | docstring "estimated" 면책 · README/RFC sizing 규범 부재 · in-tree 호출자 0건 · K 관측 1다리 |

**승격 조건 (Bug Suspected → `BUG_FOUND`, fail-closed — 기본 불승격; 2026-10-31 개정 — glossary §2.4a에 따라 기존 ②·③ 승격 분기 폐기)**: ① pinned commit/RFC의 **명시 텍스트 약속 위반**(`requirementSourceStatus=recordedBinding` + E1 근거 완비)이 입증될 때만 승격한다. ② 실제 in-tree 호출자 피해(E2)와 ③ upstream maintainer 인정(E3)은 승격 근거가 아니라 **보고 가치 근거**다 — 결함의 영향·보강을 입증할 뿐 `recordedBinding`을 소급 생성하지 못한다(glossary §2.4a 비소급 규칙). 승격 입증 전까지는 Bug Suspected(라벨 `BUG_SUSPECTED` — glossary §2.4)를 유지한다.

## 6. Certificate identity obligations + Acceptance

최소 결속 집합 (glossary §2.2 4요소 + 본 계약 §2 사슬):

| # | Obligation |
|---|---|
| 1 | exact subject commit `1853f20b…` + blob 해시 |
| 2 | exact input: `L = 3` (기계) + `s = "kzz"` (결정 벡터) |
| 3 | 위반 서술: C_out의 어느 conjunct가 어느 domain D에서 위반되는가 |
| 4 | replay 기록: 동일 커밋 + 동일 입력 재생 명령과 관측 출력 |
| 5 | §2 5링크 사슬 완비 (링크 3의 K 관측 cmd+출력 포함) |
| 6 | K 근원 계층 + rvAgree 비클레임이 보고서·인증서에 유지 |

| # | Criterion | Check |
|---|---|---|
| A1 | 판정이 ground truth와 일치 | `'kzz'` outlen=2 `[05 0F]`, `decodedLength(3)=1`, buf≥6 (probe 실측) |
| A2 | 열린 의무가 닫힌 명제로 렌더링되지 않음 | SAT 모델이 `L=3`을 바인딩, exact-input 게이트 통과 |
| A3 | 결정론성 | 독립 state dir 2회 → canonical projection 바이트 동일 |
| A4 | Subject tree untouched | `git -C <nim-stew> status --porcelain` empty |
| A5 | 3축 분리 | 대상 판정 / 프로세스 exit 1 / PR merge OID가 각각 독립 보고 |

## 7. Explicit non-claims

- NOT a memory-safety claim (`decode` fail-closes pre-write; `Overrun` is the subject's own contract).
- NOT a claim that upstream promised an upper bound ("estimated" is an affirmative disclaimer).
- NOT about `encodedLength`; NOT valid for invalid inputs or empty input (no "actual decoded length" exists there).
- NOT a claim at any `int` width other than the pinned one; NOT valid for `L > high(int) div 179`.
- NOT a claim that the pipeline verified `decode`'s semantics — K is an externally observed claim constant (§3).
- NOT a claim that all inputs at every length violate (§4 — ∃-형 only).
- NOT a claim that nim-stew was modified or annotated in-tree (Zero-Footprint).
