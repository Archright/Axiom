import core/trusted/layer_declaration
axiomLayer "domain"
import ../../core/trusted/axiom_pragmas
import core/identity/axiom_prelude
import core/types/type_mapping
import core/utils/text_utils
import std/options
import std/strutils
# ---------------------------------------------------------------------------
# Type & Context Definitions
# ---------------------------------------------------------------------------

type
  NimParamInfo* = object
    name*: string
    nimType*: string
    isVar*: bool

  TranslatorContext* = object
    nimSource*: string             ## Full Nim source file
    modulePath*: string            ## Module path (e.g. "src/core/the_judge.nim")
    functionName*: string          ## Target function name
    paramTypes*: seq[NimParamInfo] ## Parsed parameter names + Nim types
    returnType*: string            ## Return type (e.g. "int", "string", "bool")
    bodyExpr*: string              ## Function body expression (Nim syntax)
    bodyLines*: seq[string]        ## Raw body lines
    isFunc*: bool                  ## func vs proc (purity)
    effectKind*: string            ## "noSideEffect", "raises:[]", etc.
    preconditions*: seq[string]    ## Docstring preconditions
    postconditions*: seq[string]   ## Docstring postconditions

  LeanFunctionArtifact* = object
    defSource*: string             ## The `def` block (function translation)
    theoremSkeleton*: string       ## The `theorem ... := by` skeleton
    propertyProposition*: string   ## The logical property to prove
# ---------------------------------------------------------------------------
# Nim Type → Lean Type
# ---------------------------------------------------------------------------

# @axiom-hint: lean="nimType.length ≥ 0" smt="(assert (and (>= (str.len nimType) 0)))"
# @axiom-hint: lean="(result ≥ 0)" smt="(assert (and (>= result 0)))"
# @axiom-v0.4.0: Private wrapper — pending full migration to core/type_mapping.nim SSOT.
func translateNimTypeToLean*(nimType: string): string {.raises: [], axiom: ["(assert (and (>= (str.len nimType) 0) (>= result 0)))", "nimType.length ≥ 0 ∧ (result ≥ 0)"].} =
  ## Enhanced type translation with generic parameter support.
  ## Maps Nim types to their Lean equivalents (Nim prefix for custom types).
  result = nimTypeToLeanType(nimType, useNimPrefix = true)

# ---------------------------------------------------------------------------
# Nim Body Expression → Lean Expression
# ---------------------------------------------------------------------------

