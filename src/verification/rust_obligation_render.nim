import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

## Rust obligation → Lean renderer + extraction-bounded claim gate primitives
## (feat/rust-subject-v1, Phase 2-E — plan 정정 14).
##
## This module is the Rust lane's counterpart of the Nim lane's rendering
## discipline in `verification/obligation/canonical_verification.nim`
## (renderLeanForFuncDef). It reuses the Nim lane's lowering functions
## VERBATIM (`lowerIRExprToLean`, `lowerPostconditionToLean`,
## `irTypeToLeanTy`, `containsIdentToken`) so the proposition/theorem
## structure is byte-for-byte the same template family — def + one I6
## theorem closed by `intro … / unfold … / omega`. Nothing here free-composes
## Lean text: the ONLY inputs are the shared Rust canonical, its wire digest,
## and the caller's spec postcondition; every Lean token the kernel sees is
## emitted by the fixed template below.
##
## Closed template family (the ONLY shape this module can emit, and the only
## shape the mint gate admits for a Rust success certificate):
##
##   def <f> : Int → … → Int :=
##   fun p1 … pn => <lowered body>
##
##   theorem <f>_post :
##   ∀ (p1 : Int) …, <pre₁> → … → <post[result := (<f> p1 … pn)]> := by
##   intro p1 … pn h0 … h(k-1)
##   unfold <f>            (only when the proposition references the def)
##   omega
##
## Width discipline (docs/spec/rust_certified_subset.md §1 — the two
## conditions are generated with DIFFERENT origins and never conflated):
##   1. Type-derived range per integer param — `0 ≤ p ∧ p < 2^width`
##      (origin aoTypeDerived, mechanically from the canonical's recorded
##      Rust type — the source the IR type system lost).
##   2. Caller overflow obligation per `+` node — `(lhs + rhs) < 2^width`
##      (origin aoCallerObligation; plain `+` is admitted only where this is
##      discharged). Collected from the INLINED body, deduplicated in
##      first-occurrence order.
##
## SSA let-inlining: `rustCanonicalToIr` represents intermediate places as
## `irLet` (single-assignment, SSA-fresh). The Nim lane's lowering fails
## closed on `irLet`, so this module first inlines the lets (acyclic by the
## single-assignment invariant — substitution is total and terminating).
## Inlining preserves semantics exactly and keeps the rendered body inside
## the Nim lane's bounded subset.
##
## Extraction-bounded claim gate: `RustBoundedClaim` + `rustBoundedClaimRefusal`
## are the mint-time checks consumed by cert_writer.nim. A Rust success
## certificate may only carry claims whose accepted Lean artifact is a member
## of the template family above (skeleton allowlist), whose persisted
## proposition is byte-identical to the accepted source's proposition, and
## whose proposition ↔ obligation ↔ RustCanonical digests co-bind. The
## extractor-identity check (`rustExtractorIdentityRefusal`) mirrors the KAA
## mint-time fingerprint refusal (kernel_acceptance_authority.nim): the
## recorded extractor identity must equal the CURRENT pinned reference
## extractor's measured identity — a swapped/overridden extractor between
## extraction and mint refuses issuance.

import std/[options, sets, os, strutils]

import core/axiom_pragmas
import core/crypto/hash_kernel
import core/trusted/axiom_ir
import core/trusted/axiom_ir_helpers
import core/trusted/rust_canonical
import core/utils/repo_root
import verification/obligation/canonical_verification
import verification/obligation/obligation_types
import verification/rust_extraction_agreement

const RustBoundedTemplateVersion* = "axiom.rust.bounded-template/1"
  ## Version tag folded into every skeleton hash — a template change is a
  ## family cutover (old claims stop verifying at mint instead of silently
  ## passing under the new shape).

# ---------------------------------------------------------------------------
# SSA let-inlining (Rust derivation shapes)
# ---------------------------------------------------------------------------

# `inlineLets` (and its private `substVar`) live beside the derivation they
# inline — rust_extraction_agreement.nim (the renderer imports that module,
# so the public surface of THIS module is unchanged).
export rust_extraction_agreement.inlineLets

