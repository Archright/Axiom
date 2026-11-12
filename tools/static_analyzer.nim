## Track B — Consolidated Static Analyzer
##
## Absorbs: dead-code-gate, dependency-rules-gate (+dag-enforcement +topology-policy),
## architecture-config-gate, architecture-guard, validate-architecture, dep-analysis-gate,
## and binary detection from magic-number-sniffer + directory-structure-gate.
##
## Single binary, single walkDirRec pass. Outputs structured report; exit 0 = pass.

import core/trusted/layer_declaration
axiomLayer "tools"
import std/[os, strutils, json, tables, sets, hashes, monotimes, re]
import core/utils/repo_root
import core/trusted/layer_rules  ## SSOT LayerRules — replaces local duplicate below
import core/trusted/axiom_pragmas  ## axiomGate pragma (include chain: axiom_pragmas_macros)


# ─── Constants from absorbed gates ───────────────────────────────────

const
  MaxComplexity = 20
  ElfMagic: array[4, byte] = [0x7F.byte, 0x45, 0x4C, 0x46]
  IconExtensions: array[9, string] = [
    ".ico", ".png", ".jpg", ".jpeg", ".gif", ".webp", ".bmp", ".tiff", ".tif"
  ]
  MaxIconBytes = 10 * 1024
  BinaryFileAllowlist = ["_test", "_bin", "mock_", "test_"]
  SkipDirs = [".git", "vendor", "bin", "build", "__pycache__", "runners"]

  SingleFileDirAllowlist = ["passes", "protocol", "reporting", "text"]

  WhitelistPath = "data/dead_code_whitelist.json"

  # Local tuple-based rules REMOVED — consumed from authoritative LayerRules (SSOT)
  # via layerRuleToTuple() adapter below. The old local array[4, tuple[...]] was
  # a diverged duplicate; all enforcement now reads from core/trusted/layer_rules.

  ForbiddenDirPatterns = ["private/"]

  DipExceptions = [
    "src/core/application/persona_context_init.nim",
    "src/core/orchestration/pipeline_types.nim",
    "src/core/orchestration/pipeline_dispatch.nim",
    "src/core/boundary/verification_interface.nim",
    "src/verification/proof/arithmetic_type_directed_pipeline.nim",
    "src/core/encoding/smt_to_lean_codegen.nim",
    "src/gate/runners/spec_binding_gate.nim",
    "src/gate/runners/debt_blocker_gate.nim",
    "src/verification/batch_uap/loop_driver.nim",
  ]

# ─── Types ───────────────────────────────────────────────────────────

type
  ViolationKind = enum
    vkDeadCode, vkLayerViolation, vkPrivateDirAccess,
    vkCircularDep, vkBinaryInSrc, vkSingleFileDir,
    vkArchConfigLayer, vkArchConfigSrp, vkArchConfigSsot,
    vkUnregisteredModule, vkMissingScrMetadata,
    vkForwardingStub, vkRelativeImport

  Violation = object
    kind: ViolationKind
    file: string
    line: int
    message: string

# ─── Helpers ─────────────────────────────────────────────────────────

proc isElfBinary(path: string): bool =
  try:
    let f = open(path, fmRead)
    defer: close(f)
    var header: array[4, byte]
    if readBuffer(f, addr header, 4) < 4: return false
    header == ElfMagic
  except IOError, OSError: false  # axiom:best-effort(ELF header read; skip unreadable, treat as non-binary)

proc extractImportModule(line: string): string =
  let s = line.strip()
  if s.startsWith("import "):
    let after = s[7..^1].strip()
    var endIdx = 0
    while endIdx < after.len and after[endIdx] notin Whitespace: inc endIdx
    after[0..<endIdx].strip(chars = {',', ';'})
  elif s.startsWith("from "):
    let after = s[5..^1].strip()
    var endIdx = 0
    while endIdx < after.len and after[endIdx] notin Whitespace: inc endIdx
    after[0..<endIdx].strip(chars = {',', ';'})
  else: ""