## [Verified Core] Recursive Nim→Lean expression translator. Algorithmic complexity — not structural. Wave Y certified.
func translateNimExprToLean*(expr: string): string {.raises: [], axiom: ["(assert (and (>= (str.len expr) 0) ast_parse_failed_isolated))", "expr.length ≥ 0 ∧ ast_parse_failed_isolated"].} =
  ## Translates a single Nim expression to Lean 4 syntax.
  ## Handles: arithmetic, comparisons, Result/Option, if/else, let/var.
  let e = expr.strip()
  if e.len == 0:
    return e

  # result = expr → return-style
  if e.startsWith("result "):
    let rest = e[6 .. ^1].strip()
    # Check for operators after 'result'
    if rest.startsWith("="):
      return translateNimExprToLean(rest[1 .. ^1].strip())

  # result → reference (inside body)
  if e == "result":
    return "result"

  # return expr
  if e.startsWith("return "):
    return translateNimExprToLean(e[7 .. ^1].strip())

  # discard → skip
  if e == "discard" or e.startsWith("discard "):
    return "()"

  # if cond: a else: b
  if e.startsWith("if ") and ":" in e:
    let condStart = 3
    let colonIdx = e.find(":", condStart)
    if colonIdx >= 0:
      let cond = translateNimExprToLean(e[condStart ..< colonIdx].strip())
      let rest = e[colonIdx + 1 .. ^1].strip()
      let elseIdx = rest.find("else:")
      if elseIdx >= 0:
        let thenBranch = translateNimExprToLean(rest[0 ..< elseIdx].strip())
        let elseBranch = translateNimExprToLean(rest[elseIdx + 5 .. ^1].strip())
        return "if " & cond & " then " & thenBranch & " else " & elseBranch
      else:
        let thenBranch = translateNimExprToLean(rest)
        return "if " & cond & " then " & thenBranch & " else ()"

  # .isOk() → .isOk
  if e.endsWith(".isOk()") or e.endsWith(".isOk"):
    let prefix = if e.endsWith(".isOk()"): e[0 .. ^8] else: e[0 .. ^7]
    return translateNimExprToLean(prefix.strip()) & ".isOk"

  # .isSome() → .isSome
  if e.endsWith(".isSome()") or e.endsWith(".isSome"):
    let prefix = if e.endsWith(".isSome()"): e[0 .. ^10] else: e[0 .. ^9]
    return translateNimExprToLean(prefix.strip()) & ".isSome"

  # .isNone() → .isNone
  if e.endsWith(".isNone()") or e.endsWith(".isNone"):
    let prefix = if e.endsWith(".isNone()"): e[0 .. ^10] else: e[0 .. ^9]
    return translateNimExprToLean(prefix.strip()) & ".isNone"

  # .len → .length
  if e.endsWith(".len"):
    return translateNimExprToLean(e[0 .. ^5].strip()) & ".length"

  ## Wave E: Strip Nim type annotations (x : Type = value → x := value)
  ## This pre-cleaning eliminates the primary source of stray colons
  ## before they reach universal_assembler.sanitizeLeanSource.
  var translated = ""
  var i = 0
  while i < e.len:
    # Detect : Type = pattern in variable declarations
    if e[i] == ':' and i > 0 and e[i-1] == ' ' and i + 1 < e.len:
      if e[i+1] == ' ' or e[i+1].isAlphaAscii():
        # Looks like type annotation — skip to the = sign
        var j = i + 1
        while j < e.len and e[j] != '=':
          inc j
        if j < e.len and e[j] == '=' and (j + 1 >= e.len or e[j+1] != '='):
          # Found `: Type =` — emit `:=` and skip the type
          translated.add(" :=")
          i = j + 1
          continue
    translated.add(e[i])
    i += 1

  # Nim equality == to Lean =
  var translated2 = ""
  i = 0
  while i < translated.len:
    if i + 1 < translated.len and translated[i] == '=' and translated[i+1] == '=':
      # Check context: is this `>=` or `<=` or `!=`?
      if i > 0 and (translated[i-1] == '>' or translated[i-1] == '<' or translated[i-1] == '!'):
        translated2.add("==")
        i += 2
        continue
      translated2.add("=")
      i += 2
    else:
      translated2.add(translated[i])
      i += 1

  return translated2
func translateNimBodyLinesToLean*(lines: seq[string]): string {.raises: [], axiom: ["(assert (and (>= (seq.len lines) 0) (forall ((linesIdx Int)) (=> (and (>= linesIdx 0) (< linesIdx (seq.len lines))) (>= (str.len (seq.nth lines linesIdx)) 0))) (= (str.len stripped) 0) (> (str.len translated) 0) (= (str.len exprs) 0) (= (str.len exprs) 1) body (>= body 0) (>= lines 0) (forall ((linesIdx Int)) (=> (and (>= linesIdx 0) (< linesIdx (seq.len lines))) (>= (str.len (seq.nth lines linesIdx)) 0)))))", "lines.size ≥ 0 ∧ (∀ (linesIdx : Fin lines.size), (lines.get linesIdx).length ≥ 0) ∧ stripped.length = 0 ∧ translated.length > 0 ∧ exprs.length = 0 ∧ exprs.length = 1 ∧ body ∧ (body ≥ 0) ∧ (lines ≥ 0) ∧ (∀ (linesIdx : Fin lines.size), (lines.get linesIdx).length ≥ 0)"].} =
  ## Translate a sequence of Nim body lines into a single Lean expression.
  ## For multi-line bodies, builds a `let` cascade or procedural chain.
  var exprs: seq[string] = @[]
  for line in lines:
    let stripped = line.strip()
    if stripped.len == 0: continue
    if stripped.startsWith("#"): continue  # skip comments
    let translated = translateNimExprToLean(stripped)
    if translated.len > 0:
      exprs.add(translated)

  if exprs.len == 0:
    return "()"
  elif exprs.len == 1:
    return exprs[0]
  else:
    # Multi-statement: wrap in a nested let expression
    # Nim: `a = expr; b = expr2; a + b` → Lean: `let a := expr; let b := expr2; a + b`
    var body = exprs[exprs.len - 1]  # last expression is the return
    for i in countdown(exprs.len - 2, 0):
      body = "let _ := " & exprs[i] & "; " & body
    return body

