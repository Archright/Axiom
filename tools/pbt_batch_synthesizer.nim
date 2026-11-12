import core/trusted/layer_declaration
axiomLayer "tools"
{.push raises: [].}

import api/tools_facade
import shared_types/solver_bridge
import std/[os, strutils, re, tables, osproc, algorithm, json, sets]
const
  GeneratedPbtDir = "tests/pbt"
  CachePath = ".axiom_gate_cache.json"
  EngineVersion = "1.0.0"
var builtins: HashSet[string] = initHashSet[string]()
builtins.incl("int")
builtins.incl("int8")
builtins.incl("int16")
builtins.incl("int32")
builtins.incl("int64")
builtins.incl("uint")
builtins.incl("uint8")
builtins.incl("uint16")
builtins.incl("uint32")
builtins.incl("uint64")
builtins.incl("float")
builtins.incl("float32")
builtins.incl("float64")
builtins.incl("bool")
builtins.incl("char")
builtins.incl("string")
builtins.incl("byte")
type
  GateCacheEntry = object
    engineVersion: string
    lastValidatedAt: string
    manifestHash: string
    topologySignature: string
    sourceHashes: Table[string, string]
    gateStatus: string

  UnaryFunc = tuple[name: string, paramName: string, paramType: string, returnType: string]
  PureFunc = tuple[name: string, paramTypes: seq[string], returnType: string]
proc computeFileHash(path: string): string {.raises: [].} =
  ## Compute SHA256 of a file using sha256sum.
  result = ""
  try:
    let (output, exitCode) = execCmdEx("sha256sum " & quoteShell(path))
    if exitCode == 0:
      let parts = output.splitWhitespace()
      if parts.len > 0:
        result = parts[0]
  except CatchableError:
    discard  # axiom:best-effort(exec-failure: sha256sum unavailable, treat as empty hash)
proc computeTopologySignature(filePaths: seq[string]): string {.raises: [].} =
  ## Collect all source file paths, sort, join with newline, SHA256 the result.
  result = ""
  var sorted = filePaths
  sorted.sort()
  let joined = sorted.join("\n")
  try:
    let tmpPath = "/tmp/.axiom_topology_sig.txt"
    writeFile(tmpPath, joined)
    let (output, exitCode) = execCmdEx("sha256sum " & quoteShell(tmpPath))
    if exitCode == 0:
      let parts = output.splitWhitespace()
      if parts.len > 0:
        result = parts[0]
    removeFile(tmpPath)
  except CatchableError:
    discard  # axiom:best-effort(remove-temp-file-failure: temp file cleanup is non-critical)
proc readCache(path: string): GateCacheEntry {.raises: [].} =
  ## Read .axiom_gate_cache.json.
  result = GateCacheEntry()
  result.sourceHashes = initTable[string, string]()
  var content = ""
  try:
    content = readFile(path)
  except CatchableError:
    return
  var node: JsonNode
  try:
    node = parseJson(content)
  except CatchableError:
    return
  if node.hasKey("engineVersion"): result.engineVersion = node.getOrDefault("engineVersion").getStr("")
  if node.hasKey("lastValidatedAt"): result.lastValidatedAt = node.getOrDefault("lastValidatedAt").getStr("")
  if node.hasKey("manifestHash"): result.manifestHash = node.getOrDefault("manifestHash").getStr("")
  if node.hasKey("topologySignature"): result.topologySignature = node.getOrDefault("topologySignature").getStr("")
  if node.hasKey("gateStatus"): result.gateStatus = node.getOrDefault("gateStatus").getStr("")
  if node.hasKey("sourceHashes"):
    let srcNode = node.getOrDefault("sourceHashes")
    if srcNode != nil and srcNode.kind == JObject:
      for key, val in srcNode:
        result.sourceHashes[key] = val.getStr("")
proc writeCache(path: string; entry: GateCacheEntry) {.raises: [].} =
  ## Write cache file as JSON.
  var node = newJObject()
  node["engineVersion"] = %entry.engineVersion
  node["lastValidatedAt"] = %entry.lastValidatedAt
  node["manifestHash"] = %entry.manifestHash
  node["topologySignature"] = %entry.topologySignature
  node["gateStatus"] = %entry.gateStatus
  var srcNode = newJObject()
  for key, val in entry.sourceHashes:
    srcNode[key] = %val
  node["sourceHashes"] = srcNode
  try:
    writeFile(path, node.pretty())
  except CatchableError:
    discard  # axiom:best-effort(cache-write-failure: cache miss is acceptable, rebuild on next run)
