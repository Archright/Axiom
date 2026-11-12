## Comprehensive Unit Tests for core/judge/smart_search.nim
##
## Covers all 8 exported procs/funcs:
##   1. elemBoundaryConstraints
##   2. extractHintFromLine
##   3. analyzeBottleneckAst (exported wrapper — tested via none(PNode) edge cases)
##   4. bottleneckCausesToString
##   5. generateSemanticHintWithStrategy
##   6. inferenceStrategyLabel
##   7. selectInferenceStrategy
##   8. generateSemanticHint
##
## NOTE: AST-dependent code paths (interval abstraction, structural induction
## with seq params, pattern matching with case/if) require real tree-sitter
## parse results. Those paths are tested indirectly via generateSemanticHintWithStrategy
## with invalid/empty context (best-effort catch branches return none).
## Full AST-path testing requires integration tests with real source files.

import std/[options, strutils, os]
import std/unittest
import compiler/ast
import core/judge/smart_search
import core/encoding/type_logic_registry as tlr

const RegistryPath = "src/generated/type_registry_metadata.json"

# ── Setup: load type registry so elemBoundaryConstraints works ──────────────

var registryLoadedInTest = false

proc ensureRegistryLoaded() =
  if not registryLoadedInTest:
    if fileExists(RegistryPath):
      tlr.loadFromMetadata(RegistryPath)
      registryLoadedInTest = true

# ══════════════════════════════════════════════════════════════════════════════
# 1. elemBoundaryConstraints
# ══════════════════════════════════════════════════════════════════════════════

suite "elemBoundaryConstraints":
  setup:
    ensureRegistryLoaded()

  test "int → numeric category":
    let bc = elemBoundaryConstraints("int")
    check bc.lean == "elem ≥ 0"
    check bc.smt == "(>= result 0)"

  test "string → string category":
    let bc = elemBoundaryConstraints("string")
    check bc.lean == "elem.length ≥ 0"
    check bc.smt == "(>= (str.len result) 0)"

  test "bool → bool category":
    let bc = elemBoundaryConstraints("bool")
    check bc.lean == "elem = true ∨ elem = false"
    check bc.smt == "(or (= result true) (= result false))"

  test "unknown type → empty lean, empty smt":
    let bc = elemBoundaryConstraints("MyCustomType")
    check bc.lean == ""
    check bc.smt == ""

  test "uint → numeric category":
    let bc = elemBoundaryConstraints("uint")
    check bc.lean == "elem ≥ 0"
    check bc.smt == "(>= result 0)"

  test "natural → numeric category":
    let bc = elemBoundaryConstraints("natural")
    check bc.lean == "elem ≥ 0"
    check bc.smt == "(>= result 0)"

  test "void → unknown category (not numeric/string/bool)":
    let bc = elemBoundaryConstraints("void")
    check bc.lean == ""
    check bc.smt == ""

  test "empty string → unknown category":
    let bc = elemBoundaryConstraints("")
    check bc.lean == ""
    check bc.smt == ""

# ══════════════════════════════════════════════════════════════════════════════
# 2. extractHintFromLine
# ══════════════════════════════════════════════════════════════════════════════

