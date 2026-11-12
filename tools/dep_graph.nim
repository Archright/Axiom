## tools/dep_graph.nim — The Immutable Builder 의존성 그래프 엔진
## AGENTS.md §0.6: Static First Enforcement
## Nim 소스 파일을 스캔하여 import 관계를 추출하고 의존성 그래프를 구축
##
## NOTE: build_types.nim has a pre-existing {.push raises: [].} conflict with
## writeFile in save() procs. Types are defined locally to ensure compilation.
## Once build_types.nim is fixed, switch to `import build_types`.

import core/trusted/layer_declaration
axiomLayer "tools"
import std/[os, strutils, tables, times, algorithm]

# ── 공유 타입 (build_types.nim과 동일 정의) ──────────────────────────────────

type
  ModuleInfo* = object
    path*: string           ## 상대 경로 (src/core/foo.nim)
    imports*: seq[string]   ## import하는 모듈 경로 목록
    importedBy*: seq[string] ## 이 모듈을 import하는 모듈 목록

  DependencyGraph* = object
    modules*: seq[ModuleInfo]
    orphans*: seq[string]   ## 고아 모듈 경로 목록
    entryPoints*: seq[string] ## 최상위 진입점 모듈

  QuarantineEntry* = object
    path*: string           ## 격리 대상 모듈 경로
    reason*: string         ## 격리 사유 (orphan, broken_import)

  QuarantineManifest* = object
    version*: string
    entries*: seq[QuarantineEntry]

# ── 유틸리티 ──────────────────────────────────────────────────────────────────

func cmpStr(a, b: string): int {.raises: [].} =
  ## 정렬용 문자열 비교 함수 (raises: [] 보장)
  if a < b: -1
  elif a > b: 1
  else: 0

func stripComment(line: string): string {.raises: [].} =
  ## '#'으로 시작하는 주석 라인은 빈 문자열 반환
  let trimmed = line.strip()
  if trimmed.len == 0 or trimmed[0] == '#':
    return ""
  return trimmed

func canonPath(p: string): string {.raises: [].} =
  ## 경로 구분자를 '/'로 통일하고 불필요한 구분자 제거
  result = p.replace('\\', '/')
  while "//" in result:
    result = result.replace("//", "/")
  if result.endsWith("/"):
    result = result[0 .. ^2]

func dirName(filePath: string): string {.raises: [].} =
  ## 파일 경로에서 디렉토리 부분만 반환
  let sep = filePath.rfind('/')
  if sep >= 0: filePath[0 .. sep-1]
  else: "."

# ── 고아 탐지 (buildGraph보다 앞에 선언) ──────────────────────────────────────

func findOrphans*(graph: DependencyGraph): seq[string] {.raises: [].} =
  ## BFS로 entryPoints에서 도달 가능한 모듈을 탐색
  ## 도달 불가능한 모듈 = 고아 모듈
  var reachable = initTable[string, bool]()

  # BFS 큐 초기화
  var queue: seq[string] = @[]
  for ep in graph.entryPoints:
    if ep notin reachable:
      reachable[ep] = true
      queue.add(ep)

  # BFS 순회
  var head = 0
  while head < queue.len:
    let current = queue[head]
    inc head

    # 현재 모듈의 import 관계를 그래프에서 찾기
    for m in graph.modules:
      if m.path == current:
        for imp in m.imports:
          if imp notin reachable:
            reachable[imp] = true
            queue.add(imp)
        break

  # 도달 불가능한 모듈 수집
  result = @[]
  for m in graph.modules:
    if m.path notin reachable:
      result.add(m.path)
  result.sort(cmpStr)

# ── 격리 매니페스트 ────────────────────────────────────────────────────────────

func computeQuarantine*(graph: DependencyGraph): QuarantineManifest {.raises: [].} =
  ## 고아 모듈 목록으로부터 QuarantineManifest 생성
  result = QuarantineManifest(version: "1.0", entries: @[])
  for orphan in graph.orphans:
    result.entries.add(QuarantineEntry(path: orphan, reason: "orphan"))

# ── 파일 스캐너 ──────────────────────────────────────────────────────────────