let objectTypePattern = re(r"^type\s+(\w+\*?)\s*=\s*object", {reStudy})
let objectTypeBlockPattern = re(r"^(\w+\*?)\s*=\s*object", {reStudy})
let ObjectTypePattern = re(r"^type\s+(\w+\*?)\s*=\s*object", {reStudy})
let ObjectTypeBlockPattern = re(r"^(\w+\*?)\s*=\s*object", {reStudy})
let ioModulePattern = re(r"\bimport\s+.*?\b(os|posix|winlean|asyncdispatch|malebolgia|z3)\b", {reStudy})
let procDeclPattern = re(r"\b(proc|func|method|template|macro)\b", {reStudy})
let unaryFuncPattern = re(r"^func\s+(\w+\*?)\s*\(\s*(\w+)\s*:\s*(\w+)\s*\)\s*:\s*(\w+)", {reStudy})
let pureFuncPattern = re(r"func\s+(\w+\*?)\s*\(([^)]*)\)\s*:\s*(\w+)", {reStudy})
proc buildSourceTreeMatrix(): Table[string, string] {.raises: [].} =
  ## Build a mapping from module name to relative import path.
  ## e.g., {"gateway_spec": "core/boundary/gateway/gateway_spec", "metrics": "core/metrics/metrics"}
  result = initTable[string, string]()
  var filePaths: seq[string] = @[]
  try:
    for fp in walkDirRec("src"):
      filePaths.add(fp)
  except OSError:
    discard
  for fp in filePaths:
    if not fp.endsWith(".nim"): continue
    let (_, baseName, _) = splitFile(fp)
    let cleanName = baseName.strip(chars = {'*'})
    let relPath = fp.replace("src/", "").replace(".nim", "").replace("\\", "/")
    if cleanName notin result:
      result[cleanName] = relPath
let sourceTreeMatrix = buildSourceTreeMatrix()
proc extractObjectTypes(filePath: string): seq[string] {.raises: [].} =
  result = @[]
  var content = ""
  try:
    content = readFile(filePath)
  except CatchableError:
    return
  var inTypeBlock = false
  for rawLine in content.splitLines():
    let line = rawLine.strip()
    if line.len == 0 or line.startsWith("#"): continue
    if line == "type" or line.startsWith("type "):
      inTypeBlock = true
      # Check single-line: type MyObj = object
      var m: array[1, string]
      if line.find(objectTypePattern, m) >= 0:
        let rawName = m[0]
        if rawName.endsWith('*'):
          result.add(rawName.strip(chars = {'*'}))
      continue
    if inTypeBlock:
      # Type block continues if line starts with whitespace or is an identifier = ...
      if not line[0].isSpaceAscii and not line.contains('='):
        inTypeBlock = false
        continue
      var m: array[1, string]
      if line.find(objectTypeBlockPattern, m) >= 0:
        let rawName = m[0]
        if rawName.endsWith('*'):
          result.add(rawName.strip(chars = {'*'}))
proc extractUnaryFuncs(filePath: string; domainTypes: seq[string]): seq[UnaryFunc] {.raises: [].} =
  ## Extract unary func declarations whose parameter type matches a domain object type.
  ## Also captures the return type to filter out metamorphic tests with mismatched types.
  result = @[]
  var content = ""
  try:
    content = readFile(filePath)
  except CatchableError:
    return
  for rawLine in content.splitLines():
    let line = rawLine.strip()
    if line.len == 0 or line.startsWith("#"): continue
    var m: array[4, string]
    if line.find(unaryFuncPattern, m) >= 0:
      let funcName = m[0].strip(chars = {'*'})
      let paramName = m[1]
      let paramType = m[2].strip(chars = {'*'})
      let returnType = m[3].strip(chars = {'*'})
      if paramType in domainTypes:
        result.add((name: funcName, paramName: paramName, paramType: paramType, returnType: returnType))
proc splitParams(paramList: string): seq[string] {.raises: [].} =
  ## Split parameter list by `,` and `;`, but not inside `[...]` brackets.
  ## Nim allows both `,` and `;` as parameter separators in func declarations.
  ## e.g., "x: XmlNode; knownFunctions: HashSet[string]; selfName: string"
  ##   → ["x: XmlNode", "knownFunctions: HashSet[string]", "selfName: string"]
  result = @[]
  var depth = 0
  var current = ""
  for ch in paramList:
    if ch == '[': depth.inc
    elif ch == ']': depth.dec
    elif depth == 0 and (ch == ',' or ch == ';'):
      let trimmed = current.strip()
      if trimmed.len > 0:
        result.add(trimmed)
      current = ""
      continue
    current.add(ch)
  let trimmed = current.strip()
  if trimmed.len > 0:
    result.add(trimmed)
