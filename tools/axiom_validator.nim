## tools/axiom_validator.nim
## L1 of the 5-Layer Defense Stack.
## Uses Nim's compiler/parser API to parse source files into Raw AST (PNode tree)
## at the parser level — before macro expansion. Standalone tool (no compilation needed).
##
## Complementary to L2 (enforce_structural_safety.nim) which operates on expanded AST.
##
## Usage:
##   nim c --hints:off -d:release -d:useMalloc -o:bin/axiom_validator tools/axiom_validator.nim
##   bin/axiom_validator --file src/core/gateway.nim
##   bin/axiom_validator --dir src/ --json --verbose

import core/trusted/layer_declaration
axiomLayer "tools"
import compiler/[ast, parser, options, llstream, idents, pathutils]
import std/[os, strutils, strformat, json, algorithm, sets, tables]
import shared/[layer_dag, import_tokenizer, effect_classifier, magic_allowlist]

{.push raises: [].}

# ─── Types ───────────────────────────────────────────────────────────────

type
  ViolationKind = enum
    vkImportBoundary    ## Layer DAG violation
    vkMissingEffect     ## proc missing {.axiomEffect.}
    vkCastNoSideEffect  ## cast(noSideEffect) outside core/pure
    vkImportC           ## importc outside core/pure
    vkFileTooLong       ## >500 lines

  Violation = object
    kind: ViolationKind
    message: string
    line: int
    column: int

  ProcInfo = object
    name: string
    kind: string       ## "proc", "func", "method", "iterator", "template"
    line: int
    hasAxiomEffect: bool

  PragmaInfo = object
    target: string
    name: string
    value: string
    line: int

  ValidationResult = object
    file: string
    layer: string
    lineCount: int
    imports: seq[string]
    procs: seq[ProcInfo]
    typeDefs: seq[string]
    pragmas: seq[PragmaInfo]
    violations: seq[Violation]
    warnings: seq[Violation]

# ─── PNode Helpers ───────────────────────────────────────────────────────

func extractName(n: PNode): string {.raises: [].} =
  if n.isNil: return ""
  case n.kind
  of nkIdent: n.ident.s
  of nkPostfix:
    if n.len >= 2: extractName(n[1])
    else: ""
  of nkAccQuoted:
    if n.len >= 1: extractName(n[0])
    else: ""
  of nkSym: n.sym.name.s
  of nkStrLit..nkTripleStrLit: n.strVal
  else: ""

func nodeToString(n: PNode): string {.raises: [].} =
  if n.isNil: return ""
  case n.kind
  of nkIdent: n.ident.s
  of nkSym: n.sym.name.s
  of nkStrLit..nkTripleStrLit: "\"" & n.strVal & "\""
  of nkIntLit..nkInt64Lit: $n.intVal
  of nkFloatLit..nkFloat64Lit: $n.floatVal
  of nkNilLit: "nil"
  of nkDotExpr:
    if n.len >= 2: nodeToString(n[0]) & "." & nodeToString(n[1])
    else: ""
  of nkBracketExpr:
    if n.len >= 2: nodeToString(n[0]) & "[" & nodeToString(n[1]) & "]"
    else: ""
  of nkInfix:
    if n.len >= 3 and extractName(n[0]) == "/":
      nodeToString(n[1]) & "/" & nodeToString(n[2])
    else:
      var parts: seq[string]
      for i in 0 ..< n.len:
        parts.add(nodeToString(n[i]))
      parts.join(" ")
  of nkPrefix:
    if n.len >= 2: extractName(n[0]) & nodeToString(n[1])
    else: ""
  of nkCall:
    if n.len >= 1: nodeToString(n[0]) & "(" & ")"
    else: ""
  of nkPostfix:
    if n.len >= 2: extractName(n[0]) & nodeToString(n[1])
    else: ""
  of nkStmtList: ""
  else: ""