proc parseImports(content: string): seq[string] =
  var inMulti = false
  for line in content.splitLines():
    let s = line.strip()
    let tc = s.count("\"\"\"")
    if tc mod 2 == 1: inMulti = not inMulti
    if inMulti: continue
    let m = extractImportModule(s)
    if m.len > 0: result.add(m)

proc relPath(repoRoot, path: string): string =
  let r = path.replace(repoRoot & "/", "")
  if r.len == path.len and path.len > repoRoot.len:
    path[repoRoot.len + 1 .. ^1]
  else: r

proc isExcludedSym(name: string): bool =
  name.len == 0 or name == "main" or name.startsWith("_") or name.startsWith("init") or name.startsWith("test")

func startsWithAny(s: string; prefixes: seq[string]): bool =
  for p in prefixes:
    if s.startsWith(p): return true
  false

# ─── Dead Code Detection ─────────────────────────────────────────────

proc loadDeadCodeWhitelist(repoRoot: string): HashSet[string] =
  result = initHashSet[string]()
  let wlPath = repoRoot / WhitelistPath
  if not fileExists(wlPath): return
  try:
    let root = parseJson(readFile(wlPath))
    if root.hasKey("entries"):
      for e in root["entries"]:
        if e.hasKey("symbol"):
          result.incl(e["symbol"].getStr(""))
  except IOError, OSError: discard  # axiom:best-effort(watchlist optional; skip if unreadable)

proc extractSymbol(declLine: string): (string, bool) =
  let s = declLine.strip()
  var kwEnd = -1
  if s.startsWith("proc "): kwEnd = 5
  elif s.startsWith("func "): kwEnd = 5
  elif s.startsWith("method "): kwEnd = 7
  elif s.startsWith("template "): kwEnd = 9
  elif s.startsWith("macro "): kwEnd = 6
  elif s.startsWith("converter "): kwEnd = 10
  elif s.startsWith("iterator "): kwEnd = 9
  else: return ("", false)
  var start = kwEnd
  while start < s.len and s[start] == ' ': inc start
  var nameEnd = start
  while nameEnd < s.len:
    let c = s[nameEnd]
    if c.isAlphaNumeric() or c == '_' or c == '*': inc nameEnd
    else: break
  let name = s[start ..< nameEnd]
  let exported = '*' in name
  (name.replace("*", ""), exported)

proc scanDeadCode(repoRoot: string; files: seq[string]; contents: Table[string, string]): seq[Violation] =
  let whitelist = loadDeadCodeWhitelist(repoRoot)
  for fp in files:
    if fp notin contents: continue
    let content = contents[fp]
    for line in content.splitLines():
      let s = line.strip()
      if s.startsWith("#"): continue
      let (name, exported) = extractSymbol(s)
      if name.len == 0: continue
      if exported: continue
      if isExcludedSym(name): continue
      if name in whitelist: continue
      var foundCaller = false
      for ofp, oc in contents:
        if ofp == fp: continue
        if name in oc:
          for ol in oc.splitLines():
            let os = ol.strip()
            if os.startsWith("#"): continue
            var idx = 0
            while idx <= os.len - name.len:
              let mi = os.find(name, idx)
              if mi < 0: break
              let beforeOk = mi == 0 or not os[mi - 1].isAlphaNumeric()
              let afterPos = mi + name.len
              let afterOk = afterPos >= os.len or not os[afterPos].isAlphaNumeric()
              if beforeOk and afterOk: foundCaller = true; break
              idx = mi + 1
          if foundCaller: break
      if not foundCaller:
        result.add(Violation(kind: vkDeadCode, file: relPath(repoRoot, fp), line: 0, message: "dead symbol: " & name))

# ─── Layer & Dependency Rules ────────────────────────────────────────

## Adapter: convert authoritative LayerRule (object) → tuple format
## consumed by existing scanDependencyViolations logic.
proc layerRuleToTuple(r: LayerRule): (string, seq[string], seq[string]) =
  (r.source, r.allowedImports, r.forbiddenImports)