suite "extractHintFromLine":
  test "valid hint with lean and smt":
    let line = "# @axiom-hint: lean=\"x ≥ 0\" smt=\"(assert (>= x 0))\""
    let hint = extractHintFromLine(line)
    check hint.isSome
    check hint.get.leanProposition == "x ≥ 0"
    check hint.get.smtConstraint == "(assert (>= x 0))"
    check hint.get.confidence == 0.95
    check hint.get.strategy == isHintComment
    check hint.get.retryCount == 0

  test "valid hint with surrounding whitespace":
    let line = "  # @axiom-hint: lean=\"len ≥ 0\" smt=\"(assert (>= len 0))\"  "
    let hint = extractHintFromLine(line)
    check hint.isSome
    check hint.get.leanProposition == "len ≥ 0"
    check hint.get.smtConstraint == "(assert (>= len 0))"

  test "no marker → none":
    let hint = extractHintFromLine("let x = 5")
    check hint.isNone

  test "empty line → none":
    let hint = extractHintFromLine("")
    check hint.isNone

  test "marker present but no lean/smt → none":
    let line = "# @axiom-hint: some random text without quotes"
    let hint = extractHintFromLine(line)
    check hint.isNone

  test "lean only (no smt) → none":
    let line = "# @axiom-hint: lean=\"x ≥ 0\""
    let hint = extractHintFromLine(line)
    check hint.isNone

  test "smt only (no lean) → none":
    let line = "# @axiom-hint: smt=\"(assert (>= x 0))\""
    let hint = extractHintFromLine(line)
    check hint.isNone

  test "void return type → none (strict-contract-mode)":
    let line = "# @axiom-hint: lean=\"x ≥ 0\" smt=\"(assert (>= x 0))\""
    let hint = extractHintFromLine(line, returnType = "void")
    check hint.isNone

  test "non-void return type → some":
    let line = "# @axiom-hint: lean=\"x ≥ 0\" smt=\"(assert (>= x 0))\""
    let hint = extractHintFromLine(line, returnType = "int")
    check hint.isSome

  test "empty returnType → some (default parameter)":
    let line = "# @axiom-hint: lean=\"x ≥ 0\" smt=\"(assert (>= x 0))\""
    let hint = extractHintFromLine(line, returnType = "")
    check hint.isSome

  test "marker in middle of line":
    let line = "proc foo() = # @axiom-hint: lean=\"a ≥ 0\" smt=\"(assert (>= a 0))\""
    let hint = extractHintFromLine(line)
    check hint.isSome
    check hint.get.leanProposition == "a ≥ 0"

  test "partial marker (missing colon) → none":
    let hint = extractHintFromLine("# @axiom-hint lean=\"x ≥ 0\" smt=\"(assert (>= x 0))\"")
    check hint.isNone

  test "multiple lean/smt pairs → first match wins":
    let line = "# @axiom-hint: lean=\"first\" smt=\"(assert first)\" lean=\"second\" smt=\"(assert second)\""
    let hint = extractHintFromLine(line)
    check hint.isSome
    check hint.get.leanProposition == "first"
    check hint.get.smtConstraint == "(assert first)"

  test "complex smt with nested parens":
    let line = "# @axiom-hint: lean=\"ok\" smt=\"(assert (and (>= x 0) (<= x 100)))\""
    let hint = extractHintFromLine(line)
    check hint.isSome
    check hint.get.smtConstraint == "(assert (and (>= x 0) (<= x 100)))"

  test "sourceReference is hardcoded":
    let line = "# @axiom-hint: lean=\"ok\" smt=\"(assert ok)\""
    let hint = extractHintFromLine(line)
    check hint.isSome
    check hint.get.sourceReference == "Extracted from source comment"

# ══════════════════════════════════════════════════════════════════════════════
# 3. analyzeBottleneckAst (exported wrapper — edge cases only)
# ══════════════════════════════════════════════════════════════════════════════

suite "analyzeBottleneckAst":
  test "empty fileContext → @[bcNoHintComment]":
    let causes = analyzeBottleneckAst("mod::fn", "", none(PNode))
    check causes.len == 1
    check causes[0] == bcNoHintComment

  test "fileContext without hint, no AST → @[bcNoHintComment]":
    let ctx = "proc foo() =\n  let x = 5"
    let causes = analyzeBottleneckAst("mod::foo", ctx, none(PNode))
    check causes.len == 1
    check causes[0] == bcNoHintComment

  test "fileContext with hint, no AST → @[bcUnknown]":
    let ctx = "# @axiom-hint: lean=\"ok\" smt=\"(assert ok)\""
    let causes = analyzeBottleneckAst("mod::foo", ctx, none(PNode))
    check causes.len == 1
    check causes[0] == bcUnknown

  test "fileContext with hint marker (incomplete), no AST → @[bcUnknown]":
    # Starts with "# @axiom-hint:" so hasHintComment = true → no bcNoHintComment.
    # fnNodeOpt is none and result is empty → bcUnknown added.
    let ctx = "# @axiom-hint: incomplete"
    let causes = analyzeBottleneckAst("mod::foo", ctx, none(PNode))
    check causes.len == 1
    check causes[0] == bcUnknown

  test "nodeId without :: separator":
    let causes = analyzeBottleneckAst("standalone_func", "", none(PNode))
    check causes.len == 1
    check causes[0] == bcNoHintComment

  test "nodeId with :: separator":
    let causes = analyzeBottleneckAst("module::funcName", "", none(PNode))
    check causes.len == 1
    check causes[0] == bcNoHintComment

# ══════════════════════════════════════════════════════════════════════════════
# 4. bottleneckCausesToString
# ══════════════════════════════════════════════════════════════════════════════