func collectImportPath(n: PNode): string {.raises: [].} =
  ## Build a flat path string from an import node.
  if n.isNil: return ""
  case n.kind
  of nkIdent: n.ident.s
  of nkSym: n.sym.name.s
  of nkDotExpr: collectImportPath(n[0]) & "." & collectImportPath(n[1])
  of nkAccQuoted: collectImportPath(n[0])
  of nkInfix:
    if n.len >= 3 and extractName(n[0]) == "/":
      collectImportPath(n[1]) & "/" & collectImportPath(n[2])
    else: nodeToString(n)
  of nkPostfix:
    if n.len >= 2: collectImportPath(n[1])
    else: nodeToString(n)
  else: nodeToString(n)

# ─── File Parsing ────────────────────────────────────────────────────────

proc parseNimFile(path: string): PNode {.raises: [].} =
  ## Parse a Nim source file using the compiler/parser API (L1: pre-macro).
  let cache = newIdentCache()
  let config = newConfigRef()
  var topNode: PNode = nil
  try:
    # openParser raises generic Exception — cast(raises: []) per §7.
    # Only CatchableError is caught; Defect descendants are not swallowed.
    {.cast(raises: []).}:
      let absFile = AbsoluteFile(path)
      var stream = llStreamOpen(absFile, fmRead)
      var parser: Parser
      openParser(parser, absFile, stream, cache, config)
      topNode = parseAll(parser)
      closeParser(parser)
  except CatchableError:
    discard  # axiom:best-effort(parser failure)
  topNode

# ─── AST Extraction ──────────────────────────────────────────────────────

func safeLen(n: PNode): int {.inline.} =
  ## Safe child-count for PNode — returns 0 for leaf kinds (nkIdent, nkSym,
  ## nkStrLit, etc.) where accessing `sons` raises FieldDefect (Nim 2.x
  ## variant object). Only branch kinds actually store children.
  if n.isNil: return 0
  case n.kind
  of nkIdent, nkSym, nkType, nkNone, nkEmpty, nkCommentStmt,
     nkCharLit..nkUInt64Lit, nkFloatLit..nkFloat128Lit,
     nkStrLit..nkTripleStrLit, nkNilLit:
    0
  else:
    n.len  # safe: only branch nodes reach here

func extractImports(root: PNode): seq[string] {.raises: [].} =
  var acc: seq[string] = @[]
  proc walk(n: PNode) =
    if n.isNil: return
    case n.kind
    of nkImportStmt:
      for i in 0 ..< n.len:
        let modPath = collectImportPath(n[i])
        if modPath.len > 0: acc.add(modPath)
    of nkFromStmt:
      if n.len >= 1:
        let modPath = collectImportPath(n[0])
        if modPath.len > 0: acc.add(modPath)
    of nkImportExceptStmt:
      if n.len >= 1:
        let modPath = collectImportPath(n[0])
        if modPath.len > 0: acc.add(modPath)
    of nkIncludeStmt:
      for i in 0 ..< n.len:
        let modPath = collectImportPath(n[i])
        if modPath.len > 0: acc.add(modPath)
    else: discard
    for i in 0 ..< safeLen(n):
      walk(n[i])
  walk(root)
  acc

func extractProcs(root: PNode): seq[ProcInfo] {.raises: [].} =
  var acc: seq[ProcInfo] = @[]
  proc walk(n: PNode) =
    if n.isNil: return
    case n.kind
    of nkProcDef, nkFuncDef, nkMethodDef, nkIteratorDef:
      if n.len >= 5:
        let name = extractName(n[0])
        let kindStr = case n.kind
          of nkProcDef: "proc"
          of nkFuncDef: "func"
          of nkMethodDef: "method"
          of nkIteratorDef: "iterator"
          else: "unknown"
        var hasEffect = false
        let pragmaNode = n[4]
        if not pragmaNode.isNil and pragmaNode.kind == nkPragma:
          for i in 0 ..< pragmaNode.len:
            let p = pragmaNode[i]
            if p.kind == nkExprColonExpr and p.len >= 2:
              if extractName(p[0]) == "axiomEffect":
                hasEffect = true
            elif p.kind == nkIdent:
              if p.ident.s == "axiomEffect":
                hasEffect = true
        if name.len > 0:
          acc.add(ProcInfo(
            name: name, kind: kindStr,
            line: n.info.line.int, hasAxiomEffect: hasEffect))
    of nkTemplateDef:
      if n.len >= 5:
        let name = extractName(n[0])
        if name.len > 0:
          acc.add(ProcInfo(
            name: name, kind: "template",
            line: n.info.line.int, hasAxiomEffect: false))
    else: discard
    for i in 0 ..< safeLen(n):
      walk(n[i])
  walk(root)
  acc

