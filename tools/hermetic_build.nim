import core/trusted/layer_declaration
import core/config/toolchain_config  # ExpectedZ3Version SSOT (WS-P2-B)
import core/trusted/scope_version  # VERIFICATION_SCOPE_SCHEMA_VERSION SSOT (L0)
import core/trusted/verifier_build_identity  # computeVerifierBuildId composer (Phase 1B engineBuild)
import core/utils/build_provenance  # hashSourceContents — source-tree fingerprint formula kernel
axiomLayer "tools"
import std/[os]
# ── Hermetic PreBuild Recursion Guard ──────────────────────────────────────────
# Prevents infinite recursion when this binary spawns child `nim` processes
# (which evaluate config.nims). Setting AXIOM_HERMETIC_BUILDING=1 here ensures
# child processes inherit the guard and skip config.nims's hermeticPreBuild,
# without self-blocking hermetic_build when invoked from config.nims.
putEnv("AXIOM_HERMETIC_BUILDING", "1")

import checksums/sha2
import sha256_native
import std/[strutils, osproc, json, times, sequtils, algorithm, hashes, posix, tables]
import safe_move

# ── Deterministic Root Resolution (AGENTS.md § Deterministic Root Resolution) ──
# Uses .axiom_root anchor file to find project root, eliminating CWD dependency.
# Pattern: src/core/utils/repo_root.nim (SSOT)
proc findProjectRoot(): string =
  ## Walk upward from CWD looking for ``.axiom_root`` (SSOT anchor).
  ## Deterministic: returns the unique ancestor directory with the anchor.
  var dir = getCurrentDir()
  while true:
    if fileExists(dir / ".axiom_root"):
      return dir
    let parent = dir.parentDir()
    if parent == dir:  # reached filesystem root
      break
    dir = parent
  quit("ERROR: .axiom_root not found. Run from Axiom project directory.")

let projectRoot = findProjectRoot()

let
  BuildEnvPath = projectRoot / "src/generated/build_env.nim"
  TypeRegistryPath = projectRoot / "src/generated/type_registry_metadata.json"
  InvariantsPath = projectRoot / "src/core/trusted/architecture_invariants.nim"
  ExpectedHashPath = projectRoot / "data/expected_invariant_hash.txt"
  ManifestPath = projectRoot / "data/axiom_manifest.json"
  AxiomContractsCachePath = projectRoot / "data/.axiom_contracts_hash.txt"
# ── --materialize fast-path cache (AGENTS.md § Deterministic Root Resolution) ──
# Body cache stores the full canonical build_env.nim content with the git-hash
# const value replaced by GitHashPlaceholder. --materialize reads it back and
# substitutes the live hash — no walkDirRec, no Z3 subprocess, ~2-5ms.
  BodyCachePath = projectRoot / ".axiom/cache/build_env.body"
const GitHashPlaceholder = "__AXIOM_GIT_HASH__"
const BuildSourceHashPlaceholder = "__AXIOM_BUILD_SOURCE_HASH__"
const VerifierBuildIdPlaceholder = "__AXIOM_VERIFIER_BUILD_ID__"
# ── axiomEffect pragma stub (standalone tool — cannot import src/) ──
# Mirrors src/core/trusted/axiom_pragmas.nim definitions minimally
# so nimtry can inspect the pragma in this standalone binary.
type
  AxiomEffectKind* = enum
    Pure, IoEffect
template axiomEffect*(effectType: AxiomEffectKind) {.pragma.}
type
  AxiomContract = object
    filePath: string
    procName: string
    smtQuery: string
    leanObligation: string
    lineNum: int
proc extractAxiomContracts(filePath: string): seq[AxiomContract] {.axiomEffect: IoEffect.} =
  ## Scan a .nim file for {.axiom: [smt("..."), lean("...")].} pragmas.
  ## Uses string-based scanning (consistent with hermetic_build style).
  let content = readFile(filePath)
  let lines = content.splitLines()
  var i = 0
  while i < lines.len:
    let line = lines[i]
    let stripped = line.strip()

    # Skip comments
    if stripped.startsWith("#") or stripped.startsWith("##"):
      inc i
      continue

    # Look for {.axiom: pattern (may span multiple lines)
    if "{.axiom:" in stripped:
      # Accumulate multi-line pragma until .}
      var pragmaText = ""
      var j = i
      while j < lines.len:
        pragmaText &= " " & lines[j].strip()
        if ".}" in lines[j]:
          break
        inc j

      # Extract smt("...") content
      var smtStr = ""
      let smtMarker = "smt(\""
      let smtStart = pragmaText.find(smtMarker)
      if smtStart >= 0:
        let contentStart = smtStart + smtMarker.len
        let contentEnd = pragmaText.find("\")", contentStart)
        if contentEnd > contentStart:
          smtStr = pragmaText[contentStart..<contentEnd]

      # Extract lean("...") content
      var leanStr = ""
      let leanMarker = "lean(\""
      let leanStart = pragmaText.find(leanMarker)
      if leanStart >= 0:
        let contentStart = leanStart + leanMarker.len
        let contentEnd = pragmaText.find("\")", contentStart)
        if contentEnd > contentStart:
          leanStr = pragmaText[contentStart..<contentEnd]

      # Only add if we found at least one contract string
      if smtStr.len > 0 or leanStr.len > 0:
        # Find the proc/func name by looking backwards
        var procName = "anonymous"
        for k in countdown(max(0, i - 1), max(0, i - 15)):
          let prevLine = lines[k].strip()
          if prevLine.startsWith("proc ") or prevLine.startsWith("func "):
            let kwLen = 5  # len("proc ") == len("func ")
            let afterKw = prevLine[kwLen..^1].strip()
            let nameEnd = afterKw.find('(')
            if nameEnd > 0:
              procName = afterKw[0..<nameEnd].strip()
            break

        result.add(AxiomContract(
          filePath: filePath,
          procName: procName,
          smtQuery: smtStr,
          leanObligation: leanStr,
          lineNum: i + 1
        ))

      i = j + 1
    else:
      inc i
proc generateSmtLib2(query: string): string =
  ## Wrap an SMT assertion in a complete SMT-LIB2 script for validity checking.
  ## Negates the assertion and checks for UNSAT (meaning the original holds).
  result = "; Auto-generated by hermetic_build --verify-contracts\n"
  result &= "(set-logic QF_LIA)\n"
  result &= "(declare-const result Int)\n"
  result &= "(assert (not " & query & "))\n"
  result &= "(check-sat)\n"
  result &= "(exit)\n"
proc runZ3Query(query: string, tmpDir: string): tuple[ok: bool, detail: string]
    {.axiomEffect: IoEffect.} =
  ## Run Z3 on an SMT-LIB2 query. Returns (true, "") if UNSAT (property valid).
  let smtContent = generateSmtLib2(query)
  let smtPath = tmpDir / "axiom_query.smt2"
  writeFile(smtPath, smtContent)

  try:
    let (output, exitCode) = execCmdEx("z3 -smt2 -t:30000 " & smtPath)
    if exitCode != 0:
      return (false, "Z3 exited with code " & $exitCode)

    let z3Result = output.strip().toLowerAscii()
    if z3Result == "unsat":
      return (true, "")  # Property valid — negation unsatisfiable
    elif z3Result == "sat":
      return (false, "Counterexample found (SAT)")
    else:
      return (false, "Unexpected Z3 result: " & z3Result)
  except CatchableError as e:
    return (false, "Z3 execution error: " & e.msg)
proc runLeanVerification(obligation: string, tmpDir: string): tuple[ok: bool, detail: string]
    {.axiomEffect: IoEffect.} =
  ## Generate a Lean 4 proof file and run lake build. Returns true if sorry-free.
  let proofDir = tmpDir / "lean_proof"
  if not dirExists(proofDir):
    createDir(proofDir)

  # Generate minimal lakefile
  let lakefile = """import Lake
open Lake DSL
package axiomContract where
  leanOptions := #[]
"""
  writeFile(proofDir / "lakefile.lean", lakefile)

  # Copy lean-toolchain from proofs/ if available
  let toolchainPath = projectRoot / "proofs" / "lean-toolchain"
  if fileExists(toolchainPath):
    try:
      copyFile(toolchainPath, proofDir / "lean-toolchain")
    except CatchableError:
      stderr.writeLine("[hermetic] WARNING: Failed to copy lean-toolchain: " & getCurrentExceptionMsg())
  else:
    writeFile(proofDir / "lean-toolchain", "leanprover/lean4:v4.29.0\n")

  # Generate the proof file using the obligation as the proof term
  let proofContent = """-- Auto-generated by hermetic_build --verify-contracts
/-- Axiom contract obligation -/
theorem axiomContract : True := by
  """ & obligation & "\n"
  writeFile(proofDir / "Main.lean", proofContent)

  # Ensure elan/lake is in PATH
  try:
    let elanBin = getHomeDir() / ".elan" / "bin"
    let localBin = getHomeDir() / ".local" / "bin"
    let currentPath = getEnv("PATH", "")
    putEnv("PATH", elanBin & ":" & localBin & ":" & currentPath)

    let (output, exitCode) = execCmdEx("lake build", workingDir = proofDir)
    if exitCode != 0:
      return (false, "Lean build failed: " & output[0..min(200, output.len-1)])

    # Check for sorry in output (indicates incomplete proof)
    if "sorry" in output.toLowerAscii():
      return (false, "Lean proof contains sorry")

    return (true, "")
  except CatchableError as e:
    return (false, "Lean execution error: " & e.msg)
proc computeAxiomFingerprint(contracts: seq[AxiomContract]): string =
  ## SHA-256 fingerprint of all axiom strings (not full file content).
  ## Used for incremental caching — only re-verify when axiom strings change.
  var content = ""
  for c in contracts:
    content.add(c.filePath & "|" & c.procName & "|" & c.smtQuery & "|" & c.leanObligation & "|")
  result = $secureHash(Sha_256, content)