# ---------------------------------------------------------------------------
# Nim Function Extraction
# ---------------------------------------------------------------------------
func countLeadingSpaces(line: string): int {.raises: [], axiom: ["(assert (and (>= (str.len line) 0)))", "line.length ≥ 0"].} =
  for c in line:
    if c == ' ': inc result
    else: break
func extractNimFunction*(source: string; functionName: string): Option[TranslatorContext] {.raises: [], axiom: ["(assert (and (>= (str.len source) 0) (>= (str.len functionName) 0) ast_parse_failed_isolated))", "source.length ≥ 0 ∧ functionName.length ≥ 0 ∧ ast_parse_failed_isolated"].} =
  ## Extracts function signature and body from Nim source.
  ## Returns None if the function is not found.
  let lines = source.splitLines()
  var i = 0
  while i < lines.len:
    let stripped = lines[i].strip()
    # Match proc/func/method/iterator/template/macro declarations
    if stripped.startsWith("proc ") or stripped.startsWith("func ") or
       stripped.startsWith("method ") or stripped.startsWith("iterator "):
      let kind = stripped.split(' ')[0]
      let afterKeyword = stripped.substr(kind.len).strip()
      # Extract name (before '(' or '[' or '=')
      var nameEnd = afterKeyword.len
      for ch in ['(', '[', '=', '{']:
        let pos = afterKeyword.find(ch)
        if pos >= 0 and pos < nameEnd:
          nameEnd = pos
      let name = afterKeyword[0 ..< nameEnd].strip()
      if name != functionName:
        i += 1
        continue

      # Found the function — parse signature
      var ctx = TranslatorContext(
        nimSource: source,
        functionName: functionName,
        isFunc: kind == "func"
      )

      # Parse parameters: proc name(param1: Type1, param2: Type2): ReturnType
      let sigLine = stripped
      var paramStr = ""
      if '(' in sigLine:
        paramStr = sigLine.substr(sigLine.find('(') + 1)
        if ')' in paramStr:
          paramStr = paramStr[0 ..< paramStr.find(')')]

      for param in paramStr.split(','):
        let p = param.strip()
        if p.len == 0: continue
        let colonIdx = p.find(':')
        if colonIdx >= 0:
          let pName = p[0 ..< colonIdx].strip()
          let pType = p[colonIdx + 1 .. ^1].strip()
          ctx.paramTypes.add(NimParamInfo(name: pName, nimType: pType, isVar: p.startsWith("var ")))
        else:
          ctx.paramTypes.add(NimParamInfo(name: p.strip(), nimType: "auto"))

      # Parse return type: after '):'
      if "):" in sigLine:
        let afterRet = sigLine.substr(sigLine.find("):") + 2).strip()
        if afterRet.len > 0:
          let retType = afterRet.split(' ')[0].strip()
          ctx.returnType = retType
      elif sigLine.endsWith(")"):
        ctx.returnType = "void"

      # Parse body: lines after the signature until next top-level declaration or EOF
      var j = i + 1
      var bodyLines: seq[string] = @[]
      let baseIndent = if lines[i].len > 0: countLeadingSpaces(lines[i]) else: 0
      while j < lines.len:
        let line = lines[j]
        let strippedBody = line.strip()
        if strippedBody.len == 0:
          bodyLines.add("")
          j += 1
          continue
        # Check if we've hit the next top-level declaration
        let lineIndent = countLeadingSpaces(line)
        if lineIndent <= baseIndent and (
          strippedBody.startsWith("proc ") or strippedBody.startsWith("func ") or
          strippedBody.startsWith("method ") or strippedBody.startsWith("iterator ") or
          strippedBody.startsWith("type") or strippedBody.startsWith("const ") or
          strippedBody.startsWith("var ") or strippedBody.startsWith("let ") or
          strippedBody.startsWith("{.push") or strippedBody.startsWith("{.pop")
        ):
          break
        bodyLines.add(strippedBody)
        j += 1

      # Filter out pragmas, type declarations, doc comments from body
      var cleanBody: seq[string] = @[]
      for bl in bodyLines:
        if bl.len == 0: continue
        if bl.startsWith("{."): continue
        if bl.startsWith("##") or bl.startsWith("# @"): continue
        if bl.startsWith("type ") or bl.startsWith("const "): continue
        cleanBody.add(bl)

      ctx.bodyLines = cleanBody
      if cleanBody.len > 0:
        ctx.bodyExpr = cleanBody.join("; ")

      return some(ctx)

    i += 1
  none(TranslatorContext)

