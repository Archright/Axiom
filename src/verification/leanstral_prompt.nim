import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

import ../core/trusted/axiom_pragmas
import core/frontend_ir
import core/contracts/universal_pipeline_contract
import core/identity/axiom_prelude
import core/results
import core/utils/io_utils
import core/utils/text_utils
import core/vault/vault_manager_spec
import core/vault/vault_manager_storage
import frontend/nim/nim_frontend
import std/os
import std/strutils
import verification/lean_hint_db
# axiomIoBoundary

type
  LeanstralPromptContext* = object
    modulePath*: string
    functionName*: string
    sourceContext*: string
    unsatCore*: seq[string]
    vaultHistory*: seq[string]
    kernelFeedback*: string
    proofGoal*: string
    axiomIr*: string  # Wave 3.5: language-neutral IR representation
    # Tactic Backtrack Engine: goal-aware fields
    currentGoals*: seq[string]     ## Current Lean goals from LSP hover
    goalDelta*: string             ## Serialized GoalDelta JSON (resolved/new/unchanged)
    priorTactics*: seq[string]     ## Tactics already tried (to avoid repetition)
func stripComments(source: string): string {.raises: [], axiom: ["(assert (and (>= (str.len source) 0) (< i (str.len source)) (= inComment true) (= inComment false) (>= inComment 0) (and (>= i 0) (< i source))))", "source.length ≥ 0 ∧ i < source.length ∧ inComment = true ∧ inComment = false ∧ (inComment ≥ 0) ∧ ((i ≥ 0) ∧ (i < source))"].} =
  var inComment = false
  var i = 0
  while i < source.len:
    if not inComment and i + 1 < source.len and source[i] == '#' and source[i+1] == '#':
      inComment = true
      i += 2
      continue
    if inComment and source[i] == '\n':
      inComment = false
    if not inComment:
      result.add(source[i])
    i += 1