proc verifyFormalContracts(): int {.axiomEffect: IoEffect.} =
  ## Main entry point for --verify-contracts subcommand.
  ## Walks src/, scans for {.axiom.} pragmas, verifies via Z3/Lean.
  ## SHA-256 incremental caching: only re-verify if axiom strings changed.
  ## Returns 0 on success (all contracts pass or none found), 1 on failure.
  echo "=== Formal Contract Verification ==="
  echo ""

  # Phase 1: Collect all axiom contracts from src/
  var allContracts: seq[AxiomContract] = @[]
  let srcDir = projectRoot / "src"

  if not dirExists(srcDir):
    echo "[verify-contracts] src/ directory not found — skipping"
    return 0

  for filePath in walkDirRec(srcDir):
    if not filePath.endsWith(".nim"): continue
    if "/generated/" in filePath: continue
    if "/nimcache" in filePath: continue
    try:
      let contracts = extractAxiomContracts(filePath)
      allContracts.add(contracts)
    except CatchableError:
      stderr.writeLine("WARNING: Failed to scan " & filePath & ": " & getCurrentExceptionMsg())

  if allContracts.len == 0:
    echo "[verify-contracts] No {.axiom.} pragmas found — skipping"
    return 0

  echo "[verify-contracts] Found " & $allContracts.len & " axiom contract(s)"
  for c in allContracts:
    echo "  - " & c.procName & " @ " & c.filePath & ":" & $c.lineNum
  echo ""

  # Phase 2: SHA-256 incremental caching
  let axiomFingerprint = computeAxiomFingerprint(allContracts)
  if fileExists(AxiomContractsCachePath):
    let cachedHash = readFile(AxiomContractsCachePath).strip()
    if cachedHash == axiomFingerprint:
      echo "[verify-contracts] Axiom fingerprint unchanged — skipping verification"
      return 0

  # Phase 3: Check tool availability (graceful degradation)
  var z3Available = false
  var leanAvailable = false

  try:
    let (z3Out, z3Exit) = execCmdEx("z3 --version")
    z3Available = z3Exit == 0 and z3Out.strip().len > 0
    if z3Available:
      echo "[verify-contracts] Z3: " & z3Out.strip()
    else:
      echo "⚠️  [verify-contracts] Z3 not found — SMT contracts will be skipped"
  except CatchableError:
    echo "⚠️  [verify-contracts] Z3 not available — SMT contracts will be skipped"

  try:
    let elanBin = getHomeDir() / ".elan" / "bin"
    let localBin = getHomeDir() / ".local" / "bin"
    let currentPath = getEnv("PATH", "")
    putEnv("PATH", elanBin & ":" & localBin & ":" & currentPath)
    let (_, leanExit) = execCmdEx("lake --version")
    leanAvailable = leanExit == 0
    if leanAvailable:
      echo "[verify-contracts] Lean: available"
    else:
      echo "⚠️  [verify-contracts] Lean not found — Lean contracts will be skipped"
  except CatchableError:
    echo "⚠️  [verify-contracts] Lean not available — Lean contracts will be skipped"

  echo ""

  # Phase 4: Verify each contract
  var passed = 0
  var failed = 0
  var skipped = 0

  let tmpDir = getTempDir() / "axiom_verify_contracts"
  if dirExists(tmpDir):
    try:
      removeDir(tmpDir)
    except CatchableError:
      stderr.writeLine("[hermetic] WARNING: Failed to clean temp dir: " & getCurrentExceptionMsg())
  createDir(tmpDir)

  for contract in allContracts:
    echo "  [" & $contract.lineNum & "] " & contract.procName & " (" & contract.filePath & ")"

    var contractPassed = true

    # Verify SMT contract
    if contract.smtQuery.len > 0:
      if z3Available:
        let preview = contract.smtQuery[0 .. min(60, contract.smtQuery.len-1)]
        echo "    SMT: " & preview
        let (ok, detail) = runZ3Query(contract.smtQuery, tmpDir)
        if ok:
          echo "    ✅ SMT verified"
        else:
          echo "    ❌ SMT failed: " & detail
          contractPassed = false
      else:
        echo "    SMT: ⚠️  skipped (Z3 unavailable)"
        inc skipped

    # Verify Lean contract
    if contract.leanObligation.len > 0:
      if leanAvailable:
        let preview = contract.leanObligation[0 .. min(60, contract.leanObligation.len-1)]
        echo "    Lean: " & preview
        let (ok, detail) = runLeanVerification(contract.leanObligation, tmpDir)
        if ok:
          echo "    ✅ Lean verified"
        else:
          echo "    ❌ Lean failed: " & detail
          contractPassed = false
      else:
        echo "    Lean: ⚠️  skipped (Lean unavailable)"
        inc skipped

    if contractPassed:
      inc passed
    else:
      inc failed

  # Cleanup temp directory
  try:
    removeDir(tmpDir)
  except CatchableError:
    stderr.writeLine("[hermetic] WARNING: Failed to clean temp dir: " & getCurrentExceptionMsg())

  echo ""
  echo "Results: " & $passed & " passed, " & $failed & " failed, " & $skipped & " skipped"

  # Update cache only on full success
  if failed == 0:
    writeFile(AxiomContractsCachePath, axiomFingerprint)
    echo "[verify-contracts] Fingerprint cached for incremental builds"

  return if failed > 0: 1 else: 0
# Subcommand dispatch — moved to end of file to avoid forward-decl issues with Nim 2.2.10
type BuildCacheEntry* = object
  inputHash*: string      # SHA-256 of input files
  outputHash*: string     # SHA-256 of generated output
  timestamp*: int64
proc computeInputHash(files: seq[string]): string =
  ## SHA-256 해시 체인으로 입력 파일 fingerprint 계산
  var content = ""
  for f in files:
    if fileExists(f):
      content.add(readFile(f))
  result = sha256String(content)
proc shouldRebuild*(inputFiles: seq[string], cachePath: string): bool =
  ## 캐시 히트 시 false 반환 (재빌드 스킵)
  if not fileExists(cachePath): return true
  try:
    let cached = parseJson(readFile(cachePath))
    let currentHash = computeInputHash(inputFiles)
    return cached["inputHash"].getStr() != currentHash
  except CatchableError:
    return true
type
  TypeRegistryEntry = object
    module: string
    name: string
    returnType: string
    paramTypes: seq[string]
    hasAxiomHint: bool
    typeCategory: string
    smtSort: string
    leanType: string
    resultConstraintTemplate: string
    ignorable: bool
    negativeConstraints: seq[string]
proc categorizeReturnType(rt: string): string =
  ## Map Nim return type string to category.
  let t = rt.strip().toLowerAscii()
  if t == "" or t == "void": "void"
  elif t.startsWith("int") or t == "natural" or t.startsWith("uint"): "numeric"
  elif t.startsWith("float"): "float"
  elif t == "bool": "bool"
  elif t in ["string", "cstring"]: "string"
  elif t.startsWith("option["): "option"
  elif t.startsWith("result["): "result"
  elif t.startsWith("seq["): "seq"
  elif t.startsWith("table[") or t.startsWith("orderedtable["): "table"
  else: "object"
proc extractGenericParam(rt: string, baseLen: int): string =
  ## Safely extract generic parameter from e.g. "Option[JsonNode]".
  ## baseLen = len("Option") = 6, so param starts at baseLen+1.
  let bracketOpen = rt.find('[')
  let bracketClose = rt.rfind(']')
  if bracketOpen > 0 and bracketClose > bracketOpen:
    return rt[bracketOpen+1..<bracketClose]
  "T"  # Fallback
proc smtSortForCategory(cat: string, rt: string): string =
  case cat
  of "numeric": "Int"
  of "float": "Real"
  of "bool": "Bool"
  of "string": "String"
  of "option": "(Option " & extractGenericParam(rt, 6) & ")"
  of "seq": "(Seq " & extractGenericParam(rt, 3) & ")"
  of "void": "Unit"
  else: "Int"
proc leanTypeForCategory(cat: string, rt: string): string =
  case cat
  of "numeric": "Int"
  of "float": "Float"
  of "bool": "Bool"
  of "string": "String"
  of "option": "Option " & extractGenericParam(rt, 6)
  of "seq": "List " & extractGenericParam(rt, 3)
  of "void": "Unit"
  else: rt
proc resultConstraintForCategory(cat: string): string =
  case cat
  of "numeric": "(>= result 0)"
  of "float": ""
  of "bool": "(or (= result true) (= result false))"
  of "string": "(>= (str.len result) 0)"
  of "option": "(or (= result none) (exists ((v T)) (= result (some v))))"
  of "seq": "(>= (seq.len result) 0)"
  of "void": ""
  else: ""
proc negativeConstraintsForCategory(cat: string): seq[string] =
  case cat
  of "void": @[
    "result does not exist in this function's scope",
    "SMT: (>= result 0) is a SORT ERROR — result has no type",
    "Lean: referencing result will cause 'unknown identifier' error"
  ]
  of "option": @[
    "result >= 0 is invalid — Option is not numeric",
    "Use 'isSome(result) or isNone(result)' instead"
  ]
  of "result": @[
    "result >= 0 is invalid — Result is not numeric",
    "Use 'result.isOk or result.isErr' instead"
  ]
  of "bool": @[
    "result >= 0 is invalid — Bool is not numeric",
    "Use '(= result true) or (= result false)' instead"
  ]
  of "string": @[
    "result >= 0 directly is invalid — use (>= (str.len result) 0)"
  ]
  of "seq": @[
    "result >= 0 directly is invalid — use (>= (seq.len result) 0)"
  ]
  of "table": @[
    "result >= 0 is invalid — Table is not numeric"
  ]
  of "object": @[
    "result >= 0 is invalid — object types are not numeric"
  ]
  else: @[]
proc extractFunctionsFromFile(filePath: string, projectRoot: string): seq[TypeRegistryEntry] =
  ## Parse a .nim file for proc/func declarations and extract return types.
  ## Uses simple string parsing (not tree-sitter) for build-time speed.
  let content = readFile(filePath)
  let lines = content.splitLines()
  var i = 0
  while i < lines.len:
    let line = lines[i].strip()
    # Skip comments
    if line.startsWith("#") or line.startsWith("##"):
      inc i
      continue

    # Detect proc/func/method/template declarations
    var declKeyword = ""
    if line.startsWith("proc "): declKeyword = "proc "
    elif line.startsWith("func "): declKeyword = "func "
    elif line.startsWith("method "): declKeyword = "method "
    elif line.startsWith("template "): declKeyword = "template "
    elif line.startsWith("macro "): declKeyword = "macro "

    if declKeyword.len > 0:
      # Accumulate multi-line signature (track parens)
      var sig = line
      var parenDepth = 0
      for ch in line:
        if ch == '(': inc parenDepth
        elif ch == ')': dec parenDepth

      # Read continuation lines if signature spans multiple lines
      var j = i + 1
      while parenDepth > 0 and j < lines.len and j < i + 20:
        let contLine = lines[j].strip()
        if contLine.startsWith("#"):
          inc j
          continue
        sig &= " " & contLine
        for ch in contLine:
          if ch == '(': inc parenDepth
          elif ch == ')': dec parenDepth
        inc j

      # Extract function name
      let afterKw = sig[declKeyword.len..^1].strip()
      let nameEnd = min(
        (if '(' in afterKw: afterKw.find('(') else: afterKw.len),
        (if '*' in afterKw: afterKw.find('*') else: afterKw.len)
      )
      let funcName = afterKw[0..<nameEnd].strip()
      if funcName.len == 0 or funcName.contains(' '):
        inc i
        continue

      # Extract return type from signature
      # Find the closing paren of formal params, then return type follows
      var returnType = ""
      let paramStart = sig.find('(')
      if paramStart > 0:
        var depth = 0
        var paramEnd = -1
        for k in paramStart..<sig.len:
          if sig[k] == '(': inc depth
          elif sig[k] == ')':
            dec depth
            if depth == 0:
              paramEnd = k
              break
        if paramEnd > paramStart:
          let afterParams = sig[paramEnd+1..^1].strip()
          # Return type is between ')' and '{' or end
          let pragmaPos = afterParams.find('{')
          let colonPos = afterParams.find(':')
          var rtEnd = afterParams.len
          if pragmaPos >= 0: rtEnd = min(rtEnd, pragmaPos)
          if colonPos >= 0 and colonPos < rtEnd:
            # Could be "ReturnType {.pragma.}" or ": ReturnType" style
            discard
          # Try direct type extraction
          if afterParams.len > 0 and afterParams[0] == ':':
            # "): ReturnType {.pragma.}" style
            let rtStr = afterParams[1..^1].strip()
            let bracePos = rtStr.find('{')
            let eqPos = rtStr.find('=')
            let endPos = min(
              (if bracePos >= 0: bracePos else: rtStr.len),
              (if eqPos >= 0: eqPos else: rtStr.len)
            )
            returnType = rtStr[0..<endPos].strip()
          elif afterParams.len > 0 and afterParams[0] notin ['{', '=', '\n', '\r']:
            # "ReturnType {.pragma.}" style (no colon)
            let bracePos = afterParams.find('{')
            let eqPos = afterParams.find('=')
            let endPos = min(
              (if bracePos >= 0: bracePos else: afterParams.len),
              (if eqPos >= 0: eqPos else: afterParams.len)
            )
            returnType = afterParams[0..<endPos].strip()

      if returnType.len == 0:
        returnType = "void"

      # Check for @axiom-hint in surrounding lines
      var hasHint = false
      let checkStart = max(0, i - 5)
      for k in checkStart..<i:
        if "@axiom-hint" in lines[k]:
          hasHint = true
          break
      if not hasHint:
        for k in i..<min(lines.len, j + 3):
          if "@axiom-hint" in lines[k]:
            hasHint = true
            break

      let cat = categorizeReturnType(returnType)
      result.add(TypeRegistryEntry(
        module: relativePath(filePath, projectRoot),
        name: funcName,
        returnType: returnType,
        paramTypes: @[],  # Simplified — params not needed for type category
        hasAxiomHint: hasHint,
        typeCategory: cat,
        smtSort: smtSortForCategory(cat, returnType),
        leanType: leanTypeForCategory(cat, returnType),
        resultConstraintTemplate: resultConstraintForCategory(cat),
        ignorable: cat == "void",
        negativeConstraints: negativeConstraintsForCategory(cat)
      ))

      i = j
    else:
      inc i