suite "bottleneckCausesToString":
  test "empty causes → empty string":
    check bottleneckCausesToString(@[]) == ""

  test "single cause: bcNoHintComment":
    check bottleneckCausesToString(@[bcNoHintComment]) == "no @axiom-hint comment"

  test "single cause: bcComplexRecursion":
    check bottleneckCausesToString(@[bcComplexRecursion]) == "complex recursion"

  test "single cause: bcNonLinearArithmetic":
    check bottleneckCausesToString(@[bcNonLinearArithmetic]) == "non-linear arithmetic"

  test "single cause: bcExternalIO":
    check bottleneckCausesToString(@[bcExternalIO]) == "external I/O or process invocation"

  test "single cause: bcComplexControlFlow":
    check bottleneckCausesToString(@[bcComplexControlFlow]) == "complex control flow (exception handling)"

  test "single cause: bcClosureSemantics":
    check bottleneckCausesToString(@[bcClosureSemantics]) == "closure/capture semantics"

  test "single cause: bcLargeFunctionBody":
    check bottleneckCausesToString(@[bcLargeFunctionBody]) == "large function body"

  test "single cause: bcHighComplexity":
    check bottleneckCausesToString(@[bcHighComplexity]) == "high complexity (ACI > 70)"

  test "single cause: bcHighCoupling":
    check bottleneckCausesToString(@[bcHighCoupling]) == "high coupling (SRP violation)"

  test "single cause: bcUnknown":
    check bottleneckCausesToString(@[bcUnknown]) == "unknown"

  test "multiple causes → comma-separated":
    let causes = @[bcNoHintComment, bcComplexRecursion, bcExternalIO]
    let s = bottleneckCausesToString(causes)
    check "no @axiom-hint comment" in s
    check "complex recursion" in s
    check "external I/O or process invocation" in s
    check s.contains(", ")

  test "all causes → all present":
    let causes = @[
      bcNoHintComment, bcComplexRecursion, bcNonLinearArithmetic,
      bcExternalIO, bcComplexControlFlow, bcClosureSemantics,
      bcLargeFunctionBody, bcHighComplexity, bcHighCoupling, bcUnknown
    ]
    let s = bottleneckCausesToString(causes)
    check s.contains("no @axiom-hint comment")
    check s.contains("complex recursion")
    check s.contains("non-linear arithmetic")
    check s.contains("external I/O")
    check s.contains("complex control flow")
    check s.contains("closure/capture")
    check s.contains("large function body")
    check s.contains("high complexity")
    check s.contains("high coupling")
    check s.contains("unknown")

# ══════════════════════════════════════════════════════════════════════════════
# 5. inferenceStrategyLabel
# ══════════════════════════════════════════════════════════════════════════════

suite "inferenceStrategyLabel":
  test "isHintComment → \"hintComment\"":
    check inferenceStrategyLabel(isHintComment) == "hintComment"

  test "isIntervalAbstraction → \"intervalAbstraction\"":
    check inferenceStrategyLabel(isIntervalAbstraction) == "intervalAbstraction"

  test "isStructuralInduction → \"structuralInduction\"":
    check inferenceStrategyLabel(isStructuralInduction) == "structuralInduction"

  test "isPatternMatching → \"patternMatching\"":
    check inferenceStrategyLabel(isPatternMatching) == "patternMatching"

  test "isTautologyProof → \"tautologyProof\"":
    check inferenceStrategyLabel(isTautologyProof) == "tautologyProof"

# ══════════════════════════════════════════════════════════════════════════════
# 6. selectInferenceStrategy
# ══════════════════════════════════════════════════════════════════════════════

suite "selectInferenceStrategy":
  test "attemptCount 0 → isHintComment":
    check selectInferenceStrategy(0) == isHintComment

  test "attemptCount 1 → isIntervalAbstraction":
    check selectInferenceStrategy(1) == isIntervalAbstraction

  test "attemptCount 2 → isStructuralInduction":
    check selectInferenceStrategy(2) == isStructuralInduction

  test "attemptCount 3 → isPatternMatching":
    check selectInferenceStrategy(3) == isPatternMatching

  test "attemptCount 4 → cycles back to isHintComment":
    check selectInferenceStrategy(4) == isHintComment

  test "attemptCount 5 → cycles to isIntervalAbstraction":
    check selectInferenceStrategy(5) == isIntervalAbstraction

  test "attemptCount 10 → 10 mod 4 = 2 → isStructuralInduction":
    check selectInferenceStrategy(10) == isStructuralInduction

  test "attemptCount 100 → 100 mod 4 = 0 → isHintComment":
    check selectInferenceStrategy(100) == isHintComment

# ══════════════════════════════════════════════════════════════════════════════
# 7. generateSemanticHintWithStrategy
# ══════════════════════════════════════════════════════════════════════════════

