import core/trusted/layer_declaration
axiomLayer "infrastructure"

## Canonical Verification — executeCanonicalVerification
##
## Runs the genuine Lean-backed verification chain end-to-end for one
## IR function definition:
##
##   IR funcDef → obligation → generic IR-body → Lean def
##   → I6 theorem (postcondition applied to the lowered body)
##   → canonicalLeanKernelCheck → LeanKernelCheckReceipt
##   → bindReceipt → KernelAcceptanceAttestation
##   → evaluate(kaa, policy) → verdict
##   → CanonicalVerificationResult (with 4-fold identity binding)
##
## Soundness: evaluate only yields vdVerified when there is a genuine
## KAA (Lean kernel actually accepted). If canonicalLeanKernelCheck
## fails, the generated Lean fails to parse, or bindReceipt fails, the
## result is non-verified (inconclusive/candidate), NEVER a fabricated
## verified.
##
## Generic lowering (S1-A, I6 Body/Result Binding): the Lean `def` is the
## deterministic lowering of the *actual* IR function body over a bounded
## expression subset (Int literals, params, +, -, comparisons, if-then-else).
## The theorem applies the obligation postcondition to that lowered body's
## return value:
##
##   def <f> : ... := fun p1 .. pn => <lowered body>
##   theorem <f>_post : ∀ (p1 : Int) .. (pn : Int), <post[result := <f> p1 .. pn]> := by
##     intro ...; unfold <f>; omega
##
## The `result` variable of the postcondition is bound to the actual lowered
## body (I6), so the theorem's result expression IS the Lean encoding of the
## real IR body — never a hand-written or weakened proposition. Any body or
## postcondition construct outside the bounded subset is fail-closed
## (non-verified), never fabricated.

import std/[strutils, algorithm, sequtils, os, osproc, sets]
import core/axiom_pragmas
import core/crypto/hash_kernel
import core/results
import core/trusted/axiom_ir
import core/trusted/axiom_ir_helpers
import core/trusted/contract_synthesis
import core/trusted/verification_result_types
import core/types/verification_tier
import verification/obligation/obligation_types
import verification/obligation/obligation_ir
import verification/obligation/semantic_target_extractor
import verification/obligation/canonical_obligation_generator
import verification/obligation/lean_kernel_boundary
import verification/obligation/toolchain_capture
import verification/obligation/lean_evidence
import verification/obligation/kernel_acceptance_authority
import verification/obligation/verification_decision_authority
import verification/obligation/identity
import verification/lean_lsp_protocol
import verification/extraction_agreement
import infrastructure/evidence_artifact_io
import core/ast_kernel
import core/deterministic_cas_key
import core/utils/repo_root
import core/trusted/completeness_binding
import core/trusted/semantic_profile
import std/options
import std/json

# ---------------------------------------------------------------------------
# Toolchain identity capture (D2) — compile-time provenance constants.
#
# WP0-c fix: the first implementation probed `nim --version` / `lean
# --version` / `z3 --version` via execCmdEx at runtime. That made this
# module non-gcsafe, which propagated up the IR pipeline and broke
# `runIrPipelineWithCas {.gcsafe.}` (the hermetic gate caught it).
# D2 defines toolchainFingerprint as a *version/provenance* identity —
# compile-time pinned values satisfy that contract exactly (and better:
# they cannot drift between probe time and verify time). Binary/image
# digests remain an explicitly deferred successor scope.
# ---------------------------------------------------------------------------
import generated/build_env  # BuildEnvZ3Version (hermetic SSOT)
import std/strutils

const NimPin = "nim-" & $NimVersion          # compiler version of this build
const ToolchainIdentity {.strdefine.} = ""   # reserved override hook (unused by default)

const LeanToolchainFile = staticRead(currentSourcePath().parentDir().parentDir().parentDir().parentDir() / "lean-toolchain")
  ## repo-root anchor: currentSourcePath() → 4×parentDir = repo root /lean-toolchain
  ## (staticRead is CWD-relative in the canonical repo-root build; anchor absolutely)

proc captureToolchainIdentity*(): string {.raises: [].} =
  ## Formats as "nim-<v>|lean-<v>|z3-<v>" (empty components skipped),
  ## replacing the former hardcoded "nim-2.2.10|lean-4.33.0" label with
  ## measured build-time provenance values (D2; schema key unchanged).
  ## Pure: const inputs only — gcsafe by construction.
  ## Exported for Plan 1: the run-level reuse-verification context reuses
  ## this D2 identity as condition (e) (current toolchain identity).
  ## The lean pin is parsed from the lean-toolchain manifest content via
  ## `parseLeanToolchainPin` (lean_kernel_boundary.nim) — the same measured
  ## composition `computeBundleDigest` uses (§2.1a: no hardcoded version
  ## label). An unmeasurable pin is SKIPPED (empty segment), never labeled.
  if ToolchainIdentity.len > 0:
    return ToolchainIdentity

  var segments: seq[string] = @[]
  segments.add(NimPin)
  let leanPin = parseLeanToolchainPin(LeanToolchainFile)
  if leanPin.len > 0:
    segments.add(leanPin)
  if BuildEnvZ3Version.len > 0: segments.add("z3-" & BuildEnvZ3Version)
  # §4 binding set (base36 sizing binding contract): target int width and the
  # host platform are compile-time constants of this binary; the division
  # profile names the semantic the Lean encoding verifies — the renderer emits
  # Lean `/` (floor) while Nim `div` truncates; they coincide on the verified
  # nonnegative domain, which is part of the rendered proposition. The
  # checks-Defect-vs-wrap profile has no deterministic compile-time capture
  # here and is deliberately NOT labeled (an unmeasurable profile is a
  # reported gap, never a fabricated identity segment).
  segments.add("int" & $(sizeof(int) * 8) & "bit")
  segments.add(hostPlatformId)
  segments.add("div=lean-floor/nim-trunc/coincident-nonneg-domain")
  # rem profile (same domain pattern as the div segment above): the renderer
  # emits Lean `%` (Int.emod — remainder always nonneg for divisor ≠ 0) while
  # Nim `mod` truncates toward zero (sign of the dividend); they coincide when
  # the dividend is nonnegative (Int.tmod_eq_emod_of_nonneg), which is the
  # rem-domain obligation the rendered proposition's preconditions carry.
  segments.add("rem=lean-emod/nim-mod/coincident-nonneg-dividend-domain")
  # modelprofile (§4 item 2, base36 sizing binding contract): the verified
  # semantic model — modelProfileIdentitySegment (verification/obligation/
  # identity.nim) hashes SemanticProfileV1Hash, the same constant cert_writer
  # consumes as semanticProfileId. Since the 2026-10-07 weakening (DEBT#494)
  # the profile declares the coincidence semantics itself (division/modulo
  # coincide with Lean floor/emod on the nonnegative domain; overflow
  # reachability discharged via no-overflow obligations). A no-overflow
  # obligation discharges overflow reachability, so checked/wrap arithmetic
  # coincide in the verified domain — never a fabricated checked/wrap claim
  # beyond that domain.
  segments.add(modelProfileIdentitySegment)
  result = segments.join("|")

# ---------------------------------------------------------------------------
# LeanLowering — deterministic Lean source binding for an obligation
# ---------------------------------------------------------------------------
## The proposition is deterministically derived from the obligation predicate
## (cryptographically bound via propositionHash = sha256), NOT hand-written.
## The leanSource is the rendered Lean 4 theorem that the kernel must accept.

type LeanLowering* = object
  obligationId*: string          ## C4 identity of the obligation
  proposition*: string           ## canonical proposition string (IR-level)
  propositionHash*: string       ## sha256 of the canonical proposition
  leanSource*: string            ## rendered Lean 4 source
  leanSourceHash*: string        ## sha256 of the leanSource

# ---------------------------------------------------------------------------
# CanonicalVerificationResult — the complete verification outcome
# ---------------------------------------------------------------------------
## 4-fold identity binding: source identity, IR identity,
## obligation/proposition identity, proof/kernel identity.

type CanonicalVerificationResult* = object
  execution*: string                ## "executeCanonicalVerification"
  obligationKind*: ObligationKind
  obligationCount*: int
  evidence*: string                 ## "lean_kernel_accepted" | "lean_kernel_rejected" | "inconclusive"
  verdict*: VerificationDecision    ## vdVerified / vdCandidate / vdPolicyRejected
  inputHash*: string                ## §6a sourceHash — sha256 of the input source bytes
  irHash*: string                   ## sha256 of the IR funcDef
  obligationHash*: string           ## propositionHash (sha256 of canonical proposition)
  leanSourceHash*: string           ## sha256 of the leanSource
  proofDigest*: string              ## kernel observation digest (from receipt)
  toolchainIdentity*: string        ## D2: dynamically captured via captureToolchainIdentity()
  kaaIdentity*: string              ## KAA identity digest (empty if no KAA)
  artifactIdentity*: string         ## sha256 of the leanSource (artifact)
  success*: bool                    ## true only when verdict == vdVerified AND the
                                    ## subject-bound canonicalEvidence sealed (DEBT#490)
  canonicalEvidence*: Option[CanonicalLeanEvidence] = none(CanonicalLeanEvidence)
  sealError*: string = ""           ## DEBT#490: the reason the subject-bound evidence seal
                                    ## refused issuance (" " never set on a sealed result).
                                    ## Carried instead of silently dropped — a non-empty
                                    ## sealError always forces success=false (fail-closed).

# ---------------------------------------------------------------------------
# Generic IRExpr → Lean term lowering (bounded subset)
# ---------------------------------------------------------------------------
## Lowers an IRExpr to a valid Lean 4 term. Supports the bounded subset:
##   Int literals, function params, + , - , < , ≤ , > , ≥ , = , ∧ , ∨ ,
##   if-then-else. Returns "" (unsupported) for any construct outside the
##   subset or any referenced variable that is not a function parameter.
##   "" is the fail-closed marker: callers must never emit a fabricated
##   theorem when lowering returns "".