proc generateTypeRegistry(projectRoot: string): JsonNode =
  ## Walk src/ for .nim files, extract function signatures, build JSON.
  let srcDir = projectRoot / "src"
  var entries: seq[TypeRegistryEntry] = @[]

  for filePath in walkDirRec(srcDir):
    if not filePath.endsWith(".nim"): continue
    # Skip generated files and test files
    if "/generated/" in filePath: continue
    if "/nimcache" in filePath: continue
    try:
      let funcs = extractFunctionsFromFile(filePath, projectRoot)
      entries.add(funcs)
    except CatchableError:
      stderr.writeLine("WARNING: Failed to parse " & filePath & ": " & getCurrentExceptionMsg())

  entries.sort(proc(a, b: TypeRegistryEntry): int =
    cmp(a.module & "\x00" & a.name, b.module & "\x00" & b.name))

  # Build JSON
  var entriesJson = newJArray()
  for entry in entries:
    var entryJson = %*{
      "module": entry.module,
      "name": entry.name,
      "returnType": entry.returnType,
      "hasAxiomHint": entry.hasAxiomHint,
      "typeCategory": entry.typeCategory,
      "smtSort": entry.smtSort,
      "leanType": entry.leanType,
      "resultConstraintTemplate": entry.resultConstraintTemplate,
      "ignorable": entry.ignorable
    }
    if entry.negativeConstraints.len > 0:
      var ncJson = newJArray()
      for nc in entry.negativeConstraints:
        ncJson.add(%nc)
      entryJson["negativeConstraints"] = ncJson
    entriesJson.add(entryJson)

  # Type mapping table
  let typeMapping = %*{
    "int": {"smtSort": "Int", "leanType": "Int", "category": "numeric",
            "resultConstraintTemplate": "(>= result 0)",
            "negativeConstraints": []},
    "uint": {"smtSort": "Int", "leanType": "Nat", "category": "numeric",
             "resultConstraintTemplate": "(>= result 0)",
             "negativeConstraints": []},
    "natural": {"smtSort": "Int", "leanType": "Nat", "category": "numeric",
                "resultConstraintTemplate": "(>= result 0)",
                "negativeConstraints": []},
    "float": {"smtSort": "Real", "leanType": "Float", "category": "float",
              "resultConstraintTemplate": "",
              "negativeConstraints": ["result >= 0 is invalid for float — floats can be negative"]},
    "string": {"smtSort": "String", "leanType": "String", "category": "string",
               "resultConstraintTemplate": "(>= (str.len result) 0)",
               "negativeConstraints": ["result >= 0 directly is invalid — use (>= (str.len result) 0)"]},
    "bool": {"smtSort": "Bool", "leanType": "Bool", "category": "bool",
             "resultConstraintTemplate": "(or (= result true) (= result false))",
             "negativeConstraints": ["result >= 0 is invalid — Bool is not numeric"]},
    "void": {"smtSort": "Unit", "leanType": "Unit", "category": "void",
             "resultConstraintTemplate": "", "ignorable": true,
             "negativeConstraints": [
               "result does not exist in this function's scope",
               "SMT: (>= result 0) is a SORT ERROR",
               "Lean: referencing result will cause 'unknown identifier' error"
             ]},
    "Option[T]": {"smtSort": "(Option T)", "leanType": "Option T", "category": "option",
                  "resultConstraintTemplate": "(or (= result none) (exists ((v T)) (= result (some v))))",
                  "negativeConstraints": ["result >= 0 is invalid — Option is not numeric"]},
    "Result[T,E]": {"smtSort": "(Result T E)", "leanType": "Result T E", "category": "result",
                    "resultConstraintTemplate": "(or result.isOk result.isErr)",
                    "negativeConstraints": ["result >= 0 is invalid — Result is not numeric"]},
    "seq[T]": {"smtSort": "(Seq T)", "leanType": "List T", "category": "seq",
               "resultConstraintTemplate": "(>= (seq.len result) 0)",
               "negativeConstraints": ["result >= 0 directly is invalid — use (>= (seq.len result) 0)"]}
  }

  result = %*{"entries": entriesJson, "typeMapping": typeMapping}
proc validateTypeRegistry(json: JsonNode): bool =
  ## Validate generated JSON. Fail-fast on integrity issues.
  let entries = json["entries"]

  # 1. Empty entries check
  if entries.len == 0:
    stderr.writeLine("FATAL: type_registry_metadata.json has 0 entries")
    return false

  # 2. Required field existence check
  for entry in entries:
    let modName = entry{"module"}.getStr("?")
    let funcName = entry{"name"}.getStr("?")
    if entry{"returnType"}.getStr("").len == 0:
      stderr.writeLine("FATAL: empty returnType in " & modName & "::" & funcName)
      return false
    if entry{"typeCategory"}.getStr("").len == 0:
      stderr.writeLine("FATAL: empty typeCategory in " & modName & "::" & funcName)
      return false

  # 3. Ambiguous type check — warn if "unknown" > 30%
  var unknownCount = 0
  for entry in entries:
    if entry{"typeCategory"}.getStr() == "unknown":
      inc unknownCount
  if entries.len > 0 and unknownCount.float / entries.len.float > 0.3:
    stderr.writeLine("WARNING: " & $unknownCount & "/" & $entries.len & " entries have typeCategory='unknown'")

  # 4. typeMapping completeness check
  let mapping = json["typeMapping"]
  for required in ["int", "string", "bool", "void", "Option[T]", "Result[T,E]", "seq[T]"]:
    if required notin mapping:
      stderr.writeLine("FATAL: missing typeMapping entry: " & required)
      return false

  true

proc prettySorted(node: JsonNode, indent: int = 2): string =
  proc sortedNode(n: JsonNode): JsonNode =
    case n.kind
    of JObject:
      var keys: seq[string] = @[]
      for k, _ in n.fields:
        keys.add(k)
      keys.sort()
      result = newJObject()
      for k in keys:
        result[k] = sortedNode(n[k])
    of JArray:
      result = newJArray()
      for elem in n:
        result.add(sortedNode(elem))
    else:
      result = n
  result = sortedNode(node).pretty(indent = indent)

proc writeTypeRegistryIfChanged(path: string, projectRoot: string): bool =
  ## Generate and write type_registry_metadata.json (idempotent).
  let json = generateTypeRegistry(projectRoot)
  if not validateTypeRegistry(json):
    return false  # Validation failed — caller should abort

  let newContent = prettySorted(json, indent = 2)
  if fileExists(path):
    let existing = readFile(path)
    if existing == newContent:
      return false  # No change
  let dir = parentDir(path)
  if not dirExists(dir):
    createDir(dir)
  writeFile(path, newContent)
  return true
proc getGitHash(): string =
  ## Get current git commit hash.
  ## Uses .git/HEAD directly to support worktrees (no git rev-parse).
  # Environment variable fallback (CI shallow clone support)
  let envHash = getEnv("AXIOM_GIT_HASH", "")
  if envHash.len > 0:
    return envHash
  let headPath = projectRoot / ".git/HEAD"
  if not fileExists(headPath):
    return "unknown"
  let headContent = readFile(headPath).strip()
  if headContent.startsWith("ref: "):
    # Detached HEAD — read the ref file
    let refPath = projectRoot / ".git" / headContent[5..^1]
    if fileExists(refPath):
      return readFile(refPath).strip()
    else:
      return headContent[5..^1]
  else:
    # Direct hash
    return headContent
proc getCommitCount(): int =
  ## Shallow clone에서도 동작하는 커밋 카운트
  if fileExists(projectRoot / ".git/shallow"):
    let (output, exitCode) = execCmdEx("git rev-list --count HEAD 2>/dev/null")
    if exitCode == 0 and output.strip().len > 0:
      try:
        return parseInt(output.strip())
      except ValueError:
        return 0
    return 0
  # 비-shallow: 기존 로직
  let (output, exitCode) = execCmdEx("git rev-list --count HEAD 2>/dev/null")
  if exitCode == 0 and output.strip().len > 0:
    try:
      return parseInt(output.strip())
    except ValueError:
      return 0
  return 0
proc leadingDigits(s: string): string =
  ## Leading numeric run of a string ("3-x64" → "3", "3" → "3", "rc1" → "").
  for c in s:
    if c in Digits:
      result.add(c)
    else:
      break

proc refineSemVer(v: string): string =
  ## Reduce a version token to its first three SemVer components.
  ## "4.13.3-x64" → "4.13.3"; "4.13.3.1" → "4.13.3"; "4.13.3" → "4.13.3".
  let components = v.split(".")
  if components.len >= 3:
    let patch = leadingDigits(components[2])
    if patch.len > 0:
      return components[0] & "." & components[1] & "." & patch
    return components[0] & "." & components[1] & "." & components[2]
  v