proc checkLayerRule(relFile: string; importModule: string): bool =
  for rule in LayerRules:
    let (prefix, can, cannot) = layerRuleToTuple(rule)
    if relFile.startsWith(prefix):
      if importModule.startsWith("std/"): return false
      let canMatch = startsWithAny(importModule, can)
      let cannotMatch = startsWithAny(importModule, cannot)
      if cannotMatch or not canMatch: return true
  false

proc scanDependencyViolations(repoRoot: string; files: seq[string]; contents: Table[string, string]): seq[Violation] =
  for fp in files:
    let rel = relPath(repoRoot, fp)
    if not rel.startsWith("src/"): continue
    var isDipExempt = false
    for d in DipExceptions:
      if rel == d: isDipExempt = true; break
    if isDipExempt: continue
    if fp notin contents: continue
    let content = contents[fp]
    var inMulti = false
    var lineNum = 0
    for rawLine in content.splitLines():
      inc lineNum
      let s = rawLine.strip()
      let tc = s.count("\"\"\"")
      if tc mod 2 == 1: inMulti = not inMulti
      if inMulti: continue
      let modName = extractImportModule(s)
      if modName.len == 0: continue
      for forbidden in ForbiddenDirPatterns:
        if forbidden in modName:
          let privateIdx = modName.find(forbidden)
          let pkgPrefix = modName[0..<privateIdx] & "/"
          if privateIdx >= 0:
            let impMod = rel
            let impStart = if impMod.startsWith("src/"): 4 else: 0
            let impPkgPrefix = impMod[impStart..^1]
            if impPkgPrefix.startsWith(pkgPrefix): continue
          result.add(Violation(kind: vkPrivateDirAccess, file: rel, line: lineNum, message: "private dir access: " & modName))
      let resolved = if '/' in modName: modName else: (if rel.rfind('/') >= 0: rel[0..rel.rfind('/')] & "/" & modName else: modName)
      let normalizedResolved = normalizeImportPath(resolved)
      if checkLayerRule(rel, normalizedResolved):
        result.add(Violation(kind: vkLayerViolation, file: rel, line: lineNum, message: "layer violation: " & s))

# ─── Circular Dependency Detection ───────────────────────────────────

proc findCycles(graph: Table[string, seq[string]]): seq[seq[string]] =
  var visited = initHashSet[string]()
  for startNode in graph.keys:
    if startNode in visited: continue
    var stack: seq[tuple[node: string, childIdx: int, path: seq[string], pathSet: HashSet[string]]] = @[]
    stack.add((node: startNode, childIdx: 0, path: @[startNode], pathSet: toHashSet([startNode])))
    visited.incl(startNode)
    while stack.len > 0:
      let fi = stack.len - 1
      let deps = graph.getOrDefault(stack[fi].node)
      if stack[fi].childIdx < deps.len:
        let neighbor = deps[stack[fi].childIdx]
        stack[fi].childIdx.inc
        if neighbor in stack[fi].pathSet:
          var cycle: seq[string] = @[]
          var started = false
          for n in stack[fi].path:
            if n == neighbor: started = true
            if started: cycle.add(n)
          if cycle.len > 0 and cycle notin result: result.add(cycle)
        elif neighbor in graph and neighbor notin visited:
          visited.incl(neighbor)
          var newPath = stack[fi].path; newPath.add(neighbor)
          var newSet = stack[fi].pathSet; newSet.incl(neighbor)
          stack.add((node: neighbor, childIdx: 0, path: newPath, pathSet: newSet))
      else: discard stack.pop()

proc scanCycles(files: seq[string]; contents: Table[string, string]; repoRoot: string): seq[Violation] =
  var graph = initTable[string, seq[string]]()
  for fp in files:
    let rel = relPath(repoRoot, fp)
    if not rel.startsWith("src/") or not rel.endsWith(".nim"): continue
    let modName = rel[4 .. ^5]
    if fp in contents:
      graph[modName] = parseImports(contents[fp])
  let cycles = findCycles(graph)
  for cycle in cycles:
    result.add(Violation(kind: vkCircularDep, file: cycle[0], line: 0, message: "cycle: " & cycle.join(" -> ") & " -> " & cycle[0]))

# ─── Binary Detection (from magic-number-sniffer + directory-structure) ──