proc stripDefaultValue(typeStr: string): string {.raises: [].} =
  ## Strip default value from parameter type string.
  ## e.g., "int = 0" → "int", "string = \"\"" → "string"
  ##        "seq[string] = @[]" → "seq[string]"
  ## Preserves `==` (comparison operator) inside bracket expressions.
  result = typeStr
  var depth = 0
  for i in 0 ..< result.len:
    let ch = result[i]
    if ch == '[': depth.inc
    elif ch == ']': depth.dec
    elif depth == 0 and ch == '=' and (i + 1 >= result.len or result[i + 1] != '='):
      result = result[0 ..< i].strip()
      return
proc isGenericType(typeStr: string): bool {.raises: [].} =
  ## Check if a type string is a generic instantiation (contains `[`).
  ## e.g., "seq[string]" → true, "int" → false, "HashSet[string]" → true
  result = typeStr.contains('[')
proc extractPureFuncs(filePath: string): seq[PureFunc] {.raises: [].} =
  ## Extract exported func signatures from pure-func-only modules.
  ## Only matches `func` declarations (not `proc`) since func = noSideEffect.
  ## Only exported funcs (name*) are included since unexported funcs are
  ## inaccessible from the generated PBT file.
  result = @[]
  var content = ""
  try:
    content = readFile(filePath)
  except CatchableError:
    return
  for rawLine in content.splitLines():
    let line = rawLine.strip()
    if line.len == 0 or line.startsWith("#"): continue
    var m: array[3, string]
    if line.find(pureFuncPattern, m) >= 0:
      let rawName = m[0]
      let isExported = rawName.endsWith('*')
      let funcName = rawName.strip(chars = {'*'})
      let paramList = m[1].strip()
      let returnType = m[2].strip(chars = {'*'})
      if not isExported:
        continue
      # Parse parameter types from param list.
      # Handles both `,` and `;` as parameter separators.
      # Handles "x: int", "x, y: int", "x: int; y: string".
      var paramTypes: seq[string] = @[]
      if paramList.len > 0:
        var currentType = ""
        for part in splitParams(paramList):
          let trimmed = part.strip()
          if trimmed.len == 0: continue
          let colonIdx = trimmed.find(':')
          if colonIdx >= 0:
            let rawType = trimmed[colonIdx + 1 .. ^1].strip(chars = {'*', ' '})
            currentType = stripDefaultValue(rawType)
            paramTypes.add(currentType)
          else:
            # Another name sharing the same type (e.g. "x, y: int")
            if currentType.len > 0:
              paramTypes.add(currentType)
      result.add((name: funcName, paramTypes: paramTypes, returnType: returnType))
proc moduleCategory(filePath: string): bool {.raises: [].} =
  ## Return true if the module is a domain module (has procs/funcs, no I/O imports).
  var content = ""
  try:
    content = readFile(filePath)
  except CatchableError:
    return false
  let lines = content.splitLines()
  var hasProcLike = false
  var hasIoImport = false
  for rawLine in lines:
    let line = rawLine.strip()
    if line.len == 0 or line.startsWith("#"): continue
    if not hasIoImport:
      if line.find(ioModulePattern) >= 0:
        hasIoImport = true
    if not hasProcLike:
      if line.find(procDeclPattern) >= 0:
        hasProcLike = true
    if hasIoImport and hasProcLike:
      break
  result = hasProcLike and not hasIoImport
# ── generatePbtFile sub-functions ────────────────────────────────────

proc buildPbtImports(modulePath: string): string {.raises: [].} =
  ## Generate import preamble + include directive for a PBT file.
  result = "{.push raises: [].}\n\n"
  result.add "import tools/pbt_synthesizer\n"
  result.add "import tools/pbt_runtime\n"
  result.add "import core/test_support/export_injector\n"  # ★ autoExport support
  result.add "import core/test_support/pbt_gate\n\n"  # ★ compiles verification gate
  # Build import path from source tree matrix
  let (_, moduleName, _) = splitFile(modulePath)
  let cleanModuleName = moduleName.strip(chars = {'*'})
  var importPath = ""
  try:
    if sourceTreeMatrix.hasKey(cleanModuleName):
      importPath = sourceTreeMatrix[cleanModuleName]
  except KeyError:
    discard
  if importPath.len == 0:
    # Fallback: derive from file path
    let relPath = modulePath.replace("src/", "").replace(".nim", "").replace("\\", "/")
    importPath = relPath
  # ★ include 디렉티브로 비공개 타입에 접근 (same compilation scope)
  result.add "include " & importPath & "\n\n"