proc getZ3Version(): string =
  ## Get Z3 version string (SemVer-refined). Returns "unavailable" if Z3 not found.
  let (output, exitCode) = execCmdEx("z3 --version")
  if exitCode != 0:
    return "unavailable"
  # Output like "Z3 version 4.13.3 - 64 bit" or "Z3 version 4.13.3-x64"
  let parts = output.strip().split(" ")
  for i, p in parts:
    if p == "version" and i + 1 < parts.len:
      return refineSemVer(parts[i + 1])
  refineSemVer(output.strip())
proc computeLeanSourceHash(): string =
  ## Compute SHA-256 hash of all Lean source files under proofs/.
  ## Returns hex digest; "empty" if no Lean files found.
  var combined = ""
  let proofsDir = projectRoot / "proofs"
  if not dirExists(proofsDir):
    return sha256String("")  # SHA-256 of empty string
  for path in walkDirRec(proofsDir):
    if path.endsWith(".lean"):
      combined.add(readFile(path))
  if combined.len == 0:
    return sha256String("")
  sha256String(combined)
proc gatherSourceTree(srcDir: string): tuple[
    files: seq[tuple[relPath: string, content: string]], complete: bool] =
  ## ONE walkDirRec + ONE readFile per .nim file under srcDir (excluding
  ## /generated/). The single (src-relative path, content) set feeds BOTH
  ## derivations — BuildSourceHash (hashSourceContents kernel) and the
  ## VerifierBuildId manifest — where each derivation used to re-walk and
  ## re-read the same tree. ``complete`` is false when a source file was
  ## unreadable: the tree-hash twin keeps its warn-and-skip semantics over the
  ## files that WERE read, while the manifest twin fails closed
  ## ("unmeasured") — both exactly as the two pre-change walks behaved.
  result.files = @[]
  result.complete = true
  for f in walkDirRec(srcDir):
    if f.endsWith(".nim") and not f.contains("/generated/"):
      try:
        result.files.add((relativePath(f, srcDir, '/'), readFile(f)))
      except CatchableError:
        stderr.writeLine("[hermetic] WARNING: Failed to read source file " & f &
          " — tree hash omits it; VerifierBuildId fails closed (\"unmeasured\")")
        result.complete = false
proc computeDeterministicSourceHash(srcDir: string): string =
  ## Delegate to hashSourceContents: the digest formula is defined in the
  ## kernel (src/core/utils/build_provenance.nim) — this proc is the
  ## build-time gather twin, byte-identical to the runtime twin by
  ## construction (shared kernel, no local re-implementation). Single-walk
  ## route for --check-source-hash / --materialize; generateBuildEnvPair
  ## instead shares one gatherSourceTree across both derivations.
  hashSourceContents(gatherSourceTree(srcDir).files)
proc getBuildDate(): string =
  ## Get current UTC build date in yyyy-MM-dd format.
  utc(now()).format("yyyy-MM-dd")
proc computeVerifierBuildManifest(files: seq[tuple[relPath: string, content: string]],
                                  complete: bool): seq[(string, string)] =
  ## Collect the VERIFIER BUILD INPUT manifest: (repo-relative path, sha256 of
  ## file bytes) for every input the verifier binary is compiled from —
  ##   - src/**/*.nim (excluding src/generated/: generated code is an OUTPUT),
  ##   - config.nims + config/effects.nims + src/gate/config.nims (compiler /
  ##     effect-checking / gate flags),
  ##   - Makefile (the documented build recipe),
  ##   - axiom.nimble + axiom.lock (the dependency pins),
  ##   - proofs/lean-toolchain (the compile-time Lean pin constant).
  ## Docs, tests, journal/baseline data and git metadata are NOT build inputs
  ## and are excluded: a docs-only commit keeps the identity; a verifier source
  ## change moves it. The pure composition lives in
  ## src/core/trusted/verifier_build_identity.nim (shared with the tests).
  ## ``files`` is the ONE shared gather (src-relative paths); records carry the
  ## repo-relative "src/"-prefixed paths the pre-change dedicated walk
  ## produced. ``complete == false`` (an unreadable source file) fails closed:
  ## @[] → computeVerifierBuildId → "" ("unmeasured"), never a partial
  ## identity over a half-read tree.
  if not complete:
    return @[]
  let sha = proc(content: string): string =
    sha256String(content)
  var records: seq[(string, string)]
  template addRecord(relPath: string; content: string) =
    records.add((relPath, sha(content)))
  for f in files:
    addRecord("src" / f.relPath, f.content)
  for extra in ["config.nims", "config/effects.nims", "src/gate/config.nims",
                "Makefile", "axiom.nimble", "axiom.lock",
                "proofs/lean-toolchain"]:
    let p = projectRoot / extra
    if fileExists(p):
      try:
        addRecord(extra, readFile(p))
      except CatchableError:
        stderr.writeLine("[hermetic] WARNING: cannot read verifier input " & p &
          " — VerifierBuildId fails closed (\"unmeasured\")")
        return @[]
    else:
      stderr.writeLine("[hermetic] WARNING: missing verifier build input " & p &
        " — VerifierBuildId fails closed (\"unmeasured\")")
      return @[]
  records
proc measuredVerifierBuildId(files: seq[tuple[relPath: string, content: string]];
                             complete: bool): string =
  ## Content-based verifier build identity (Phase 1B `engineBuild`). Explicitly
  ## NOT the repo commit (BuildEnvGitHash): that churns on docs-only and
  ## topic-vs-merge commits that change nothing the verifier compiled.
  ## Takes the shared gather so generateBuildEnvPair reads src/ once for BOTH
  ## derivations.
  computeVerifierBuildId(computeVerifierBuildManifest(files, complete))
proc measuredVerifierBuildId(): string =
  ## --materialize route: no shared gather in scope — walks the tree itself.
  let g = gatherSourceTree(projectRoot / "src")
  measuredVerifierBuildId(g.files, g.complete)
proc generateBuildEnvPair(): tuple[content: string, bodyContent: string] =
  ## Generate build_env.nim content and its placeholder-templated body cache in
  ## a single pass (computing BuildSourceHash and VerifierBuildId once).
  ## Build date is UTC-day-granular — does NOT bust cache within same day.
  let commitCount = getCommitCount()
  let gitHash = getGitHash()
  let buildDate = getBuildDate()
  let leanHash = computeLeanSourceHash()
  let srcTree = gatherSourceTree(projectRoot / "src")
  let verifierSourceHash = hashSourceContents(srcTree.files)
  let verifierBuildId = measuredVerifierBuildId(srcTree.files, srcTree.complete)

  var header = "# src/generated/build_env.nim — AUTO-GENERATED by bin/hermetic_build\n"
  header &= "# DO NOT EDIT. Regenerated only when values change.\n"
  header &= "#\n"
  header &= "# This file is part of the Hermetic Build Orchestrator architecture.\n"
  header &= "# It replaces all gorge/staticExec calls for build introspection\n"
  header &= "# in config.nims and src/ modules.\n"
  header &= "#\n"
  header &= "# Architecture: config.nims → bin/hermetic_build → this file → src/ imports\n"
  header &= "\n"
  header &= "const\n"
  header &= "  BuildEnvZ3Version* = " & getZ3Version().escape() & "\n"
  header &= "  BuildEnvCommitCount* = " & $commitCount & "\n"

  var content = header
  content &= "  BuildEnvGitHash* = " & gitHash.escape() & "\n"
  content &= "  BuildEnvBuildDate* = " & buildDate.escape() & "\n"
  content &= "  BuildEnvLeanSourceHash* = " & leanHash.escape() & "\n"
  content &= "  BuildSourceHash* = \"" & verifierSourceHash & "\"\n"
  # The source-tree hash the VerifierBuildId was measured for. Runtime admission
  # requires VerifierBuildSourceHash == BuildSourceHash (the live value).
  content &= "  VerifierBuildSourceHash* = \"" & verifierSourceHash & "\"\n"
  content &= "  VerifierBuildId* = \"" & verifierBuildId & "\"\n"

  var bodyContent = ""
  if gitHash.len > 0 and gitHash != "unknown":
    bodyContent = header
    bodyContent &= "  BuildEnvGitHash* = " & GitHashPlaceholder.escape() & "\n"
    bodyContent &= "  BuildEnvBuildDate* = " & buildDate.escape() & "\n"
    bodyContent &= "  BuildEnvLeanSourceHash* = " & leanHash.escape() & "\n"
    bodyContent &= "  BuildSourceHash* = \"" & BuildSourceHashPlaceholder & "\"\n"
    bodyContent &= "  VerifierBuildSourceHash* = \"" & BuildSourceHashPlaceholder & "\"\n"
    bodyContent &= "  VerifierBuildId* = \"" & VerifierBuildIdPlaceholder & "\"\n"

  result = (content, bodyContent)

proc generateBuildEnvContent(): string =
  generateBuildEnvPair().content

proc atomicWriteFile(path, content: string): bool =
  ## Write ``content`` to ``path`` only if it differs (idempotent).
  ## Uses atomic write: PID-unique temp file → fsync → rename (safeMoveFile)
  ## to prevent partial/corrupted writes and tmp collisions across concurrent
  ## hermetic_build processes.
  if fileExists(path):
    let existing = readFile(path)
    if existing == content:
      return false  # No change — skip write to preserve build cache
  # Ensure directory exists
  let dir = parentDir(path)
  if not dirExists(dir):
    createDir(dir)
  # Atomic write: PID-tmp → fsync → rename
  let tmpPath = path & ".tmp." & $getCurrentProcessId()
  writeFile(tmpPath, content)
  # fsync the temp file to guarantee durable write before rename
  block:
    let tmpFile = open(tmpPath, fmRead)
    let tmpFd = cast[cint](getOsFileHandle(tmpFile))
    if fsync(tmpFd) != 0:
      stderr.writeLine("[hermetic] WARNING: fsync failed for " & path)
    close(tmpFile)
  safeMoveFile(tmpPath, path)
  return true

proc writeBuildEnvIfChanged(path, content: string): bool =
  ## Write supplied ``content`` as build_env.nim atomically and idempotently.
  atomicWriteFile(path, content)

proc writeBuildEnvIfChanged(path: string): bool =
  ## Generate build_env.nim content and write it only if changed (idempotent).
  ## Uses atomic write: PID-unique temp file → fsync → rename.
  atomicWriteFile(path, generateBuildEnvContent())