proc scanBinaries(repoRoot: string): seq[Violation] =
  for scanDir in ["src", "tests"]:
    let dirPath = repoRoot / scanDir
    if not dirExists(dirPath): continue
    try:
      for path in walkDirRec(dirPath):
        var skip = false
        for part in path.split(DirSep):
          if part.startsWith(".") or part in SkipDirs: skip = true; break
        if skip: continue
        if not fileExists(path): continue
        if path.endsWith(".nim") or path.endsWith(".json") or path.endsWith(".md") or path.endsWith(".txt") or
           path.endsWith(".toml") or path.endsWith(".yaml") or path.endsWith(".yml") or path.endsWith(".lock"): continue
        let baseName = lastPathPart(path)
        var allowed = false
        for pat in BinaryFileAllowlist:
          if baseName.startsWith(pat) or baseName.endsWith(pat): allowed = true; break
        if allowed: continue
        let (_, _, ext) = splitFile(path)
        var isIcon = false
        for e in IconExtensions:
          if ext.toLowerAscii() == e: isIcon = true; break
        if isIcon:
          try:
            if getFileSize(path) <= MaxIconBytes: continue
          except IOError, OSError: discard  # axiom:best-effort(icon size check; skip if unreadable)
        if isElfBinary(path):
          let rel = relPath(repoRoot, path)
          result.add(Violation(kind: vkBinaryInSrc, file: rel, line: 0, message: "ELF binary in " & scanDir & "/ (not LFS-tracked)"))
    except IOError, OSError: discard  # axiom:best-effort(directory walk; skip unreadable entry)

# ─── Single-File Directory Scan ───────────────────────────────────────

proc scanSingleFileDirs(repoRoot: string): seq[Violation] =
  let coreDir = repoRoot / "src" / "core"
  if not dirExists(coreDir): return
  try:
    for kind, path in walkDir(coreDir):
      if kind != pcDir: continue
      let dirName = lastPathPart(path)
      if dirName.startsWith("."): continue
      if dirName in SingleFileDirAllowlist: continue
      var nimCount = 0; var nimName = ""
      try:
        for fk, fp in walkDir(path):
          if fk == pcFile and fp.endsWith(".nim"): nimCount.inc; nimName = lastPathPart(fp)
      except IOError, OSError: continue  # axiom:best-effort(single-file dir subdir walk; skip unreadable entry)
      if nimCount == 1:
        let rel = relPath(repoRoot, path)
        result.add(Violation(kind: vkSingleFileDir, file: rel, line: 0, message: "single-file dir: " & nimName))
  except IOError, OSError: discard  # axiom:best-effort(single-file dir scan; skip unreadable)

# ─── Architecture Config Checks (layer-isolation, SRP, SSOT mutation) ──

type ArchViolation = object
  ruleId: string
  severity: string
  filePath: string
  line: int
  message: string

proc loadArchConfig(repoRoot: string): JsonNode =
  let configPath = repoRoot / "src" / "gate" / "configs" / "architecture_rules.json"
  if not fileExists(configPath): return newJNull()
  parseJson(readFile(configPath))

proc extractImports(content: string): seq[tuple[lineNo: int, path: string]] =
  var lineNo = 0; var inImportBlock = false
  for rawLine in content.splitLines():
    lineNo.inc
    let s = rawLine.strip()
    if s.len == 0 or s.startsWith("#"): inImportBlock = false; continue
    var isImport = false
    if s.startsWith("import ") or s.startsWith("from "): inImportBlock = false; isImport = true
    elif s == "import": inImportBlock = true; continue
    elif inImportBlock:
      if rawLine.startsWith(" ") or rawLine.startsWith("\t"): isImport = true
      else: inImportBlock = false
    if isImport:
      var importPart = s
      if importPart.startsWith("from "):
        let parts = importPart.split(" import ")
        if parts.len >= 1: importPart = parts[0][5..^1].strip()
      elif importPart.startsWith("import "): importPart = importPart[7..^1].strip()
      for part in importPart.split(","):
        var p = part.strip()
        let excIdx = p.find(" except"); if excIdx >= 0: p = p[0..<excIdx].strip()
        let asIdx = p.find(" as "); if asIdx >= 0: p = p[0..<asIdx].strip()
        if p.len > 0 and not p.startsWith("std/") and not p.startsWith("pkg/"):
          result.add((lineNo, p))