func collectAddNodes*(e: IRExpr; acc: var seq[IRExpr]) {.raises: [].} =
  ## First-occurrence-order collection of every `boAdd` node (the plain `+`
  ## the checked-add collapse produced) — each one owes a caller overflow
  ## obligation.
  if e.isNil:
    return
  case e.kind
  of irBinOp:
    if e.binOp == boAdd:
      acc.add(e)
    collectAddNodes(e.binLhs, acc)
    collectAddNodes(e.binRhs, acc)
  of irIf:
    collectAddNodes(e.ifCond, acc)
    collectAddNodes(e.ifThen, acc)
    collectAddNodes(e.ifElse, acc)
  of irUnaryOp:
    collectAddNodes(e.unaryArg, acc)
  else:
    discard

# ---------------------------------------------------------------------------
# Template skeleton classification + allowlist
# ---------------------------------------------------------------------------

func rustTemplateSkeleton*(leanSource: string): string {.raises: [].} =
  ## Classify the source line-by-line against the closed template grammar and
  ## return the skeleton token string — or "" when ANY line is outside the
  ## family (unknown declaration, unknown tactic, extra content). Subject
  ## tokens (names, body, proposition) are abstracted away by the
  ## classification; only the TEMPLATE SHAPE remains.
  if leanSource.len == 0:
    return ""
  var defName = ""
  var toks: seq[string] = @[]
  for rawLine in leanSource.splitLines():
    let line = rawLine.strip()
    if line.len == 0:
      continue
    if line.startsWith("def ") and line.endsWith(":="):
      let rest = line["def ".len .. ^1]
      let nameEnd = rest.find(' ')
      if nameEnd <= 0:
        return ""
      defName = rest[0 ..< nameEnd]
      toks.add("def")
    elif line.startsWith("fun ") and line.contains(" => ") and defName.len > 0:
      toks.add("fun")
    elif line == "theorem " & defName & "_post :" and defName.len > 0:
      toks.add("thm")
    elif line.endsWith(" := by") and defName.len > 0:
      toks.add("prop")
    elif line.startsWith("intro ") and defName.len > 0:
      toks.add("intro")
    elif line == "unfold " & defName and defName.len > 0:
      toks.add("unfold")
    elif line == "omega":
      toks.add("omega")
    else:
      return ""  # ANY other line is outside the closed family
  toks.join(";")

func rustBoundedTemplateFamilyHashes*(): seq[string] {.raises: [].} =
  ## The closed allowlist: every skeleton the renderer can emit. A Rust mint
  ## is refused unless the accepted artifact's skeleton hash is IN this set.
  let skeletons = [
    "def;fun;thm;prop;intro;unfold;omega",   # params + pres + result-bound post
    "def;fun;thm;prop;intro;omega",          # params + pres, result-free post
    "def;fun;thm;prop;unfold;omega",         # params, no pres, result-bound post
    "def;fun;thm;prop;omega",                # params, no pres, result-free post
  ]
  for s in skeletons:
    result.add(sha256Hex(RustBoundedTemplateVersion & "|" & s))

func rustTemplateSkeletonHash*(leanSource: string): string {.raises: [].} =
  ## The skeleton hash of a source — "" when the source is outside the family.
  let skeleton = rustTemplateSkeleton(leanSource)
  if skeleton.len == 0:
    return ""
  sha256Hex(RustBoundedTemplateVersion & "|" & skeleton)

func rustTemplateInFamily*(leanSource: string): bool {.raises: [].} =
  ## Allowlist membership test (the mint gate's shape check).
  let h = rustTemplateSkeletonHash(leanSource)
  h.len > 0 and h in rustBoundedTemplateFamilyHashes()

func rustPropositionFromSource*(leanSource: string): string {.raises: [].} =
  ## Extract the proposition text (the theorem body line, " := by" stripped)
  ## from a family-shaped source; "" when the shape does not match. The mint
  ## gate requires this to equal the persisted proposition byte-for-byte.
  var defName = ""
  var afterTheorem = false
  for rawLine in leanSource.splitLines():
    let line = rawLine.strip()
    if line.len == 0:
      continue
    if line.startsWith("def ") and line.endsWith(":="):
      let rest = line["def ".len .. ^1]
      let nameEnd = rest.find(' ')
      if nameEnd <= 0:
        return ""
      defName = rest[0 ..< nameEnd]
    elif line == "theorem " & defName & "_post :" and defName.len > 0:
      afterTheorem = true  # the proposition is the NEXT non-empty line
    elif afterTheorem and line.endsWith(" := by"):
      return line[0 ..< line.len - " := by".len]
  ""