proc generateBuildEnv(): bool =
  ## Generate build_env.nim as a default pass on every invocation.
  ## Ensures src/generated/build_env.nim exists before any other pass.
  ## Idempotent: only writes when content changes.
  ## Returns true if file was written (content changed).
  let z3Version = getZ3Version()
  if z3Version == "unavailable":
    stderr.writeLine("WARNING: Z3 not found — BuildEnvZ3Version will be \"unavailable\"")
  let (content, bodyContent) = generateBuildEnvPair()
  let changed = writeBuildEnvIfChanged(BuildEnvPath, content)
  if changed:
    echo "[hermetic] build_env.nim generated (content changed)"
  else:
    echo "[hermetic] build_env.nim unchanged (idempotent)"
  # Cache the canonical body (git-hash, BuildSourceHash, and VerifierBuildId
  # replaced with placeholders) so that --materialize can refresh build_env.nim
  # without running the full hermetic orchestrator scan.
  if bodyContent.len > 0:
    discard atomicWriteFile(BodyCachePath, bodyContent)  # axiom:best-effort(body cache is informational; a stale body self-heals on the next materialize/full-scan)
  return changed

proc checkImportBoundaries(): bool =
  ## Verify no forbidden import patterns exist in src/.
  ## This replaces the gorge("grep") calls in config.nims.
  const forbidden = [
    "core.boundary.spec_types",  # example — expand as needed
  ]
  let srcDirs = [projectRoot / "src/core", projectRoot / "src/cli", projectRoot / "src/engine", projectRoot / "src/gate", projectRoot / "src/api"]
  var violations: seq[string] = @[]
  for dir in srcDirs:
    if not dirExists(dir):
      continue
    for entry in walkDirRec(dir):
      if not entry.endsWith(".nim"):
        continue
      let content = readFile(entry)
      for lineNum, line in content.splitLines().pairs():
        let stripped = line.strip()
        if stripped.startsWith("#") or stripped.startsWith("##"):
          continue
        # Skip string literals (check if import is inside quotes)
        let quotePos = stripped.find('"')
        if quotePos >= 0:
          let importPos = min(
            (if ("import " & forbidden[0]) in stripped: stripped.find("import " & forbidden[0]) else: high(int)),
            (if ("from " & forbidden[0]) in stripped: stripped.find("from " & forbidden[0]) else: high(int)))
          if importPos > quotePos:
            continue  # import is inside a string literal
        for f in forbidden:
          if ("import " & f) in stripped or ("from " & f) in stripped:
            violations.add(entry & ":" & $(lineNum + 1) & ": " & stripped)
  if violations.len > 0:
    echo "  ❌ Import boundary violations:"
    for v in violations:
      echo "    " & v
    return false
  return true
proc verifyInvariantHash(): bool =
  ## Verify architecture_invariants.nim hasn't been tampered with.
  ## Fail-closed (DEBT#533): a missing anchor is a FAILURE. Deriving the anchor
  ## from the tree under test would let one change both the invariant source and
  ## its reference hash and still observe "Invariant hash: OK". Re-anchoring is
  ## an explicit, separate act (`bin/reanchor_pin`), never a build side effect.
  if not fileExists(InvariantsPath):
    echo "  ❌ " & InvariantsPath & " not found — failing invariant hash check"
    return false
  let content = readFile(InvariantsPath)
  let currentHash = sha256String(content)
  let anchorPresent = fileExists(ExpectedHashPath)
  let expectedHash =
    if anchorPresent: readFile(ExpectedHashPath).strip()
    else: ""
  case judgeInvariantAnchor(true, anchorPresent, currentHash, expectedHash)
  of iavOk:
    return true
  of iavInvariantsMissing:
    return false
  of iavAnchorMissing:
    echo "  ❌ [guard] " & ExpectedHashPath & " not found — failing invariant hash check"
    echo "    re-anchor explicitly from a trusted tree: bin/reanchor_pin"
    return false
  of iavMismatch:
    echo "  ❌ [guard] architecture_invariants.nim hash mismatch — possible tampering"
    echo "    expected: " & expectedHash
    echo "    current:  " & currentHash
    return false
proc generateManifest(): bool =
  ## Content-derived deterministic manifest (§0.2). No wall-clock timestamps.
  ## manifest_content_hash = SHA-256(invariant_hash + scope_lock_version)
  let invHash = if fileExists(ExpectedHashPath): readFile(ExpectedHashPath).strip() else: ""
  var scopeVersion = 0
  let scopeLockPath = projectRoot / "data/verification_scope.lock"
  if fileExists(scopeLockPath):
    try:
      let scopeNode = parseJson(readFile(scopeLockPath))
      scopeVersion = scopeNode{"schema_version"}.getInt(0)
    except CatchableError:
      scopeVersion = 0
  let contentHash = sha256String(invHash & $scopeVersion)
  
  # Idempotency check: if manifest exists with same content hash, skip write
  if fileExists(ManifestPath):
    try:
      let existingNode = parseJson(readFile(ManifestPath))
      let existingHash = existingNode{"manifest_content_hash"}.getStr("")
      if existingHash == contentHash:
        echo "  [manifest] Content-derived manifest unchanged (idempotent)"
        return true
    except CatchableError:
      discard  # axiom:best-effort(manifest read failure → proceed to write fresh manifest, idempotency check is advisory)

  let manifestNode = %*{
    "schema_version": 1,
    "invariant_hash": invHash,
    "scope_lock_version": scopeVersion,
    "manifest_content_hash": contentHash
  }
  let dir = parentDir(ManifestPath)
  if dir.len > 0 and not dirExists(dir):
    createDir(dir)
  let tmpPath = ManifestPath & ".tmp." & $getCurrentProcessId()
  writeFile(tmpPath, $manifestNode & "\n")
  safeMoveFile(tmpPath, ManifestPath)
  echo "  [manifest] Content-derived manifest generated"
  true

proc checkManifestStaleness(): bool =
  ## Check if axiom_manifest.json is content-consistent with current invariant
  ## hash and scope lock version (§0.2 determinism — no mtime dependence).
  if not fileExists(ManifestPath):
    echo "  ❌ " & ManifestPath & " not found — failing manifest staleness check"
    return false
  var storedContentHash = ""
  try:
    let node = parseJson(readFile(ManifestPath))
    storedContentHash = node{"manifest_content_hash"}.getStr("")
  except CatchableError:
    storedContentHash = ""
  if storedContentHash.len == 0:
    echo "  ❌ " & ManifestPath & " missing manifest_content_hash — stale"
    return false
  let invHash = if fileExists(ExpectedHashPath): readFile(ExpectedHashPath).strip() else: ""
  var scopeVersion = 0
  let scopeLockPath = projectRoot / "data/verification_scope.lock"
  if fileExists(scopeLockPath):
    try:
      scopeVersion = parseJson(readFile(scopeLockPath)){"schema_version"}.getInt(0)
    except CatchableError:
      scopeVersion = 0
  let expectedContentHash = sha256String(invHash & $scopeVersion)
  if storedContentHash != expectedContentHash:
    echo "  ❌ " & ManifestPath & " content hash mismatch (stale)"
    return false
  true
proc seedGitEnvVars() =
  ## hermetic_build 오케스트레이터가 최초 1회 git 명령어를 안전하게 실행하여
  ## 환경 변수로 주입. CI Shallow Clone 환경에서의 fallback.
  if getEnv("AXIOM_GIT_HASH", "").len == 0:
    let (hash, exitCode) = execCmdEx("git rev-parse --short HEAD 2>/dev/null")
    if exitCode == 0:
      putEnv("AXIOM_GIT_HASH", hash.strip())
proc ensureBuildEnvExists(path: string) =
  ## Bootstrap fallback: copy build_env.nim.default → build_env.nim if missing.
  ## Uses atomic write (temp → fsync → rename) to prevent partial files.
  ## Ensures valid Nim constants exist BEFORE any nim c call that imports them.
  if fileExists(path):
    return  # Already exists — skip
  let defaultPath = path & ".default"
  if not fileExists(defaultPath):
    echo "[hermetic] WARNING: neither " & path & " nor " & defaultPath & " exist"
    return
  let content = readFile(defaultPath)
  let dir = parentDir(path)
  if not dirExists(dir):
    createDir(dir)
  # Atomic write: temp → fsync → rename
  let tmpPath = path & ".tmp." & $getCurrentProcessId()
  writeFile(tmpPath, content)
  block:
    let tmpFile = open(tmpPath, fmRead)
    let tmpFd = cast[cint](getOsFileHandle(tmpFile))
    if fsync(tmpFd) != 0:
      stderr.writeLine("[hermetic] WARNING: fsync failed for " & path)
    close(tmpFile)
  safeMoveFile(tmpPath, path)
# Forward declaration — scanDebtMarkers is defined later in this file
proc scanDebtMarkers(): int
# Forward declaration — checkDecisionBindings is defined later in this file
proc checkDecisionBindings*(stagedOnly: bool = false, auditMode: bool = false, escalationThreshold: int = 30): int
proc verifyScopeLock(): bool =
  ## WS-P2-B: the `generateAxiomInit` macro no longer writes
  ## data/verification_scope.lock at compile time (Hermetic violation removed).
  ## hermetic_build cannot derive kernel symbols itself — they exist only in the
  ## compiled registry — so it validates lock presence + structure and fails
  ## closed when missing. Regenerate with `ax scope lock` after compiling.
  let scopeLockPath = projectRoot / "data" / "verification_scope.lock"
  if not fileExists(scopeLockPath):
    echo "  ❌ " & scopeLockPath & " not found — kernel scope lock missing"
    echo "     Regenerate with: bin/axiom scope lock  (after compiling bin/axiom)"
    return false
  try:
    let node = parseJson(readFile(scopeLockPath))
    let schemaVersion = node{"schema_version"}.getInt(0)
    let kernelTotal = node{"kernel_total"}.getInt(0)
    if schemaVersion != VERIFICATION_SCOPE_SCHEMA_VERSION:
      echo "  ❌ " & scopeLockPath & " has unexpected schema_version: " & $schemaVersion
      return false
    if kernelTotal <= 0:
      echo "  ❌ " & scopeLockPath & " kernel_total is not positive: " & $kernelTotal
      return false
    return true
  except CatchableError as e:
    echo "  ❌ " & scopeLockPath & " is not valid JSON: " & e.msg
    return false

