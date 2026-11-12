# Nim Empty Multiline Table Constructor Quirk

## 증상

Nim 2.2.10 파서는 빈 테이블 생성자가 여러 줄로 발행되면 `invalid indentation` 파스
오류로 실패한다 (실측 2026-10-08).

```nim
const
  PostProcess = {
  }.toTable
```

→ `<string>(54, 3) Error: invalid indentation` (행/열은 발행 위치에 따름)

같은 줄 형태와 내용이 있는 multiline 형태는 모두 파스된다:

```nim
  PostProcess = {}.toTable          # OK — 한 줄
  TargetProcs = {                   # OK — multiline, 항목 존재
    "a.nim": {
      "proc": "skip",
    }.toTable,
  }.toTable
```

즉 `{` 뒤에 항목 없이 개행만 오고 닫는 `}`가 문장과 같은 인덴트에 놓이는
구성만 파서가 거부한다.

## 이 저장소에서의 실측 경로 (2026-10-08)

- `tools/ci/add_raises_annotations.nim` (tracked)가 위 빈 multiline 형태로
  커밋되어 있었다.
- `ax prove`가 GlobalSymbolGraph를 만들 때 저장소의 모든 .nim을
  `src/core/parser_utils.nim`의 `parseStringAST`로 파싱한다. 이 파서는
  `fakePath = AbsoluteFile("<string>")`로 진단 위치를 심는다 — 따라서 오류는
  `<string>(54, 3) Error: invalid indentation`로 stderr에 매 실행마다 출력됐다.
- 실패한 파일의 기호는 심볼 그래프에서 추출되지 않는다(파일 전체가 사라진
  것과 동일).
- `logs/lean_lsp_payloads.jsonl`의 `parse_string_failure` 이벤트에 실패 소스
  전문이 기록된다(진단 보조).
- **귀속 교정**: `docs/evidence/debt465_c20_borem_slice_2026-10-07.md` §2는 이
  `<string>(54,3)` 오류를 Lean 4.33.0 커널 소스 파싱 실패로 추정했으나, 실측
  결과 Nim 파서 진단이다. Lean 커널 오류는 `file:line:col: error:` 형식으로
  다르다. 같은 슬라이스에서 확인된 실제 Lean 생성 결함은
  "bare 숫자 리터럴 + `.toInt` 토큰화"이다 —
  `src/core/trusted/ir_to_lean.nim`의 `leanBvSignedProj` 참조.

## 정답 절차

- 생성기/툴이 빈 테이블을 발행할 때는 multiline 빈 생성자를 발행하지 않는다 —
  indent push/pop 휴리스틱으로 줄바꿈을 보정하지 않는다.
- 추가 실측(2026-10-08, nim 2.2.10): 한 줄 `{}` 형태는 **파스**는 되지만
  컴파일은 안 된다 — `{}`/`{:}`는 빈 array 생성자라서 `toTable`의 요소 타입을
  추론할 수 없다(`undeclared field: 'toTable'` / `cannot instantiate`).
  빈 `const Table`의 컴파일 가능 형태는 타입 명시 디폴트다:
  `PostProcess = default(Table[string, Table[string, string]])`.
  (파일의 소비처는 `getOrDefault` + `pairs` 순회 — `.pairs` 필요.)
- `tools/ci/add_raises_annotations.nim`은 2026-10-08 슬라이스에서 위
  컴파일 가능 형태로 교정되었다.

## 참고

- 이 파일의 `{...}.toTable` 형태는 파스는 되지만 Nim 테이블 생성자 `{k: v}`가
  이미 `Table`을 산출하므로 의미론적으로는 컴파일되지 않는다(선존재, 본
  quirk와 무관 — 파스만이 심볼 그래프의 요구사항).