func extractTypeDefs(root: PNode): seq[string] {.raises: [].} =
  var acc: seq[string] = @[]
  proc walk(n: PNode) =
    if n.isNil: return
    if n.kind == nkTypeSection:
      for i in 0 ..< n.len:
        let child = n[i]
        if child.kind == nkTypeDef and child.len >= 1:
          let name = extractName(child[0])
          if name.len > 0: acc.add(name)
    for i in 0 ..< safeLen(n):
      walk(n[i])
  walk(root)
  acc

func extractPragmas(root: PNode): seq[PragmaInfo] {.raises: [].} =
  var acc: seq[PragmaInfo] = @[]
  proc walk(n: PNode) =
    if n.isNil: return
    case n.kind
    of nkProcDef, nkFuncDef, nkMethodDef, nkIteratorDef:
      if n.len >= 5:
        let target = extractName(n[0])
        let pragmaNode = n[4]
        if not pragmaNode.isNil and pragmaNode.kind == nkPragma:
          for i in 0 ..< pragmaNode.len:
            let p = pragmaNode[i]
            var pname = ""
            var pvalue = ""
            if p.kind == nkExprColonExpr and p.len >= 2:
              pname = extractName(p[0])
              pvalue = nodeToString(p[1])
            elif p.kind == nkIdent:
              pname = p.ident.s
            if pname.len > 0:
              acc.add(PragmaInfo(
                target: target, name: pname,
                value: pvalue, line: p.info.line.int))
    of nkPragmaExpr:
      # Type pragmas via nkPragmaExpr
      if n.len >= 2 and n[1].kind == nkPragma:
        let target = extractName(n[0])
        let pragmaNode = n[1]
        for i in 0 ..< pragmaNode.len:
          let p = pragmaNode[i]
          var pname = ""
          var pvalue = ""
          if p.kind == nkExprColonExpr and p.len >= 2:
            pname = extractName(p[0])
            pvalue = nodeToString(p[1])
          elif p.kind == nkIdent:
            pname = p.ident.s
          if pname.len > 0:
            acc.add(PragmaInfo(
              target: target, name: pname,
              value: pvalue, line: p.info.line.int))
    else: discard
    for i in 0 ..< safeLen(n):
      walk(n[i])
  walk(root)
  acc

# ─── Violation Detection ─────────────────────────────────────────────────

func detectCastNoSideEffect(root: PNode): seq[Violation] {.raises: [].} =
  ## Detect cast(noSideEffect) usage outside core/pure/.
  var acc: seq[Violation] = @[]
  proc walk(n: PNode) =
    if n.isNil: return
    # Pattern: cast(noSideEffect(...)) or cast(noSideEffect[...])
    if n.kind == nkCall and n.len >= 2:
      let callee = extractName(n[0])
      if callee == "cast" and n.len >= 2:
        let arg = n[1]
        # cast(noSideEffect(...)) — bracket expression
        if arg.kind == nkBracketExpr and arg.len >= 1:
          let innerName = extractName(arg[0])
          if innerName == "noSideEffect":
            acc.add(Violation(
              kind: vkCastNoSideEffect,
              message: "cast(noSideEffect) detected — forbidden outside core/pure/",
              line: n.info.line.int,
              column: n.info.col.int + 1))
        # cast(noSideEffect) — direct ident (no brackets)
        elif arg.kind == nkIdent and arg.ident.s == "noSideEffect":
          acc.add(Violation(
            kind: vkCastNoSideEffect,
            message: "cast(noSideEffect) detected — forbidden outside core/pure/",
            line: n.info.line.int,
            column: n.info.col.int + 1))
    for i in 0 ..< safeLen(n):
      walk(n[i])
  walk(root)
  acc

