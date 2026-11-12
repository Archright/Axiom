# Nim Forward Declaration Quirks (Nim 2.2.10)

> AGENTS.md §0.5 Quirk Mandate — 발견 시각 2026-09-26, 발견 위치:
> `tools/ci/derive_checker_closure.nim` 개발(gateway-landing-authority).
> 도구체인: Nim 2.2.10 (choosenim pin). 본 문서는 관측된 컴파일러 행동의 기록이다.

## Q1: `{.forward.}` pragma 거부

Nim 2.2.10은 무본문 forward 선언에 붙인 `{.forward.}` pragma를 거부한다.
정확한 forward 선언 형태는 **pragma 없는 무본문 proc 선언**이다
(시그니처만 선언, 이후 동일 시그니처로 본문 정의).

```nim
# WRONG (Nim 2.2.10 거부)
proc foo(x: int): int {.forward.}

# OK
proc foo(x: int): int
```

## Q2: forward 선언과 정의부의 파라미터명이 다르면 중복 오버로드가 생긴다 (silent)

무본문 forward 선언을 선언할 때 **파라미터명이 정의부와 다르면**, 그 선언은
정의에 바인딩되지 않고 **별도의 오버로드**가 조용히 생성된다. 결과:

- 호출 지점에서 `ambiguous call` 컴파일 에러 (두 선언 모두 매칭), 또는
- 기대와 다른 오버로드가 선택되는 조용한 오류.

```nim
# WRONG — 파라미터명 불일치 → 두 개의 오버로드
proc analyze(w: var Walker, toks: seq[string], ctx: string)
proc analyze(w: var Walker, toksIn: seq[string], ctx: string) =  # 새 오버로드!
  discard

# OK — 정의부와 파라미터명까지 동일해야 하나의 시그니처로 결속
proc analyze(w: var Walker, toksIn: seq[string], ctx: string)
proc analyze(w: var Walker, toksIn: seq[string], ctx: string) =
  discard
```

## 적용 사례 (권고)

서로를 참조하는 walk/analyze 계열의 mutual forward 선언 시 선언과 정의의
파라미터명을 **문자열까지 일치**시킨다. 실천 위치:
`tools/ci/derive_checker_closure.nim:111-116`
(코어 forward 선언 주석: "{.forward.} 프라그마 거부 + 파라미터명 불일치 시
중복 오버로드 생성 — 정의부와 동일한 파라미터명으로 무본문 선언해야 한다").

## 판정

- Quiet failure 위험도: **높음** (불일치가 에러가 아니라 오버로드 증식으로
  나타나므로 리뷰에서 눈에 띄기 어렵다 — 첫 발현은 보통 `ambiguous call`).
- 회피 전략: forward 선언 자체를 최소화하고, 필요 시 Q2 규칙 준수 + `nim c`로
  즉시 검증.


## Q3: forward 선언은 추론된 `{.gcsafe.}`를 전파하지 않는다 (DEBT#497 follow-up, 2026-10-08)

- **Symptom**: 구현부가 순수 문자열 처리뿐인 forward-declared proc(`checkProc`)을
  gcsafe 컨텍스트(예: `{.gcsafe.}` 어댑터) 경유로 호출하면
  `'run' is not GC-safe as it calls 'scanFileForDecisionBinding'` 류의
  gcsafe 불일치가 호출 체인 상류에서 보고된다.
- **Root cause**: 구현 전 소비되는 forward 선언에는 gcsafe 추론이 적용되지 않고,
  비-gcsafe 추정이 호출 체인을 따라 전파된다 (선언→정의 결속은 Q2 규칙과 별개).
- **Resolution**: forward 선언(및 정의부)에 `{.gcsafe.}`를 명시 — 본문이 실제로
  순수할 때만. 실측 위치: `src/gate/runners/decision_binding_gate.nim:147`
  (DEBT#497 follow-up runInProcess 어댑터 작업 중 발견).