proc scanFile(path: string): ModuleInfo =
  ## .nim 파일에서 import/from 문을 파싱하여 ModuleInfo 반환
  ## 텍스트 기반 파싱 (AST 미사용), 안정적이고 빠름
  var content: string
  try:
    content = readFile(path)
  except IOError:
    return ModuleInfo(path: path)

  result = ModuleInfo(path: path, imports: @[], importedBy: @[])

  var inMultilineImport = false

  for rawLine in content.splitLines():
    let line = stripComment(rawLine)
    if line.len == 0:
      inMultilineImport = false
      continue

    let trimmed = line.strip()

    # 'from X import symbol' 처리
    if trimmed.startsWith("from "):
      let rest = trimmed[5 .. ^1]
      let importIdx = rest.find(" import")
      if importIdx > 0:
        let moduleName = rest[0 .. importIdx-1].strip()
        if moduleName.len > 0:
          result.imports.add(moduleName)
      continue

    # 'import ...' 처리
    if trimmed.startsWith("import "):
      let rest = trimmed[7 .. ^1]

      # multi-line import: 쉼표로 끝나면 다음 라인 계속
      if rest.strip().endsWith(","):
        let items = rest[0 .. ^2].strip()  # 쉼표 제거
        for item in items.split(','):
          let s = item.strip()
          if s.len > 0:
            result.imports.add(s)
        inMultilineImport = true
        continue
      else:
        # 단일 라인 import (여러 모듈 가능: import a, b, c)
        for item in rest.split(','):
          let s = item.strip()
          if s.len > 0:
            result.imports.add(s)
        inMultilineImport = false
        continue

    # multi-line continuation: 쉼표로 끝나는 라인
    if inMultilineImport:
      if trimmed.endsWith(","):
        let items = trimmed[0 .. ^2].strip()
        for item in items.split(','):
          let s = item.strip()
          if s.len > 0:
            result.imports.add(s)
        continue
      else:
        # 마지막 항목
        for item in trimmed.split(','):
          let s = item.strip()
          if s.len > 0:
            result.imports.add(s)
        inMultilineImport = false
        continue

# ── 경로 해결 ──────────────────────────────────────────────────────────────────

proc resolveImport(fromFile: string, imported: string, srcDir: string): string =
  ## import 경로를 절대(소스 기준) 경로로 변환
  let clean = imported.strip()
  if clean.len == 0:
    return ""

  # stdlib 필터링: 단일 토큰且 점 없는 경우 stdlib로 간주
  let parts = clean.split('/')
  if parts.len == 1 and '.' notin parts[0]:
    return ""  # stdlib 모듈

  # .nim 확장자 보장
  var resolved = clean
  if not resolved.endsWith(".nim"):
    resolved = resolved & ".nim"

  # 상대 경로 해결: import하는 파일의 디렉토리 기준
  let fromDir = dirName(fromFile)
  var candidate = canonPath(fromDir / resolved)

  if not fileExists(candidate):
    candidate = canonPath(srcDir / resolved)

  if not fileExists(candidate):
    if resolved.startsWith(srcDir & "/"):
      candidate = canonPath(resolved)
    else:
      candidate = canonPath(srcDir / resolved)

  if fileExists(candidate):
    return canonPath(candidate)

  return canonPath(candidate)

# ── 그래프 빌더 ──────────────────────────────────────────────────────────────

proc buildGraph*(srcDir: string): DependencyGraph =
  ## src/ 디렉토리를 재귀적으로 순회하며 모든 .nim 파일을 스캔
  ## import/importedBy 관계를 포함한 의존성 그래프 구축
  ## 진입점: src/cli/ 및 src/gate/runners/ 디렉토리의 파일
  result = DependencyGraph(modules: @[], orphans: @[], entryPoints: @[])

  # 1단계: 모든 .nim 파일 스캔하여 ModuleInfo 수집
  var moduleMap = initTable[string, int]()  # 경로 → modules 인덱스
  var allFiles: seq[string] = @[]

  for path in walkDirRec(srcDir):
    if path.endsWith(".nim"):
      allFiles.add(path)

  # 정렬하여 결정론적 결과 보장
  allFiles.sort(cmpStr)

  for filePath in allFiles:
    let normalized = canonPath(filePath)
    let info = scanFile(filePath)
    let idx = result.modules.len
    moduleMap[normalized] = idx
    result.modules.add(info)

  # 2단계: import 관계를 resolved path로 변환하고 importedBy 역방향 구축
  for i in 0 ..< result.modules.len:
    var resolvedImports: seq[string] = @[]
    for rawImport in result.modules[i].imports:
      let resolved = resolveImport(result.modules[i].path, rawImport, srcDir)
      if resolved.len > 0:
        resolvedImports.add(resolved)
        # importedBy 역방향 엣지 추가
        if resolved in moduleMap:
          let targetIdx = moduleMap[resolved]
          result.modules[targetIdx].importedBy.add(result.modules[i].path)
    result.modules[i].imports = resolvedImports

  # 3단계: 진입점 자동 탐지 (src/cli/ 및 src/gate/runners/)
  for m in result.modules:
    if m.path.startsWith(srcDir & "/cli/") or
       m.path.startsWith(srcDir & "/gate/runners/"):
      result.entryPoints.add(m.path)

  result.entryPoints.sort(cmpStr)

  # 4단계: 고아 모듈 탐지
  result.orphans = findOrphans(result)

# ── 분석 함수 ──────────────────────────────────────────────────────────────────

