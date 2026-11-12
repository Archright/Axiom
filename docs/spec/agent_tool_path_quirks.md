# Agent CLI Path-Encoding Quirks (Write/Edit × non-ASCII repository path)

> AGENTS.md §0.5 Quirk Mandate — 관측 시작 2026-10-31경(④ 재현 판정 슬라이스),
> 2026-11-02 ①' u64 산술 폐쇄 세션에서 재관측·문서화. 측정·운영 기록이며
> 코드·레지스트리 변경을 수반하지 않는다.

## Symptom

에이전트 CLI의 `Write`/`Edit` 도구가 이 저장소의 정본 클론 경로
`.4`(경로에 비ASCII 문자 포함) 아래
파일에서 **간헐적으로 실패**한다. 동일 경로에서 `Read`·`Bash`는 정상 동작한다.

실패 양상: 도구 호출이 거부되거나 경로 해석이 비결정적으로 어긋난다.
전체 클론 이동 없이는 회피가 불가능하므로 운영 우회가 필요하다.

## Measured evidence

- 2026-11-02 세션(폐쇄 커밋 6a248f2ff 작성 창): repo 내 파일(`OBSERVATION.md`
  등)은 `Write`/`Edit` 실패 → **Bash heredoc(`cat > file <<'EOF'`)으로 전부
  작성**해 우회. `/tmp` 하위 절대경로는 동일 도구로 정상 작성됨 — 실패는
  경로 인코딩에 결합, 내용·크기와 무관.
- 컴팩션 인수인계 기록에도 동일 우회 지침이 세션 간 반복 등장(2026-10-31
  ④ 슬라이스 세션 포함) — 단발이 아닌 **반복 관측**.

## Sanctioned workaround (운영 규범)

1. repo 내 신규/편집 파일은 `Write`/`Edit` 대신 **Bash heredoc**으로
   작성한다(append는 `cat >>`). 이미 검증된 본 세션의 작성 경로다.
2. `/tmp` 등 ASCII 절대경로 초안 → 재검토 후 heredoc 반영의 2단 경로도
   허용된다(대형 문서의 안전성 확보용).
3. `Read`·`Grep`·`Glob`은 영향 없음 — 탐색은 그대로 수행한다.
4. 이 실패를 "파일이 없다"로 오판하지 않는다: `Read` 성공·`Write` 실패
   조합이 본 퀴크의 서명이다.

## Official documentation basis / UNKNOWN

- 경로의 비ASCII 문자가 도구 실패를 유발하는 정확한 계층(CLI 경로
  정규화·파일시스템 인코딩·그 외)은 공식 문서로 확인 불가 → **UNKNOWN**로
  기록한다(추측 금지, §0.5).
- 업스트림 수정 여부는 미추적: 동일 실패가 재관측될 때마다 본 문서의
  Measured evidence에 날짜와 함께 누적 기록한다.