## Extract Function Signature.
# @axiom-hint: lean="modulePath.length ≥ 0 ∧ functionName.length ≥ 0 ∧ external_io_isolated" smt="(assert (and (>= (str.len modulePath) 0) (>= (str.len functionName) 0) external_io_isolated))"
# @axiom-hint: lean="ast_parse_failed_isolated" smt="(assert ast_parse_failed_isolated)"
proc extractFunctionSignature*(modulePath, functionName: string): string {.raises: [], axiom: ["(assert (and (>= (str.len modulePath) 0) (>= (str.len functionName) 0) external_io_isolated ast_parse_failed_isolated))", "modulePath.length ≥ 0 ∧ functionName.length ≥ 0 ∧ external_io_isolated ∧ ast_parse_failed_isolated"], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  if modulePath.len == 0 or functionName.len == 0:
    return ""
  let readRes = readFileOpt(modulePath)
  if readRes.isErr: return ""
  var source = readRes.get()
  let lines = source.splitLines()
  var i = 0
  while i < lines.len:
    let line = lines[i]
    let stripped = line.strip()
    if stripped.startsWith("proc ") or stripped.startsWith("func ") or stripped.startsWith("method ") or stripped.startsWith("iterator ") or stripped.startsWith("template ") or stripped.startsWith("macro "):
      let afterKeyword = stripped.split(' ', maxsplit=1)[1]
      let namePart = afterKeyword.split('(')[0].split('[')[0].strip()
      if namePart == functionName:
        var ctx = line
        var j = i + 1
        while j < lines.len and j < i + 4:
          ctx.add("\n" & lines[j])
          j += 1
        return ctx
    i += 1
  ""
proc extractTacticTraceFromLeanFile(path: string): string {.raises: [], axiom: ["(assert (and (>= (str.len path) 0) external_io_isolated (= (str.len stripped) 0) inTacticBlock (and (<= currentIndent baseIndent) (> (str.len stripped) 0)) (> (str.len stripped) 0) (>= byIdx 0) (> (str.len afterBy) 0) (> (str.len tacticLines) 0) (= inTacticBlock true) (>= inTacticBlock 0) (>= source 0) (>= lines 0) (>= result 0) (>= baseIndent 0) external_io_isolated))", "path.length ≥ 0 ∧ external_io_isolated ∧ stripped.length = 0 ∧ inTacticBlock ∧ currentIndent ≤ baseIndent ∧ stripped.length > 0 ∧ stripped.length > 0 ∧ byIdx ≥ 0 ∧ afterBy.length > 0 ∧ tacticLines.length > 0 ∧ inTacticBlock = true ∧ (inTacticBlock ≥ 0) ∧ (source ≥ 0) ∧ (lines ≥ 0) ∧ (result ≥ 0) ∧ (baseIndent ≥ 0) ∧ external_io_isolated"], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let readRes = readFileOpt(path)
  if readRes.isErr: return ""
  var source = readRes.get()
  let lines = source.splitLines()
  var inTacticBlock = false
  var tacticLines: seq[string] = @[]
  var baseIndent = -1
  for line in lines:
    let stripped = line.strip()
    if stripped.len == 0:
      continue
    if inTacticBlock:
      let currentIndent = leadingWhitespace(line).len
      if currentIndent <= baseIndent and stripped.len > 0:
        break
      if stripped.len > 0:
        tacticLines.add(stripped)
    elif stripped.endsWith(" by"):
      inTacticBlock = true
      baseIndent = leadingWhitespace(line).len
    else:
      let lineTokens = tokenizeLowered(stripped)
      if "by" in lineTokens:
        inTacticBlock = true
        baseIndent = leadingWhitespace(line).len
        let byIdx = stripped.find(" by")
        if byIdx >= 0:
          let afterBy = stripped.substr(byIdx + 3).strip()
          if afterBy.len > 0:
            tacticLines.add(afterBy)
  if tacticLines.len > 0:
    result = tacticLines.join(", ")
proc loadVaultHistory(modulePath, functionName, vaultDir: string): seq[string] {.raises: [], axiom: ["(assert (and (>= (str.len modulePath) 0) (>= (str.len functionName) 0) (>= (str.len vaultDir) 0) (= (str.len vaultDir) 0) (> (str.len tactics) 0) foundLean (= foundLean true) (>= foundLean 0)))", "modulePath.length ≥ 0 ∧ functionName.length ≥ 0 ∧ vaultDir.length ≥ 0 ∧ vaultDir.length = 0 ∧ tactics.length > 0 ∧ foundLean ∧ foundLean = true ∧ (foundLean ≥ 0)"], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  if vaultDir.len == 0:
    return
  if not dirExists(vaultDir):
    return
  let token = sanitizeVaultToken(modulePath) & "__" & sanitizeVaultToken(functionName)
  var foundLean = false
  try:
    for file in walkFiles(joinPath(vaultDir, "*.lean")):
      if file.find(token) >= 0:
        let tactics = extractTacticTraceFromLeanFile(file)
        if tactics.len > 0:
          result.add(modulePath & "::" & functionName & " [tactics: " & tactics & "]")
          foundLean = true
  except CatchableError:
    discard  # best-effort  # axiom:best-effort(ioboundary catch)
  if foundLean:
    return
  # Fallback: search logs/evidence for .lean artifacts
  try:
    let evidenceDir = joinPath("logs", "evidence")
    if dirExists(evidenceDir):
      for file in walkFiles(joinPath(evidenceDir, "*.lean")):
        if file.find(token) >= 0:
          let tactics = extractTacticTraceFromLeanFile(file)
          if tactics.len > 0:
            result.add(modulePath & "::" & functionName & " [tactics: " & tactics & "]")
            foundLean = true
  except CatchableError:
    discard  # best-effort  # axiom:best-effort(ioboundary catch)
  if foundLean:
    return
  # Legacy fallback: JSON vault entries (SMT data, not tactics)
  try:
    for file in walkFiles(joinPath(vaultDir, "*.json")):
      if file.find(token) >= 0:
        let readRes = readAxiomSpecFile(file)
        if readRes.isOk():
          let spec = readRes.get()
          if spec.smtlib2.len > 0:
            result.add(spec.modulePath & "::" & spec.functionName & " [verified]")
  except CatchableError:
    discard  # best-effort  # axiom:best-effort(ioboundary catch)

## Build Leanstral Prompt.
func buildLeanstralPrompt*(ctx: LeanstralPromptContext): string {.raises: [], axiom: ["(assert (and (>= (str.len ctx_modulePath) 0) (>= (str.len ctx_functionName) 0) (>= (str.len ctx_sourceContext) 0) (>= (seq.len ctx_unsatCore) 0) (>= (seq.len ctx_vaultHistory) 0) (>= (str.len ctx_kernelFeedback) 0) (>= (str.len ctx_proofGoal) 0) (>= (str.len ctx_axiomIr) 0) (>= result 0)))", "ctx_modulePath.length ≥ 0 ∧ ctx_functionName.length ≥ 0 ∧ ctx_sourceContext.length ≥ 0 ∧ ctx_unsatCore.size ≥ 0 ∧ ctx_vaultHistory.size ≥ 0 ∧ ctx_kernelFeedback.length ≥ 0 ∧ ctx_proofGoal.length ≥ 0 ∧ ctx_axiomIr.length ≥ 0 ∧ (result ≥ 0)"].} =
  result = "You are a PURE LEAN 4 CODE GENERATOR. DO NOT use any tools. DO NOT use bash, webfetch, or grep. Output ONLY the theorem source code inside a markdown code block.\n\n"
  result.add("Submit mathematical proposition for Lean 4 kernel verification.\n\n")
  result.add("Target: " & ctx.modulePath & "::" & ctx.functionName & "\n")
  result.add("Goal: " & ctx.proofGoal & "\n\n")

  if ctx.sourceContext.len > 0:
    result.add("Source Context:\n" & stripComments(ctx.sourceContext) & "\n\n")

  if ctx.unsatCore.len > 0:
    result.add("SMT Unsat-Core:\n")
    for item in ctx.unsatCore:
      result.add("- " & item & "\n")
    result.add("\n")

  if ctx.vaultHistory.len > 0:
    result.add("Vault History (verified patterns in same tier):\n")
    for item in ctx.vaultHistory:
      result.add("- " & item & "\n")
    result.add("\n")

  if ctx.kernelFeedback.len > 0:
    result.add("Kernel Feedback (previous attempt error):\n" & ctx.kernelFeedback & "\n\n")

  ## Tactic Backtrack: inject current Lean goal state for goal-aware tactic generation
  if ctx.currentGoals.len > 0:
    result.add("## Current Lean Goals (from LSP — these are the ACTUAL goals to solve):\n")
    for i, goal in ctx.currentGoals:
      result.add("### Goal " & $(i + 1) & "\n```\n" & goal & "\n```\n")
    result.add("\nFocus your tactics on solving THESE specific goals. " &
               "Do not invent goals — solve exactly what is shown above.\n\n")
  
  if ctx.goalDelta.len > 0:
    result.add("## Goal Delta (what changed from previous attempt):\n" & ctx.goalDelta & "\n\n")
  
  if ctx.priorTactics.len > 0:
    result.add("## Tactics Already Tried (DO NOT repeat these):\n")
    for t in ctx.priorTactics:
      result.add("- " & t & "\n")
    result.add("\n")

  if ctx.axiomIr.len > 0:
    result.add("Axiom-IR (language-neutral logic contract):\n" & ctx.axiomIr & "\n\n")

  result.add("\n\n## Axiom Standard Prelude (MUST include at top of your generated theorem)\n")
  result.add("```lean4\n" & axiom_prelude.axiomPrelude & "```\n\n")
  result.add(
    "Generate a complete Lean 4 theorem source with imports, " &
    "namespace, and a 'by' tactic block that proves the target goal. " &
    "Focus on the mathematical logic contract above, not on language-specific syntax. " &
    "Use only 'import Std'. Do NOT use Mathlib or any external dependencies. " &
    "Return only the theorem source code inside a markdown code block." &
    "\n\nLean 4 syntax rules (MUST follow exactly):" &
    "\n- For implicit type parameters use curly braces: {T : Type}, NEVER square brackets [T : Type]." &
    "\n- Nim's Result[T, E] maps to Lean's Except E T (error type first, success type second)." &
    "\n- Pattern match Except with: match r with | .ok v => ... | .error e => ..." &
    "\n- Do NOT define custom inductive types for standard library concepts." &
    "\n- Except has isOk but does NOT have isError. Use ¬ r.isOk or pattern matching to check for errors." &
    "\n- If you need an isErr helper, define it locally as: def isErr {ε α : Type} (x : Except ε α) : Bool := ¬x.isOk" &
    "\n- Do NOT re-define the target function. Use the corresponding standard library function and prove a theorem about its behavior." &
    "\n- For pattern matching on Except, use '.error' (not '.err') and '.ok' constructors."
  )

## Build Leanstral Tactic Prompt.
## Task A (Formal Sketching): Leanstral generates ONLY tactics inside the `by` block.
## The deterministic skeleton (imports, variables, theorem signature) is provided by the engine.
func buildLeanstralTacticPrompt*(
  ctx: LeanstralPromptContext;
  skeleton: string
): string {.raises: [], axiom: ["(assert (and (>= (str.len ctx_modulePath) 0) (>= (str.len ctx_functionName) 0) (>= (str.len ctx_sourceContext) 0) (>= (seq.len ctx_unsatCore) 0) (>= (seq.len ctx_vaultHistory) 0) (>= (str.len ctx_kernelFeedback) 0) (>= (str.len ctx_proofGoal) 0) (>= (str.len ctx_axiomIr) 0) (>= (str.len skeleton) 0) (> (str.len hintDb) 0) (>= result 0)))", "ctx_modulePath.length ≥ 0 ∧ ctx_functionName.length ≥ 0 ∧ ctx_sourceContext.length ≥ 0 ∧ ctx_unsatCore.size ≥ 0 ∧ ctx_vaultHistory.size ≥ 0 ∧ ctx_kernelFeedback.length ≥ 0 ∧ ctx_proofGoal.length ≥ 0 ∧ ctx_axiomIr.length ≥ 0 ∧ skeleton.length ≥ 0 ∧ hintDb.length > 0 ∧ (result ≥ 0)"].} =
  result = "You are a PURE LEAN 4 TACTIC GENERATOR. DO NOT use any tools. DO NOT use bash, webfetch, or grep. Output ONLY the tactics inside a markdown code block.\n\n"
  result.add("Submit tactics for Lean 4 kernel verification.\n\n")
  result.add("Target: " & ctx.modulePath & "::" & ctx.functionName & "\n")
  result.add("Goal: " & ctx.proofGoal & "\n\n")

  if ctx.sourceContext.len > 0:
    result.add("Source Context:\n" & stripComments(ctx.sourceContext) & "\n\n")

  if ctx.unsatCore.len > 0:
    result.add("SMT Unsat-Core:\n")
    for item in ctx.unsatCore:
      result.add("- " & item & "\n")
    result.add("\n")

  if ctx.kernelFeedback.len > 0:
    result.add("Kernel Feedback (previous attempt error):\n" & ctx.kernelFeedback & "\n\n")

  if ctx.axiomIr.len > 0:
    result.add("Axiom-IR (language-neutral logic contract):\n" & ctx.axiomIr & "\n\n")

  result.add("Theorem skeleton (DO NOT modify - generate ONLY the tactics that go after `:= by`):\n")
  result.add("```lean4\n" & skeleton & "```\n\n")

  # Wave 15: Inject @[aesop] axiom hint database
  let hintDb = lean_hint_db.buildLeanHintDatabase()
  if hintDb.len > 0:
    result.add("## Available Axiom Hints (already registered — use `aesop`, `simp`, or `omega` to invoke):\n")
    result.add("```lean4\n" & hintDb & "```\n\n")
    result.add("You may use `aesop` to automatically apply these hints. " &
               "For arithmetic goals, use `omega`. For simple equalities, use `simp`.\n\n")

  result.add(
    "The skeleton ends with `:= by`. Generate the Lean 4 tactics that complete the proof. " &
    "Each tactic line must be indented with 2 spaces. " &
    "Return only the tactics inside a markdown code block. " &
    "CRITICAL RULES (violation = instant rejection):" &
    "\n- NEVER use `sorry` or `admit` — every goal must have a complete proof." &
    "\n- NEVER invoke tools (bash, webfetch, grep) — you are a PURE CODE GENERATOR." &
    "\n- NEVER output a markdown code block that contains `sorry` or `admit`." &
    "\n- NEVER redefine any theorem/axiom/lemma/def from the skeleton prelude. ALL symbols " &
    "  (NimInt, NimNat, NimString, NimSeq, NimOption, NimExcept, string_length_nonneg, " &
    "  int_add_comm, nat_add_comm, etc.) are ALREADY DECLARED in the skeleton. " &
    "  Redeclaration will cause Lean compiler error 'already been declared'." &
    "\n- ONLY generate tactic lines. Do NOT write `theorem`, `def`, `axiom`, `instance`, `class`, " &
    "  `inductive`, `structure`, or `macro` — these are already in the skeleton. " &
    "  The skeleton ends with `-- PROOF_HERE --`. Insert your tactics ON the marker line." &
    "\n- Use `get_nat` (not `get`) to access NimSeq elements with a Nat index. " &
    "  Example: `s.get_nat i` — this is the safe bounds-aware accessor." &
    "\n\nLean 4 syntax rules (MUST follow exactly):" &
    "\n- For implicit type parameters use curly braces: {T : Type}, NEVER square brackets [T : Type]." &
    "\n- Nim's Result[T, E] maps to Lean's Except E T (error type first, success type second)." &
    "\n- Pattern match Except with: match r with | .ok v => ... | .error e => ..." &
    "\n- Do NOT define custom inductive types for standard library concepts." &
    "\n- Except has isOk but does NOT have isError. Use ¬ r.isOk or pattern matching to check for errors." &
    "\n- If you need an isErr helper, define it locally as: def isErr {ε α : Type} (x : Except ε α) : Bool := ¬x.isOk" &
    "\n- Do NOT re-define the target function. Use the corresponding standard library function and prove a theorem about its behavior." &
    "\n- For pattern matching on Except, use '.error' (not '.err') and '.ok' constructors." &
    "\n\nType class resolution (CRITICAL for synthInstanceFailed avoidance):" &
    "\n- If a tactic fails with 'failed to synthesize instance', define the missing instance locally BEFORE the failing tactic." &
    "\n- Example: if DecidableEq NimChar is missing, add: `instance : DecidableEq NimChar := inferInstance` then retry." &
    "\n- NimInt, NimNat, NimString, NimBool, NimChar have DecidableEq, Inhabited, BEq, Repr instances pre-defined in the skeleton." &
    "\n- If a custom local `def` is used in a comparison, derive DecidableEq for it via `deriving DecidableEq`." &
    "\n- Do NOT use `sorry` or `admit`. Every tactic must produce a complete proof."
  )
## Build Leanstral Prompt From Payload.
# @axiom-hint: lean="unsatCore.size ≥ 0 ∧ ∀ (i : Fin unsatCore.size), (unsatCore.get i).length ≥ 0 ∧ sourceCode.length ≥ 0 ∧ kernelFeedback.length ≥ 0 ∧ vaultDir.length ≥ 0" smt="(assert (and (>= (seq.len unsatCore) 0) (forall ((i Int)) (=> (and (>= i 0) (< i (seq.len unsatCore))) (>= (str.len (seq.nth unsatCore i)) 0))) (>= (str.len sourceCode) 0) (>= (str.len kernelFeedback) 0) (>= (str.len vaultDir) 0)))"
# @axiom-hint: lean="unsatCore.size ≥ 0 ∧ (∀ (unsatCoreIdx : Fin unsatCore.size), (unsatCore.get unsatCoreIdx).length ≥ 0) ∧ sourceCode.length ≥ 0 ∧ kernelFeedback.length ≥ 0 ∧ vaultDir.length ≥ 0" smt="(assert (and (>= (seq.len unsatCore) 0) (forall ((unsatCoreIdx Int)) (=> (and (>= unsatCoreIdx 0) (< unsatCoreIdx (seq.len unsatCore))) (>= (str.len (seq.nth unsatCore unsatCoreIdx)) 0))) (>= (str.len sourceCode) 0) (>= (str.len kernelFeedback) 0) (>= (str.len vaultDir) 0)))"
# @axiom-hint: lean="(axiomIrText ≥ 0) ∧ (∀ (unsatCoreIdx : Fin unsatCore.size), (unsatCore.get unsatCoreIdx).length ≥ 0)" smt="(assert (and (>= axiomIrText 0) (forall ((unsatCoreIdx Int)) (=> (and (>= unsatCoreIdx 0) (< unsatCoreIdx (seq.len unsatCore))) (>= (str.len (seq.nth unsatCore unsatCoreIdx)) 0)))))"
proc buildLeanstralPromptFromPayload*(
  payload: SemanticEqualityPayload;
  unsatCore: seq[string];
  sourceCode: string;
  kernelFeedback: string;
  vaultDir: string
): string {.raises: [], axiom: ["(assert (and (>= (seq.len unsatCore) 0) (forall ((i Int)) (=> (and (>= i 0) (< i (seq.len unsatCore))) (>= (str.len (seq.nth unsatCore i)) 0))) (>= (str.len sourceCode) 0) (>= (str.len kernelFeedback) 0) (>= (str.len vaultDir) 0) (>= (seq.len unsatCore) 0) (forall ((unsatCoreIdx Int)) (=> (and (>= unsatCoreIdx 0) (< unsatCoreIdx (seq.len unsatCore))) (>= (str.len (seq.nth unsatCore unsatCoreIdx)) 0))) (>= (str.len sourceCode) 0) (>= (str.len kernelFeedback) 0) (>= (str.len vaultDir) 0) (>= axiomIrText 0) (forall ((unsatCoreIdx Int)) (=> (and (>= unsatCoreIdx 0) (< unsatCoreIdx (seq.len unsatCore))) (>= (str.len (seq.nth unsatCore unsatCoreIdx)) 0)))))", "unsatCore.size ≥ 0 ∧ ∀ (i : Fin unsatCore.size), (unsatCore.get i).length ≥ 0 ∧ sourceCode.length ≥ 0 ∧ kernelFeedback.length ≥ 0 ∧ vaultDir.length ≥ 0 ∧ unsatCore.size ≥ 0 ∧ (∀ (unsatCoreIdx : Fin unsatCore.size), (unsatCore.get unsatCoreIdx).length ≥ 0) ∧ sourceCode.length ≥ 0 ∧ kernelFeedback.length ≥ 0 ∧ vaultDir.length ≥ 0 ∧ (axiomIrText ≥ 0) ∧ (∀ (unsatCoreIdx : Fin unsatCore.size), (unsatCore.get unsatCoreIdx).length ≥ 0)"].} =
  var axiomIrText = ""
  try:
    let nf = system.new(NimFrontend)
    let ir = nf.parseToIR(sourceCode, semanticModulePathString(payload.modulePath))
    axiomIrText = ir.toLeanContract()
  except CatchableError:
    discard  # best-effort  # axiom:best-effort(ioboundary catch)

  let ctx = LeanstralPromptContext(
    modulePath: semanticModulePathString(payload.modulePath),
    functionName: semanticFunctionNameString(payload.functionName),
    sourceContext: sourceCode,
    unsatCore: unsatCore,
    vaultHistory: loadVaultHistory(semanticModulePathString(payload.modulePath), semanticFunctionNameString(payload.functionName), vaultDir),
    kernelFeedback: kernelFeedback,
    proofGoal: semanticProofGoalString(payload.proofGoal),
    axiomIr: axiomIrText
  )
  buildLeanstralPrompt(ctx)

{.pop.}