func detectImportCPragma(root: PNode): seq[Violation] {.raises: [].} =
  ## Detect importc pragma usage outside core/pure/.
  var acc: seq[Violation] = @[]
  proc walk(n: PNode) =
    if n.isNil: return
    case n.kind
    of nkPragma:
      for i in 0 ..< n.len:
        let pname = extractName(n[i])
        if pname == "importc":
          acc.add(Violation(
            kind: vkImportC,
            message: "importc pragma detected — forbidden outside core/pure/",
            line: n.info.line.int,
            column: n.info.col.int + 1))
    else: discard
    for i in 0 ..< safeLen(n):
      walk(n[i])
  walk(root)
  acc

# ─── Layer Detection ─────────────────────────────────────────────────────

func determineLayer(filePath: string; dag: LayerDag): string {.raises: [].} =
  ## Determine which layer a file belongs to. Uses layer_dag if available,
  ## falls back to path prefix matching.
  let fromDag = getLayer(filePath, dag)
  if fromDag.len > 0: return fromDag

  # Fallback: prefix matching
  let normalized = filePath.replace("\\", "/")
  if normalized.startsWith("src/core"): "core"
  elif normalized.startsWith("src/cli"): "cli"
  elif normalized.startsWith("src/mcp"): "mcp"
  elif normalized.startsWith("src/verification"): "verification"
  elif normalized.startsWith("src/gate"): "gate"
  elif normalized.startsWith("src/api"): "api"
  elif normalized.startsWith("src/engine"): "engine"
  elif normalized.startsWith("src/frontend"): "frontend"
  elif normalized.startsWith("tools"): "tools"
  else: ""

func isPureSubDomain(filePath: string): bool =
  ## Check if file is in src/core/pure/ — exempt from importc/cast rules.
  let normalized = filePath.replace("\\", "/")
  normalized.startsWith("src/core/pure/") or normalized == "src/core/pure"

# ─── Validation Engine ───────────────────────────────────────────────────

proc validateFile(filePath: string; dag: LayerDag): ValidationResult =
  let layer = determineLayer(filePath, dag)

  # Count lines
  var lineCount = 0
  try:
    let content = readFile(filePath)
    lineCount = content.splitLines().len
  except IOError:
    discard

  # Parse the file
  let root = parseNimFile(filePath)

  # Extract facts from PNode tree
  let imports = if root != nil: extractImports(root) else: @[]
  let procs = if root != nil: extractProcs(root) else: @[]
  let typeDefs = if root != nil: extractTypeDefs(root) else: @[]
  let pragmas = if root != nil: extractPragmas(root) else: @[]

  result = ValidationResult(
    file: filePath,
    layer: layer,
    lineCount: lineCount,
    imports: imports,
    procs: procs,
    typeDefs: typeDefs,
    pragmas: pragmas,
    violations: @[],
    warnings: @[])

  # ── Rule 1: Import boundary check (layer DAG) ──────────────────────
  for imp in imports:
    # Skip std, pkg, compiler, and external prefixes
    let firstSeg = imp.split(".")[0].split("/")[0]
    if firstSeg in ["std", "pkg", "checksums", "malebolgia",
                     "compiler", "fusion", "nimcrypto"]:
      continue
    # Determine target layer from import path
    let targetLayer = getLayer(imp, dag)
    if targetLayer.len > 0 and layer.len > 0 and targetLayer != layer:
      if not dag.isAllowed(layer, targetLayer):
        result.violations.add(Violation(
          kind: vkImportBoundary,
          message: fmt"Import boundary: {layer} → {targetLayer} (via {imp})",
          line: 0, column: 0))

  # ── Rule 2: Effect annotation presence ─────────────────────────────
  # Procs in core/gate/verification layers should have {.axiomEffect.}
  for p in procs:
    if p.kind in ["proc", "func"] and not p.hasAxiomEffect:
      if layer in ["core", "gate", "verification"]:
        result.warnings.add(Violation(
          kind: vkMissingEffect,
          message: fmt"{p.kind} '{p.name}' missing {{.axiomEffect.}} pragma",
          line: p.line, column: 0))

  # ── Rule 3: File length check ──────────────────────────────────────
  if lineCount > 500:
    result.warnings.add(Violation(
      kind: vkFileTooLong,
      message: fmt"File has {lineCount} lines (>500 threshold)",
      line: 0, column: 0))

  # ── Rule 4: cast(noSideEffect) detection ───────────────────────────
  if root != nil:
    let csViolations = detectCastNoSideEffect(root)
    for v in csViolations:
      if not isPureSubDomain(filePath):
        result.violations.add(v)

  # ── Rule 5: importc detection ──────────────────────────────────────
  if root != nil:
    let icViolations = detectImportCPragma(root)
    for v in icViolations:
      if not isPureSubDomain(filePath):
        result.violations.add(v)