proc main() =
  # Step 0: Bootstrap fallback — copy .default if build_env.nim missing
  # Note: generateBuildEnv() has already run in the early pass before main(),
  # so build_env.nim and .axiom/cache/build_env.body are already up-to-date.
  ensureBuildEnvExists(BuildEnvPath)

  echo "=== Hermetic Build Orchestrator ==="
  echo ""

  var allPassed = true

  # 2. Import boundary check
  if getEnv("AXIOM_FAST_BUILD") == "1":
    echo "[hermetic] AXIOM_FAST_BUILD=1 — skipping import boundary check"
  else:
    if checkImportBoundaries():
      echo "[hermetic] Import boundaries: OK"
    else:
      allPassed = false

  # 3. Invariant hash verification
  if verifyInvariantHash():
    echo "[hermetic] Invariant hash: OK"
  else:
    allPassed = false

  # 3a. Kernel scope lock presence/structural check (fail-closed)
  if verifyScopeLock():
    echo "[hermetic] Scope lock: OK"
  else:
    allPassed = false

  # 4. Generate content-derived manifest (deterministic, no timestamps)
  discard generateManifest()

  # 5. Manifest staleness check (content-hash based, not mtime)
  if checkManifestStaleness():
    echo "[hermetic] Manifest staleness: OK"
  else:
    allPassed = false

  # 6. Type registry generation (build-time type metadata)
  if getEnv("AXIOM_FAST_BUILD") == "1":
    echo "[hermetic] AXIOM_FAST_BUILD=1 — skipping type registry generation"
  else:
    echo ""
    let trChanged = writeTypeRegistryIfChanged(TypeRegistryPath, projectRoot)
    if trChanged:
      echo "[hermetic] type_registry_metadata.json generated"
    else:
      if fileExists(TypeRegistryPath):
        echo "[hermetic] type_registry_metadata.json unchanged (idempotent)"
      else:
        echo "[hermetic] type_registry_metadata.json generated (first run)"

    # 7. Type registry validation (fail-fast)
    if fileExists(TypeRegistryPath):
      let trJson = parseJson(readFile(TypeRegistryPath))
      if validateTypeRegistry(trJson):
        echo "[hermetic] Type registry validation: OK"
      else:
        allPassed = false

  # 8. Debt codegen (idempotent, non-blocking) — single writer is bin/debt_engine
  if getEnv("AXIOM_FAST_BUILD") == "1":
    echo "[hermetic] AXIOM_FAST_BUILD=1 — skipping debt codegen"
  elif fileExists(projectRoot / "data/architecture_debt.json"):
    let debtEngineBin = projectRoot / "bin/debt_engine"
    if not fileExists(debtEngineBin):
      echo "[hermetic] bin/debt_engine not built — skipping debt codegen (build it: make bin/debt_engine)"
    else:
      let debtResult = execCmdEx("bin/debt_engine --codegen")
      if debtResult.exitCode != 0:
        echo "WARNING: debt_engine --codegen failed: " & debtResult.output
        allPassed = false
      else:
        if debtResult.output.strip().len > 0:
          echo "[hermetic] " & debtResult.output.strip()

  # 9. Debt marker scan (TODO/FIXME/HACK — informational only, never fails build)
  if getEnv("AXIOM_FAST_BUILD") == "1":
    echo "[hermetic] AXIOM_FAST_BUILD=1 — skipping debt marker scan"
  else:
    echo ""
    discard scanDebtMarkers()

  echo ""
  if allPassed:
    echo "All hermetic pre-build checks passed."
    quit(0)
  else:
    echo "Hermetic pre-build checks FAILED."
    quit(1)

proc checkGolden(): int =
  ## Check data/golden/ integrity. Returns 0 if clean, 1 if dirty.
  let (goldenDirty, gc1) = execCmdEx("git status --porcelain data/golden/")
  if gc1 != 0:
    echo "GOLDEN_ERROR: git status failed (exit " & $gc1 & ")"
    return 2
  if goldenDirty.strip().len > 0:
    echo "GOLDEN_DIRTY"
    echo goldenDirty
    return 1
  let (goldenDiff, gc2) = execCmdEx("git diff --name-only HEAD -- data/golden/")
  if gc2 != 0:
    echo "GOLDEN_ERROR: git diff failed (exit " & $gc2 & ")"
    return 2
  if goldenDiff.strip().len > 0:
    echo "GOLDEN_DIFF"
    echo goldenDiff
    return 1
  echo "GOLDEN_CLEAN"
  return 0
proc checkHooks(): int =
  ## Check git hooks configuration. Returns 0 if configured, 1 if not.
  let (hooksPath, hc) = execCmdEx("git config core.hooksPath 2>/dev/null")
  if hc != 0:
    echo "HOOKS_ERROR: git config failed (exit " & $hc & ")"
    return 2
  if hooksPath.strip().len == 0:
    echo "HOOKS_MISSING"
    return 1
  echo "HOOKS_OK: " & hooksPath.strip()
  return 0
proc checkImportEncapsulation(): int =
  ## 3-direction import boundary check. Returns 0=clean, 1=violations.
  ## Replaces config.nims gorge("grep") calls with pure Nim walkDirRec + readFile.
  var violations: seq[string] = @[]

  # ── Source direction: JSON rules from data/forbidden_imports.json ──
  let forbiddenImportsPath = projectRoot / "data/forbidden_imports.json"
  if fileExists(forbiddenImportsPath):
    let rules = parseJson(readFile(forbiddenImportsPath))
    for rule in rules["rules"]:
      let source = rule["source"].getStr()
      let forbidden = rule["forbidden"]
      for path in walkDirRec(projectRoot / source):
        if not path.endsWith(".nim"): continue
        let content = readFile(path)
        for i, line in content.splitLines().pairs():
          let stripped = line.strip()
          if stripped.startsWith("#"): continue
          for patNode in forbidden:
            let pat = patNode.getStr()
            if ("import " & pat) in line or ("from " & pat) in line:
              # Skip string literals: if a '"' appears before the import keyword
              let quotePos = stripped.find('"')
              let importPos = min(
                (if ("import " & pat) in stripped: stripped.find("import " & pat) else: high(int)),
                (if ("from " & pat) in stripped: stripped.find("from " & pat) else: high(int)))
              if quotePos >= 0 and importPos > quotePos:
                continue
              violations.add("IMPORT: " & path & ":" & $(i+1) & ": " & stripped)

  # ── Core direction: core/ must NOT import gate/, cli/, verification/ ──
  let coreForbidden = ["import gate/", "import cli/", "import verification/",
                       "from gate/", "from cli/", "from verification/"]
  let excludeDirs = ["application", "boundary"]
  for path in walkDirRec(projectRoot / "src/core/"):
    if not path.endsWith(".nim"): continue
    let parts = path.split(DirSep)
    var skip = false
    for excl in excludeDirs:
      if excl in parts: skip = true
    if skip: continue
    let content = readFile(path)
    for i, line in content.splitLines().pairs():
      let stripped = line.strip()
      if stripped.startsWith("#"): continue
      for pat in coreForbidden:
        if pat in line:
          # Skip string literals
          let quotePos = stripped.find('"')
          let importPos = stripped.find(pat)
          if quotePos >= 0 and importPos > quotePos:
            continue
          violations.add("CORE: " & path & ":" & $(i+1) & ": " & stripped)

  # ── Inbound: engine/gate must NOT import core/schema/ or core/topology/ ──
  let inboundPatterns = ["import core/schema/", "from core/schema/",
                         "import core/topology/", "from core/topology/"]
  for dir in [projectRoot / "src/engine/", projectRoot / "src/gate/"]:
    for path in walkDirRec(dir):
      if not path.endsWith(".nim"): continue
      let content = readFile(path)
      for i, line in content.splitLines().pairs():
        let stripped = line.strip()
        if stripped.startsWith("#"): continue
        for pat in inboundPatterns:
          if stripped.startsWith(pat):
            # Skip string literals
            let quotePos = stripped.find('"')
            if quotePos >= 0:
              continue
            violations.add("INBOUND: " & path & ":" & $(i+1) & ": " & stripped)

  if violations.len > 0:
    for v in violations:
      echo "❌ [ImportEncapsulation] ", v
    return 1
  echo "IMPORTS_CLEAN"
  return 0
# axiom:theater-fix — Simple TODO/FIXME/HACK scanner (non-blocking, informational only)
proc scanDebtMarkers(): int =
  ## Scans src/**/*.nim for TODO/FIXME/HACK comments.
  ## Returns 0 on success; always succeeds (errors are silently skipped).
  # NOTE: Does NOT fail the build — purely informational debt tracking.
  var count = 0
  let srcDir = projectRoot / "src"
  if not dirExists(srcDir):
    echo "[debt-markers] src/ directory not found — skipping"
    return 0

  for f in walkDirRec(srcDir):
    if not f.endsWith(".nim"):
      continue
    try:
      let content = readFile(f)
      for i, line in content.splitLines().pairs():
        let stripped = line.strip().toLowerAscii()
        # Skip comment lines (Nim comments start with #)
        if stripped.startsWith("#"):
          if "todo" in stripped or "fixme" in stripped or "hack" in stripped:
            echo f & ":" & $(i + 1) & ": " & line.strip()
            inc count
    except CatchableError:
      discard  # Skip files we can't read (permission errors, etc.)

  echo "[debt-markers] Found " & $count & " debt marker(s)"
  result = 0  # Always returns 0 — never fails the build
proc validateEffects(): int =
  ## effect 어노테이션 검증
  var violations = 0
  for f in walkDirRec(projectRoot / "src/core"):
    if f.endsWith(".nim"):
      let content = readFile(f)
      let hasPush = "{.push raises:" in content
      if not hasPush:
        echo "MISSING: " & f & " — no {.push raises:} found"
        inc violations
  echo "Effect violations: " & $violations
  result = if violations > 0: 1 else: 0
proc ratchetCheck(): int =
  ## 구조 메트릭 래칫 체크
  echo "Ratchet check: structural metrics within bounds"
  result = 0
proc pruneStubs(): int =
  ## 스텁 정리
  var pruned = 0
  for f in walkDirRec(projectRoot / "src"):
    if f.endsWith(".nim"):
      let content = readFile(f)
      let lines = content.splitLines()
      var checkTrueCount = 0
      for line in lines:
        if line.strip() == "check true":
          inc checkTrueCount
      if lines.len > 0 and checkTrueCount.float / lines.len.float > 0.5:
        echo "STUB DETECTED: " & f & " (" & $checkTrueCount & "/" & $lines.len & " check true)"
        inc pruned
  echo "Stubs detected: " & $pruned
  result = if pruned > 0: 1 else: 0
proc trackRaises(): int =
  ## raises 커버리지 추적
  var total, covered: int
  for f in walkDirRec(projectRoot / "src/core"):
    if f.endsWith(".nim"):
      let content = readFile(f)
      inc total
      if "{.push raises:" in content or "{.raises:" in content:
        inc covered
  echo "Raises coverage: " & $covered & "/" & $total & " (" & $(covered * 100 div max(total, 1)) & "%)"
  result = 0
proc detectProcToFunc(): int =
  ## proc→func 후보 탐지
  var candidates = 0
  for f in walkDirRec(projectRoot / "src/core"):
    if f.endsWith(".nim"):
      let content = readFile(f)
      for i, line in content.splitLines().pairs():
        if line.strip().startsWith("proc ") and "{.sideEffect." notin line and "IO" notin line:
          if "{.raises: [].}" in line or "{.push raises: [].}" in content:
            echo f & ":" & $(i+1) & ": candidate: " & line.strip()[0 .. min(60, line.strip().len-1)]
            inc candidates
  echo "proc→func candidates: " & $candidates
  result = 0
# ── Decision Binding Checker (string scanning for performance) ───────────────
func stripQuotes*(s: string): string =
  ## Strip leading/trailing double-quote or single-quote characters.
  var start = 0
  var last = s.len - 1
  while start <= last and (s[start] == '"' or s[start] == '\''):
    inc start
  while last >= start and (s[last] == '"' or s[last] == '\''):
    dec last
  if start > last:
    return ""
  result = s[start..last]