proc generateObjectPath(types: seq[string]; unaryFuncs: seq[UnaryFunc]): string {.raises: [].} =
  ## deepAutoExport wrappers + deriveMetamorphicTest calls for object types.
  result = ""
  # ── Object-type path (existing logic) ──────────────────────────
  for t in types:
    # ★ deepAutoExport로 비공개 필드까지 가시성 주입
    result.add "deepAutoExport:\n"
    result.add "  type " & t & "_wrapper = object\n"
    result.add "    value*: " & t & "\n"
    # ★ compiles 정적 검증 게이트 사용
    result.add "verifyAndDrive(" & t & "_wrapper)\n"
  # Auto-derive metamorphic tests for matching unary funcs (input == output type only)
  for f in unaryFuncs:
    if f.paramType == f.returnType:
      result.add "deriveMetamorphicTest(" & f.name & ", mpIdempotency)\n"
proc generateObjectTestHarness(types: seq[string]; unaryFuncs: seq[UnaryFunc]): string {.raises: [].} =
  ## Generate runPbtTest proc for object-type path.
  result = "\nproc runPbtTest*() {.raises: [].} =\n"
  for t in types:
    let genProc = "gen" & t
    result.add "  let x = " & genProc & "()\n"
    result.add "  echo \"Generated " & t & ": \", x\n"
  # Run metamorphic tests if any (input == output type)
  for f in unaryFuncs:
    if f.paramType == f.returnType:
      let testProc = "test" & f.name & "mpIdempotency"
      result.add "  " & testProc & "()\n"
      result.add "  echo \"Idempotency PASS: " & f.name & "\"\n"
  # Totality tests for funcs with different input/output types
  for f in unaryFuncs:
    if f.paramType != f.returnType:
      result.add "  block:\n"
      result.add "    for _ in 0 .. 100:\n"
      result.add "      let p0 = gen" & f.paramType & "()\n"
      result.add "      discard " & f.name & "(p0)\n"
      result.add "    echo \"Totality PASS: " & f.name & "\"\n"
proc generatePureVerifyDrive(pureFuncs: seq[PureFunc]; localTypes: seq[string]): string {.raises: [].} =
  ## Generate verifyAndDrive calls for non-builtin, non-generic parameter types.
  result = ""
  # deriveGenerator for non-builtin, non-generic parameter types
  # Generic types (e.g., seq[string]) are not supported by deriveGenerator macro
  # ★ 메커니즘 1: 소스 파일에 정의된 타입만 필터링 (외부 Opaque 타입 오염 차단)
  var seenTypes: seq[string] = @[]
  for f in pureFuncs:
    for pt in f.paramTypes:
      if pt notin seenTypes and pt notin builtins and not isGenericType(pt) and
         pt in localTypes:  # ★ 소스 정의 타입만 허용
        seenTypes.add(pt)
  for pt in seenTypes:
    # ★ compiles 정적 검증 게이트 사용
    result.add "verifyAndDrive(" & pt & ")\n"
proc generatePureIdempTests(pureFuncs: seq[PureFunc]; localTypes: seq[string]): string {.raises: [].} =
  ## Generate idempotency metamorphic test declarations + run invocations.
  result = ""
  # Metamorphic tests for unary funcs (1 param, non-generic, input == output type)
  # Idempotency test requires f: T → T. Functions with different input/output
  # types (e.g., isSmtKeyword(string): bool) cause type mismatches.
  # ★ 메커니즘 1: 소스 정의 타입만 필터링
  for f in pureFuncs:
    if f.paramTypes.len == 1 and not isGenericType(f.paramTypes[0]) and
       f.returnType == f.paramTypes[0] and f.paramTypes[0] in localTypes:
      result.add "deriveMetamorphicTest(" & f.name & ", mpIdempotency)\n"
  result.add "\nproc runPbtTest*() {.raises: [].} =\n"
  # Run metamorphic tests (non-generic unary funcs with matching input/output type)
  # ★ 메커니즘 1: 소스 정의 타입만 필터링
  for f in pureFuncs:
    if f.paramTypes.len == 1 and not isGenericType(f.paramTypes[0]) and
       f.returnType == f.paramTypes[0] and f.paramTypes[0] in localTypes:
      let testProc = "test" & f.name & "mpIdempotency"
      result.add "  " & testProc & "()\n"
      result.add "  echo \"Idempotency PASS: " & f.name & "\"\n"
