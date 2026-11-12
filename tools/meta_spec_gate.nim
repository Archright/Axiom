import std/[os, strutils]

proc isReferenceStart(content: string, start: int): bool =
  let candidates = [
    "src/", "docs/", "tools/", "bin/", "tests/", "data/", "config.nims",
    "axiom.nimble", "AGENTS.md"
  ]
  for candidate in candidates:
    if start + candidate.len <= content.len and content.substr(start, start + candidate.len - 1) == candidate:
      return true
  false

proc collectReference(content: string, start: int): string =
  var i = start
  while i < content.len:
    let ch = content[i]
    if ch in {' ', '\n', '\r', '\t'}:
      break
    result.add(ch)
    inc i

proc normalizeReference(path: string): string =
  result = path.strip()
  while result.len > 0 and result[^1] in {')', ']', '}', ',', '.', ';', ':'}:
    result = result[0 ..< result.len - 1]

proc isFileLikeReference(path: string): bool =
  path == "AGENTS.md" or path == "config.nims" or path == "axiom.nimble" or
  path.endsWith(".nim") or path.endsWith(".md") or path.endsWith(".yml")

proc resolveReferencedPath(path: string): string =
  if path.contains("/") or path == "AGENTS.md" or path == "config.nims" or
      path == "axiom.nimble":
    return path

  let needle = path[0 ..< path.len - 4]
  for fullPath in walkDirRec("src"):
    if splitFile(fullPath).name == needle:
      return fullPath
  path

proc hasGlobPattern(path: string): bool =
  ## Treat glob metacharacters (* ? [ ]) AND angle-bracket template placeholders
  ## (<...>, e.g. docs/spec/<topic>_quirks.md — a mandate/template, not a literal
  ## file) as non-literal so they are never resolved as real paths.
  path.contains("*") or path.contains("?") or path.contains("[") or path.contains("]") or
    path.contains("<") or path.contains(">")

proc extractFileReferences*(content: string): seq[string] =
  ## AGENTS.md에서 파일 참조 추출
  result = @[]
  var i = 0
  while i < content.len:
    let ch = content[i]
    if ch == '`':
      i += 1
      var span = ""
      while i < content.len and content[i] != '`':
        span.add(content[i])
        inc i
      if i < content.len and content[i] == '`':
        inc i
      let parts = normalizeReference(span).splitWhitespace()
      if parts.len == 0:
        continue
      let path = parts[0]
      if path.len > 0 and path[^1] != '/' and isFileLikeReference(path) and not hasGlobPattern(path):
        result.add(path)
      continue

    if (ch == '/' or ch == '.') and isReferenceStart(content, i):
      let path = collectReference(content, i)
      let normalized = normalizeReference(path)
      if normalized.len > 0 and normalized[^1] != '/' and not normalized.contains(" ") and not hasGlobPattern(normalized):
        result.add(normalized)
      i = max(i, i + path.len)
    else:
      inc i

proc verifyAGENTSSync*(): bool =
  ## AGENTS.md와 실제 레포지토리 상태 동기화 검증
  let agentMdPath = "AGENTS.md"
  if not fileExists(agentMdPath):
    echo "[META-GATE] AGENTS.md not found"
    return false

  let content = readFile(agentMdPath)

  # 1. .circleci/config.yml 존재 여부 검사 (CI=0 cutover — must be absent)
  if fileExists(".circleci/config.yml"):
    echo "[META-GATE] FAIL: .circleci/config.yml exists but CI=0 cutover removed all CI"
    return false

  # 3. AGENTS.md 내의 파일 참조가 실제로 존재하는지 검사
  let referencedFiles = extractFileReferences(content)
  for file in referencedFiles:
    let resolvedFile = resolveReferencedPath(file)
    if not fileExists(resolvedFile):
      echo "[META-GATE] FAIL: Referenced file " & resolvedFile & " not found"
      return false

  echo "[META-GATE] PASS: AGENTS.md sync verified"
  return true

when isMainModule:
  if verifyAGENTSSync():
    quit(0)
  else:
    quit(1)