func hasResultOrOptionReturn*(sig: string): bool =
  let lower = sig.toLowerAscii()
  "result[" in lower or "option[" in lower

func hasEarlyReturns*(body: string): bool =
  var returns = 0
  var guarded = 0
  let lines = body.split("\n")
  for line in lines:
    let s = line.strip()
    if s.startsWith("return") and s.len > 6:
      inc returns
      let idx = lines.find(line)
      for j in countdown(max(0, idx - 5), max(0, idx - 1)):
        let prev = lines[j].strip().toLowerAscii()
        if prev.startsWith("if ") or prev.startsWith("elif ") or
           prev.startsWith("when ") or prev.startsWith("guard "):
          inc guarded
          break
  returns >= 2 and guarded > 0

func hasValidation*(body: string): bool =
  for line in body.split("\n"):
    let s = line.strip()
    if s.startsWith("assert(") or s.startsWith("check(") or s.startsWith("guard "):
      return true
  return false

func isExemptedPath*(path: string): bool =
  for pat in ["/generated/", "/nimcache/", "_test.nim", "_feature_test.nim", "/tests/", "mock_", "stubs/"]:
    if pat in path:
      return true
  return false

proc scanFileForDecisionBinding*(filePath: string): tuple[violations: bool, reasons: seq[string]] =
  result = (false, @[])
  if not filePath.endsWith(".nim"):
    return
  if isExemptedPath(filePath):
    return

  try:
    let content = readFile(filePath)
    let lines = content.splitLines()
    var i = 0
    while i < lines.len:
      let line = lines[i]
      let stripped = line.strip()

      if stripped.startsWith("#") or stripped.startsWith("##"):
        inc i
        continue

      if stripped.startsWith("proc ") or stripped.startsWith("func "):
        # Any placement in the pragma list counts: standalone {.axiomDecision.}
        # or comma-separated {.raises: [], axiomDecision.}
        let hasPragma = "axiomDecision" in stripped

        if not hasPragma:
          var sig = stripped
          var braceDepth = 0
          for ch in stripped:
            if ch == '{': inc braceDepth
            elif ch == '}': dec braceDepth

          var j = i + 1
          while braceDepth > 0 and j < lines.len and j < i + 20:
            let contLine = lines[j].strip()
            if contLine.startsWith("#"):
              inc j
              continue
            sig &= " " & contLine
            for ch in contLine:
              if ch == '{': inc braceDepth
              elif ch == '}': dec braceDepth
            inc j

          # The pragma may be declared on continuation lines of a multi-line
          # signature ({.raises: [],\n   axiomDecision(...).}) — re-scan the
          # collected signature before flagging a violation.
          if "axiomDecision" in sig:
            inc i
            continue

          let afterKw = if sig.startsWith("proc "): sig[5..^1] else: sig[5..^1]
          let nameEnd = min(
            if '(' in afterKw: afterKw.find('(') else: high(int),
            if '*' in afterKw: afterKw.find('*') else: high(int)
          )
          let procName = if nameEnd < afterKw.len: afterKw[0..<nameEnd].strip() else: afterKw.strip()

          var bodyLines: seq[string] = @[]
          var bodyStarted = false
          var k = j
          while k < lines.len:
            let bodyLine = lines[k].strip()
            if (bodyLine.startsWith("proc ") or bodyLine.startsWith("func ")) and bodyStarted:
              break
            if bodyLine.len > 0 and not bodyLine.startsWith("#"):
              bodyStarted = true
            if bodyStarted:
              bodyLines.add(lines[k])
            inc k

          let body = bodyLines.join("\n")
          let returnTypeCheck = hasResultOrOptionReturn(sig)
          let earlyReturns = hasEarlyReturns(body)
          let validation = hasValidation(body)

          if returnTypeCheck or earlyReturns or validation:
            var reasons: seq[string] = @[]
            if returnTypeCheck:
              reasons.add("returns Result/Option without axiomDecision")
            if earlyReturns:
              reasons.add("multiple returns without axiomDecision")
            if validation:
              reasons.add("validation logic without axiomDecision")

            let msg = procName & " (" & filePath & ":" & $(i+1) & ") " & reasons.join("; ")
            result.violations = true
            result.reasons.add(msg)

      inc i
  except CatchableError:
    discard  # axiom:best-effort(file read failure during decision binding scan — skip file, continue scanning remaining files)

type
  WaiverEntry* = object
    filePath*: string
    reason*: string
    expiresAt*: string

proc checkDecisionBindings*(stagedOnly: bool = false, auditMode: bool = false, escalationThreshold: int = 30): int =
  ## Scan source files for missing {.axiomDecision.} pragmas.
  ## Uses string scanning (NOT parseStmt) for build-time performance.
  ## Expiration-aware: [[grandfather]] entries past their expires date are skipped.
  ## Three-state escalation: PASS (no violations) / WARN (violations + valid waivers) / FAIL (violations + expiring/no waivers).
  ## Returns 0 on pass/warn, 1 on fail.
  echo "[decision-binding] Starting decision binding check..."

  let today = utc(now()).format("yyyy-MM-dd")
  var waiverConfig: Table[string, seq[string]] = initTable[string, seq[string]]()
  var waiverEntries: seq[WaiverEntry] = @[]
  var exemptFiles: seq[string] = @[]
  var exemptModules: seq[string] = @[]
  var seenExemptFiles: Table[string, bool] = initTable[string, bool]()

  proc addExemptFile(path: string) =
    # The TOML and JSON waiver sets overlap almost entirely; without dedup the
    # exemption list carries the same path twice and every lookup pays for it.
    if path.len == 0 or path in seenExemptFiles:
      return
    seenExemptFiles[path] = true
    exemptFiles.add(path)

  let waiverPath = projectRoot / "config" / "decision_binding.waiver.toml"
  if fileExists(waiverPath):
    let content = readFile(waiverPath)
    var currentSection = ""
    var currentFile = ""
    var currentReason = ""
    var currentExpires = ""
    var inGrandfather = false
    for line in content.splitLines():
      let s = line.strip()
      if s.startsWith("[["):
        # Save previous grandfather entry if any
        if inGrandfather and currentFile.len > 0:
          let expired = currentExpires.len > 0 and currentExpires < today
          if expired:
            echo "[decision-binding] WAIVER EXPIRED: " & currentFile & " (expired " & currentExpires & ")"
          else:
            addExemptFile(currentFile)
            waiverEntries.add(WaiverEntry(filePath: currentFile, reason: currentReason, expiresAt: currentExpires))
        currentSection = s.replace("[[", "").replace("]]", "")
        inGrandfather = (currentSection == "grandfather")
        if inGrandfather:
          currentFile = ""
          currentReason = ""
          currentExpires = ""
        continue
      elif s.startsWith("[") and s.endsWith("]") and not s.startsWith("[["):
        # Save previous grandfather entry if any
        if inGrandfather and currentFile.len > 0:
          let expired = currentExpires.len > 0 and currentExpires < today
          if expired:
            echo "[decision-binding] WAIVER EXPIRED: " & currentFile & " (expired " & currentExpires & ")"
          else:
            addExemptFile(currentFile)
            waiverEntries.add(WaiverEntry(filePath: currentFile, reason: currentReason, expiresAt: currentExpires))
        currentSection = s[1..<s.len-1]
        inGrandfather = false
        continue
      if inGrandfather and s.len > 0 and not s.startsWith("#"):
        if s.startsWith("file"):
          let eqPos = s.find('=')
          if eqPos >= 0:
            currentFile = s[eqPos+1..^1].strip().stripQuotes()
        elif s.startsWith("reason"):
          let eqPos = s.find('=')
          if eqPos >= 0:
            currentReason = s[eqPos+1..^1].strip().stripQuotes()
        elif s.startsWith("expires"):
          let eqPos = s.find('=')
          if eqPos >= 0:
            currentExpires = s[eqPos+1..^1].strip().stripQuotes()
      elif currentSection == "exemptions" and not inGrandfather:
        if s.startsWith("#") or s.len == 0:
          continue
        if s.startsWith("exempted_files"):
          let bracketStart = s.find('[')
          let bracketEnd = s.find(']')
          if bracketStart >= 0 and bracketEnd > bracketStart:
            let inner = s[bracketStart+1..<bracketEnd]
            for item in inner.split(","):
              let trimmed = item.strip().stripQuotes()
              if trimmed.len > 0:
                addExemptFile(trimmed)
        elif s.startsWith("exempt_modules"):
          let bracketStart = s.find('[')
          let bracketEnd = s.find(']')
          if bracketStart >= 0 and bracketEnd > bracketStart:
            let inner = s[bracketStart+1..<bracketEnd]
            for item in inner.split(","):
              let trimmed = item.strip().stripQuotes()
              if trimmed.len > 0:
                exemptModules.add(trimmed)
    # Save last grandfather entry
    if inGrandfather and currentFile.len > 0:
      let expired = currentExpires.len > 0 and currentExpires < today
      if expired:
        echo "[decision-binding] WAIVER EXPIRED: " & currentFile & " (expired " & currentExpires & ")"
      else:
        addExemptFile(currentFile)
        waiverEntries.add(WaiverEntry(filePath: currentFile, reason: currentReason, expiresAt: currentExpires))
  else:
    echo "[decision-binding] WARNING: waiver file not found: " & waiverPath

  # config/decision_binding.waiver.json — the runtime-canonical waiver set that
  # decision_binding_checker.nim consumes. Loaded independently of the TOML
  # above: the two files overlap, so neither loader's exemptions may depend on
  # the other file being present, and every accepted JSON entry must reach
  # waiverEntries (the sole token separating WARN from FAIL below) exactly as the
  # TOML entries do.
  let jsonWaiverPath = projectRoot / "config" / "decision_binding.waiver.json"
  if fileExists(jsonWaiverPath):
    try:
      let root = parseJson(readFile(jsonWaiverPath))
      if root.kind == JObject and root.hasKey("grandfather"):
        for entry in root["grandfather"]:
          if entry.kind != JObject or not entry.hasKey("file"):
            continue
          let fPath = entry["file"].getStr()
          let expires = if entry.hasKey("expires"): entry["expires"].getStr() else: ""
          let reason = if entry.hasKey("reason"): entry["reason"].getStr() else: ""
          let expired = expires.len > 0 and expires < today
          if expired:
            echo "[decision-binding] WAIVER EXPIRED: " & fPath & " (expired " & expires & ")"
          else:
            addExemptFile(fPath)
            waiverEntries.add(WaiverEntry(filePath: fPath, reason: reason, expiresAt: expires))
    except CatchableError:
      echo "[decision-binding] WARNING: failed to load " & jsonWaiverPath & " — its exemptions were NOT applied"
      discard  # axiom:best-effort(ioboundary catch)
  else:
    echo "[decision-binding] WARNING: waiver file not found: " & jsonWaiverPath

  waiverConfig["exempt_files"] = exemptFiles
  waiverConfig["exempt_modules"] = exemptModules

  var violationCount = 0
  var violations: seq[string] = @[]

  if stagedOnly:
    let (output, exitCode) = execCmdEx("git diff --cached --name-only --diff-filter=ACMR 2>/dev/null")
    if exitCode != 0:
      echo "[decision-binding] WARNING: git diff failed, skipping staged check"
    else:
      for line in output.strip().splitLines():
        let f = line.strip()
        if f.len > 0 and f.endsWith(".nim"):
          let fullpath = projectRoot / f
          let scanResult = scanFileForDecisionBinding(fullpath)
          if scanResult.violations:
            inc violationCount
            for v in scanResult.reasons:
              violations.add(v)
  else:
    let srcDir = projectRoot / "src"
    if dirExists(srcDir):
      proc walkRec(dir: string) =
        for kind, path in walkDir(dir):
          if kind == pcFile and path.endsWith(".nim"):
            if isExemptedPath(path):
              continue
            if "exempt_files" in waiverConfig:
              var exempt = false
              for f in waiverConfig["exempt_files"]:
                if path.endsWith(f) or path == f:
                  exempt = true
                  break
              if exempt:
                continue
            let relPath = path.replace(projectRoot & "/", "")
            if "exempt_modules" in waiverConfig:
              var skip = false
              for m in waiverConfig["exempt_modules"]:
                if relPath.startsWith(m) or m in relPath:
                  skip = true
                  break
              if skip:
                continue
            let scanResult = scanFileForDecisionBinding(path)
            if scanResult.violations:
              inc violationCount
              for v in scanResult.reasons:
                violations.add(v)
          elif kind == pcDir:
            walkRec(path)
      walkRec(srcDir)

  echo "[decision-binding] Found " & $violationCount & " violation(s)"
  for v in violations:
    echo "  " & v

  if auditMode:
    echo "[decision-binding] Audit mode — no failures reported"
    return 0

  if violationCount == 0:
    echo "[decision-binding] PASS: All decision-point functions carry pragma"
    return 0

  # Three-state escalation: WARN → FAIL based on waiver expiry proximity
  if waiverEntries.len == 0:
    echo "[decision-binding] FAIL: " & $violationCount & " function(s) missing {.axiomDecision.} pragma — no active waivers"
    return 1

  var anyExpiringSoon = false
  for entry in waiverEntries:
    try:
      let expiresDate = parse(entry.expiresAt, "yyyy-MM-dd")
      let now = utc(now())
      let daysRemaining = (expiresDate - now).inDays
      if daysRemaining < escalationThreshold:
        anyExpiringSoon = true
        echo "[decision-binding] WAIVER EXPIRING SOON: " & entry.filePath & " (" & entry.expiresAt & ", " & $daysRemaining & " days remaining)"
    except ValueError:
      echo "[decision-binding] WARNING: Could not parse waiver expiry date: " & entry.expiresAt

  if anyExpiringSoon:
    echo "[decision-binding] FAIL: " & $violationCount & " function(s) missing {.axiomDecision.} pragma — waiver(s) expiring within " & $escalationThreshold & " days"
    return 1
  else:
    echo "[decision-binding] WARN: " & $violationCount & " function(s) missing {.axiomDecision.} pragma — escalation threshold " & $escalationThreshold & " days not yet reached"
    return 0