proc getDomainPrefix(path: string): string =
  let parts = path.split("/")
  if parts.len >= 2: parts[1] elif parts.len == 1 and parts[0].len > 0: parts[0] else: ""

proc runArchConfigChecks(repoRoot: string): seq[Violation] =
  let config = loadArchConfig(repoRoot)
  if config.isNil or config.kind == JNull: return
  let rules = config{"rules"}
  if rules.isNil or rules.kind == JNull: return

  var allViolations: seq[ArchViolation]

  # Layer isolation check
  for ruleName, ruleNode in rules.pairs:
    if not ruleNode.hasKey("source") or not ruleNode.hasKey("forbidden"): continue
    let sev = ruleNode{"severity"}.getStr("error")
    let source = ruleNode{"source"}.getStr("")
    let sourceDir = repoRoot / source
    if not dirExists(sourceDir): continue
    var exemptNames: seq[string] = @[]
    if ruleNode.hasKey("exempt"):
      for e in ruleNode{"exempt"}: exemptNames.add(e.getStr(""))
    var forbiddenTargets: seq[string] = @[]
    for t in ruleNode{"forbidden"}: forbiddenTargets.add(t.getStr(""))
    if forbiddenTargets.len == 0: continue
    for filePath in walkDirRec(sourceDir):
      if not filePath.endsWith(".nim"): continue
      let fn = extractFilename(filePath)
      var exempt = false
      for en in exemptNames:
        if fn.contains(en): exempt = true; break
      if exempt: continue
      let content = try: readFile(filePath) except CatchableError: ""  # axiom:best-effort(file unreadable; skip file, continue with remainder)
      if content.len == 0: continue
      let imports = extractImports(content)
      let rel = relPath(repoRoot, filePath)
      for imp in imports:
        for tgt in forbiddenTargets:
          let effective = if tgt.startsWith("src/"): tgt[4..^1] else: tgt
          if imp.path.startsWith(effective & "/") or imp.path == effective:
            allViolations.add(ArchViolation(ruleId: ruleName, severity: sev, filePath: rel, line: imp.lineNo, message: "forbidden import: " & imp.path))

  # SRP check
  if rules.hasKey("srp-import-prefix"):
    let srpRule = rules{"srp-import-prefix"}
    let maxPref = srpRule{"max_prefixes"}.getInt(3)
    let sev = srpRule{"severity"}.getStr("warn")
    var scanRoots: seq[string] = @[]
    if srpRule.hasKey("scan_roots"):
      for r in srpRule{"scan_roots"}: scanRoots.add(r.getStr(""))
    for root in scanRoots:
      let scanDir = repoRoot / root
      if not dirExists(scanDir): continue
      for filePath in walkDirRec(scanDir):
        if not filePath.endsWith(".nim"): continue
        let content = try: readFile(filePath) except CatchableError: ""  # axiom:best-effort(file unreadable; skip file, continue with remainder)
        if content.len == 0: continue
        let imports = extractImports(content)
        let rel = relPath(repoRoot, filePath)
        var prefixes = initHashSet[string]()
        for imp in imports:
          let prefix = getDomainPrefix(imp.path)
          if prefix.len > 0: prefixes.incl(prefix)
        if prefixes.len >= maxPref:
          allViolations.add(ArchViolation(ruleId: "srp-import-prefix", severity: sev, filePath: rel, line: 0, message: $prefixes.len & " prefixes (max " & $maxPref & ")"))

  # SSOT mutation check
  if rules.hasKey("ssot-mutation"):
    let ssotRule = rules{"ssot-mutation"}
    let sev = ssotRule{"severity"}.getStr("error")
    var patterns: seq[string] = @[]
    if ssotRule.hasKey("patterns"):
      for p in ssotRule{"patterns"}: patterns.add(p.getStr(""))
    var exemptFiles: seq[string] = @[]
    if ssotRule.hasKey("exempt_files"):
      for f in ssotRule{"exempt_files"}: exemptFiles.add(f.getStr(""))
    if patterns.len > 0:
      let srcDir = repoRoot / "src"
      if dirExists(srcDir):
        for filePath in walkDirRec(srcDir):
          if not filePath.endsWith(".nim"): continue
          let fn = extractFilename(filePath)
          var exempt = false
          for ef in exemptFiles:
            if fn == ef: exempt = true; break
          if exempt: continue
          let content = try: readFile(filePath) except CatchableError: ""  # axiom:best-effort(file unreadable; skip file, continue with remainder)
          if content.len == 0: continue
          let rel = relPath(repoRoot, filePath)
          var lineNo = 0
          for line in content.splitLines():
            lineNo.inc
            let s = line.strip()
            if s.startsWith("#"): continue
            for pat in patterns:
              if pat in s:
                let patIdx = s.find(pat)
                let afterPat = patIdx + pat.len
                if afterPat < s.len and s[afterPat] == '=': continue
                allViolations.add(ArchViolation(ruleId: "ssot-mutation", severity: sev, filePath: rel, line: lineNo, message: "forbidden mutation: " & pat))

  for v in allViolations:
    let kind = if v.severity == "error": vkArchConfigLayer else: vkArchConfigSrp
    result.add(Violation(kind: kind, file: v.filePath, line: v.line, message: v.ruleId & ": " & v.message))