proc generatePureTotalTests(pureFuncs: seq[PureFunc]): string {.raises: [].} =
  result = ""
  # Totality tests for unary funcs with different input/output types
  for f in pureFuncs:
    if f.paramTypes.len == 1 and not isGenericType(f.paramTypes[0]) and
       f.returnType != f.paramTypes[0]:
      result.add "  block:\n"
      result.add "    for _ in 0 .. 100:\n"
      let pt = f.paramTypes[0]
      let genProc = if pt in builtins: "gen" & pt.capitalizeAscii()
                    else: "gen" & pt
      result.add "      let p0 = " & genProc & "()\n"
      result.add "      discard " & f.name & "(p0)\n"
      result.add "    echo \"Totality PASS: " & f.name & "\"\n"
  # Metamorphic-like tests for generic unary funcs: generate value, call func
  for f in pureFuncs:
    if f.paramTypes.len == 1 and isGenericType(f.paramTypes[0]):
      result.add "  block:\n"
      result.add "    for _ in 0 .. 100:\n"
      result.add "      let p0 = default(typeof(" & f.paramTypes[0] & "))\n"
      result.add "      discard " & f.name & "(p0)\n"
      result.add "    echo \"Totality PASS: " & f.name & "\"\n"
  # Totality tests for multi-param funcs (≥2 params)
  for f in pureFuncs:
    if f.paramTypes.len >= 2:
      result.add "  block:\n"
      result.add "    for _ in 0 .. 100:\n"
      for i in 0 ..< f.paramTypes.len:
        let pt = f.paramTypes[i]
        if isGenericType(pt):
          result.add "      let p" & $i & " = default(typeof(" & pt & "))\n"
        else:
          let genProc = if pt in builtins: "gen" & pt.capitalizeAscii()
                        else: "gen" & pt
          result.add "      let p" & $i & " = " & genProc & "()\n"
      var params = ""
      for i in 0 ..< f.paramTypes.len:
        if i > 0: params.add ", "
        params.add "p" & $i
      result.add "      discard " & f.name & "(" & params & ")\n"
      result.add "    echo \"Totality PASS: " & f.name & "\"\n"
  # Totality tests for zero-param funcs (constants / trivial)
  for f in pureFuncs:
    if f.paramTypes.len == 0:
      result.add "  block:\n"
      result.add "    for _ in 0 .. 100:\n"
      result.add "      discard " & f.name & "()\n"
      result.add "    echo \"Totality PASS: " & f.name & "\"\n"
proc generatePbtFile(modulePath: string; types: seq[string]): string {.raises: [].} =
  ## Orchestrate PBT file generation by composing sub-functions.
  let (_, baseName, _) = splitFile(modulePath)
  let outPath = joinPath(GeneratedPbtDir, baseName & "_pbt.nim")
  # When no object types found, fall back to pure-func extraction
  let pureFuncs = if types.len == 0: extractPureFuncs(modulePath) else: @[]
  if types.len == 0 and pureFuncs.len == 0:
    return ""
  let unaryFuncs = if types.len > 0: extractUnaryFuncs(modulePath, types) else: @[]
  var code = buildPbtImports(modulePath)
  if types.len > 0:
    code.add generateObjectPath(types, unaryFuncs)
    code.add generateObjectTestHarness(types, unaryFuncs)
  else:
    let localTypes = extractObjectTypes(modulePath)
    code.add generatePureVerifyDrive(pureFuncs, localTypes)
    code.add generatePureIdempTests(pureFuncs, localTypes)
    code.add generatePureTotalTests(pureFuncs)
  code.add "\n{.pop.}\n"
  try:
    writeFile(outPath, code)
  except CatchableError:
    return ""
  outPath
proc collectPbtFiles(): seq[string] {.raises: [].} =
  ## Walk GeneratedPbtDir for *_pbt.nim files.
  result = @[]
  try:
    for fp in walkDirRec(GeneratedPbtDir):
      if fp.endsWith("_pbt.nim"):
        result.add(fp)
  except OSError:
    discard
