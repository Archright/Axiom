# Nim Array Constructor Doc Comment Quirk

## 증상

Nim 2.2.10 파서는 배열 생성자(`@[...]`)의 **요소들 사이**(선행 쉼표 뒤)에 놓인
`##` 문서 주석 블록을 파스하지 못한다. 문서 주석 토큰 하나로 흡수된 뒤
`expression expected` 파스 오류가 난다 (실측 2026-10-13).

```nim
const x*: seq[tuple[file, internal: string]] = @[
  ## 첫 요소 앞 주석 — 파스된다
  (file: "a", internal: "b"),
  ## 요소 사이 주석 — 파스 실패
  (file: "a", internal: "c"),
]
```

→ `Error: expression expected, but found '<## 블록 전문>'` + 후속
`Error: expected: ']', but got: '('` (2중 진단; 행/열은 발생 위치에 따름)

첫 요소 **앞**(여는 `@[` 직후)의 `##` 블록과 일반 `#` 주석(요소 사이 포함)은
모두 파스된다. 거부되는 것은 "선행 쉼표 뒤의 `##` 블록" 구성만이다.

## 이 저장소에서의 실측 경로 (2026-10-13)

- `tools/debt_engine.nim`의 `sanctionedToolSrcImports`에 둘째 승인 엣지 튜플을
  추가하며 기존 선입력의 `##` 주석 스타일을 요소 사이에 그대로 모방했다가
  `make bin/debt_engine`이 위 파스 오류로 실패했다.
- 최소 재현(`nim check --skipParentCfg --skipProjCfg`, nim 2.2.10)으로
  저장소 코드와 무관한 파서 quirk임을 확인.

## 정답 절차

- 배열 생성자 요소 사이에는 `##` 문서 주석을 쓰지 않는다 — 일반 `#` 주석으로
  기술한다 (`tools/debt_engine.nim` `sanctionedToolSrcImports` 둘째 엣지가
  이 형태로 착지).
- 요소 사이에 기계 판독이 필요한 문서가 필요하면 요소 앞의 첫 위치(여는
  `@[` 직후)로 모으거나, 요소의 `##` 필드 문서(레코드 타입 쪽)로 옮긴다.