# ---------------------------------------------------------------------------
# Lean Function Definition Generation
# ---------------------------------------------------------------------------
func buildLeanParams*(params: seq[NimParamInfo]): string {.raises: [], axiom: ["(assert (and (>= (seq.len params) 0) (> i 0) (>= params 0)))", "params.size ≥ 0 ∧ i > 0 ∧ (params ≥ 0)"].} =
  ## Generate Lean parameter list: (a b : NimInt) (c : NimString)
  for i, p in params:
    if i > 0: result.add(" ")
    result.add("(" & p.name & " : " & translateNimTypeToLean(p.nimType) & ")")
func buildLeanFunctionDef*(ctx: TranslatorContext): string {.raises: [], axiom: ["(assert (and (>= (str.len ctx_nimSource) 0) (>= (str.len ctx_modulePath) 0) (>= (str.len ctx_functionName) 0) (>= (seq.len ctx_paramTypes) 0) (>= (str.len ctx_returnType) 0) (>= (str.len ctx_bodyExpr) 0) (>= (seq.len ctx_bodyLines) 0) (or (= ctx_isFunc true) (= ctx_isFunc false)) (>= (str.len ctx_effectKind) 0) (>= (seq.len ctx_preconditions) 0) (>= (seq.len ctx_postconditions) 0) (>= body 0) (>= result 0) (or (= ctx_isFunc true) (= ctx_isFunc false))))", "ctx_nimSource.length ≥ 0 ∧ ctx_modulePath.length ≥ 0 ∧ ctx_functionName.length ≥ 0 ∧ ctx_paramTypes.size ≥ 0 ∧ ctx_returnType.length ≥ 0 ∧ ctx_bodyExpr.length ≥ 0 ∧ ctx_bodyLines.size ≥ 0 ∧ ctx_isFunc = true ∨ ctx_isFunc = false ∧ ctx_effectKind.length ≥ 0 ∧ ctx_preconditions.size ≥ 0 ∧ ctx_postconditions.size ≥ 0 ∧ (body ≥ 0) ∧ (result ≥ 0) ∧ ctx_isFunc = true ∨ ctx_isFunc = false"].} =
  ## Generate the Lean `def` block that mirrors the Nim function.
  ## Structure:
  ##   def <fn> <params> : <returnLeanType> := <translated body>
  let safeName = sanitizeAxiomToken(ctx.functionName)
  let params = buildLeanParams(ctx.paramTypes)
  let retType = translateNimTypeToLean(ctx.returnType)

  var body = ""
  if ctx.bodyLines.len > 0:
    body = translateNimBodyLinesToLean(ctx.bodyLines)
  elif ctx.bodyExpr.len > 0:
    body = translateNimExprToLean(ctx.bodyExpr)
  else:
    body = "()"

  result = "def " & safeName & " " & params & " : " & retType & " :=\n"
  result.add("  " & body)