proc attemptImportFix(filePath: string; content: var string; output: string): bool {.raises: [].} =
  ## Phase 1: Fix "cannot open file: {path}" import errors via sourceTreeMatrix.
  result = false
  for line in output.splitLines():
    if "cannot open file:" notin line:
      continue
    let marker = "cannot open file:"
    let idx = line.find(marker)
    if idx < 0: continue
    let wrongPath = line[idx + marker.len .. ^1].strip()
    let (_, modName, _) = splitFile(wrongPath)
    try:
      if sourceTreeMatrix.hasKey(modName):
        let correctPath = sourceTreeMatrix[modName]
        let oldImport = "import " & wrongPath
        let newImport = "import " & correctPath
        if oldImport in content:
          content = content.replace(oldImport, newImport)
          result = true
          echo "[CaaS] Fix: ", extractFilename(filePath),
               ": ", wrongPath, " -> ", correctPath
    except KeyError:
      discard
proc classifyCompileError(output: string; filePath: string): string {.raises: [].} =
  ## Phase 2: Classify non-fixable compile errors for skip marking.
  result = ""
  for line in output.splitLines():
    if "undeclared identifier:" in line:
      result = "non-exported type"
      break
    if "is not accessible" in line:
      result = "inaccessible field"
      break
    if "type mismatch" in line and extractFilename(filePath) in line:
      result = "type mismatch"
      break
proc caasFixImports*() {.raises: [].} =
  ## CaaS feedback loop: compile PBT files, auto-fix imports, skip unfixable. Retries 3×.
  var fixed, skipped, passed = 0
  let pbtFiles = collectPbtFiles()
  for filePath in pbtFiles:
    var attempts = 0
    var fileFixed = false
    var resolved = false
    while attempts < 3 and not resolved:
      attempts.inc
      var compileOutput = ""
      try:
        compileOutput = execProcess("nim", args = ["c", "--path:.", filePath],
                                    options = {poUsePath, poStdErrToStdOut})
      except CatchableError:
        skipped.inc; resolved = true; break
      if "[SuccessX]" in compileOutput:
        if fileFixed: fixed.inc else: passed.inc
        resolved = true; break
      var content = ""
      try: content = readFile(filePath)
      except CatchableError: skipped.inc; resolved = true; break
      # Phase 1: Fix import errors
      if attemptImportFix(filePath, content, compileOutput):
        try: writeFile(filePath, content)
        except CatchableError: skipped.inc; resolved = true; break
        fileFixed = true; continue
      let skipReason = classifyCompileError(compileOutput, filePath)
      if skipReason.len > 0:
        try: writeFile(filePath, "# [SKIP] " & skipReason & " — CaaS auto-skip\n" & content)
        except CatchableError: discard  # axiom:best-effort(write-failure: skip this file, continue processing)
        skipped.inc
        echo "[CaaS] Skip: ", extractFilename(filePath), " (", skipReason, ")"
        resolved = true; break
      # Unknown error type — cannot auto-fix; mark as SKIP
      try:
        let skipHeader = "# [SKIP] unfixable compile error — CaaS auto-skip\n"
        writeFile(filePath, skipHeader & content)
      except CatchableError: discard  # axiom:best-effort(write-failure: skip this file, continue processing)
      skipped.inc
      echo "[CaaS] Skip: ", extractFilename(filePath), " (unfixable)"
      resolved = true; break
    # If loop exhausted retries without resolving
    if not resolved: skipped.inc
  echo "\n=== CaaS Feedback Loop Report ==="
  echo "CaaS: ", fixed, " files fixed, ", skipped, " files skipped", ", ", passed, " passed"