# ─── JSON Serialization ──────────────────────────────────────────────────

func violationKindStr(k: ViolationKind): string =
  case k
  of vkImportBoundary: "import_boundary"
  of vkMissingEffect: "missing_effect"
  of vkCastNoSideEffect: "cast_no_side_effect"
  of vkImportC: "importc"
  of vkFileTooLong: "file_too_long"

func toJson(v: Violation): JsonNode =
  result = newJObject()
  result["kind"] = newJString(violationKindStr(v.kind))
  result["message"] = newJString(v.message)
  if v.line > 0: result["line"] = newJInt(v.line)
  if v.column > 0: result["column"] = newJInt(v.column)

func toJson(p: ProcInfo): JsonNode =
  result = newJObject()
  result["name"] = newJString(p.name)
  result["kind"] = newJString(p.kind)
  result["line"] = newJInt(p.line)
  result["hasAxiomEffect"] = newJBool(p.hasAxiomEffect)

func toJson(r: ValidationResult): JsonNode =
  result = newJObject()
  result["file"] = newJString(r.file)
  result["layer"] = newJString(r.layer)
  result["lineCount"] = newJInt(r.lineCount)

  var importsArr = newJArray()
  for imp in r.imports: importsArr.add(newJString(imp))
  result["imports"] = importsArr

  var procsArr = newJArray()
  for p in r.procs: procsArr.add(toJson(p))
  result["procs"] = procsArr

  var typesArr = newJArray()
  for t in r.typeDefs: typesArr.add(newJString(t))
  result["typeDefs"] = typesArr

  var violationsArr = newJArray()
  for v in r.violations: violationsArr.add(toJson(v))
  result["violations"] = violationsArr

  var warningsArr = newJArray()
  for w in r.warnings: warningsArr.add(toJson(w))
  result["warnings"] = warningsArr

func toJson(results: seq[ValidationResult]): JsonNode =
  result = newJObject()
  var filesArr = newJArray()
  for r in results: filesArr.add(toJson(r))
  result["files"] = filesArr

  var totalViolations = 0
  var totalWarnings = 0
  for r in results:
    totalViolations += r.violations.len
    totalWarnings += r.warnings.len

  result["summary"] = %*{
    "totalFiles": results.len,
    "totalViolations": totalViolations,
    "totalWarnings": totalWarnings
  }

{.pop.} # end of raises:[] block — CLI is I/O boundary

# ─── CLI ─────────────────────────────────────────────────────────────────

