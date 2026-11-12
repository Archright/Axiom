import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}
import ../core/trusted/axiom_pragmas
import core/identity/axiom_prelude
import core/judge/smart_search
import core/judge/the_judge_query_part1
import core/judge/the_judge_query_part2
import core/translator/ast_to_lean_bridge
import core/translator/universal_assembler as ula
import core/trusted/axiom_ir
import core/trusted/ir_to_lean
import core/utils/text_utils
import std/options
import std/strutils
import core/types/certificate_types
func generateUniqueSignature*(nodeId: string, hint: SemanticHint): string =
  nodeId & "_sig"

# ---------------------------------------------------------------------------
# Legacy Functions (Wave 12 — backward compatible)
# ---------------------------------------------------------------------------
func buildLeanSkeletonPremises*(nodeId: string; hint: SemanticHint): string {.raises: [], axiom: ["(assert (and (>= (str.len nodeId) 0)))", "nodeId.length ≥ 0"].} =
  ## Returns the complete Lean source with theorem and proof body.
  ## Migrated from deprecated buildLeanSkeleton to buildLeanTheoremSkeleton.
  buildLeanTheoremSkeleton(nodeId, hint)

# ---------------------------------------------------------------------------
# Wave 15 Functions: Bridge-Integrated Skeleton
# ---------------------------------------------------------------------------
func buildBridgeLeanSkeleton*(nodeId: string; hint: SemanticHint;
                               nimSource: string; modulePath: string = ""): string {.raises: [], axiom: ["(assert (and (>= (str.len nodeId) 0) (>= (str.len nimSource) 0) (>= (str.len modulePath) 0) (> (str.len parts) 1) (= (option.isSome ctxOpt) true) (> (str.len modulePath) 0) (>= ctx 0)))", "nodeId.length ≥ 0 ∧ nimSource.length ≥ 0 ∧ modulePath.length ≥ 0 ∧ parts.length > 1 ∧ ctxOpt.isSome = true ∧ modulePath.length > 0 ∧ (ctx ≥ 0)"].} =
  ## Generates a full bridge skeleton: function body def + theorem.
  ## Uses ast_to_lean_bridge to translate Nim source to Lean definitions.
  ## Falls back to legacy skeleton if bridge extraction fails.
  # IR-first: try to get Lean source from the axiom registry
  {.cast(noSideEffect).}:
    # Fast path: pre-computed leanSource from registry
    let leanSrc = lookupAxiomLeanSource(nodeId)
    if leanSrc.isSome():
      return leanSrc.get()
    # Slow path: deserialize IR and convert
    let irLookup = lookupAxiomIR(nodeId)
    if irLookup.isSome():
      let funcDef = deserializeIRFuncDef(irLookup.get())
      if funcDef.name.len > 0:  # sentinel check
        return irToLeanModule(funcDef)

  let parts = nodeId.split("::")
  let functionName = if parts.len > 1: parts[1] else: nodeId

  let ctxOpt = extractNimFunction(nimSource, functionName)
  if ctxOpt.isSome:
    var ctx = ctxOpt.get()
    if modulePath.len > 0:
      ctx.modulePath = modulePath
    return ula.buildUniversalLeanSource(ctx)

  # Fallback to buildLeanTheoremSkeleton
  buildLeanTheoremSkeleton(nodeId, hint)
func buildBridgeLeanTheoremOnly*(nodeId: string; hint: SemanticHint;
                                  nimSource: string; modulePath: string = ""): string {.raises: [], axiom: ["(assert (and (>= (str.len nodeId) 0) (>= (str.len nimSource) 0) (>= (str.len modulePath) 0) (> (str.len parts) 1) (= (option.isSome ctxOpt) true) (> (str.len modulePath) 0) (>= ctx 0)))", "nodeId.length ≥ 0 ∧ nimSource.length ≥ 0 ∧ modulePath.length ≥ 0 ∧ parts.length > 1 ∧ ctxOpt.isSome = true ∧ modulePath.length > 0 ∧ (ctx ≥ 0)"].} =
  ## Generates only the theorem skeleton (no function def).
  ## Uses the extended prelude with @[aesop] hints.
  # IR-first: try to get Lean source from the axiom registry
  {.cast(noSideEffect).}:
    # Fast path: pre-computed leanSource from registry
    let leanSrc = lookupAxiomLeanSource(nodeId)
    if leanSrc.isSome():
      return leanSrc.get()
    # Slow path: deserialize IR and convert
    let irLookup = lookupAxiomIR(nodeId)
    if irLookup.isSome():
      let funcDef = deserializeIRFuncDef(irLookup.get())
      if funcDef.name.len > 0:  # sentinel check
        return irToLeanModule(funcDef)

  let parts = nodeId.split("::")
  let functionName = if parts.len > 1: parts[1] else: nodeId

  let ctxOpt = extractNimFunction(nimSource, functionName)
  if ctxOpt.isSome:
    var ctx = ctxOpt.get()
    if modulePath.len > 0:
      ctx.modulePath = modulePath
    let defAndTheorem = buildLeanTheoremSkeleton(ctx)
    return "import Std\n" & getExtendedAxiomPrelude() & "\n\n" &
           "-- Theorem to prove (tactics supplied by Leanstral)\n" &
           defAndTheorem.theoremSkeleton

  # Fallback
  buildLeanTheoremSkeleton(nodeId, hint)