# ---------------------------------------------------------------------------
# Width conditions — the two-origin precondition set (rust_certified_subset §1)
# ---------------------------------------------------------------------------

type RustWidthPrecondition* = object
  origin*: AssumptionOrigin
  pred*: IRExpr
    ## A precondition IRExpr over the function parameters (Int domain).

func widthBound(widthBits: int): Option[int64] {.raises: [].} =
  ## 2^widthBits for the closed width set (8/32); none marks "not
  ## representable" — width 64 has no 2^64 bound in the int64 literal domain
  ## (the width-64 forms bound at 2^64−1 instead, a different shape; the
  ## canonical validator already admits only 8/32/64 unsigned integers, so
  ## this remains defense in depth, fail-closed).
  case widthBits
  of 8: some(256'i64)
  of 32: some(4294967296'i64)
  else: none(int64)

func rustTypeRangePrecondition*(paramName: string; ty: RustType):
    RustWidthPrecondition {.raises: [].} =
  ## Condition 1 — type-derived range `0 ≤ p ∧ p < 2^width`, origin
  ## aoTypeDerived (mechanically from the recorded Rust type).
  ## Width-64 (v1.2): the two-part literal form carries the 2^64−1 ceiling,
  ## so the hypothesis is the honest FULL range
  ## `0 ≤ p ∧ p ≤ 18446744073709551615` — the v1.1 lower-bound-only shape is
  ## retired with the wall that forced it. Full-width '+' no longer refuses
  ## upstream either: the caller obligation discharges in the closed-form
  ## equivalent `lhs + rhs ≤ 18446744073709551615` (rustOverflowPrecondition).
  let bv = irTypeBitVec64()
  if ty.widthBits == 64:
    return RustWidthPrecondition(
      origin: aoTypeDerived,
      pred: irAnd(irLe(irLit(0), irVar(paramName, bv)),
                  irLe(irVar(paramName, bv), irLitU64(u64DomainHigh))))
  RustWidthPrecondition(
    origin: aoTypeDerived,
    pred: irAnd(irLe(irLit(0), irVar(paramName, bv)),
                irLt(irVar(paramName, bv),
                     irLit(widthBound(ty.widthBits).get(0'i64)))))

func rustOverflowPrecondition*(addNode: IRExpr; subjectWidthBits: int):
    RustWidthPrecondition {.raises: [].} =
  ## Condition 2 — caller overflow obligation, origin aoCallerObligation.
  ## `addNode` must be a `boAdd` node of the INLINED body (its operand
  ## sub-expressions are reused verbatim). 8/32: `(lhs + rhs) < 2^width`.
  ## 64 (v1.2): the closed-form equivalent `(lhs + rhs) ≤ 2^64−1` —
  ## mathematically exact over Int (omega-closable), and deliberately NOT a
  ## wrapping BV64 addition (which would be trivially bounded — theater).
  doAssert addNode.kind == irBinOp and addNode.binOp == boAdd
  if subjectWidthBits == 64:
    return RustWidthPrecondition(
      origin: aoCallerObligation,
      pred: irLe(irAdd(addNode.binLhs, addNode.binRhs),
                 irLitU64(u64DomainHigh)))
  let bound = widthBound(subjectWidthBits).get(0'i64)
  RustWidthPrecondition(
    origin: aoCallerObligation,
    pred: irLt(irAdd(addNode.binLhs, addNode.binRhs), irLit(bound)))

func subjectWidthBits(canonical: RustCanonical): int {.raises: [].} =
  ## The subject-uniform width: the maximum integer width among the recorded
  ## param/return types (v1 subjects are width-uniform per the canonical's
  ## closed type set; the max keeps a mixed-shape honest rather than guessed).
  result = 0
  for p in canonical.params:
    if p.ty.kind == rtyInt and p.ty.widthBits > result:
      result = p.ty.widthBits
  if canonical.retType.kind == rtyInt and canonical.retType.widthBits > result:
    result = canonical.retType.widthBits

func buildWidthPreconditions*(canonical: RustCanonical; body: IRExpr):
    seq[RustWidthPrecondition] {.raises: [].} =
  ## The full two-origin precondition set: one type-derived range per integer
  ## param (width 64 → full range ≤ 2^64−1 — see rustTypeRangePrecondition),
  ## then one deduplicated caller overflow obligation per distinct `+` node
  ## of the inlined body (dedup by canonical predicate text, first-occurrence
  ## order — the inlined mutant body repeats its inner add). Width 64 emits
  ## the closed-form obligation `(lhs+rhs) ≤ 2^64−1` — representable since
  ## the v1.2 two-part literal form, so a body containing `+` no longer
  ## refuses here. Widths outside the closed set still yield NO precondition
  ## set (nothing can soundly restore them — this refusal is the
  ## defense-in-depth mirror, never the primary gate).
  let width = subjectWidthBits(canonical)
  for p in canonical.params:
    if p.ty.kind == rtyInt:
      if p.ty.widthBits notin {8, 32, 64}:
        return @[]  # width outside the closed set — no precondition can restore it
      result.add(rustTypeRangePrecondition(p.name, p.ty))
    elif p.ty.kind == rtyBool:
      # v1.3 bool-expression row: the Int 0/1 embedding's domain.
      let bv = irTypeBitVec64()
      result.add(RustWidthPrecondition(
        origin: aoTypeDerived,
        pred: irAnd(irLe(irLit(0), irVar(p.name, bv)),
                    irLt(irVar(p.name, bv), irLit(2)))))
  var adds: seq[IRExpr] = @[]
  collectAddNodes(body, adds)
  if adds.len == 0:
    return
  if width == 0 or (width != 64 and widthBound(width).isNone):
    return @[]  # '+' present but no dischargeable bound form for this width — refuse
  var seen: seq[string] = @[]
  for node in adds:
    let pre = rustOverflowPrecondition(node, width)
    let canon = canonicalizePredicate(pre.pred)
    if canon notin seen:
      seen.add(canon)
      result.add(pre)

# ---------------------------------------------------------------------------
# The renderer — closed template family, reusing the Nim lane's lowering
# ---------------------------------------------------------------------------

type RustObligationRender* = object
  ok*: bool
  reason*: string              ## refusal reason when not ok (fail-closed "")
  obligationId*: string        ## C4 identity (computeObligationId) of the obligation
  proposition*: string         ## the full Lean proposition (theorem body text)
  leanSource*: string          ## the rendered Lean 4 artifact
  templateHash*: string        ## skeleton hash — member of the family allowlist
  obligationDigest*: string    ## H(rustCanonicalDigest | proposition | leanSource)

func renderRustObligationLean*(canonical: RustCanonical;
                               rustCanonicalDigest: string;
                               specPost: IRExpr): RustObligationRender {.
    raises: [].} =
  ## Render the closed-template Lean source for one Rust subject + spec
  ## postcondition, or return not-ok with the precise refusal reason.
  ## Every failure is fail-closed — a partial or fabricated source is never
  ## returned (the empty leanSource is the refusal marker, as in the Nim lane).
  # 0. The subject must be a validated canonical of the closed grammar.
  let v = validateRustCanonical(canonical)
  if v != rceNone:
    return RustObligationRender(ok: false,
      reason: "canonical failed validation: " & rustCanonicalErrorReason(v))
  if canonical.funcName.len == 0:
    return RustObligationRender(ok: false, reason: "canonical has no function name")
  if canonical.params.len == 0:
    return RustObligationRender(ok: false,
      reason: "zero-parameter subjects are outside the rendered family v1 " &
              "(fail-closed scope choice)")
  if rustCanonicalDigest.len != 64:
    return RustObligationRender(ok: false,
      reason: "rustCanonicalDigest is not a SHA256 hex digest")
  if specPost.isNil:
    return RustObligationRender(ok: false, reason: "spec postcondition is empty")

  # 1. The Nim-leg IR derivation (the SAME derivation the INV-4 differential
  #    byte-compared against the Lean reference extractor — reused, not forked).
  let derivation = rustCanonicalToIr(canonical)
  if not derivation.ok:
    return RustObligationRender(ok: false,
      reason: "Nim-leg derivation failed: " & derivation.error)

  # 2. SSA let-inlining → the Nim lane's bounded-subset lowering applies.
  let body = inlineLets(derivation.body)
  var paramNames = initHashSet[string]()
  for p in canonical.params:
    if p.name.len == 0:
      return RustObligationRender(ok: false, reason: "unnamed parameter")
    if p.name == "result":
      return RustObligationRender(ok: false,
        reason: "'result' is reserved as the postcondition free variable")
    paramNames.incl(p.name)
  let loweredBody = lowerIRExprToLean(body, paramNames)
  if loweredBody.len == 0:
    return RustObligationRender(ok: false,
      reason: "lowered body outside the bounded rendering subset")

  # 3. The two-origin width precondition set.
  let pres = buildWidthPreconditions(canonical, body)
  if pres.len == 0:
    return RustObligationRender(ok: false,
      reason: "width preconditions unrepresentable for the recorded types")
  var loweredPres: seq[string] = @[]
  var assumptionCanonicals: seq[string] = @[]
  for pre in pres:
    let lowered = lowerIRExprToLean(pre.pred, paramNames)
    if lowered.len == 0:
      return RustObligationRender(ok: false,
        reason: "width precondition outside the bounded rendering subset")
    loweredPres.add(lowered)
    assumptionCanonicals.add($pre.origin & ":" & canonicalizePredicate(pre.pred))

  # 4. The spec postcondition, `result` bound to the lowered body application.
  let postText = lowerPostconditionToLean(specPost, canonical.funcName,
                                          paramNames)
  if postText.len == 0:
    return RustObligationRender(ok: false,
      reason: "spec postcondition outside the bounded rendering subset (free " &
              "variables must be parameters or 'result')")

  # 5. Emit the template — the Nim lane's def + I6 theorem structure.
  var defSig = "def " & canonical.funcName & " : "
  for p in canonical.params:
    let lt = irTypeToLeanTy(rustIrType(p.ty))
    if lt.len == 0:
      return RustObligationRender(ok: false,
        reason: "param type outside the width-uniform Int domain")
    defSig.add(lt & " → ")
  defSig.add("Int")
  var binder = "fun"
  for p in canonical.params:
    binder.add(" " & p.name)
  var src = defSig & " :=\n  " & binder & " => " & loweredBody & "\n"

  let needsUnfold = containsIdentToken(postText, canonical.funcName)
  var binderPart = "∀ ("
  for i, p in canonical.params:
    if i > 0:
      binderPart.add(") (")
    binderPart.add(p.name & " : Int")
  binderPart.add("), ")
  for lowered in loweredPres:
    binderPart.add(lowered & " → ")
  let proposition = binderPart & postText
  src.add("\ntheorem " & canonical.funcName & "_post :\n")
  src.add("  " & proposition & " := by\n")
  var introLine = "  intro"
  for p in canonical.params:
    introLine.add(" " & p.name)
  for i in 0 ..< loweredPres.len:
    var hyp = "h" & $i
    while paramNames.contains(hyp):
      hyp = hyp & "_h"
    introLine.add(" " & hyp)
  src.add(introLine & "\n")
  if needsUnfold:
    src.add("  unfold " & canonical.funcName & "\n")
  src.add("  omega\n")

  # 6. Identity digests — the co-binding triple the mint gate re-derives.
  let obligationId = computeObligationId(
    subject = "rust:" & canonical.modulePath & ":" & canonical.funcName,
    kind = okContractPost,
    canonicalAssumptions = assumptionCanonicals.join("|"),
    canonicalPredicate = canonicalizePredicate(specPost),
    derivationRule = "rust-subject-v1/straight-line-omega",
    assumptionOrigin = aoUserDeclared)
  let templateHash = rustTemplateSkeletonHash(src)
  if templateHash.len == 0:
    return RustObligationRender(ok: false,
      reason: "rendered source does not classify into the template family " &
              "(renderer/template divergence — fail-closed)")
  RustObligationRender(
    ok: true,
    obligationId: obligationId,
    proposition: proposition,
    leanSource: src,
    templateHash: templateHash,
    obligationDigest: sha256Hex(
      rustCanonicalDigest & "|" & proposition & "|" & src))

# ---------------------------------------------------------------------------
# Guard mode — declaration-free proof attempts (undeclared denominators)
# ---------------------------------------------------------------------------

func rustGuardGoals*(canonical: RustCanonical): seq[IRExpr] {.raises: [].} =
  ## One mechanical guard goal per DISTINCT `+` node of the INLINED body:
  ## `irLt(irAdd(lhs, rhs), irLit(2^width))` — the overflow obligation
  ## RELOCATED from hypothesis to GOAL (the declaration-free attempt's whole
  ## point: the caller never owed these, so nothing is laundered into an
  ## assumption). Same collection/dedup/first-occurrence discipline as the
  ## existing hypothesis collector (buildWidthPreconditions:
  ## collectAddNodes + canonicalizePredicate dedup), same width rule
  ## (subjectWidthBits — v1 subjects are width-uniform), operands reused
  ## verbatim via rustOverflowPrecondition. Empty for no-arithmetic bodies
  ## and for any derivation/validation failure (the caller has already
  ## classified those — eaAgree — so empty simply means "no goals").
  let derivation = rustCanonicalToIr(canonical)
  if not derivation.ok:
    return
  let body = inlineLets(derivation.body)
  let width = subjectWidthBits(canonical)
  if width == 0 or (width != 64 and widthBound(width).isNone):
    return
  var adds: seq[IRExpr] = @[]
  collectAddNodes(body, adds)
  var seen: seq[string] = @[]
  for node in adds:
    let goal = rustOverflowPrecondition(node, width).pred
    let canon = canonicalizePredicate(goal)
    if canon notin seen:
      seen.add(canon)
      result.add(goal)

proc renderRustGuardObligationLean*(canonical: RustCanonical;
                                    rustCanonicalDigest: string;
                                    goal: IRExpr): RustObligationRender {.
    raises: [].} =
  ## GUARD MODE of the closed-template renderer: hypotheses are the
  ## TYPE-DERIVED RANGES ONLY (aoTypeDerived, one per int param — the SAME
  ## range-construction path rustTypeRangePrecondition), the post is the
  ## guard goal itself, and the caller-overflow conditions appear NOWHERE as
  ## hypotheses. Spike S1 (tmp/guard_spike/s1_s6_render.nim) showed why the
  ## standard renderer must never mint a guard: with specPost = the overflow
  ## condition, the collected body hypothesis equals the goal → trivial
  ## accept = theater. Template emission, lowering reuse, refusals, and
  ## identity digests mirror renderRustObligationLean exactly; the only
  ## divergence is the hypothesis set (ranges only) and the identity's
  ## derivationRule/origin, which keep a guard artifact's C4 identity
  ## DISTINCT from any declared-spec artifact. The record is evidence of an
  ## ATTEMPT — never mint-admissible on its own (undeclared lane entries
  ## issue no certificate; the lane classification stays "unknown").
  # 0. The same refusals as the standard renderer (nil goal, zero params,
  #    reserved 'result', 64-hex digest; canonical validation; the bool/width
  #    refusals fire in the def-signature/range loops below, exactly as in
  #    renderRustObligationLean).
  let v = validateRustCanonical(canonical)
  if v != rceNone:
    return RustObligationRender(ok: false,
      reason: "canonical failed validation: " & rustCanonicalErrorReason(v))
  if canonical.funcName.len == 0:
    return RustObligationRender(ok: false, reason: "canonical has no function name")
  if canonical.params.len == 0:
    return RustObligationRender(ok: false,
      reason: "zero-parameter subjects are outside the rendered family v1 " &
              "(fail-closed scope choice)")
  if rustCanonicalDigest.len != 64:
    return RustObligationRender(ok: false,
      reason: "rustCanonicalDigest is not a SHA256 hex digest")
  if goal.isNil:
    return RustObligationRender(ok: false, reason: "guard goal is empty")

  # 1+2. The Nim-leg derivation, SSA-inlined, lowered — byte-identical to the
  #      standard renderer's body path (VERBATIM lowering reuse).
  let derivation = rustCanonicalToIr(canonical)
  if not derivation.ok:
    return RustObligationRender(ok: false,
      reason: "Nim-leg derivation failed: " & derivation.error)
  let body = inlineLets(derivation.body)
  var paramNames = initHashSet[string]()
  for p in canonical.params:
    if p.name.len == 0:
      return RustObligationRender(ok: false, reason: "unnamed parameter")
    if p.name == "result":
      return RustObligationRender(ok: false,
        reason: "'result' is reserved as the postcondition free variable")
    paramNames.incl(p.name)
  let loweredBody = lowerIRExprToLean(body, paramNames)
  if loweredBody.len == 0:
    return RustObligationRender(ok: false,
      reason: "lowered body outside the bounded rendering subset")

  # 3. Hypotheses: the type-derived ranges ONLY — no overflow condition is
  #    ever assumed here (the goal IS the overflow condition).
  var loweredPres: seq[string] = @[]
  var assumptionCanonicals: seq[string] = @[]
  for p in canonical.params:
    if p.ty.kind != rtyInt:
      continue
    if widthBound(p.ty.widthBits).isNone and p.ty.widthBits != 64:
      return RustObligationRender(ok: false,
        reason: "width precondition unrepresentable for the recorded types")
    let rangePre = rustTypeRangePrecondition(p.name, p.ty)
    let lowered = lowerIRExprToLean(rangePre.pred, paramNames)
    if lowered.len == 0:
      return RustObligationRender(ok: false,
        reason: "width precondition outside the bounded rendering subset")
    loweredPres.add(lowered)
    assumptionCanonicals.add($rangePre.origin & ":" &
      canonicalizePredicate(rangePre.pred))

  # 4. The guard goal as the post (no `result` in a guard goal — the
  #    postcondition lowering still binds it if one ever appeared).
  let postText = lowerPostconditionToLean(goal, canonical.funcName, paramNames)
  if postText.len == 0:
    return RustObligationRender(ok: false,
      reason: "guard goal outside the bounded rendering subset (free " &
              "variables must be parameters or 'result')")

  # 5. The template — same family emission as the standard renderer.
  var defSig = "def " & canonical.funcName & " : "
  for p in canonical.params:
    let lt = irTypeToLeanTy(rustIrType(p.ty))
    if lt.len == 0:
      return RustObligationRender(ok: false,
        reason: "param type outside the width-uniform Int domain")
    defSig.add(lt & " → ")
  defSig.add("Int")
  var binder = "fun"
  for p in canonical.params:
    binder.add(" " & p.name)
  var src = defSig & " :=\n  " & binder & " => " & loweredBody & "\n"

  let needsUnfold = containsIdentToken(postText, canonical.funcName)
  var binderPart = "∀ ("
  for i, p in canonical.params:
    if i > 0:
      binderPart.add(") (")
    binderPart.add(p.name & " : Int")
  binderPart.add("), ")
  for lowered in loweredPres:
    binderPart.add(lowered & " → ")
  let proposition = binderPart & postText
  src.add("\ntheorem " & canonical.funcName & "_post :\n")
  src.add("  " & proposition & " := by\n")
  var introLine = "  intro"
  for p in canonical.params:
    introLine.add(" " & p.name)
  for i in 0 ..< loweredPres.len:
    var hyp = "h" & $i
    while paramNames.contains(hyp):
      hyp = hyp & "_h"
    introLine.add(" " & hyp)
  src.add(introLine & "\n")
  if needsUnfold:
    src.add("  unfold " & canonical.funcName & "\n")
  src.add("  omega\n")

  # 6. Identity digests — the guard's OWN identity: origin aoTypeDerived
  #    (every hypothesis IS type-derived) and a distinct derivationRule, so a
  #    guard artifact can never share a C4 identity with a declared-spec one.
  let obligationId = computeObligationId(
    subject = "rust:" & canonical.modulePath & ":" & canonical.funcName,
    kind = okContractPost,
    canonicalAssumptions = assumptionCanonicals.join("|"),
    canonicalPredicate = canonicalizePredicate(goal),
    derivationRule = "rust-subject-v1/guard-omega",
    assumptionOrigin = aoTypeDerived)
  let templateHash = rustTemplateSkeletonHash(src)
  if templateHash.len == 0:
    return RustObligationRender(ok: false,
      reason: "rendered source does not classify into the template family " &
              "(renderer/template divergence — fail-closed)")
  RustObligationRender(
    ok: true,
    obligationId: obligationId,
    proposition: proposition,
    leanSource: src,
    templateHash: templateHash,
    obligationDigest: sha256Hex(
      rustCanonicalDigest & "|" & proposition & "|" & src))

# ---------------------------------------------------------------------------
# RustBoundedClaim — the mint gate's input record
# ---------------------------------------------------------------------------

type RustBoundedClaim* = object
  ## Measured at the Rust lane, re-verified at mint (cert_writer.nim). All
  ## fields are digests over THIS run's artifacts — nothing here is authority
  ## by itself; the gate refuses unless every field co-binds with the
  ## certificate input and the accepted kernel artifact.
  templateHash*: string
    ## skeleton hash of the rendered artifact (must be an allowlist member)
  rustCanonicalDigest*: string
    ## the RustCanonical wire sha256 (ExtractionAgreementResult.nimDigest);
    ## must equal the certificate's irHash
  obligationDigest*: string
    ## H(rustCanonicalDigest | proposition | leanSource) — the co-binding of
    ## proposition, obligation, and canonical digests
  extractorIdentity*: string
    ## the extractor identity measured at extraction time; mint refuses unless
    ## it equals the CURRENT pinned reference extractor identity

func rustBoundedClaimRefusal*(claim: RustBoundedClaim; irHash: string;
                              leanProposition: string; leanSource: string):
    string {.raises: [].} =
  ## "" = the claim co-binds; otherwise the precise refusal reason. Pure —
  ## the extractor-identity half is `rustExtractorIdentityRefusal` (measured).
  if not rustTemplateInFamily(leanSource):
    return "leanSource is not from the closed renderer template family " &
           "(free/unrecognized composition)"
  let sourceProp = rustPropositionFromSource(leanSource)
  if sourceProp.len == 0:
    return "proposition is not extractable from the accepted source"
  if sourceProp != leanProposition:
    return "persisted proposition does not match the accepted source's " &
           "proposition (co-binding failure)"
  if claim.templateHash != rustTemplateSkeletonHash(leanSource):
    return "templateHash does not match the accepted source's skeleton"
  if claim.rustCanonicalDigest != irHash:
    return "rustCanonicalDigest != certificate irHash (the claim does not " &
           "bind THIS extraction's canonical)"
  let recomputed = sha256Hex(claim.rustCanonicalDigest & "|" &
                             leanProposition & "|" & leanSource)
  if claim.obligationDigest != recomputed:
    return "obligationDigest does not co-bind (rustCanonicalDigest | " &
           "proposition | leanSource)"
  ""

# ---------------------------------------------------------------------------
# Extractor identity — measured, mint-time refusal (KAA :363-370 mirror)
# ---------------------------------------------------------------------------

proc rustExtractorIdentityDigest*(rcheckExe: string = ""): string {.
    raises: [], axiomEffect: IOEffect,
    tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Measure the CURRENT extractor identity with the SAME resolution order the
  ## differential worker uses (rust_extraction_agreement
  ## .runRustReferenceExtractorOnWire): explicit argument > AXIOM_RUSTCHECK_CMD
  ## env > the pinned Lean reference extractor source. Only the PINNED identity
  ## is mint-admissible: an env- or argument-pointed extractor records a
  ## distinct identity that the mint refusal (`rustExtractorIdentityRefusal`)
  ## rejects — the same recorded-vs-measured discipline as the KAA's
  ## toolchain-fingerprint refusal.
  if rcheckExe.len > 0:
    return "explicit|" & sha256Hex(rcheckExe)
  let envCmd = getEnv("AXIOM_RUSTCHECK_CMD", "")
  if envCmd.len > 0:
    return "explicit|" & sha256Hex(envCmd)
  let root = resolveRepoRoot()
  let pinnedSource = root / "proofs" / "IR" / "RustReferenceExtractor.lean"
  if not fileExists(pinnedSource):
    return "pinned|missing"
  try:
    "pinned|" & sha256Hex(readFile(pinnedSource))
  except CatchableError:
    "pinned|missing"

proc rustExtractorIdentityRefusal*(recorded: string): string {.
    raises: [], axiomEffect: IOEffect,
    tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Mint-time unauthorized-extractor rejection: the recorded identity must
  ## equal the CURRENT pinned reference-extractor identity. A divergence means
  ## the extractor changed (or was overridden) between extraction and mint —
  ## refuse issuance.
  let current = rustExtractorIdentityDigest()
  if recorded.len == 0:
    return "extractor identity was not recorded at extraction time"
  if recorded != current:
    return "extractor identity mismatch: recorded '" & recorded & "' != " &
           "current pinned '" & current & "' (unauthorized extractor)"
  ""

{.pop.}