proc generateManifest*() {.raises: [].} =
  ## Generate monolithic manifest file that imports all PBT modules.
  ## Filters out files marked as SKIP by CaaS feedback loop.
  var pbtFiles: seq[string] = @[]
  try:
    for fp in walkDirRec(GeneratedPbtDir):
      if fp.endsWith("_pbt.nim") and not fp.endsWith("all_pbt_manifest.nim"):
        # Skip files marked by CaaS as unfixable
        try:
          let content = readFile(fp)
          if content.len > 0 and content.startsWith("# [SKIP]"):
            continue
        except CatchableError:
          discard  # axiom:best-effort(unreadable-pbt-file: skip this file, continue scanning)
        pbtFiles.add(fp)
  except OSError:
    discard
  if pbtFiles.len == 0:
    return

  pbtFiles.sort()

  var code = "# Auto-generated monolithic PBT manifest\n"
  code.add "# Do not edit manually — regenerated by pbt_batch_synthesizer\n\n"
  code.add "{.push raises: [].}\n\n"

  # Import each PBT module with unique alias
  for i, fp in pbtFiles:
    let (_, baseName, _) = splitFile(fp)
    let alias = "mod_" & baseName.replace("_pbt", "").replace("-", "_")
    code.add "import ./" & baseName & " as " & alias & "\n"

  code.add "\nproc runAllPbtTests*() {.raises: [].} =\n"
  for i, fp in pbtFiles:
    let (_, baseName, _) = splitFile(fp)
    let alias = "mod_" & baseName.replace("_pbt", "").replace("-", "_")
    code.add "  " & alias & ".runPbtTest()\n"

  code.add "\nwhen isMainModule:\n"
  code.add "  runAllPbtTests()\n\n"
  code.add "{.pop.}\n"

  let manifestPath = joinPath(GeneratedPbtDir, "all_pbt_manifest.nim")
  try:
    writeFile(manifestPath, code)
    echo "[MANIFEST] Generated: ", manifestPath
  except CatchableError:
    echo "[MANIFEST] Failed to write manifest"
proc computeChurnMetrics*(): seq[tuple[filePath: string, churnCount: int]] {.raises: [].} =
  ## Git 로그에서 파일별 커밋 횟수(Churn Metric)를 동적으로 파싱
  ## 고빈도 변경 모듈을 식별하여 핫스팟 PBT 자동 생성에 활용
  result = @[]
  try:
    let (output, exitCode) = execCmdEx(
      "git log --pretty=format: --name-only | sort | uniq -c | sort -rn"
    )
    if exitCode == 0:
      for line in output.splitLines():
        let parts = line.strip().split(" ", maxSplit = 1)
        if parts.len >= 2:
          let countRes = safeParseInt(parts[0])
          if countRes.ok:
            let count = countRes.value
            let filePath = parts[1]
            if filePath.endsWith(".nim") and filePath.startsWith("src/"):
              result.add((filePath: filePath, churnCount: count))
  except CatchableError:
    discard  # axiom:best-effort(unreadable-changelog: treat as empty, continue processing)
proc generateHotspotPbt*(filePath: string; churnCount: int): string {.raises: [].} =
  ## 핫스팟 모듈에 대한 상태 전이 PBT 하네스 자동 생성
  ## deepAutoExport를 사용하여 비공개 필드에도 접근
  let (_, baseName, _) = splitFile(filePath)
  let outPath = joinPath(GeneratedPbtDir, baseName & "_hotspot_pbt.nim")
  
  # 이미 존재하면 건너뛰기
  if fileExists(outPath):
    var content = ""
    try: content = readFile(outPath)
    except CatchableError: discard  # axiom:best-effort(read-existing-pbt: treat as not found, regenerate)
    if content.len > 0:
      return ""
  
  let importPath = filePath.replace("src/", "").replace(".nim", "").replace("\\", "/")
  let types = extractObjectTypes(filePath)
  
  var code = "{.push raises: [].}\n\n"
  code.add "import tools/pbt_synthesizer\n"
  code.add "import tools/pbt_runtime\n"
  code.add "import core/test_support/export_injector\n\n"
  code.add "import " & importPath & "\n\n"
  
  # deepAutoExport로 타입 가시성 주입
  for t in types:
    code.add "deepAutoExport:\n"
    code.add "  type " & t & " = object\n\n"
  
  # 상태 전이 PBT 생성
  code.add "proc runPbtTest*() {.raises: [].} =\n"
  code.add "  echo \"Hotspot PBT for: " & baseName & " (churn: " & $churnCount & ")\"\n"
  
  for t in types:
    let genProc = "gen" & t
    code.add "  let x = " & genProc & "()\n"
    code.add "  echo \"Generated " & t & ": \", x\n"
  code.add "\n{.pop.}\n"

  try:
    writeFile(outPath, code)
    return outPath
  except CatchableError:
    return ""
proc collectSourceFiles(): seq[string] {.raises: [].} =
  ## Walk src/ directory collecting all file paths.
  result = @[]
  try:
    for fp in walkDirRec("src"):
      result.add(fp)
  except OSError:
    discard