func lowerIRExprToLean*(
  e: IRExpr;
  paramNames: HashSet[string]
): string {.raises: [].} =
  if e == nil:
    return ""
  case e.kind
  of irLit:
    # u64-domain literals render as their unsigned decimal value (Int
    # semantics — the mathematical value, not the bit pattern).
    result = if e.litU64 != 0'u64: $e.litU64 else: $e.litVal
  of irVar:
    if e.varName in paramNames:
      result = e.varName
    else:
      # Not a function parameter (e.g. `result` must be bound by the caller,
      # loop state, or synthesized locals) — outside the bounded subset.
      result = ""
  of irBinOp:
    let lhs = lowerIRExprToLean(e.binLhs, paramNames)
    let rhs = lowerIRExprToLean(e.binRhs, paramNames)
    if lhs.len == 0 or rhs.len == 0:
      return ""
    case e.binOp
    of boAdd:  result = "(" & lhs & " + " & rhs & ")"
    of boSub:  result = "(" & lhs & " - " & rhs & ")"
    of boMul:  result = "(" & lhs & " * " & rhs & ")"
    of boDiv:  result = "(" & lhs & " / " & rhs & ")"
    of boRem:  result = "(" & lhs & " % " & rhs & ")"
    of boLt:   result = "(" & lhs & " < " & rhs & ")"
    of boLtU:  result = "(" & lhs & " < " & rhs & ")"
    of boLe:   result = "(" & lhs & " ≤ " & rhs & ")"
    of boGt:   result = "(" & lhs & " > " & rhs & ")"
    of boGe:   result = "(" & lhs & " ≥ " & rhs & ")"
    of boEq:   result = "(" & lhs & " = " & rhs & ")"
    of boAnd:  result = "(" & lhs & " ∧ " & rhs & ")"
    of boOr:   result = "(" & lhs & " ∨ " & rhs & ")"
    else:
      # boRemU / boShl / boShr / boUnsupported — outside the bounded subset.
      # boRem is IN the subset: Lean `%` (Int.emod, always-nonneg remainder)
      # vs Nim `mod` (truncated, sign of the dividend) coincide when the
      # dividend is nonnegative — the rem-domain identity segment
      # (`rem=lean-emod/nim-mod/coincident-nonneg-dividend-domain` in
      # captureToolchainIdentity), the div profile's domain pattern. proofs/IR/
      # Denotation.lean carries the matching Certified rem form.
      result = ""
  of irIf:
    let cond = lowerIRExprToLean(e.ifCond, paramNames)
    let t = lowerIRExprToLean(e.ifThen, paramNames)
    let el = lowerIRExprToLean(e.ifElse, paramNames)
    if cond.len == 0 or t.len == 0 or el.len == 0:
      return ""
    result = "(if " & cond & " then " & t & " else " & el & ")"
  of irUnaryOp:
    # uoNot on a Bool-typed sub-expression is expressible in the bounded
    # subset; arithmetic negation (uoBvNeg) and bitwise-not are not.
    if e.unaryOp == uoNot:
      let arg = lowerIRExprToLean(e.unaryArg, paramNames)
      if arg.len == 0:
        return ""
      result = "¬ " & arg
    else:
      result = ""
  else:
    # irFloatLit / irLet / irCase / irCall / irRecCall / irLoop /
    # irStringLit / irCast — outside the bounded subset.
    result = ""

# ---------------------------------------------------------------------------
# Postcondition → Lean proposition (I6 Body/Result Binding)
# ---------------------------------------------------------------------------
## Binds the postcondition's `result` variable to the lowered body applied to
## the function's parameters, i.e. produces
##     <post[result := (<f> p1 .. pn)]>
## so the proposition's result expression IS the actual IR body (via the
## `def`). Any construct outside the bounded subset → "" (fail-closed).
##
## The `result` variable name is `"result"` (matches the postcondition
## synthesis in contract_synthesis.nim / semantic_target_extractor).
## A non-result free variable that is not a parameter is unsupported.

func lowerPostconditionToLean*(
  post: IRExpr;
  funcDefName: string;
  paramNames: HashSet[string]
): string {.raises: [].} =
  ## Lower a postcondition IRExpr, mapping `result` to the body application
  ## `(<funcDefName> <p1> .. <pn>)`. Variables that are neither `result` nor
  ## a parameter are outside the bounded subset and fail closed.
  if post == nil:
    return ""
  # Build the ranks of param names in declaration order for the `result` term.
  var resultTerm: string
  var orderedParams: seq[string] = @[]
  for p in paramNames:
    orderedParams.add(p)
  orderedParams.sort
  if funcDefName.len > 0:
    if orderedParams.len == 0:
      # Zero-parameter function: `result` IS the body constant `def <name>`.
      resultTerm = funcDefName
    else:
      resultTerm = "(" & funcDefName
      for p in orderedParams:
        resultTerm.add(" " & p)
      resultTerm.add(")")
  let paramSet = paramNames
  let resultVarIsBound = funcDefName.len > 0
  # Recursive lowering with `result` substitution.
  proc lower(node: IRExpr): string {.raises: [].} =
    if node == nil:
      return ""
    case node.kind
    of irLit:
      result = $node.litVal
    of irVar:
      if node.varName == "result" and resultVarIsBound:
        result = resultTerm
      elif node.varName in paramSet:
        result = node.varName
      else:
        result = ""
    of irBinOp:
      let lhs = lower(node.binLhs)
      let rhs = lower(node.binRhs)
      if lhs.len == 0 or rhs.len == 0:
        return ""
      case node.binOp
      of boAdd: result = "(" & lhs & " + " & rhs & ")"
      of boSub: result = "(" & lhs & " - " & rhs & ")"
      of boMul: result = "(" & lhs & " * " & rhs & ")"
      of boDiv: result = "(" & lhs & " / " & rhs & ")"
      of boRem: result = "(" & lhs & " % " & rhs & ")"
      of boLt:  result = "(" & lhs & " < " & rhs & ")"
      of boLtU: result = "(" & lhs & " < " & rhs & ")"
      of boLe:  result = "(" & lhs & " ≤ " & rhs & ")"
      of boGt:  result = "(" & lhs & " > " & rhs & ")"
      of boGe:  result = "(" & lhs & " ≥ " & rhs & ")"
      of boEq:  result = "(" & lhs & " = " & rhs & ")"
      of boAnd: result = "(" & lhs & " ∧ " & rhs & ")"
      of boOr:  result = "(" & lhs & " ∨ " & rhs & ")"
      else:     result = ""
    of irIf:
      let c = lower(node.ifCond)
      let t = lower(node.ifThen)
      let el = lower(node.ifElse)
      if c.len == 0 or t.len == 0 or el.len == 0:
        return ""
      result = "(if " & c & " then " & t & " else " & el & ")"
    of irUnaryOp:
      if node.unaryOp == uoNot:
        let arg = lower(node.unaryArg)
        if arg.len == 0:
          return ""
        result = "¬ " & arg
      else:
        result = ""
    else:
      result = ""
  result = lower(post)

# ---------------------------------------------------------------------------
# Generic IR-body → Lean `def` + I6 theorem rendering
# ---------------------------------------------------------------------------
## Renders the full Lean source for one funcDef:
##
##   def <f> : (T1 → ... → Tn → Int) := fun p1 .. pn => <lowered body>
##   theorem <f>_post : ∀ (p1 : Int) .. (pn : Int),
##     <pre₁> → ... → <preₖ> → <post[result := <f> p1 .. pn]> := by
##     intro p1 .. pn h0 .. h(k-1)
##     unfold <f>
##     omega
##
## The preconditions are rendered as explicit discharged hypotheses (arrow
## binders intro'd before the unfold) — contract §3.2: the domain is part of
## the verified proposition, and `omega` discharges the overflow/div goals
## from the context hypotheses (Denotation.lean:384-416 precedent). The
## arithmetic subset covers + - * / (fixed-divisor `/`, floor — coinciding
## with Nim's truncating `div` on the nonneg domain); rem/shift remain
## outside and fail closed.
## I6 Body/Result Binding: the `def` body is the actual IR body lowering, and
## the theorem's proposition is the obligation postcondition applied to that
## lowered body. Returns "" if the body or a postcondition is outside the
## bounded subset (fail-closed → callers produce a non-verified result).

func irTypeToLeanTy*(ty: IRType): string {.raises: [].} =
  ## Map the bounded IR type subset to Lean 4 types. Only Int-mappable types
  ## are supported in S1-A; anything else returns "" (fail-closed).
  if ty == nil:
    return ""
  case ty.kind
  of irtBitVec64:
    result = "Int"
  else:
    result = ""

func containsIdentToken*(s, tok: string): bool {.raises: [].} =
  ## True iff `tok` occurs in `s` as a whole identifier token — i.e. not
  ## glued to a Lean identifier character (alnum, `_`, `'`) on either side.
  ## Used to decide whether a rendered proposition references the def
  ## constant (an `unfold` of a non-occurring constant is a tactic failure).
  if tok.len == 0:
    return false
  const identChars = {'a'..'z', 'A'..'Z', '0'..'9', '_', '\''}
  var i = 0
  while true:
    i = s.find(tok, i)
    if i < 0:
      return false
    let beforeOk = i == 0 or not (s[i - 1] in identChars)
    let afterIdx = i + tok.len
    let afterOk = afterIdx >= s.len or not (s[afterIdx] in identChars)
    if beforeOk and afterOk:
      return true
    inc i

func collectDivisions(e: IRExpr; acc: var seq[IRExpr]) {.raises: [].} =
  ## Collect every integer division node in the IR body. The I6 proof below
  ## needs explicit `Int.ediv_*` bounds for these nodes because `omega` does
  ## not reason about division on its own.
  if e == nil:
    return
  case e.kind
  of irBinOp:
    if e.binOp == boDiv:
      acc.add(e)
    collectDivisions(e.binLhs, acc)
    collectDivisions(e.binRhs, acc)
  of irIf:
    collectDivisions(e.ifCond, acc)
    collectDivisions(e.ifThen, acc)
    collectDivisions(e.ifElse, acc)
  of irLet:
    collectDivisions(e.letVal, acc)
    collectDivisions(e.letBody, acc)
  of irCall:
    for a in e.callArgs:
      collectDivisions(a, acc)
  of irRecCall:
    for a in e.recArgs:
      collectDivisions(a, acc)
  of irUnaryOp:
    collectDivisions(e.unaryArg, acc)
  of irCast:
    collectDivisions(e.castExpr, acc)
  else:
    discard

func rootIfCond(e: IRExpr): IRExpr {.raises: [].} =
  ## The top-level if condition of the body, when the body is a single
  ## if-expression. The division proof below case-splits on it.
  if e != nil and e.kind == irIf:
    e.ifCond
  else:
    nil