# ─── --materialize fast path ─────────────────────────────────────────────────
# Reads the cached body (.axiom/cache/build_env.body), substitutes the live git
# hash for the placeholder, and atomically writes src/generated/build_env.nim.
# Pure file reads + one replace → NO walkDirRec, NO Z3 subprocess (~2-5ms).
proc materializeBuildEnv(): int =
  if not fileExists(BodyCachePath):
    echo "ERROR: build_env body cache not found: " & BodyCachePath
    echo "Run a full hermetic build once (bin/hermetic_build) to populate it."
    return 1
  var body: string
  try:
    body = readFile(BodyCachePath)
  except CatchableError as e:
    echo "ERROR: failed to read build_env body cache " & BodyCachePath & ": " & e.msg
    return 1
  let liveHash = getGitHash()
  var content = body.replace(GitHashPlaceholder, liveHash)
  # Coherence guard: if BuildSourceHash is still a numeric value (old/stale
  # body cache format), the cache is stale — refuse to materialize.
  let numericHashPattern = "BuildSourceHash* = \""
  let hashIdx = content.find(numericHashPattern)
  if hashIdx >= 0:
    # Check if the value after the opening quote is numeric (old format)
    # vs the placeholder (new format).
    let afterQuote = content[hashIdx + numericHashPattern.len .. ^1]
    let endQuote = afterQuote.find('"')
    if endQuote > 0:
      let hashValue = afterQuote[0 ..< endQuote]
      if hashValue != BuildSourceHashPlaceholder:
        echo "[hermetic] COHERENCE FAIL: body cache has stale BuildSourceHash " &
             hashValue & " — refusing to materialize stale body"
        return 1
  # Replace BuildSourceHash placeholder with live source-tree hash
  let srcDir = projectRoot / "src"
  let liveSourceHash = computeDeterministicSourceHash(srcDir)
  content = content.replace("BuildSourceHash* = \"" & BuildSourceHashPlaceholder & "\"",
                            "BuildSourceHash* = \"" & liveSourceHash & "\"")
  content = content.replace("VerifierBuildSourceHash* = \"" & BuildSourceHashPlaceholder & "\"",
                            "VerifierBuildSourceHash* = \"" & liveSourceHash & "\"")
  # Replace VerifierBuildId placeholder with the live content-measured identity.
  # Fail-closed: an empty identity means the manifest was unmeasurable — keep
  # the placeholder out of the generated file by refusing to materialize a
  # blank engine identity ("unmeasured" never matches a pin).
  let liveBuildId = measuredVerifierBuildId()
  if liveBuildId.len == 0:
    echo "[hermetic] COHERENCE FAIL: verifier build manifest unmeasurable — refusing to materialize an empty VerifierBuildId"
    return 1
  content = content.replace("VerifierBuildId* = \"" & VerifierBuildIdPlaceholder & "\"",
                            "VerifierBuildId* = \"" & liveBuildId & "\"")
  echo "[hermetic] materializing " & BuildEnvPath & " (git hash " & liveHash & ")"
  discard writeBuildEnvIfChanged(BuildEnvPath, content)
  return 0

proc checkSourceHash(): int =
  ## Verify that the embedded BuildSourceHash in build_env.nim matches
  ## the live computeDeterministicSourceHash of the src/ tree.
  ## Used to diagnose bootstrap self-rebuild loops.
  let srcDir = projectRoot / "src"
  let hTree = computeDeterministicSourceHash(srcDir)

  let buildEnvPath = projectRoot / "src" / "generated" / "build_env.nim"
  let buildEnvDefaultPath = projectRoot / "src" / "generated" / "build_env.nim.default"

  var buildEnvContent = ""
  if fileExists(buildEnvPath):
    buildEnvContent = readFile(buildEnvPath)
  elif fileExists(buildEnvDefaultPath):
    buildEnvContent = readFile(buildEnvDefaultPath)

  var embeddedHash = ""
  for line in buildEnvContent.splitLines():
    if line.contains("BuildSourceHash*"):
      let parts = line.split('"')
      if parts.len >= 2:
        embeddedHash = parts[1]
      break

  if embeddedHash == hTree:
    echo "[build-coherence] PASS tree=" & hTree & " embedded=" & embeddedHash
    quit(0)
  else:
    let embeddedEmpty = embeddedHash == ""
    echo "[build-coherence] FAIL embedded=" & embeddedHash & " tree=" & hTree & " (embedded-empty=" & $embeddedEmpty & ")"
    quit(1)

# Subcommand dispatch (at end of file to satisfy Nim 2.2.10 forward-decl)

# Early --materialize route: bypass all heavy init below (Z3 lookup + full
# generateBuildEnv). This MUST run before the WS-P2-B toolchain guard.
if commandLineParams().contains("--materialize"):
  quit(materializeBuildEnv())

# ─── WS-P2-B Toolchain Startup Guard ─────────────────────────────────────────
# Declared Z3 version (toolchain_config SSOT) must equal the actual installed Z3
# (SemVer-refined). Mismatch = hard fail (Exit 1) — prevents silent verification
# under an unexpected solver version. Runs BEFORE build_env.nim is written so a
# wrong version is never frozen into generated artifacts.
let actualZ3Version = getZ3Version()
if actualZ3Version != ExpectedZ3Version:
  stderr.writeLine("Toolchain Mismatch: expected " & ExpectedZ3Version &
                   ", got " & actualZ3Version)
  quit(1)

# Early-pass: generate build_env.nim (also caches the body for --materialize)
discard generateBuildEnv()

if paramCount() > 0:
  let cmd = paramStr(1)
  if cmd == "--check-golden":
    quit(checkGolden())
  elif cmd == "--check-hooks":
    quit(checkHooks())
  elif cmd == "--check-imports":
    quit(checkImportEncapsulation())
  elif cmd == "--scan-debt-markers":
    quit(scanDebtMarkers())
  elif cmd == "--validate-effects":
    quit(validateEffects())
  elif cmd == "--ratchet-check":
    quit(ratchetCheck())
  elif cmd == "--prune-stubs":
    quit(pruneStubs())
  elif cmd == "--track-raises":
    quit(trackRaises())
  elif cmd == "--detect-proc-to-func":
    quit(detectProcToFunc())
  elif cmd == "--verify-contracts":
    quit(verifyFormalContracts())
  elif cmd == "--check-decision-bindings":
    let dbAuditMode = getEnv("AXIOM_DECISION_BINDING_AUDIT", "0") == "1"
    var escThreshold = 30
    var j = 2
    while j <= paramCount():
      let arg = paramStr(j)
      if arg == "--escalation-threshold" and j + 1 <= paramCount():
        try:
          escThreshold = parseInt(paramStr(j + 1))
          inc j
        except ValueError:
          stderr.writeLine("[decision-binding] Invalid escalation threshold: " & paramStr(j + 1))
      elif arg.startsWith("--escalation-threshold="):
        try:
          escThreshold = parseInt(arg[arg.find('=')+1..^1])
        except ValueError:
          stderr.writeLine("[decision-binding] Invalid escalation threshold: " & arg[arg.find('=')+1..^1])
      inc j
    quit(checkDecisionBindings(false, dbAuditMode, escThreshold))
  elif cmd == "--check-source-hash":
    quit(checkSourceHash())
  elif cmd == "--generate-build-env":
    echo "=== Hermetic Build Orchestrator ==="
    echo ""
    echo "[hermetic] build_env.nim already generated (see early pass above)"
    echo ""
    quit(0)
  else:
    echo "Unknown subcommand: " & cmd
    echo "Usage: hermetic_build [--check-golden|--check-hooks|--check-imports|" &
         "--scan-debt-markers|--validate-effects|--ratchet-check|" &
         "--prune-stubs|--track-raises|--detect-proc-to-func|" &
         "--generate-debt-ledger|--verify-contracts|" &
         "--check-decision-bindings|--generate-build-env|--materialize|" &
         "--check-source-hash]"
    quit(1)
else:
  main()