proc parseArgs(): tuple[file: string, dir: string,
                        jsonOut: bool, verbose: bool] =
  result = ("", "", false, false)
  var i = 1
  while i <= paramCount():
    let p = paramStr(i)
    if p == "--file":
      inc i
      if i <= paramCount(): result.file = paramStr(i)
    elif p.startsWith("--file="):
      result.file = p[7..^1]
    elif p == "--dir":
      inc i
      if i <= paramCount(): result.dir = paramStr(i)
    elif p.startsWith("--dir="):
      result.dir = p[6..^1]
    elif p == "--json":
      result.jsonOut = true
    elif p == "--verbose":
      result.verbose = true
    elif p == "--help" or p == "-h":
      echo "axiom_validator — L1 Architecture Validator (pre-macro AST)"
      echo ""
      echo "Usage:"
      echo "  axiom_validator --file path.nim"
      echo "  axiom_validator --dir src/ [--json] [--verbose]"
      echo ""
      echo "Options:"
      echo "  --file PATH     Validate a single .nim file"
      echo "  --dir PATH      Validate all .nim files in directory (recursive)"
      echo "  --json          Output JSON (default for --dir)"
      echo "  --verbose       Include warnings in output"
      echo "  --help, -h      Show this help"
      echo ""
      echo "Rules enforced:"
      echo "  1. Import boundary check (layer DAG from architecture_policy.lock)"
      echo "  2. Effect annotation presence ({.axiomEffect.} on proc/func)"
      echo "  3. File length check (>500 lines → warning)"
      echo "  4. cast(noSideEffect) detection (forbidden outside core/pure/)"
      echo "  5. importc detection (forbidden outside core/pure/)"
      quit(0)
    inc i

# ─── Main ────────────────────────────────────────────────────────────────

proc main() =
  let args = parseArgs()

  if args.file.len == 0 and args.dir.len == 0:
    echo "Error: specify --file or --dir. Use --help for usage."
    quit(1)

  # Load layer DAG from architecture_policy.lock
  var dag = LayerDag(
    edges: initTable[string, seq[string]](),
    layerPaths: initTable[string, string]())
  let lockPath = "src/gate/architecture_policy.lock"
  if fileExists(lockPath):
    try:
      dag = parseLayerEdges(readFile(lockPath))
    except IOError:
      discard

  var results: seq[ValidationResult] = @[]

  if args.file.len > 0:
    if not fileExists(args.file):
      echo "Error: file not found: " & args.file
      quit(1)
    results.add(validateFile(args.file, dag))
  elif args.dir.len > 0:
    if not dirExists(args.dir):
      echo "Error: directory not found: " & args.dir
      quit(1)
    var nimFiles: seq[string] = @[]
    for entry in walkDirRec(args.dir):
      if entry.endsWith(".nim"):
        nimFiles.add(entry)
    nimFiles.sort()
    for f in nimFiles:
      results.add(validateFile(f, dag))

  # Output
  let useJson = args.jsonOut or args.dir.len > 0
  if useJson:
    echo toJson(results).pretty()
  else:
    for r in results:
      echo "=== " & r.file & " ==="
      echo "  Layer:  " & r.layer
      echo "  Lines:  " & $r.lineCount
      echo "  Imports: " & $r.imports.len
      echo "  Procs:  " & $r.procs.len
      echo "  Types:  " & $r.typeDefs.len
      echo ""

      if r.violations.len > 0:
        echo "  VIOLATIONS (" & $r.violations.len & "):"
        for v in r.violations:
          let loc = if v.line > 0: ":" & $v.line else: ""
          echo "    [" & violationKindStr(v.kind) & "] " & v.message & loc
      if args.verbose and r.warnings.len > 0:
        echo "  WARNINGS (" & $r.warnings.len & "):"
        for w in r.warnings:
          let loc = if w.line > 0: ":" & $w.line else: ""
          echo "    [" & violationKindStr(w.kind) & "] " & w.message & loc

      if r.violations.len == 0 and (not args.verbose or r.warnings.len == 0):
        echo "  OK No violations"
      echo ""

  # Exit code: non-zero if any violations
  for r in results:
    if r.violations.len > 0:
      quit(1)

main()