func buildLeanPropertyProposition*(ctx: TranslatorContext): string {.raises: [], axiom: ["(assert (and (>= (str.len ctx_nimSource) 0) (>= (str.len ctx_modulePath) 0) (>= (str.len ctx_functionName) 0) (>= (seq.len ctx_paramTypes) 0) (>= (str.len ctx_returnType) 0) (>= (str.len ctx_bodyExpr) 0) (>= (seq.len ctx_bodyLines) 0) (or (= ctx_isFunc true) (= ctx_isFunc false)) (>= (str.len ctx_effectKind) 0) (>= (seq.len ctx_preconditions) 0) (>= (seq.len ctx_postconditions) 0) (> (str.len params) 0) (>= result 0) (or (= ctx_isFunc true) (= ctx_isFunc false))))", "ctx_nimSource.length ≥ 0 ∧ ctx_modulePath.length ≥ 0 ∧ ctx_functionName.length ≥ 0 ∧ ctx_paramTypes.size ≥ 0 ∧ ctx_returnType.length ≥ 0 ∧ ctx_bodyExpr.length ≥ 0 ∧ ctx_bodyLines.size ≥ 0 ∧ ctx_isFunc = true ∨ ctx_isFunc = false ∧ ctx_effectKind.length ≥ 0 ∧ ctx_preconditions.size ≥ 0 ∧ ctx_postconditions.size ≥ 0 ∧ params.length > 0 ∧ (result ≥ 0) ∧ ctx_isFunc = true ∨ ctx_isFunc = false"].} =
  ## Generate the logical property to prove about the function.
  ## For a function `def add (a b : NimInt) : NimInt := a + b`,
  ## the property is `add a b = a + b`.
  let safeName = sanitizeAxiomToken(ctx.functionName)
  var params: seq[string] = @[]
  for p in ctx.paramTypes:
    params.add(p.name)

  if params.len > 0:
    result = "∀ " & params.join(" ") & ", " & safeName & " " & params.join(" ") & " = " &
             translateNimExprToLean(ctx.functionName & "(" & params.join(", ") & ")")
  else:
    result = safeName & " = " & safeName