func divisionProofLines(divisions: seq[IRExpr]; ifCond: IRExpr;
                        paramNames: HashSet[string]): string {.raises: [].} =
  ## Proof shape for nonnegative division:
  ##   by_cases h : <ifCond>
  ##   · simp [h]
  ##   · simp [h]
  ##     have divLeN : lhs / rhs ≤ lhs := Int.ediv_le_self rhs (by omega)
  ##     have divGeN : 0 ≤ lhs / rhs := Int.ediv_nonneg (by omega) (by omega)
  ##     omega
  ## This is the minimal proof that closes `60 / (i+1)` range goals with the
  ## pinned Lean core (measured 2026-10-19, lean 4.33.0).
  if divisions.len == 0 or ifCond == nil:
    return ""
  let cond = lowerIRExprToLean(ifCond, paramNames)
  if cond.len == 0:
    return ""
  var hname = "hcond"
  while hname in paramNames:
    hname.add("_")
  result.add("  by_cases " & hname & " : " & cond & "\n")
  result.add("  · simp [" & hname & "]\n")
  result.add("  · simp [" & hname & "]\n")
  for i, d in divisions:
    let lhs = lowerIRExprToLean(d.binLhs, paramNames)
    let rhs = lowerIRExprToLean(d.binRhs, paramNames)
    if lhs.len == 0 or rhs.len == 0:
      return ""
    result.add("    have hdivLe" & $i & " : " & lhs & " / " & rhs & " ≤ " &
      lhs & " := Int.ediv_le_self (" & rhs & ") (by omega)\n")
    result.add("    have hdivGe" & $i & " : 0 ≤ " & lhs & " / " & rhs &
      " := Int.ediv_nonneg (by omega) (by omega)\n")
  result.add("    omega\n")

func renderLeanForFuncDef*(
  funcDef: IRFuncDef
): string {.raises: [].} =
  ## Render the complete Lean source (def + I6 theorem per postcondition) for
  ## the funcDef, or "" if any construct is outside the bounded subset.
  if funcDef.body == nil or funcDef.name.len == 0:
    return ""
  let name = funcDef.name

  # Param name set + per-param Lean type in declaration order.
  var paramNames = initHashSet[string]()
  var leanTypes: seq[string] = @[]
  for p in funcDef.params:
    let lt = irTypeToLeanTy(p.ty)
    if lt.len == 0:
      return ""
    if p.name.len == 0:
      return ""
    # Safety: `result` is reserved as the postcondition free variable; a
    # parameter named `result` cannot be bound by this I6 scheme.
    if p.name == "result":
      return ""
    paramNames.incl(p.name)
    leanTypes.add(lt)

  # Lower the actual body (I6).
  let lowerBody = lowerIRExprToLean(funcDef.body, paramNames)
  if lowerBody.len == 0:
    return ""
  var divisions: seq[IRExpr]
  collectDivisions(funcDef.body, divisions)
  let divProof = divisionProofLines(divisions, rootIfCond(funcDef.body), paramNames)

  # Build the def signature.
  var defSig = "def " & name & " : "
  if leanTypes.len == 0:
    defSig.add("Int")
  else:
    for i, lt in leanTypes:
      if i > 0:
        defSig.add(" → ")
      defSig.add(lt)
    defSig.add(" → Int")
  var binder = "fun"
  for p in funcDef.params:
    binder.add(" " & p.name)
  defSig.add(" :=")
  var src = defSig & "\n  " & binder & " => " & lowerBody & "\n"

  # Render one I6 theorem per postcondition (explicit + synthesized), using
  # the same order/source the obligation generator uses.
  var seen: seq[string] = @[]
  var postExprs: seq[IRExpr] = @[]
  for post in funcDef.postConditions:
    if post != nil:
      let canon = canonicalizePredicate(post)
      if canon notin seen:
        seen.add(canon)
        postExprs.add(post)
  let synth = collectPostconditions(funcDef)
  for post in synth:
    if post != nil:
      let canon = canonicalizePredicate(post)
      if canon notin seen:
        seen.add(canon)
        postExprs.add(post)

  # The domain preconditions are discharged hypotheses INSIDE the theorem
  # (contract §3.2 / §2.1a-5): part of the verified proposition, never an
  # informal preamble. Same bounded subset — an unsupported precondition
  # fails the whole funcDef closed.
  var preExprs: seq[string] = @[]
  for pre in funcDef.preConditions:
    if pre != nil:
      let loweredPre = lowerIRExprToLean(pre, paramNames)
      if loweredPre.len == 0:
        return ""
      preExprs.add(loweredPre)
  # Hypothesis binder names for the intro chain; a name colliding with a
  # parameter would shadow the binder rather than intro the hypothesis, so
  # it is renamed until unique (deterministically).
  var hypNames: seq[string] = @[]
  for i in 0 ..< preExprs.len:
    var cand = "h" & $i
    while cand in paramNames:
      cand = cand & "_h"
    hypNames.add(cand)

  var theoremCount = 0
  for post in postExprs:
    let proposition = lowerPostconditionToLean(post, name, paramNames)
    if proposition.len == 0:
      return ""  # one unsupported postcondition fails the whole funcDef (fail-closed)
    # `unfold <name>` is only meaningful when the goal actually references the
    # def constant — a RESULT-FREE postcondition (e.g. the β-spliced composite
    # body) already carries the body inline, and unfolding a constant that
    # does not occur in the goal is a tactic FAILURE (lean_kernel_rejected,
    # observed 2026-10-06). Emit the unfold iff the def name occurs as an
    # identifier token in the proposition.
    let needsUnfold = containsIdentToken(proposition, name)
    var theName = name & "_post"
    if theoremCount > 0:
      theName = name & "_post_" & $theoremCount
    src.add("\ntheorem " & theName & " :\n")
    if funcDef.params.len == 0 and preExprs.len == 0:
      # Zero-parameter function with no preconditions: no ∀-quantification,
      # no intro.
      src.add("  " & proposition & " := by\n")
      if needsUnfold:
        src.add("  unfold " & name & "\n")
      if divProof.len > 0 and needsUnfold:
        src.add(divProof)
      else:
        src.add("  omega\n")
    else:
      var binderPart = ""
      if funcDef.params.len > 0:
        var bs = "∀ ("
        for i, p in funcDef.params:
          if i > 0:
            bs.add(") (")
          bs.add(p.name & " : Int")
        bs.add("), ")
        binderPart = bs
      for pe in preExprs:
        binderPart.add(pe & " → ")
      src.add("  " & binderPart & proposition & " := by\n")
      var introLine = "  intro"
      for p in funcDef.params:
        introLine.add(" " & p.name)
      for h in hypNames:
        introLine.add(" " & h)
      src.add(introLine & "\n")
      if needsUnfold:
        src.add("  unfold " & name & "\n")
      if divProof.len > 0 and needsUnfold:
        src.add(divProof)
      else:
        src.add("  omega\n")
    inc theoremCount

  if theoremCount == 0:
    return ""  # no postconditions → nothing to prove (fail-closed to non-verified)
  result = src

# ---------------------------------------------------------------------------
# Choose a proof tactic appropriate for the proposition
# ---------------------------------------------------------------------------
## For the bounded S1-A subset the primary tactic is `omega` (Int linear
## arithmetic), which discharges if/then/else + ≥/≤/>/</= over Int.

func chooseTactic*(leanProposition: string): string {.raises: [].} =
  "omega"

# ---------------------------------------------------------------------------
# §6a sourceHash — the input-identity half of (sourceHash, irHash)
# ---------------------------------------------------------------------------
## productization_contract.md §6a defines function-level input identity as the
## pair (sourceHash, irHash): sourceHash digests the *input source*, irHash
## digests the translation state. §10.1 (D3) forbids a physical path from
## reaching a hash function — only the source *bytes* may be digested.

proc resolveSourceHashForVerification*(
  sourceContent: string;
  sourcePath: string
): string {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## sha256 hex of the input source bytes the funcDef was derived from.
  ##
  ## `sourceContent` is the resolver-authorised byte string (external subjects
  ## are bound to a subject root by `ModuleContentResolver`, which OWNS source
  ## location resolution — see external_ir_materializer.nim WP4-a B-5b). When it
  ## is absent, the module-relative `sourcePath` is read instead; that is the
  ## repo-relative convention every current call site already assumes.
  ##
  ## Returns "" when the source bytes are genuinely unreachable. Callers MUST
  ## then fail closed: substituting a path- or name-derived digest would turn
  ## §6a input identity back into "trust me".
  if sourceContent.len > 0:
    return sha256Hex(sourceContent)
  try:
    let content = readFile(sourcePath)
    if content.len > 0:
      result = sha256Hex(content)
  except CatchableError:
    result = ""

# ---------------------------------------------------------------------------
# executeCanonicalVerification — the single canonical verification function
# ---------------------------------------------------------------------------
## Runs the genuine Lean-backed verification chain end-to-end for one
## IR function definition.
##
## Chain:
##   IR funcDef → generateCanonicalObligations → first obligation
##   → generic body lowering + I6 theorem (leanSource)
##   → canonicalLeanKernelCheck(leanSource) → LeanKernelCheckReceipt
##   → bindReceipt(receipt) → KernelAcceptanceAttestation
##   → evaluate(kaa, policy) → VerificationDecision
##   → CanonicalVerificationResult (with 4-fold identity binding)
##
## Soundness invariant: evaluate only yields vdVerified when there is a
## genuine KAA (Lean kernel actually accepted). If the generic lowering
## cannot produce a valid Lean source (unsupported construct), or the Lean
## kernel check fails, the result is non-verified (inconclusive/candidate).

proc baseVerificationResult(kind: ObligationKind; count: int;
                             inputHash, irHash: string): CanonicalVerificationResult =
  ## The spine every outcome shares: an inconclusive, non-verified result that
  ## names the invocation and carries no claim about proof content. Callers
  ## override only the fields their outcome actually establishes.
  CanonicalVerificationResult(
    execution: "executeCanonicalVerification",
    obligationKind: kind,
    obligationCount: count,
    evidence: "inconclusive",
    verdict: vdCandidate,
    inputHash: inputHash,
    irHash: irHash,
    obligationHash: "",
    leanSourceHash: "",
    proofDigest: "",
    toolchainIdentity: captureToolchainIdentity(),
    kaaIdentity: "",
    artifactIdentity: "",
    success: false
  )

proc kernelRejectedResult(kind: ObligationKind; count: int; inputHash, irHash,
                          obligationHash, leanSourceHash,
                          proofDigest: string): CanonicalVerificationResult =
  ## Outcome for every point at which the Lean kernel declined to produce an
  ## acceptance: the obligation and the rendered source are known, but nothing
  ## was proved, so the result stays a candidate with an explicit reason.
  result = baseVerificationResult(kind, count, inputHash, irHash)
  result.evidence = "lean_kernel_rejected"
  result.obligationHash = obligationHash
  result.leanSourceHash = leanSourceHash
  result.proofDigest = proofDigest
  result.artifactIdentity = leanSourceHash

proc runKernelCheck(leanSource: string): Result[LeanKernelCheckReceipt, string] {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect, TimeEffect].} =
  ## The kernel call is this module's only external process boundary. Any
  ## failure becomes an error value; no exception escapes.
  try:
    canonicalLeanKernelCheck(leanSource, timeoutMs = 120_000)
  except CatchableError:
    Result[LeanKernelCheckReceipt, string](
      ok: false,
      err: "canonicalLeanKernelCheck: " & getCurrentExceptionMsg()
    )

