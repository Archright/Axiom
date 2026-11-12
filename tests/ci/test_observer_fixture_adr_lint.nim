## test_observer_fixture_adr_lint.nim — E-B fixture 디렉터리 ↔ ADR-0033
## 이름 목록 1:1 정합 lint (observer-verdict slice PR-β1).
##
## 계약 (SSOT 대조 — _index.json "index matches files on disk" 패턴 및
## proof_unit_consistency_gate의 docs↔코드 1:1 대조 선례):
##   tests/negative/observer_manifest_gate/ 바로 아래의 디렉터리 목록과
##   ADR-0033(authority-declaration)의 "E-B fixture 목록" 섹션 마커 하위에
##   백틱으로 나열된 이름들이 정확히 1:1로 대응해야 한다.
##
##   - ADR에 해당 섹션이 없으면 **명시적 메시지로 fail**한다 (fail-closed).
##     PR-α(authority-declaration 개정)가 섹션을 추가하면 green으로 전환된다.
##   - 백틱 토큰은 전체 경로(`tests/negative/observer_manifest_gate/x`)든
##     베어 이름(`x`)이든 허용하며, observer_manifest_gate/ 이후의 이름을
##     추출해 대조한다.
##
## 실행: nim c -r --hints:off tests/ci/test_observer_fixture_adr_lint.nim
## Exit: 0 = 1:1 정합, 1 = 불일치 또는 섹션 부재.

import std/[os, strutils, algorithm]

const
  FixtureRoot = "tests/negative/observer_manifest_gate"
  AdrPath = "docs/adr/0033-authority-declaration.md"
  SectionMarker = "E-B fixture"

var
  passed = 0
  failed = 0

template ck(label: string; cond: bool) =
  if cond:
    inc passed
    echo "  PASS: " & label
  else:
    inc failed
    echo "  FAIL: " & label

proc repoRoot(): string =
  result = absolutePath(currentSourcePath())
  for _ in 0 ..< 3:
    result = result.parentDir()

proc fixtureDirsOnDisk(): seq[string] =
  ## fixture 디렉터리 목록 (SSOT = 디렉터리; 숨김 항목 제외, 정렬).
  let root = repoRoot() / FixtureRoot
  for kind, path in walkDir(root):
    if kind == pcDir:
      let name = path.extractFilename()
      if not name.startsWith("."):
        result.add(name)
  result.sort()

proc adrSectionBody(adr: string): tuple[found: bool, body: string] =
  ## "E-B fixture" 섹션 마커가 있는 줄부터 다음 헤딩(#) 직전까지의 본문.
  let markerLine = adr.splitLines()
  for i, line in markerLine:
    if line.contains(SectionMarker):
      var body = ""
      for j in (i + 1) ..< markerLine.len:
        if markerLine[j].startsWith("#"):
          break
        body &= markerLine[j] & "\n"
      return (true, body)
  result = (false, "")

proc extractFixtureNames(body: string): seq[string] =
  ## 백틱 토큰 추출 → observer_manifest_gate/ 이후 이름으로 정규화.
  ## (PR-α 형식: 백틱 경로 나열 — 베어 이름과 전체 경로 모두 수용.)
  let parts = body.split('`')
  for i in countup(1, parts.len - 1, 2):
    var tok = parts[i].strip()
    if tok.len == 0:
      continue
    const anchor = "observer_manifest_gate/"
    if tok.contains(anchor):
      tok = tok[tok.rfind(anchor) + anchor.len .. ^1]
    while tok.endsWith("/"):
      tok = tok[0 .. ^2]
    if tok == "pass_control" or tok == "fault_probe" or
       tok.startsWith("violation_"):
      result.add(tok)
  result.sort()

proc main =
  echo "── E-B fixture 목록 ↔ ADR-0033 1:1 정합 ──"
  let disk = fixtureDirsOnDisk()
  echo "  디스크 (SSOT = 디렉터리): " & $disk

  let adrPath = repoRoot() / AdrPath
  if not fileExists(adrPath):
    inc failed
    echo "  FAIL: ADR-0033 파일 부재: " & adrPath
    quit(1)
  let (found, body) = adrSectionBody(readFile(adrPath))
  if not found:
    inc failed
    echo "  FAIL: ADR-0033에 \"" & SectionMarker & "\" 섹션이 없습니다 — " &
         "PR-α(authority-declaration 개정)의 \"E-B fixture 목록\" 절 대기 중. " &
         "lint 계약: 섹션 부재 = fail (fail-closed)."
    quit(1)

  let names = extractFixtureNames(body)
  echo "  ADR-0033 섹션:            " & $names

  var missingInAdr: seq[string] = @[]
  for d in disk:
    if d notin names:
      missingInAdr.add(d)
  var missingOnDisk: seq[string] = @[]
  for n in names:
    if n notin disk:
      missingOnDisk.add(n)

  ck "ADR에 없는 fixture 디렉터리 없음" &
     (if missingInAdr.len > 0: " — 누락: " & $missingInAdr else: ""),
     missingInAdr.len == 0
  ck "디스크에 없는 ADR 이름 없음" &
     (if missingOnDisk.len > 0: " — 유령: " & $missingOnDisk else: ""),
     missingOnDisk.len == 0
  ck "1:1 대응 (디스크 " & $disk.len & " == ADR " & $names.len & ")",
     disk == names

  echo ""
  echo "══════════════════════════════════════════════════════════"
  echo "Observer fixture/ADR lint: $# passed, $# failed" % [$passed, $failed]
  echo "══════════════════════════════════════════════════════════"
  if failed > 0:
    quit(1)
  quit(0)

main()