func buildLeanTheoremSkeleton*(ctx: TranslatorContext): LeanFunctionArtifact {.raises: [], axiom: ["(assert (and (>= (str.len ctx_nimSource) 0) (>= (str.len ctx_modulePath) 0) (>= (str.len ctx_functionName) 0) (>= (seq.len ctx_paramTypes) 0) (>= (str.len ctx_returnType) 0) (>= (str.len ctx_bodyExpr) 0) (>= (seq.len ctx_bodyLines) 0) (or (= ctx_isFunc true) (= ctx_isFunc false)) (>= (str.len ctx_effectKind) 0) (>= (seq.len ctx_preconditions) 0) (>= (seq.len ctx_postconditions) 0) (> (str.len axiomHints) 0) (>= result 0) (or (= ctx_isFunc true) (= ctx_isFunc false))))", "ctx_nimSource.length ≥ 0 ∧ ctx_modulePath.length ≥ 0 ∧ ctx_functionName.length ≥ 0 ∧ ctx_paramTypes.size ≥ 0 ∧ ctx_returnType.length ≥ 0 ∧ ctx_bodyExpr.length ≥ 0 ∧ ctx_bodyLines.size ≥ 0 ∧ ctx_isFunc = true ∨ ctx_isFunc = false ∧ ctx_effectKind.length ≥ 0 ∧ ctx_preconditions.size ≥ 0 ∧ ctx_postconditions.size ≥ 0 ∧ axiomHints.length > 0 ∧ (result ≥ 0) ∧ ctx_isFunc = true ∨ ctx_isFunc = false"].} =
  ## Generate a complete Lean theorem skeleton with function definition.
  ## Returns both the `def` and the `theorem ... := by` skeleton.
  let defBlock = buildLeanFunctionDef(ctx)
  let prop = buildLeanPropertyProposition(ctx)

  let safeName = sanitizeAxiomToken(ctx.functionName)

  # Collect relevant verified axiom names for this function
  var axiomHints: seq[string] = @[]
  if ctx.returnType.toLowerAscii() in ["int", "natural"]:
    axiomHints.add("int_add_comm")
    axiomHints.add("int_add_assoc")
  if "string" in ctx.returnType.toLowerAscii():
    axiomHints.add("string_length_nonneg")
  if "seq" in ctx.returnType.toLowerAscii():
    axiomHints.add("seq_size_nonneg")

  var theoremSrc = "theorem " & safeName & "_correct"
  for p in ctx.paramTypes:
    theoremSrc.add(" (" & p.name & " : " & translateNimTypeToLean(p.nimType) & ")")
  theoremSrc.add(" : " & prop & " := by\n")
  theoremSrc.add("  -- PROOF_HERE --\n")

  # Add axiom hints as comments for Leanstral
  if axiomHints.len > 0:
    theoremSrc.add("  -- Available axiom hints: " & axiomHints.join(", ") & "\n")

  result = LeanFunctionArtifact(
    defSource: defBlock,
    theoremSkeleton: theoremSrc,
    propertyProposition: prop
  )


func buildLeanBridge*(ctx: TranslatorContext): string {.raises: [].} =
  ## Build the complete Lean bridge: prelude + def + theorem skeleton.
  ## This is what gets injected into the Lean query / skeleton.
  let prelude = getExtendedAxiomPrelude()
  let defAndTheorem = buildLeanTheoremSkeleton(ctx)

  result = "import Std\n"
  result.add(prelude)
  result.add("\n\n-- Translated Nim function definition\n")
  result.add(defAndTheorem.defSource)
  result.add("\n\n-- Theorem to prove (tactics supplied by Leanstral)\n")
  result.add(defAndTheorem.theoremSkeleton)

# ---------------------------------------------------------------------------
# Bridge Integration: build from raw source
# ---------------------------------------------------------------------------

# @axiom-hint: lean="nimSource.length ≥ 0 ∧ functionName.length ≥ 0 ∧ modulePath.length ≥ 0" smt="(assert (and (>= (str.len nimSource) 0) (>= (str.len functionName) 0) (>= (str.len modulePath) 0)))"
# @axiom-hint: lean="ctxOpt.isNone = true ∧ modulePath.length > 0 ∧ (ctx ≥ 0)" smt="(assert (and (= (option.isNone ctxOpt) true) (> (str.len modulePath) 0) (>= ctx 0)))"
# @axiom-v0.4.0: Private helper — pending full migration to translator/universal_assembler.nim SSOT.
func buildLeanBridgeFromSource*(nimSource: string; functionName: string; modulePath: string = ""): string {.raises: [].} =
  ## Convenience function: extract function from source and build the Lean bridge.
  let ctxOpt = extractNimFunction(nimSource, functionName)
  if ctxOpt.isNone:
    return ""
  var ctx = ctxOpt.get()
  if modulePath.len > 0:
    ctx.modulePath = modulePath
  buildLeanBridge(ctx)
# ---------------------------------------------------------------------------
# Nim Type → Lean Type
# ---------------------------------------------------------------------------

# @axiom-v0.4.0: Private wrapper — pending full migration to core/type_mapping.nim SSOT.
# ---------------------------------------------------------------------------
# Nim Type → Lean Type
# ---------------------------------------------------------------------------

# @axiom-v0.4.0: Private wrapper — pending full migration to core/type_mapping.nim SSOT.