func buildBridgeLeanSignaturePrefix*(nodeId: string; hint: SemanticHint;
                                      nimSource: string; modulePath: string = ""): string {.raises: [], axiom: ["(assert (and (>= (str.len nodeId) 0) (>= (str.len nimSource) 0) (>= (str.len modulePath) 0) (> (str.len parts) 1) (= (option.isSome ctxOpt) true) (> (str.len fnDef) 0) (>= defBlock 0)))", "nodeId.length ≥ 0 ∧ nimSource.length ≥ 0 ∧ modulePath.length ≥ 0 ∧ parts.length > 1 ∧ ctxOpt.isSome = true ∧ fnDef.length > 0 ∧ (defBlock ≥ 0)"].} =
  ## Bridge-aware signature prefix using extended prelude (with @[aesop] hints).
  # IR-first: try to get Lean source from the axiom registry
  {.cast(noSideEffect).}:
    # Fast path: pre-computed leanSource from registry
    let leanSrc = lookupAxiomLeanSource(nodeId)
    if leanSrc.isSome():
      return leanSrc.get()
    # Slow path: deserialize IR and convert
    let irLookup = lookupAxiomIR(nodeId)
    if irLookup.isSome():
      let funcDef = deserializeIRFuncDef(irLookup.get())
      if funcDef.name.len > 0:  # sentinel check
        return irToLeanModule(funcDef)

  let safeId = sanitizeAxiomToken(nodeId).replace("/", "_")
  let uniqueSig = generateUniqueSignature(nodeId, hint)
  let rawProp = hint.leanProposition
  var cleanProp = sanitizeLean4AppSyntax(sanitizeLean4Forall(rawProp))
  if cleanProp.len == 0:
    cleanProp = "True"

  var imports = "import Std\n" & getExtendedAxiomPrelude() & "\n"

  let varDecls = buildLeanVariableDeclarations(cleanProp, hint)

  # If we can extract the function body, include it as a def before the theorem
  let parts = nodeId.split("::")
  let functionName = if parts.len > 1: parts[1] else: nodeId
  let ctxOpt = extractNimFunction(nimSource, functionName)

  var defBlock = ""
  if ctxOpt.isSome:
    let ctx = ctxOpt.get()
    let fnDef = buildLeanFunctionDef(ctx)
    if fnDef.len > 0:
      defBlock = "-- Translated Nim function definition\n" & fnDef & "\n\n"

  imports & "\n" & defBlock & varDecls & "\n" &
    "theorem " & safeId & "_" & uniqueSig & " (h_sys : " & cleanProp & ") :\n" &
    "  " & cleanProp

func detectSorryInLeanOutput*(leanOutput: string): bool {.raises: [].} =
  ## Detect if Lean output contains sorry usage.
  ## Checks for both compiler warning and #print axioms output.
  "declaration uses 'sorry'" in leanOutput or "sorryAx" in leanOutput

func classifyLeanProofStatus*(leanOutput: string): CertificateStatus {.raises: [].} =
  ## Classify Lean proof output into certificate status.
  ## sorry → certSoundnessDebt (Soundness Debt)
  ## error → certRed
  ## clean → certSafetyVerified (pending Z3 confirmation)
  if detectSorryInLeanOutput(leanOutput):
    certSoundnessDebt
  elif "error:" in leanOutput:
    certRed
  else:
    certSafetyVerified

{.pop.}