# ─── Architecture Guard Checks (domain registration, SCR metadata) ────

proc runArchitectureGuard(repoRoot: string): seq[Violation] =
  let registryPath = repoRoot / "src" / "core" / "domain_layout.json"
  if not fileExists(registryPath): return
  let registry = try: parseJson(readFile(registryPath)) except: return
  let domains = registry{"domains"}
  # SCR metadata check
  if not domains.isNil:
    for name, config in domains.pairs:
      let hasOwner = config.hasKey("owner")
      let hasScore = config.hasKey("priority_score")
      if not (hasOwner and hasScore):
        result.add(Violation(kind: vkMissingScrMetadata, file: "domain_layout.json", line: 0, message: "domain '" & name & "' missing owner or priority_score"))
  # Unregistered module check
  if not domains.isNil:
    var registeredPrefixes: seq[string] = @[]
    for name, config in domains.pairs:
      let prefixes = config{"prefix"}
      if not prefixes.isNil:
        for p in prefixes: registeredPrefixes.add(p.getStr(""))
    let coreDir = repoRoot / "src" / "core"
    if dirExists(coreDir):
      for path in walkDirRec(coreDir):
        if not path.endsWith(".nim"): continue
        let stem = changeFileExt(extractFilename(path), "")
        var registered = false
        for p in registeredPrefixes:
          if stem.startsWith(p): registered = true; break
        if not registered:
          result.add(Violation(kind: vkUnregisteredModule, file: relPath(repoRoot, path), line: 0, message: "unregistered module: " & stem))

# ─── Validate Architecture Checks (stub detection, relative imports) ──