proc canonicalVerificationPolicy*(): VerificationPolicy {.raises: [].} =
  ## The committed product policy for the canonical path
  ## (docs/spec/base36_sizing_binding_contract.md §5): the project's existing
  ## `LeanAxiomAllowlist` (reused, not reinvented) and sorry forbidden. The
  ## allowlist is non-empty by contract — under Authority C an empty
  ## allowlist rejects every axiom-bearing KAA instead of silently skipping
  ## the check, so the historical `@[]` construction was never a neutral
  ## default.
  VerificationPolicy(allowedAxioms: @LeanAxiomAllowlist, sorryPolicy: spForbid)

proc scanSorryMarkers*(artifactSource: string; kernelObservation: string): seq[string] {.raises: [].} =
  ## Measured sorry profile bound into the KAA at the bindReceipt call site —
  ## never the empty default. Repo-wide convention (lean_sorry_gate.md,
  ## lean_evidence.containsSorryMarker): lowercase substring scan; presence
  ## in the artifact source and in the kernel's own output are recorded as
  ## distinct markers. Empty result = none observed.
  let loweredSource = artifactSource.toLowerAscii()
  let loweredObservation = kernelObservation.toLowerAscii()
  if "sorry" in loweredSource:
    result.add("sorry")
  if "sorry" in loweredObservation:
    result.add("declaration uses 'sorry'")

proc captureKernelAxioms(receipt: LeanKernelCheckReceipt;
                         leanSource: string): seq[string] {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect, TimeEffect].} =
  ## Step 6: the axiom profile is the honest record of what the Lean kernel
  ## actually consumed; it feeds the cert's axiomsUsed field for the lean sorry
  ## gate (isDeepVerified).
  let probeSource = leanSource & "\n#print axioms " &
    receipt.receiptTheoremIdentity & "\n"
  let (probeOutput, _) = runLeanProbe(probeSource, "_axioms", 120_000)
  parseAxiomProfile(probeOutput)

proc buildExecutionContract(inputId: string): ExecutionContract =
  ## §10/D3 role projection: workdir and fsBoundary use role literals, never
  ## physical paths, in the canonical execution contract.
  let repoRoot = getCurrentDir()
  canonicalExecutionContract(
    invocation = "lake env lean --threads=1 <artifact>.lean",
    platform = hostPlatformId,
    workdir = "<execution>",
    allowedEnv = @[
      EnvVarSpec(name: "AXIOM_LEAN_CMD", canonicalValue: canonicalizeEnvValue("AXIOM_LEAN_CMD", getEnv("AXIOM_LEAN_CMD", ""), repoRoot)),
      EnvVarSpec(name: "PATH", canonicalValue: canonicalizeEnvValue("PATH", getEnv("PATH", ""), repoRoot)),
      EnvVarSpec(name: "TMPDIR", canonicalValue: canonicalizeEnvValue("TMPDIR", getEnv("TMPDIR", ""), repoRoot))
    ],
    fsBoundary = "<subject>",
    networkPolicy = "deny",
    mountedInputs = inputId,
    resourcePolicy = "cpu=1,mem=512MB"
  )