proc computeSourceHash*(srcDir: string): uint64 =
  ## 모든 .nim 파일의 mtime와 file size를 결합하여 간단한 해시 생성
  ## SHA-256 대신 사용 (crypto 라이브러리 불필요)
  result = 0'u64
  var allFiles: seq[string] = @[]

  for path in walkDirRec(srcDir):
    if path.endsWith(".nim"):
      allFiles.add(path)

  allFiles.sort(cmpStr)

  for filePath in allFiles:
    try:
      let info = getFileInfo(filePath)
      # mtime과 fileSize를 간단한 해시에 결합
      result = result xor (cast[uint64](info.lastWriteTime.toUnix()) shl 16)
      result = result + cast[uint64](info.size)
      # 경로 문자열도 해시에 포함
      for c in filePath:
        result = result xor (cast[uint64](c) shl (result mod 56))
        result = result + 1
    except OSError:
      discard

proc loadStoredHash*(hashFile: string): uint64 =
  ## 저장된 해시 값을 파일에서 로드
  try:
    let content = readFile(hashFile)
    return parseUint(content.strip())
  except IOError, ValueError:
    return 0'u64

proc saveHash*(hashFile: string, hash: uint64) =
  ## 해시 값을 파일에 저장
  writeFile(hashFile, $hash)

proc analyze*(srcDir: string, hashFile: string): (DependencyGraph, bool) =
  ## 소스 해시를 확인하고 변경된 경우에만 그래프를 재구축
  ## (그래프, 변경여부) 튜플 반환
  let currentHash = computeSourceHash(srcDir)
  let storedHash = loadStoredHash(hashFile)

  if currentHash == storedHash:
    # 변경 없음 → 빈 그래프 반환
    return (DependencyGraph(modules: @[], orphans: @[], entryPoints: @[]), false)

  # 변경됨 → 그래프 재구축
  let graph = buildGraph(srcDir)

  # 새 해시 저장
  saveHash(hashFile, currentHash)

  return (graph, true)

# ── JSON 직렬화 ────────────────────────────────────────────────────────────────

proc toJson*(graph: DependencyGraph): string =
  ## DependencyGraph를 JSON 문자열로 직렬화 (간단한 수동 직렬화)
  result = "{\n  \"modules\": [\n"
  for i, m in graph.modules:
    result.add("    {\"path\": \"" & m.path & "\", \"imports\": [")
    for j, imp in m.imports:
      if j > 0: result.add(", ")
      result.add("\"" & imp & "\"")
    result.add("], \"importedBy\": [")
    for j, ib in m.importedBy:
      if j > 0: result.add(", ")
      result.add("\"" & ib & "\"")
    result.add("]}")
    if i < graph.modules.len - 1: result.add(",")
    result.add("\n")
  result.add("  ],\n")
  result.add("  \"orphans\": [")
  for i, o in graph.orphans:
    if i > 0: result.add(", ")
    result.add("\"" & o & "\"")
  result.add("],\n")
  result.add("  \"entryPoints\": [")
  for i, ep in graph.entryPoints:
    if i > 0: result.add(", ")
    result.add("\"" & ep & "\"")
  result.add("]\n}")

proc toJson*(manifest: QuarantineManifest): string =
  ## QuarantineManifest를 JSON 문자열로 직렬화
  result = "{\n  \"version\": \"" & manifest.version & "\",\n"
  result.add("  \"entries\": [\n")
  for i, e in manifest.entries:
    result.add("    {\"path\": \"" & e.path & "\", \"reason\": \"" & e.reason & "\"}")
    if i < manifest.entries.len - 1: result.add(",")
    result.add("\n")
  result.add("  ]\n}")

proc saveJson*(graph: DependencyGraph, path: string) =
  ## DependencyGraph를 JSON 파일로 저장
  writeFile(path, graph.toJson())

proc saveJson*(manifest: QuarantineManifest, path: string) =
  ## QuarantineManifest를 JSON 파일로 저장
  writeFile(path, manifest.toJson())

# ── 메인 ───────────────────────────────────────────────────────────────────────

when isMainModule:
  let srcDir = "src"
  let hashFile = "data/.dep_graph_hash"

  echo "=== Dep Graph Analysis ==="
  let (graph, changed) = analyze(srcDir, hashFile)

  if not changed:
    echo "No changes detected. Skipping graph rebuild."
  else:
    echo "Changes detected. Graph rebuilt."
    echo "Modules: ", graph.modules.len
    echo "Entry points: ", graph.entryPoints.len
    echo "Orphans: ", graph.orphans.len

    for ep in graph.entryPoints:
      echo "  [entry] ", ep
    for orphan in graph.orphans:
      echo "  [orphan] ", orphan

    # 그래프 저장
    saveJson(graph, "build/dep_graph.json")
    echo "Graph saved to build/dep_graph.json"

    # 격리 매니페스트 생성
    let manifest = computeQuarantine(graph)
    saveJson(manifest, "build/quarantine.json")
    echo "Quarantine manifest saved to build/quarantine.json"