suite "generateSemanticHintWithStrategy":
  test "isHintComment: valid hint in fileContext → some":
    let ctx = "# @axiom-hint: lean=\"x ≥ 0\" smt=\"(assert (>= x 0))\""
    let hint = generateSemanticHintWithStrategy("mod::fn", ctx, "", isHintComment)
    check hint.isSome
    check hint.get.leanProposition == "x ≥ 0"
    check hint.get.smtConstraint == "(assert (>= x 0))"
    check hint.get.strategy == isHintComment
    check "Source context for mod::fn:" in hint.get.sourceReference

  test "isHintComment: hint in docContext → some":
    let doc = "# @axiom-hint: lean=\"y ≥ 0\" smt=\"(assert (>= y 0))\""
    let hint = generateSemanticHintWithStrategy("mod::fn", "", doc, isHintComment)
    check hint.isSome
    check hint.get.leanProposition == "y ≥ 0"
    check "Doc context for mod::fn:" in hint.get.sourceReference

  test "isHintComment: fileContext takes precedence over docContext":
    let ctx = "# @axiom-hint: lean=\"from_file\" smt=\"(assert from_file)\""
    let doc = "# @axiom-hint: lean=\"from_doc\" smt=\"(assert from_doc)\""
    let hint = generateSemanticHintWithStrategy("mod::fn", ctx, doc, isHintComment)
    check hint.isSome
    check hint.get.leanProposition == "from_file"

  test "isHintComment: no hint in either → none":
    let hint = generateSemanticHintWithStrategy("mod::fn", "let x = 5", "no hints here", isHintComment)
    check hint.isNone

  test "isHintComment: empty context → none":
    let hint = generateSemanticHintWithStrategy("mod::fn", "", "", isHintComment)
    check hint.isNone

  test "isHintComment: retryCount propagated":
    let ctx = "# @axiom-hint: lean=\"ok\" smt=\"(assert ok)\""
    let hint = generateSemanticHintWithStrategy("mod::fn", ctx, "", isHintComment, retryCount = 7)
    check hint.isSome
    check hint.get.retryCount == 7

  test "isIntervalAbstraction: empty context → none":
    let hint = generateSemanticHintWithStrategy("mod::fn", "", "", isIntervalAbstraction)
    check hint.isNone

  test "isIntervalAbstraction: invalid nim code → none (best-effort)":
    let hint = generateSemanticHintWithStrategy("mod::fn", "not valid nim {{{{", "", isIntervalAbstraction)
    check hint.isNone

  test "isStructuralInduction: empty context → none":
    let hint = generateSemanticHintWithStrategy("mod::fn", "", "", isStructuralInduction)
    check hint.isNone

  test "isStructuralInduction: invalid nim code → none (best-effort)":
    let hint = generateSemanticHintWithStrategy("mod::fn", "broken code {{{{", "", isStructuralInduction)
    check hint.isNone

  test "isPatternMatching: empty context → none":
    let hint = generateSemanticHintWithStrategy("mod::fn", "", "", isPatternMatching)
    check hint.isNone

  test "isPatternMatching: invalid nim code → none (best-effort)":
    let hint = generateSemanticHintWithStrategy("mod::fn", "bad code {{{{", "", isPatternMatching)
    check hint.isNone

  test "isTautologyProof: always returns none":
    let hint = generateSemanticHintWithStrategy("mod::fn", "any context", "any doc", isTautologyProof)
    check hint.isNone

  test "isTautologyProof: with hint comment → still none (tautology is excluded)":
    let ctx = "# @axiom-hint: lean=\"ok\" smt=\"(assert ok)\""
    let hint = generateSemanticHintWithStrategy("mod::fn", ctx, "", isTautologyProof)
    check hint.isNone

# ══════════════════════════════════════════════════════════════════════════════
# 8. generateSemanticHint (wrapper — strategy cycling)
# ══════════════════════════════════════════════════════════════════════════════

suite "generateSemanticHint":
  test "attemptCount 0 uses isHintComment strategy":
    let ctx = "# @axiom-hint: lean=\"a ≥ 0\" smt=\"(assert (>= a 0))\""
    let hint = generateSemanticHint("mod::fn", ctx, "", attemptCount = 0)
    check hint.isSome
    check hint.get.strategy == isHintComment

  test "attemptCount 1 uses isIntervalAbstraction → none for invalid code":
    let hint = generateSemanticHint("mod::fn", "bad", "", attemptCount = 1)
    check hint.isNone

  test "attemptCount 2 uses isStructuralInduction → none for invalid code":
    let hint = generateSemanticHint("mod::fn", "bad", "", attemptCount = 2)
    check hint.isNone

  test "attemptCount 3 uses isPatternMatching → none for invalid code":
    let hint = generateSemanticHint("mod::fn", "bad", "", attemptCount = 3)
    check hint.isNone

  test "attemptCount 4 cycles back to isHintComment":
    let ctx = "# @axiom-hint: lean=\"b ≥ 0\" smt=\"(assert (>= b 0))\""
    let hint = generateSemanticHint("mod::fn", ctx, "", attemptCount = 4)
    check hint.isSome
    check hint.get.strategy == isHintComment

  test "default attemptCount (0) → isHintComment":
    let ctx = "# @axiom-hint: lean=\"c ≥ 0\" smt=\"(assert (>= c 0))\""
    let hint = generateSemanticHint("mod::fn", ctx, "")
    check hint.isSome
    check hint.get.strategy == isHintComment