proc bindExecutionIdentity(receipt: LeanKernelCheckReceipt; inputId, contractDigest: string;
                           funcDef: IRFuncDef): tuple[bundleFp, execId: string] {.
  raises: [], axiomEffect: IOEffect,
  tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Step 8 (C1 closure). The dependency digests capture the direct call
  ## dependencies of this unit, so a change to any dependency's identity changes
  ## the execution identity. `bundleFp` is combined with the sorted dependency
  ## digests without changing the executionIdentity formula
  ## (H(InputId + ContractDigest + BundleFp)).
  ## §2.1a evaluation-implementation binding: the bundle fingerprint is the
  ## BOUND composition (`computeSemanticBundleFingerprintBound`) — it folds the
  ## measured content digests of the lowering implementation (pnode_to_canon,
  ## ast_to_ir, the IR→Lean renderer, proofs/IR/Denotation.lean) into the
  ## execution identity, so an edit that quietly widens the lowering semantics
  ## can no longer reuse evidence produced under the old semantics.
  let depNames = collectSemanticDependencies(funcDef)
  let bundleFp = computeSemanticBundleFingerprintBound(
    toolchainFingerprint = receipt.receiptToolchainFingerprint,
    dependencyDigests = computeDependencyDigests(depNames),
    evaluationImplDigest = evaluationImplementationDigest(
      measureEvaluationImplementationDigests())
  )
  # Phase A — fail-closed identity binding. `bundleFp` MUST be a genuine SHA256
  # hex digest (64 hex chars). doAssert is used (not assert) so it survives
  # -d:release: a future edit that substitutes a placeholder or hardcoded label
  # at this identity site crashes the build loudly instead of silently issuing a
  # certificate under a divergent execution identity.
  doAssert bundleFp.len == 64, "bundleFp is not a SHA256 hex digest (len=" & $bundleFp.len & ")"
  (bundleFp, executionIdentity(inputId, contractDigest, bundleFp))

# ---------------------------------------------------------------------------
# §2.1a subject binding — measurement boundary for the bound obligation id
# ---------------------------------------------------------------------------
## docs/spec/obligation_semantics.md §2.1a: the evidence-facing identity folds
## the subject-side measurements into the id, and `computeBoundObligationId`
## is fail-closed ("" is not an identity). Every measurement below follows the
## same rule: unmeasurable ⇒ ""/err ⇒ no bound id ⇒ no verified certificate.
## These are IO-boundary procs, consistent with this module's existing IO.

proc resolveSubjectModuleSource*(sourceContent: string; sourcePath: string): string {.
  raises: [], axiomEffect: IOEffect,
  tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## The exact byte string §6a input identity digests — the same rule
  ## `resolveSourceHashForVerification` applies: resolver-authorised content
  ## when carried, else the module-relative `sourcePath` read from the process
  ## CWD (the repo-relative internal-subject convention). "" when genuinely
  ## unreachable.
  if sourceContent.len > 0:
    return sourceContent
  try:
    result = readFile(sourcePath)
  except CatchableError:
    result = ""

proc resolveSubjectRepoRoot*(subjectRepoRoot: string; sourcePath: string;
                             contentCarried: bool): string {.
  raises: [], axiomEffect: IOEffect,
  tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Subject repo root resolution (the §2.1a `git`/`treeMerkle` anchor).
  ## 1) The root threaded from the pipeline (`subjectRepoRoot` — the engine's
  ##    analysis root, which IS the subject root for the external flow).
  ## 2) Otherwise the CWD repo (`git rev-parse --show-toplevel`): internal
  ##    subjects carry a repo-relative `sourcePath` under the repo-root build.
  ## A content-carried external subject (`contentCarried` — its bytes arrived
  ## in-band, not read from the subject repo) with no threaded root is
  ## UNMEASURABLE (its `sourcePath` is subject-relative and must never be
  ## resolved against the process CWD — WP4-a B-5b), so "" there fails the
  ## binding closed. NOTE: contentCarried reflects the ORIGINAL in-band
  ## source bytes, not the resolved module bytes (which are non-empty for
  ## internal subjects too — they were read from the subject repo).
  if subjectRepoRoot.len > 0:
    return subjectRepoRoot
  if contentCarried:
    return ""
  try:
    let (output, code) = execCmdEx("git rev-parse --show-toplevel",
      options = {poUsePath})
    if code == 0:
      let root = output.strip()
      if root.len > 0 and dirExists(root):
        return root
  except CatchableError: # bestEffort("""unreachable git root — "" keeps binding fail-closed upstream""")
    discard
  ""

proc measureSubjectGitRef*(subjectRoot: string): string {.
  raises: [], axiomEffect: IOEffect,
  tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## §2.1a `git` — the git commit hash of the SUBJECT repo (the project under
  ## verification, e.g. nim-stew — not the Axiom repo). Read-only measurement
  ## (`git rev-parse HEAD`); the subject is never mutated. "" when the subject
  ## has no resolvable git identity — fail-closed upstream.
  if subjectRoot.len == 0:
    return ""
  try:
    let (output, code) = execCmdEx("git rev-parse HEAD",
      options = {poUsePath}, workingDir = subjectRoot)
    if code == 0:
      let refHash = output.strip()
      let hexOk = refHash.len == 40 or refHash.len == 64
      if hexOk:
        for ch in refHash:
          if ch notin {'0'..'9', 'a'..'f'}:
            return ""
        return refHash
  except CatchableError: # bestEffort("""unreadable subject git identity — "" fails closed upstream""")
    discard
  ""

proc extractFirstPartyImports(moduleSource: string): seq[string] {.raises: [].} =
  ## Deterministic line-level extraction of import designators from the subject
  ## module (`import`/`from`/`include`, bracket groups expanded, `as`/`except`
  ## clauses stripped, comments dropped). The same resolution spelling as
  ## run_context.collectDependencyClosureAST is applied by the caller:
  ## `a.b` → `a/b.nim`. Pure — the resolution against the subject root is IO
  ## and lives in measureSubjectTreeMerkleRoot.
  for rawLine in moduleSource.splitLines():
    let line = strip(rawLine)
    if line.len == 0 or line.startsWith("#"):
      continue
    var body = ""
    if line.startsWith("import "):
      body = line["import ".len .. ^1]
    elif line.startsWith("from "):
      let rest = line["from ".len .. ^1]
      let impIdx = rest.find(" import ")
      if impIdx < 0:
        continue
      body = rest[0 ..< impIdx]
    elif line.startsWith("include "):
      body = line["include ".len .. ^1]
    else:
      continue
    let hashIdx = body.find(" #")
    if hashIdx >= 0:
      body = body[0 ..< hashIdx]
    # Split the top-level comma list, tracking [] nesting.
    var parts: seq[string] = @[]
    var depth = 0
    var cur = ""
    for ch in body:
      if ch == '[':
        inc depth
      elif ch == ']':
        dec depth
      if ch == ',' and depth == 0:
        parts.add(strip(cur))
        cur = ""
      else:
        cur.add(ch)
    if strip(cur).len > 0:
      parts.add(strip(cur))
    for part in parts:
      var designators: seq[string] = @[]
      let open = part.find('[')
      if open >= 0 and part.endsWith("]"):
        # `import std/[strutils, sequtils]` → std.strutils, std.sequtils
        let head = strip(part[0 ..< open])
        let inner = strip(part[open + 1 ..< part.high])
        for item in inner.split(','):
          var d = strip(item)
          let asIdx = d.find(" as ")
          if asIdx >= 0:
            d = strip(d[0 ..< asIdx])
          if d.len > 0 and head.len > 0:
            designators.add(head & "." & d)
      else:
        var d = strip(part)
        let asIdx = d.find(" as ")
        if asIdx >= 0:
          d = strip(d[0 ..< asIdx])
        let exceptIdx = d.find(" except ")
        if exceptIdx >= 0:
          d = strip(d[0 ..< exceptIdx])
        if d.len > 0:
          designators.add(d)
      for d in designators:
        result.add(d)

proc measureSubjectTreeMerkleRoot*(subjectRoot: string; moduleRelPath: string;
                                   moduleSource: string): string {.
  raises: [], axiomEffect: IOEffect,
  tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## §2.1a `treeMerkle` — choice documented. The spec-named machine
  ## (`computeSourceMerkleRoot`, global_symbol_graph_builder_part2.nim) walks
  ## the ENTIRE subject tree and folds the walked (absolute) paths into its
  ## accumulator, so its output depends on where the subject repo is checked
  ## out — a physical-path input to a binding identity, which §2.1a forbids
  ## ("no wall-clock, run id or path enters the payload") — and its per-file
  ## hashes are MD5-based. The canonical path therefore measures the honest
  ## cheaper alternative that still names subject tree content: a SHA-256
  ## merkle over the subject module and its first-party import closure
  ## (one hop, stdlib/foreign imports resolve nowhere in the repo and are
  ## skipped). Records are "<repo-relative path>:<sha256(content)>" lines
  ## sorted by path; the root is sha256 over the joined lines. The module's
  ## own record uses the resolver-authorised bytes. Deterministic across
  ## machines; "" when any record is unmeasurable (fail-closed).
  if subjectRoot.len == 0 or moduleRelPath.len == 0:
    return ""
  # Canonical rel-path invariant: the merkle record labels are repo-relative,
  # so the producer (which may hold the resolved absolute module path) and the
  # reader (which holds the claim's relative modulePath) MUST measure the same
  # root. Normalizing here is the single place that guarantees it; an absolute
  # path outside the subject root is unmeasurable (fail-closed, never "../").
  var relModule = moduleRelPath
  if moduleRelPath.isAbsolute:
    try:
      let rel = relativePath(moduleRelPath, subjectRoot)
      if rel.len == 0 or rel.startsWith("..") or rel.isAbsolute:
        return ""
      relModule = rel
    except CatchableError:
      return ""
  var relSet = initHashSet[string]()
  relSet.incl(relModule)
  for designator in extractFirstPartyImports(moduleSource):
    let relCandidate = designator.replace('.', '/') & ".nim"
    if fileExists(subjectRoot / relCandidate):
      relSet.incl(relCandidate)
  var rels: seq[string] = @[]
  for rel in relSet:
    rels.add(rel)
  rels.sort(cmp[string])
  var records: seq[string] = @[]
  for rel in rels:
    try:
      if rel == relModule and moduleSource.len > 0:
        records.add(rel & ":" & sha256Hex(moduleSource))
      else:
        let content = readFile(subjectRoot / rel)
        if content.len == 0:
          return ""
        records.add(rel & ":" & sha256Hex(content))
    except CatchableError:
      return ""
  sha256Hex(records.join("\n"))

proc measureExtractionAgreement*(moduleSource: string; funcName: string): tuple[
    nimDigest, leanDigest, ircheckBinaryDigest: string, agreed: bool, reason: string] {.
  raises: [], axiomEffect: IOEffect,
  tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## §2.1a `ea` components. Runs the existing per-run differential
  ## (`runExtractionAgreement`, extraction_agreement.nim) over the subject
  ## module source for this funcDef, and measures the ircheck worker binary
  ## content at the same resolution the worker itself uses
  ## (AXIOM_IRCHECK_CMD override, else <repoRoot>/proofs/.lake/build/bin/ircheck
  ## — the extraction_agreement.nim default). No digest is ever fabricated:
  ## any unmeasured leg stays "" and fails the binding closed upstream.
  ## NOT gcsafe (parses the subject source; the Nim parser holds process
  ## globals) — only `measureParseBoundComponents` (main thread) may call it.
  result = ("", "", "", false, "")
  if moduleSource.len == 0 or funcName.len == 0:
    result.reason = "extraction agreement input unavailable (empty source or func name)"
    return
  var ea: ExtractionAgreementResult
  try:
    ea = runExtractionAgreement(moduleSource, funcName, ircheckExe = "",
                                projectRoot = "", timeoutMs = 60_000)
  except CatchableError as e:
    result.reason = "extraction agreement invocation failed: " & e.msg
    return
  result.nimDigest = ea.nimDigest
  result.leanDigest = ea.leanDigest
  result.agreed = ea.verdict == eaAgree
  result.reason = agreementReasonCode(ea.verdict) & ": " & ea.reason
  let worker =
    if getEnv("AXIOM_IRCHECK_CMD", "").len > 0:
      getEnv("AXIOM_IRCHECK_CMD", "")
    else:
      resolveRepoRoot() / "proofs" / ".lake" / "build" / "bin" / "ircheck"
  try:
    if worker.len > 0 and fileExists(worker):
      let bin = readFile(worker)
      if bin.len > 0:
        result.ircheckBinaryDigest = sha256Hex(bin)
  except CatchableError: # bestEffort("""unreadable ircheck binary — empty digest leaves EA unbound, fail-closed""")
    discard

type SubjectParseBoundComponents* = object
  ## §2.1a components whose measurement requires the Nim parser
  ## (`parseStringAST` / `parseSourceToPNode` hold process-global caches and
  ## are NOT gcsafe — measured 2026-10-06, see docs/spec/obligation_semantics.md
  ## §2.1a measurement table). They are therefore measured on the MAIN thread
  ## at the selection boundary (`selectProofCandidates`) and threaded into the
  ## gcsafe IR-worker chain as values; the worker chain never parses subject
  ## source. All-empty = unmeasured → the binding fails closed.
  pnodeCanonicalV2Digest*: string = ""
  eaNimDigest*: string = ""
  eaLeanDigest*: string = ""
  eaIrcheckBinaryDigest*: string = ""
  eaAgreed*: bool = false
  eaDetail*: string = ""
  measuredForFuncName*: string = ""
    ## The funcName the extraction agreement was measured FOR — the binding
    ## site must verify it matches the funcDef being sealed, or the EA legs
    ## would attest a different subject than the obligation's.
    ## For a synthesized composite (`synthesizedComposite = true`) the legs
    ## attest the two ORIGINAL subject symbols instead (§2.1a-1: a composite
    ## name never appears in the subject source, so the single-symbol rule
    ## cannot apply to it literally), and the correspondence gate below
    ## enforces the composite shape: two distinct original names, both agreed.
  synthesizedComposite*: bool = false
    ## Marks components measured for a SYNTHESIZED relational composite.
  claimCarrierSingleOrigin*: bool = false
    ## Marks components measured for a synthesized claim CARRIER derived from
    ## ONE original subject symbol (e.g. the base32 rem-range overlay: the
    ## claim quantifies over `<symbol>`'s own `mod` term). The single EA leg
    ## attests that original; there is no second leg to measure, and the
    ## binding site must refuse to seal if one were present (a fabricated
    ## second leg is theater, not measurement).
  synthesisDerivationDigest*: string = ""
    ## Digest of the recorded deterministic β-splice derivation rule (rule
    ## identity + ordered original symbols). Part of the composite binding
    ## (§2.1a-2); empty in single-symbol mode.
  ea2NimDigest*: string = ""
  ea2LeanDigest*: string = ""
  ea2IrcheckBinaryDigest*: string = ""
  ea2Agreed*: bool = false
  ea2Detail*: string = ""
  ea2MeasuredForFuncName*: string = ""
  compositeCarrierTypename*: string = ""
    ## S6 (PROPOSITION_DISPROVED replay): the typedesc carrier token measured from the
    ## subject source for a synthesized composite (`typedesc[<T>]` in the
    ## outer original's signature). The replay adapter composes the two
    ## ORIGINAL subject symbols — `outer(<T>, inner(<T>, n))` — and the Nim
    ## call needs the exact carrier type name; a subject without a typedesc
    ## carrier measures "" and the composite replay fails closed
    ## (rvUnavailable), never guesses a token.
  replayHarnessTemplate*: string = ""
    ## The d2-agent binding's replay harness (string-control-gate contract):
    ## the FULL harness source with the `<lit>` placeholder where the model's
    ## byte value renders (the `<module>` import slot is fixed at synthesis).
    ## Non-empty marks a bespoke-harness binding — the replay observes the
    ## ORIGINAL subject through its public API instead of calling subject
    ## symbols directly, so the composite call shape is bypassed. Empty for
    ## every other binding (zero-diff).

func parseComponentsMeasured*(c: SubjectParseBoundComponents): bool {.raises: [].} =
  if c.claimCarrierSingleOrigin:
    ## Single-origin claim carrier: ONE original leg plus the recorded
    ## derivation rule must be present. No second leg exists to measure —
    ## requiring one would force its fabrication (fail-closed instead).
    return c.pnodeCanonicalV2Digest.len > 0 and c.eaNimDigest.len > 0 and
      c.eaLeanDigest.len > 0 and c.eaIrcheckBinaryDigest.len > 0 and
      c.measuredForFuncName.len > 0 and
      c.synthesisDerivationDigest.len > 0
  if c.synthesizedComposite:
    ## Composite mode: BOTH original legs plus the recorded derivation rule
    ## must be present (§2.1a-3: one missing leg = not sealable).
    return c.pnodeCanonicalV2Digest.len > 0 and c.eaNimDigest.len > 0 and
      c.eaLeanDigest.len > 0 and c.eaIrcheckBinaryDigest.len > 0 and
      c.measuredForFuncName.len > 0 and
      c.ea2NimDigest.len > 0 and c.ea2LeanDigest.len > 0 and
      c.ea2IrcheckBinaryDigest.len > 0 and c.ea2MeasuredForFuncName.len > 0 and
      c.synthesisDerivationDigest.len > 0
  c.pnodeCanonicalV2Digest.len > 0 and c.eaNimDigest.len > 0 and
  c.eaLeanDigest.len > 0 and c.eaIrcheckBinaryDigest.len > 0 and
  c.measuredForFuncName.len > 0

func parseBoundCarried*(c: SubjectParseBoundComponents): bool {.raises: [].} =
  ## True when the components carry ANY measured or composite-flagged state.
  ## The selection boundary re-measures only entries that arrive empty, so a
  ## synthesized composite's pre-measured legs (measured at the synthesis
  ## site — also main thread, also non-gcsafe) are never clobbered by a
  ## per-name re-measurement that cannot succeed for a name absent from the
  ## subject source.
  c.synthesizedComposite or c.claimCarrierSingleOrigin or
  c.replayHarnessTemplate.len > 0 or
  c.measuredForFuncName.len > 0 or
  c.pnodeCanonicalV2Digest.len > 0 or c.eaDetail.len > 0

proc measureParseBoundComponents*(moduleSource: string; funcName: string): SubjectParseBoundComponents {.
  raises: [], axiomEffect: IOEffect,
  tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Main-thread measurement of the parser-bound §2.1a components (the
  ## `pnodeV2` module-AST digest per DECISION-0002 and the extraction
  ## agreement differential). NOT gcsafe — must never be called from the IR
  ## worker chain. Unmeasurable legs stay ""/false and fail the binding
  ## closed; no digest is ever fabricated.
  result = SubjectParseBoundComponents()
  if moduleSource.len == 0:
    result.eaDetail = "module source bytes unavailable"
    return
  result.measuredForFuncName = funcName
  let pnodeRes = computeCanonicalAstHash(moduleSource)
  if pnodeRes.isErr:
    result.eaDetail = "pnodeCanonicalV2Digest unmeasurable (" & pnodeRes.error & "); "
  else:
    result.pnodeCanonicalV2Digest = pnodeRes.get()
  let ea = measureExtractionAgreement(moduleSource, funcName)
  result.eaNimDigest = ea.nimDigest
  result.eaLeanDigest = ea.leanDigest
  result.eaIrcheckBinaryDigest = ea.ircheckBinaryDigest
  result.eaAgreed = ea.agreed
  result.eaDetail.add(ea.reason)

func betaSpliceDerivationDigest*(outerSymbol, innerSymbol: string): string {.
  raises: [].} =
  ## The deterministic β-splice derivation rule recorded by the synthesis
  ## (base36 sizing binding contract §2.1a-2): the rule identity plus the
  ## ORDERED original symbols. The composite IR digest binds the RESULT of
  ## the derivation; this digest binds the RULE that produced it, so the
  ## sealed identity names both. sha256 output (64 hex) keeps the bound-id
  ## canonical-form gate satisfied.
  sha256Hex("beta-splice-v1|outer=" & outerSymbol & "|inner=" & innerSymbol)

proc measureCompositeCarrierTypename*(moduleSource: string; outerName: string): string {.
    raises: [], axiomEffect: IOEffect,
    tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## S6 (PROPOSITION_DISPROVED replay): the typedesc carrier token of the OUTER original's
  ## signature, measured from the subject bytes (`func <outer>*(
  ## <param>: typedesc[<T>], ...` → "<T>"). Deterministic byte scan at the
  ## same selection boundary as the other §2.1a parse-bound components;
  ## "" when the signature carries no typedesc carrier (fail-closed — the
  ## composite replay refuses rather than guessing a token).
  if moduleSource.len == 0 or outerName.len == 0:
    return ""
  var sigIdx = moduleSource.find(outerName & "*(")
  if sigIdx < 0:
    sigIdx = moduleSource.find(outerName & "(")
  if sigIdx < 0:
    return ""
  let tdIdx = moduleSource.find("typedesc[", sigIdx)
  if tdIdx < 0:
    return ""
  let nameStart = tdIdx + "typedesc[".len
  var nameEnd = nameStart
  while nameEnd < moduleSource.len and
      moduleSource[nameEnd] in {'A'..'Z', 'a'..'z', '0'..'9', '_'}:
    inc nameEnd
  if nameEnd >= moduleSource.len or nameEnd == nameStart:
    return ""
  if nameEnd < moduleSource.len and moduleSource[nameEnd] != ']':
    return ""
  moduleSource[nameStart ..< nameEnd]

proc measureCompositeParseBoundComponents*(moduleSource: string;
                                           outerName, innerName: string
): SubjectParseBoundComponents {.
  raises: [], axiomEffect: IOEffect,
  tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## §2.1a-1: the extraction agreement is measured per ORIGINAL symbol against
  ## the real subject bytes. A synthesized composite never appears in the
  ## subject source, so the single-symbol differential cannot be run for its
  ## name — the composite binding instead carries BOTH originals' legs plus
  ## the recorded derivation rule digest. Each leg is the SAME fail-closed
  ## differential the single-symbol path uses (runExtractionAgreement) — the
  ## EA gate is not weakened; it is applied to each original independently.
  ## NOT gcsafe (parses subject source) — main-thread callers only, like
  ## measureParseBoundComponents.
  result = SubjectParseBoundComponents(
    synthesizedComposite: true,
    synthesisDerivationDigest: betaSpliceDerivationDigest(outerName, innerName))
  if moduleSource.len == 0:
    result.eaDetail = "module source bytes unavailable"
    return
  if outerName.len == 0 or innerName.len == 0 or outerName == innerName:
    result.eaDetail = "composite originals must be two distinct non-empty " &
      "subject symbols (outer=\"" & outerName & "\", inner=\"" & innerName & "\")"
    return
  let outerLeg = measureParseBoundComponents(moduleSource, outerName)
  let innerLeg = measureParseBoundComponents(moduleSource, innerName)
  result.pnodeCanonicalV2Digest = outerLeg.pnodeCanonicalV2Digest
  result.eaNimDigest = outerLeg.eaNimDigest
  result.eaLeanDigest = outerLeg.eaLeanDigest
  result.eaIrcheckBinaryDigest = outerLeg.eaIrcheckBinaryDigest
  result.eaAgreed = outerLeg.eaAgreed
  result.eaDetail = outerLeg.eaDetail
  result.measuredForFuncName = outerLeg.measuredForFuncName
  result.ea2NimDigest = innerLeg.eaNimDigest
  result.ea2LeanDigest = innerLeg.eaLeanDigest
  result.ea2IrcheckBinaryDigest = innerLeg.eaIrcheckBinaryDigest
  result.ea2Agreed = innerLeg.eaAgreed
  result.ea2Detail = innerLeg.eaDetail
  result.ea2MeasuredForFuncName = innerLeg.measuredForFuncName
  result.compositeCarrierTypename =
    measureCompositeCarrierTypename(moduleSource, outerName)

proc measureClaimCarrierParseBoundComponents*(moduleSource: string;
                                              symbol: string;
                                              derivationRule: string
): SubjectParseBoundComponents {.
    raises: [], axiomEffect: IOEffect,
    tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## §2.1a-1 for a claim CARRIER derived from ONE original subject symbol
  ## (base32 rem-range binding contract §3 D2/D3): the extraction agreement
  ## is measured against the real subject bytes for that one original — the
  ## SAME fail-closed differential the single-symbol path uses. A carrier
  ## name never appears in the subject source, so the name-correspondence
  ## rule cannot apply literally; the binding records the single honest leg
  ## plus the deterministic derivation rule digest instead. There is NO
  ## second original to measure — the ea2 slot stays empty and the binding
  ## site refuses to seal a carrier whose ea2 slot was filled (a fabricated
  ## second leg is theater, not measurement). The original's typedesc carrier
  ## token is measured the same way the composite binding measures it
  ## (measureCompositeCarrierTypename) — the S6 replay of a single-origin
  ## carrier calls the ONE original, which needs that token; "" means the
  ## original signature carries no typedesc formal and the replay refuses
  ## rather than guessing. NOT gcsafe (parses subject
  ## source) — main-thread callers only, like measureCompositeParseBoundComponents.
  result = SubjectParseBoundComponents(
    synthesizedComposite: true,
    claimCarrierSingleOrigin: true,
    synthesisDerivationDigest:
      sha256Hex(derivationRule & "|symbol=" & symbol))
  if moduleSource.len == 0:
    result.eaDetail = "module source bytes unavailable"
    return
  if symbol.len == 0 or derivationRule.len == 0:
    result.eaDetail = "claim carrier needs a non-empty original symbol and " &
      "derivation rule (symbol=\"" & symbol & "\", rule=\"" & derivationRule & "\")"
    return
  let leg = measureParseBoundComponents(moduleSource, symbol)
  result.pnodeCanonicalV2Digest = leg.pnodeCanonicalV2Digest
  result.eaNimDigest = leg.eaNimDigest
  result.eaLeanDigest = leg.eaLeanDigest
  result.eaIrcheckBinaryDigest = leg.eaIrcheckBinaryDigest
  result.eaAgreed = leg.eaAgreed
  result.eaDetail = leg.eaDetail
  result.measuredForFuncName = leg.measuredForFuncName
  # S6 (buffer-binding slice): the typedesc carrier token of the ONE original's
  # signature, measured like the composite's — consumed by the replay adapter's
  # single-origin shape (`outer(<carrier>, <valueLit>)`); "" fails the replay
  # closed. Not part of any binding identity — a pure replay-capability
  # measurement.
  result.compositeCarrierTypename =
    measureCompositeCarrierTypename(moduleSource, symbol)

proc measureCompletenessRecordDigest*(funcDef: IRFuncDef;
                                      preSynthesisIrDigest: string;
                                      currentSourceIdentity,
                                      currentSubjectModuleSha256: string
): Option[CompletenessBindingRef] {.
  raises: [], axiomEffect: IOEffect,
  tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## §2.1a `completeness` — strict-first reader (Phase 1A).
  ##
  ## The canonical producers (external_ir_materializer, ensureKernelCompleteness,
  ## the axiom_engine carrier syntheses) dual-write every evidence artifact:
  ##   <key>.json         — the legacy 5-field CompletenessEvidence
  ##   <key>.binding.json — the strict CompletenessBinding (authenticated:
  ##                        key equality, recomputed evidenceDigest, and
  ##                        source/profile/toolchain equality are ALL enforced
  ##                        by loadCompletenessBinding)
  ## This reader consults the strict artifact FIRST, at the same deterministic
  ## two-anchor search the runner cache uses (pre-synthesis anchor threaded
  ## from the pipeline entry, then the current funcDef's key). A strict hit
  ## yields a CompletenessBindingRef; `payloadDigest` re-serializes the
  ## binding's embedded 5-field payload with `evidenceToJson` and hashes it —
  ## the EXACT digest the legacy reader would have computed — so
  ## `ObligationSubjectBinding.completenessRecordDigest` is byte-compatible
  ## across generations (the bound-obligation representation does not fork).
  ##
  ## Strict miss: only when `AXIOM_EVIDENCE_STRICT` is unset does the reader
  ## fall back to the legacy `loadEvidenceArtifact` (payloadDigest over the
  ## legacy record). With the flag set, a legacy-only anchor contributes
  ## nothing and the search continues strictly at the next anchor; no strict
  ## artifact anywhere → none (fail-closed) — never a fabricated record.
  var anchors: seq[string] = @[]
  if preSynthesisIrDigest.len > 0:
    anchors.add(preSynthesisIrDigest)
  anchors.add(computeDeterministicCasKey(serializeIRFuncDef(funcDef)))
  let strictRequired = getEnv("AXIOM_EVIDENCE_STRICT", "").len > 0
  let captureToolchainFingerprint = measureCanonicalCaptureToolchainFingerprint()
  for key in anchors.deduplicate():
    let strictBinding = loadCompletenessBinding(key,
      currentSourceIdentity = currentSourceIdentity,
      currentSubjectModuleSha256 = currentSubjectModuleSha256,
      currentSemanticProfileId = SemanticProfileV1Hash,
      currentToolchainFingerprint = captureToolchainFingerprint)
    if strictBinding.isSome:
      let b = strictBinding.get
      return some(CompletenessBindingRef(
        evidenceKey: b.evidenceKey,
        evidenceDigest: b.evidenceDigest,
        payloadDigest: sha256Hex($evidenceToJson(b.payload))))
    # A marked anchor belongs to the strict generation. A missing, corrupt or
    # stale-context binding is UNKNOWN for that anchor — never a legacy
    # fallback. The generation tag is written by the producer even when its
    # measurement fails, so "we tried and could not measure" cannot silently
    # degrade into a legacy certificate. (Unmarked pre-generation records keep
    # the compatibility path below.)
    if hasStrictGenerationMarker(key):
      continue
    if strictRequired:
      continue  # legacy fallback refused under AXIOM_EVIDENCE_STRICT
    let legacyRecord = loadEvidenceArtifact(key)
    if legacyRecord.isSome:
      return some(CompletenessBindingRef(
        payloadDigest: sha256Hex($evidenceToJson(legacyRecord.get))))
  none(CompletenessBindingRef)

func validateClaimCarrierLegs(funcDef: IRFuncDef;
    parseBound: SubjectParseBoundComponents): Result[void, string] {.raises: [].} =
  ## §2.1a claim-carrier binding (base32 rem-range binding contract §3 D2/D3):
  ## the ONE EA leg attests the single ORIGINAL subject symbol the claim is
  ## derived from (the carrier name does not exist in the subject source, so
  ## name correspondence cannot apply literally). The leg must name an
  ## original other than this funcDef and must agree; the ea2 slot must be
  ## EMPTY — a filled second leg on a single-origin carrier is a fabricated
  ## measurement, exactly the artifact the contract refuses as theater.
  if parseBound.ea2MeasuredForFuncName.len > 0 or parseBound.ea2Agreed or
      parseBound.ea2NimDigest.len > 0:
    return err("subject binding: single-origin claim carrier must carry " &
               "exactly ONE original leg (ea2 slot filled: \"" &
               parseBound.ea2MeasuredForFuncName & "\")")
  if parseBound.measuredForFuncName == funcDef.name:
    return err("subject binding: claim carrier \"" & funcDef.name &
               "\" is not a subject symbol — its EA leg must attest the " &
               "original subject symbol, not the carrier name")
  if not parseBound.eaAgreed:
    return err("subject binding: extraction agreement mismatch on '" &
               parseBound.measuredForFuncName & "' (" & parseBound.eaDetail & ")")
  Result[void, string](ok: true)

func validateCompositeLegs(funcDef: IRFuncDef;
    parseBound: SubjectParseBoundComponents): Result[void, string] {.raises: [].} =
  ## §2.1a composite binding: the EA legs attest the two ORIGINAL subject
  ## symbols (the composite name does not exist in the subject source). Both
  ## legs must be measured for distinct names other than this funcDef's, and
  ## BOTH must agree — one agreed leg with the other missing or disagreeing
  ## is exactly the "binding constructed without both EA legs" artifact the
  ## contract refuses as theater. There is no EA-free seal of a composite.
  if parseBound.measuredForFuncName == funcDef.name or
      parseBound.ea2MeasuredForFuncName == funcDef.name or
      parseBound.measuredForFuncName == parseBound.ea2MeasuredForFuncName:
    return err("subject binding: composite EA legs must be measured for the " &
               "two DISTINCT original subject symbols, not the composite \"" &
               funcDef.name & "\" (legs: \"" & parseBound.measuredForFuncName &
               "\", \"" & parseBound.ea2MeasuredForFuncName & "\")")
  if not parseBound.eaAgreed:
    return err("subject binding: extraction agreement mismatch on '" &
               parseBound.measuredForFuncName & "' (" & parseBound.eaDetail & ")")
  if not parseBound.ea2Agreed:
    return err("subject binding: extraction agreement mismatch on '" &
               parseBound.ea2MeasuredForFuncName & "' (" & parseBound.ea2Detail & ")")
  Result[void, string](ok: true)

func validateSingleSymbolLegs(funcDef: IRFuncDef;
    parseBound: SubjectParseBoundComponents): Result[void, string] {.raises: [].} =
  ## Plain single-symbol correspondence: the EA legs attest the extraction
  ## agreement FOR one function — sealing a funcDef under a different name
  ## would bind evidence about a different subject. Fail closed.
  if parseBound.measuredForFuncName != funcDef.name:
    return err("subject binding: parse-bound components were measured for \"" &
               parseBound.measuredForFuncName & "\", not this funcDef (\"" &
               funcDef.name & "\")")
  if not parseBound.eaAgreed:
    # extraction_agreement.nim contract: IR_Nim == IR_Lean byte-for-byte ELSE
    # FAIL CLOSED. Extractor disagreement is measurable but never verifiable —
    # a certificate must not be issued over a disagreed extraction.
    return err("subject binding: extraction agreement mismatch (" & parseBound.eaDetail & ")")
  Result[void, string](ok: true)

func validateParseBoundCorrespondence(funcDef: IRFuncDef;
    parseBound: SubjectParseBoundComponents): Result[void, string] {.raises: [].} =
  ## §2.1a per-mode correspondence gates for the pre-measured parse-bound legs.
  ## Pure and raises-free — the binding site calls this after the presence
  ## gate and fails closed on its error.
  if parseBound.synthesizedComposite and parseBound.claimCarrierSingleOrigin:
    return validateClaimCarrierLegs(funcDef, parseBound)
  elif parseBound.synthesizedComposite:
    return validateCompositeLegs(funcDef, parseBound)
  else:
    return validateSingleSymbolLegs(funcDef, parseBound)

func assembleSubjectBinding(firstObl: VerificationObligation;
                            inputHash, irHash, subjectGitRef, treeMerkle: string;
                            parseBound: SubjectParseBoundComponents;
                            completenessDigest: string): ObligationSubjectBinding {.
    raises: [].} =
  ## Pure assembly of the binding record from measured components — the
  ## seal-site components stay empty here; the caller fills them from the
  ## kernel receipt (DEBT#490).
  ObligationSubjectBinding(
    obligationTupleId: computeObligationId(firstObl.subject, firstObl.kind,
      firstObl.assumptions, firstObl.predicate, firstObl.derivationRule),
    subjectTreeMerkleRoot: treeMerkle,
    subjectModuleSha256: inputHash,
    subjectGitRef: subjectGitRef,
    pnodeCanonicalV2Digest: parseBound.pnodeCanonicalV2Digest,
    irDigest: irHash,
    eaNimDigest: parseBound.eaNimDigest,
    eaLeanDigest: parseBound.eaLeanDigest,
    eaIrcheckBinaryDigest: parseBound.eaIrcheckBinaryDigest,
    eaAgreed: parseBound.eaAgreed,
    completenessRecordDigest: completenessDigest,
    leanSourceHash: "",
    toolchainFingerprint: "",
    synthesisDerivationDigest: parseBound.synthesisDerivationDigest,
    claimCarrierSingleOrigin: parseBound.claimCarrierSingleOrigin,
    ea2NimDigest: parseBound.ea2NimDigest,
    ea2LeanDigest: parseBound.ea2LeanDigest,
    ea2IrcheckBinaryDigest: parseBound.ea2IrcheckBinaryDigest,
    ea2Agreed: parseBound.ea2Agreed
  )

proc buildSubjectBinding(funcDef: IRFuncDef; firstObl: VerificationObligation;
                         inputHash, irHash: string;
                         moduleSource, sourcePath, subjectRepoRoot,
                         preSynthesisIrDigest: string;
                         contentCarried: bool;
                         parseBound: SubjectParseBoundComponents): Result[
    tuple[binding: ObligationSubjectBinding,
          completeness: CompletenessBindingRef], string] {.
  raises: [], axiomDecision, axiomEffect: IOEffect,
  tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## §2.1a measurement site: constructs the ObligationSubjectBinding from
  ## measured components only. Any unmeasurable component → err → the caller
  ## refuses to seal (no bound id ⇒ no verified certificate). The two
  ## seal-site components (`leanSourceHash`, `toolchainFingerprint`) are
  ## filled by the caller after the kernel receipt exists — they are measured
  ## from this execution, never composed independently (DEBT#490). The
  ## parse-bound components (`parseBound`) are measured on the MAIN thread at
  ## the selection boundary and threaded here as values — this worker-chain
  ## site never parses subject source (the parser and the differential
  ## extractor hold process globals and are not gcsafe).
  ##
  ## The completeness read is strict-first (Phase 1A): the strict
  ## CompletenessBinding is loaded under the canonical source identity
  ## (composeCompletenessSourceIdentity over the git ref, tree merkle and
  ## module digest measured above — the SAME composite the producers
  ## recorded) and the current module sha. On success the ref travels to the
  ## evidence seal; only its payloadDigest enters
  ## `completenessRecordDigest` (bound-obligation representation stays
  ## legacy-compatible). Strict miss with AXIOM_EVIDENCE_STRICT unset falls
  ## back to the legacy artifact; with the flag set it fails the binding
  ## closed.
  if moduleSource.len == 0:
    return err("subject binding: §6a module source bytes unavailable")
  let subjectRoot = resolveSubjectRepoRoot(subjectRepoRoot, sourcePath, contentCarried)
  let subjectGitRef = measureSubjectGitRef(subjectRoot)
  if subjectGitRef.len == 0:
    return err("subject binding: subjectGitRef unmeasurable (no resolvable git " &
               "identity for the subject repo at \"" & subjectRoot & "\")")
  let treeMerkle = measureSubjectTreeMerkleRoot(subjectRoot, sourcePath, moduleSource)
  if treeMerkle.len == 0:
    return err("subject binding: subjectTreeMerkleRoot unmeasurable")
  # Parse-bound components (pnodeV2 + extraction agreement) arrive pre-measured
  # from the selection boundary; unmeasured legs fail the binding closed.
  if not parseComponentsMeasured(parseBound):
    return err("subject binding: parse-bound components unmeasured at the " &
               "selection boundary (pnodeV2/extraction agreement" &
               (if parseBound.eaDetail.len > 0: ": " & parseBound.eaDetail else: "") & ")")
  let correspondence = validateParseBoundCorrespondence(funcDef, parseBound)
  if correspondence.isErr:
    return err(correspondence.error)
  let completenessRef = measureCompletenessRecordDigest(funcDef,
    preSynthesisIrDigest,
    composeCompletenessSourceIdentity(subjectGitRef, treeMerkle, inputHash),
    inputHash)
  if completenessRef.isNone:
    return err("subject binding: completeness record unmeasurable — no strict " &
               "CompletenessBinding (and, only when AXIOM_EVIDENCE_STRICT is " &
               "unset, no legacy CompletenessEvidence artifact) for this funcDef " &
               "(the external materializer must run before canonical verification)")
  ok((binding: assembleSubjectBinding(firstObl, inputHash, irHash, subjectGitRef,
       treeMerkle, parseBound, completenessRef.get.payloadDigest),
      completeness: completenessRef.get))

proc verifyGeneratedObligation(funcDef: IRFuncDef;
                               obligations: LightNonEmptySeq[VerificationObligation];
                               inputHash, irHash: string;
                               moduleSource, sourcePath, subjectRepoRoot,
                               preSynthesisIrDigest: string;
                               contentCarried: bool;
                               parseBound: SubjectParseBoundComponents): CanonicalVerificationResult {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect, TimeEffect].} =
  ## The proof path: obligations exist and were rendered to Lean, so the kernel
  ## is consulted and its acceptance (or refusal) becomes the result.
  ## §2.1a: the kernel is only consulted for a subject whose binding set is
  ## fully measurable — an unmeasurable component fails closed BEFORE the
  ## kernel run (no bound id ⇒ no verified certificate is possible).
  let firstObl = obligations.value[0]
  let obligationCount = obligations.value.len
  let proposition = firstObl.predicate
  let propositionHash = sha256Hex(proposition)

  # Step 3: Render the I6 Lean source from the funcDef body and postconditions.
  let leanSource = renderLeanForFuncDef(funcDef)
  if leanSource.len == 0:
    # Bounded subset exceeded / no postcondition → fail-closed (candidate).
    var res = baseVerificationResult(firstObl.kind, obligationCount, inputHash, irHash)
    res.obligationHash = propositionHash
    return res
  let leanSourceHash = sha256Hex(leanSource)

  # Step 3b: §2.1a subject binding measurement (fail-closed). The two seal-site
  # components (leanSourceHash, toolchainFingerprint) are filled at Step 8b —
  # they are measured from this execution, never composed independently.
  let bindingResult = buildSubjectBinding(funcDef, firstObl, inputHash, irHash,
    moduleSource, sourcePath, subjectRepoRoot, preSynthesisIrDigest,
    contentCarried, parseBound)
  if bindingResult.isErr:
    var res = baseVerificationResult(firstObl.kind, obligationCount, inputHash, irHash)
    res.obligationHash = propositionHash
    res.leanSourceHash = leanSourceHash
    res.artifactIdentity = leanSourceHash
    res.sealError = bindingResult.error
    return res
  var binding = bindingResult.get().binding
  let completenessRef = bindingResult.get().completeness

  # Step 4: Build LeanLowering record
  let lowering = LeanLowering(
    obligationId: firstObl.id,
    proposition: proposition,
    propositionHash: propositionHash,
    leanSource: leanSource,
    leanSourceHash: leanSourceHash
  )

  # Step 5: Run canonicalLeanKernelCheck on the Lean source.
  let kernelResult = runKernelCheck(leanSource)
  if kernelResult.isErr:
    return kernelRejectedResult(firstObl.kind, obligationCount, inputHash, irHash, propositionHash, leanSourceHash, "")
  let receipt = kernelResult.get()

  # Step 6: capture the axiom profile and the measured sorry profile, then
  # bindReceipt → KAA (the KAA records what was actually observed).
  let kaaResult = bindReceipt(receipt, captureKernelAxioms(receipt, leanSource),
                              scanSorryMarkers(leanSource, receipt.receiptKernelObservation))
  if kaaResult.isErr:
    return kernelRejectedResult(firstObl.kind, obligationCount, inputHash, irHash, propositionHash, leanSourceHash, receipt.receiptKernelObservation)
  let kaa = kaaResult.get()

  # Step 7: evaluate(kaa, policy) → verdict (non-empty allowlist + spForbid,
  # per docs/spec/base36_sizing_binding_contract.md §5).
  let verdict = evaluate(kaa, canonicalVerificationPolicy())

  # Step 8: build the execution contract (its mounted input is the rendered
  # source digest) and bind the execution identity under it.
  let contractDigest = executionContractDigest(buildExecutionContract(leanSourceHash))
  let (bundleFp, execId) = bindExecutionIdentity(receipt, leanSourceHash, contractDigest, funcDef)

  # Step 8b: complete the binding with the two components measured from THIS
  # execution: the rendered source and the kernel-measured toolchain
  # fingerprint. DEBT#490: the CLE factory requires exactly the receipt's
  # fingerprint here — the composed bundle fingerprint (`bundleFp`) is the
  # execution-identity input, NOT the CLE fingerprint.
  binding.leanSourceHash = leanSourceHash
  binding.toolchainFingerprint = receipt.receiptToolchainFingerprint
  let boundId = computeBoundObligationId(binding)

  # Step 9: build the self-contained durable evidence object binding obligation,
  # proposition, source, KAA and execution identity into one sealed unit —
  # sealed under the subject-bound identity (§2.1a), via the single
  # subject-bound seal authority `newCanonicalLeanEvidenceBound`.
  let cleResult =
    if boundId.len == 0:
      Result[CanonicalLeanEvidence, string](
        ok: false,
        err: "subject binding is incomplete at the seal site — no bound obligation " &
             "identity exists (fail-closed)")
    else:
      newCanonicalLeanEvidenceBound(
        obligationId = boundId,
        binding = binding,
        funcDef = funcDef,
        proposition = proposition,
        leanSource = leanSource,
        kaa = kaa,
        toolchainFingerprint = receipt.receiptToolchainFingerprint,
        executionContractDigest = contractDigest,
        completeness = completenessRef
      )

  result = baseVerificationResult(firstObl.kind, obligationCount, inputHash, irHash)
  result.evidence = "lean_kernel_accepted"
  result.verdict = verdict
  result.obligationHash = propositionHash
  result.leanSourceHash = leanSourceHash
  result.proofDigest = receipt.receiptKernelObservation
  result.kaaIdentity = kaaIdentity(kaa, execId)
  result.artifactIdentity = leanSourceHash
  result.canonicalEvidence = if cleResult.isOk: some(cleResult.get()) else: none(CanonicalLeanEvidence)
  # DEBT#490: the seal error is carried on the result, never silently dropped,
  # and no verified result exists without a sealed subject-bound
  # canonicalEvidence (fail-closed).
  result.sealError = if cleResult.isOk: "" else: cleResult.error
  result.success = (verdict == vdVerified) and cleResult.isOk

proc executeCanonicalVerification*(
  funcDef: IRFuncDef;
  sourcePath: string;
  funcName: string;
  sourceContent: string = "";
  subjectRepoRoot: string = "";
  preSynthesisIrDigest: string = "";
  parseBound: SubjectParseBoundComponents = SubjectParseBoundComponents()
): CanonicalVerificationResult =
  ## `subjectRepoRoot`: the subject repo root threaded from the pipeline
  ## (the engine's analysis root). Empty means "resolve internally" — for
  ## internal subjects that is the CWD repo; a content-carried external
  ## subject without a threaded root has NO resolvable subject root and the
  ## §2.1a binding fails closed (WP4-a B-5b: subject-relative sourcePath is
  ## never resolved against the process CWD).
  ## `preSynthesisIrDigest`: the CAS key of the PRE-synthesis funcDef
  ## serialization (the completeness-artifact anchor the materializer wrote);
  ## empty means only the current funcDef's key is searched.
  let inputHash = resolveSourceHashForVerification(sourceContent, sourcePath)
  let irHash = sha256Hex(serializeIRFuncDef(funcDef))
  let moduleSource = resolveSubjectModuleSource(sourceContent, sourcePath)

  if inputHash.len == 0:
    # Fail closed: §6a input identity is (sourceHash, irHash) and the source
    # half is unavailable, so no verdict may be issued from this invocation.
    # A path- or name-derived digest is never substituted here.
    return baseVerificationResult(okContractPost, 0, inputHash, irHash)

  # Step 1: Generate obligations from funcDef
  let scopePolicy = defaultScopePolicy()
  let ogr = generateCanonicalObligations(funcDef, scopePolicy)

  case ogr.kind
  of ogrNoApplicableObligation, ogrUnsupported, ogrIllFormed:
    baseVerificationResult(okContractPost, 0, inputHash, irHash)
  of ogrGenerated:
    verifyGeneratedObligation(funcDef, ogr.obligations, inputHash, irHash,
      moduleSource, sourcePath, subjectRepoRoot, preSynthesisIrDigest,
      sourceContent.len > 0, parseBound)