proc runValidateArchitecture(repoRoot: string; contents: Table[string, string]): seq[Violation] =
  const declKws = ["proc ", "func ", "type ", "var ", "let ", "const ", "macro ", "template "]
  let coreDir = repoRoot / "src" / "core"
  if dirExists(coreDir):
    for path in walkDir(coreDir):
      if path.kind != pcFile or not path.path.endsWith(".nim"): continue
      let rel = relPath(repoRoot, path.path)
      let content = try: readFile(path.path) except CatchableError: ""  # axiom:best-effort(file unreadable; skip file, continue with remainder)
      if content.len == 0: continue
      var cleaned = content
      for ln in content.splitLines():
        if ln.strip().startsWith("#"): cleaned = cleaned.replace(ln & "\n", "")
      const tripleQuotePat = "(?s)\"\"\".*?\"\"\""
      const tripleQuoteFmtPat = "(?s)fmt\"\"\".*?\"\"\""
      const tripleQuoteRawPat = "(?s)[rR]\"\"\".*?\"\"\""
      const strPat = "\"(?:[^\"\\\\]|\\\\.)*\""
      const rawStrPat = "[rR]\"(?:[^\"\\\\]|\\\\.)*\""
      const fmtStrPat = "fmt\"(?:[^\"\\\\]|\\\\.)*\""
      cleaned = cleaned.replace(re(tripleQuotePat), "\"\"")
      cleaned = cleaned.replace(re(tripleQuoteFmtPat), "\"\"")
      cleaned = cleaned.replace(re(tripleQuoteRawPat), "\"\"")
      cleaned = cleaned.replace(re(strPat), "\"\"")
      cleaned = cleaned.replace(re(rawStrPat), "\"\"")
      cleaned = cleaned.replace(re(fmtStrPat), "\"\"")
      var hasDecl = false
      for kw in declKws:
        if kw in cleaned: hasDecl = true; break
      if not hasDecl:
        var onlyStructural = true
        for line in cleaned.splitLines():
          let s = line.strip()
          if s.len == 0: continue
          if s.startsWith("import ") or s.startsWith("from ") or s.startsWith("export ") or s.startsWith("include ") or s == "import" or s == "export" or s == "include": continue
          if s.startsWith("{.") and s.endsWith(".}"): continue
          onlyStructural = false; break
        if onlyStructural and cleaned.strip().len > 0:
          result.add(Violation(kind: vkForwardingStub, file: rel, line: 0, message: "forwarding stub"))
  # Relative imports
  for fp, content in contents:
    var lineNo = 0
    for line in content.splitLines():
      lineNo.inc
      let s = line.strip()
      if "#" in s: continue
      if s.contains("import " & "../") or s.contains("import " & "./"):
        result.add(Violation(kind: vkRelativeImport, file: relPath(repoRoot, fp), line: lineNo, message: "relative import"))

# ─── Main ────────────────────────────────────────────────────────────

proc main() =
  let repoRoot = findRepoRoot()
  setCurrentDir(repoRoot)
  let t0 = getMonoTime().ticks

  # Single walkDirRec pass: collect all .nim files + contents
  var files: seq[string] = @[]
  var contents = initTable[string, string]()
  try:
    for path in walkDirRec(repoRoot / "src"):
      if path.endsWith(".nim"):
        files.add(path)
        let content = try: readFile(path) except CatchableError: ""  # axiom:best-effort(file unreadable; skip file, continue with remainder)
        if content.len > 0:
          contents[path] = content
  except IOError, OSError: discard  # axiom:best-effort(content read; skip unreadable path)

  var allViolations: seq[Violation]

  allViolations.add scanDeadCode(repoRoot, files, contents)
  allViolations.add scanDependencyViolations(repoRoot, files, contents)
  allViolations.add scanCycles(files, contents, repoRoot)
  allViolations.add scanBinaries(repoRoot)
  allViolations.add scanSingleFileDirs(repoRoot)
  allViolations.add runArchConfigChecks(repoRoot)
  allViolations.add runArchitectureGuard(repoRoot)
  allViolations.add runValidateArchitecture(repoRoot, contents)

  let elapsedMs = (getMonoTime().ticks - t0) div 1_000_000

  # Output
  var jFindings = newJArray()
  for v in allViolations:
    jFindings.add(%*{"kind": $v.kind, "file": v.file, "line": v.line, "message": v.message})
  let report = %*{
    "analyzer": "static-analyzer",
    "durationMs": elapsedMs,
    "totalViolations": allViolations.len,
    "violations": jFindings
  }
  stdout.writeLine(report.pretty())

  if allViolations.len > 0:
    stderr.writeLine("[static-analyzer] FAIL — " & $allViolations.len & " violation(s)")
    for v in allViolations:
      stderr.writeLine("  [" & $v.kind & "] " & v.file & ":" & $v.line & " " & v.message)
    quit(1)
  else:
    stderr.writeLine("[static-analyzer] PASS — no violations (" & $files.len & " files, " & $elapsedMs & "ms)")
    quit(0)

when isMainModule:
  main()