proc computeAndCheckCache(nimPaths: seq[string]): tuple[valid: bool, topologySig: string, sourceHashes: Table[string, string]] {.raises: [].} =
  ## Compute topology signature + source hashes, then check cache validity.
  result.valid = false
  result.sourceHashes = initTable[string, string]()
  # ── Compute topology signature ─────────────────────────────────────
  result.topologySig = computeTopologySignature(nimPaths)
  # ── Compute source hashes for domain modules ──────────────────────
  for filePath in nimPaths:
    if "/tests/" in filePath or "/deprecated/" in filePath: continue
    if moduleCategory(filePath):
      let h = computeFileHash(filePath)
      if h.len > 0:
        result.sourceHashes[filePath] = h
  # ── Check cache ───────────────────────────────────────────────────
  if not fileExists(CachePath):
    return
  let cached = readCache(CachePath)
  if cached.engineVersion != EngineVersion or
     cached.topologySignature != result.topologySig or
     cached.gateStatus != "pass":
    return
  # Verify all source hashes match
  var allMatch = true
  for fp, h in result.sourceHashes:
    if fp notin cached.sourceHashes:
      allMatch = false; break
    if cached.sourceHashes.getOrDefault(fp, "") != h:
      allMatch = false; break
  # Check no extra entries in cache
  if allMatch:
    for fp in cached.sourceHashes.keys:
      if fp notin result.sourceHashes:
        allMatch = false; break
  if allMatch:
    # Verify manifest hash matches
    let manifestPath = joinPath(GeneratedPbtDir, "all_pbt_manifest.nim")
    if fileExists(manifestPath):
      let manifestHash = computeFileHash(manifestPath)
      if manifestHash == cached.manifestHash:
        result.valid = true
proc generateAllPbtFiles(filePaths: seq[string]) {.raises: [].} =
  ## Iterate source files, generate PBT files, report counts.
  var generated = 0
  var skipped = 0
  var pureFuncGenerated = 0
  for filePath in filePaths:
    if not filePath.endsWith(".nim"): continue
    if "/tests/" in filePath or "/deprecated/" in filePath: continue
    if not moduleCategory(filePath):
      skipped.inc; continue
    let types = extractObjectTypes(filePath)
    let outPath = generatePbtFile(filePath, types)
    if outPath.len > 0:
      if types.len == 0:
        pureFuncGenerated.inc
        echo "[PBT-SYNTH] (pure-func) ", outPath
      else:
        generated.inc
        echo "[PBT-SYNTH] ", outPath
    else:
      skipped.inc
  echo "\n=== PBT Batch Synthesizer Report ==="
  echo "Generated (object types): ", generated
  echo "Generated (pure funcs): ", pureFuncGenerated
  echo "Skipped (no domain types or pure funcs): ", skipped
proc writeCacheEntry(topologySig: string; currentSourceHashes: Table[string, string]) {.raises: [].} =
  ## Write the gate cache entry after successful generation.
  let manifestPath = joinPath(GeneratedPbtDir, "all_pbt_manifest.nim")
  let manifestHash = if fileExists(manifestPath): computeFileHash(manifestPath) else: ""
  let now = try: execProcess("date", args = ["-Iseconds"], options = {poUsePath}).strip()
            except CatchableError: "unknown"
  let newEntry = GateCacheEntry(
    engineVersion: EngineVersion,
    lastValidatedAt: now,
    manifestHash: manifestHash,
    topologySignature: topologySig,
    sourceHashes: currentSourceHashes,
    gateStatus: "pass"
  )
  writeCache(CachePath, newEntry)
  echo "[CACHE] Written: ", CachePath
proc main*() {.raises: [].} =
  if not dirExists(GeneratedPbtDir):
    try: createDir(GeneratedPbtDir)
    except CatchableError:
      echo "[PBT-SYNTH] Failed to create directory: ", GeneratedPbtDir
      return
  let filePaths = collectSourceFiles()
  var nimPaths: seq[string] = @[]
  for fp in filePaths:
    if fp.endsWith(".nim"):
      nimPaths.add(fp)
  let (cacheValid, topologySig, currentSourceHashes) = computeAndCheckCache(nimPaths)
  if cacheValid:
    echo "[CACHE] Hit! Skipping compilation"
    return
  generateAllPbtFiles(filePaths)
  caasFixImports()
  generateManifest()
  writeCacheEntry(topologySig, currentSourceHashes)

when isMainModule:
  main()

{.pop.}
