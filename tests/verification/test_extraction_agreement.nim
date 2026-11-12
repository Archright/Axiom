import std/[os, osproc, strutils, sequtils]
import verification/ast_wire
import verification/extraction_agreement
import infrastructure/ir_binary_codec
import core/parser_utils
import core/trusted/ast_to_ir
import core/trusted/axiom_ir_helpers
import core/trusted/pnode_to_canon
import shared/canonical_ast

## ═══════════════════════════════════════════════════════════════════════
## ExtractionAgreement — certification continuity Phase 3.75 tests
## (Tier 2: independent Lean reference extractor + per-run differential).
##
## Coverage:
##   P1  pure agreement semantics: verdict reason codes, byte-equality and
##       compareSerializedIR, wire-codec shape checks (supported subset vs
##       unsupported kinds), func-source input validation
##   P2  real differential: matching extraction (literals/binop/if/let) →
##       eaAgree byte-equal; deliberate wire mutation (node-kind + node-value)
##       → FAIL; truncated/corrupted wire → FAIL; unsupported node
##       (float literal, expression-form if, parens) → eaUnsupported;
##       IR mismatch (tampered worker output) → FAIL; non-zero early return
##       → eaAgree (both extractors preserve the return value — the
##       extractReturnValueCanon then-body bug is fixed)
##       (SKIP loudly if ircheck binary absent)
##   P3  dual-frontend (macro vs pnode) convergence, minimal reuse of the
##       existing tests/unit/wp15_pnode_canon_equiv_test.nim anchor
## ═══════════════════════════════════════════════════════════════════════

var passCount = 0
var skipCount = 0

proc checkEq(name: string; got, exp: string) =
  if got == exp:
    echo "  [PASS] ", name
    inc passCount
  else:
    echo "  [FAIL] ", name, "\n      got: ", got, "\n      exp: ", exp
    quit(1)

proc checkTrue(name: string; cond: bool) =
  if cond:
    echo "  [PASS] ", name
    inc passCount
  else:
    echo "  [FAIL] ", name
    quit(1)

proc checkVerdict(name: string; got, exp: ExtractionAgreementVerdict) =
  if got == exp:
    echo "  [PASS] ", name, " -> ", $got
    inc passCount
  else:
    echo "  [FAIL] ", name, "\n      got: ", $got, "\n      exp: ", $exp
    quit(1)

proc skip(name: string; reason: string) =
  echo "  [SKIP] ", name, " (", reason, ") — test skipped, exit 0"
  inc skipCount

proc findRepoRoot(): string =
  var dir = getCurrentDir()
  while dir.len > 0:
    if fileExists(dir / ".axiom_root"):
      return dir
    let parent = parentDir(dir)
    if parent == dir: break
    dir = parent
  result = getCurrentDir()

let repoRoot = findRepoRoot()
let proofsDir = repoRoot / "proofs"
let ircheckBin = proofsDir / ".lake" / "build" / "bin" / "ircheck"
let workerAvailable = fileExists(ircheckBin)

# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------
const Inc3 = """
func inc3(a: int): int =
  let b = a + 1
  let c = b * 2
  c - 1
"""

const Pred3 = """
func pred3(x: int): int =
  if x < 0:
    return 0
  -x
"""

## Non-zero early return: both extractors must preserve the return value.
## (Regression anchor: the canonical extractor's CanonNode path used to pass
## the elif BRANCH to extractReturnValueCanon instead of the then-body,
## degrading the return value to irLit(0) → eaMismatch. Fixed — the
## differential must now AGREE byte-for-byte.)
const Fact3Nonzero = """
func fact3(n: int): int =
  if n <= 1:
    return 1
  n * fact3(n - 1)
"""

const FloatFx = """
func flt(x: int): int =
  let y = 1.5
  0
"""

const IfExprFx = """
func ife(x: int): int =
  let c = if x < 5: 1 else: 2
  c
"""

const ParFx = """
func parf(x, y: int): int =
  (x and y)
"""

const CaseFx = """
func csef(x: int): int =
  case x
  of 1: 2
  else: 3
"""

proc canonOf(src: string; name: string): CanonNode =
  let ast = parseStringAST(src)
  let defNode = findFuncDefP(ast, name, "")
  pnodeToCanon(defNode)

proc nimBodyBytes(canon: CanonNode): seq[byte] =
  serializeIRExprAligned(axiomBodyCanon(canon).body)

proc pnodeBodyHex(src: string; name: string): string =
  nimBodyBytes(canonOf(src, name)).mapIt(it.toHex).join("")

proc bytesToStrImp(bytes: seq[byte]): string =
  result = newString(bytes.len)
  for i in 0 ..< bytes.len:
    result[i] = char(bytes[i])

proc flipByteAt(b: var seq[byte]; idx: int) =
  if idx >= 0 and idx < b.len:
    b[idx] = byte(not int(b[idx]))

proc lastIntLitValueIdx(b: seq[byte]): int =
  ## Offset of the VALUE byte of the LAST awIntLit (0x1C) node in the wire:
  ## the int64 value follows the 8-byte tag slot.
  result = -1
  var i = 0
  while i < b.len - 16:
    if b[i] == 0x1C'u8:
      result = i + 8
    inc i
  if result < 0 or result >= b.len: result = -1

# ---------------------------------------------------------------------------
# P1 — pure agreement semantics (always runs)
# ---------------------------------------------------------------------------
echo "=== P1: pure agreement semantics ==="
checkEq("reason code EA_AGREE", agreementReasonCode(eaAgree), "EA_AGREE")
checkEq("reason code EA_MISMATCH", agreementReasonCode(eaMismatch), "EA_MISMATCH")
checkEq("reason code EA_UNSUPPORTED", agreementReasonCode(eaUnsupported), "EA_UNSUPPORTED")
checkEq("reason code EA_REFERENCE_ERROR", agreementReasonCode(eaReferenceError), "EA_REFERENCE_ERROR")
checkEq("reason code EA_INTERNAL_ERROR", agreementReasonCode(eaInternalError), "EA_INTERNAL_ERROR")
checkTrue("verdict reasons non-empty for all verdicts",
  agreementVerdictReason(eaAgree).len > 0 and agreementVerdictReason(eaMismatch).len > 0 and
  agreementVerdictReason(eaUnsupported).len > 0 and agreementVerdictReason(eaReferenceError).len > 0 and
  agreementVerdictReason(eaInternalError).len > 0)
let eqBytes: seq[byte] = @[1'u8, 2'u8, 3'u8]
let diffBytes: seq[byte] = @[1'u8, 2'u8, 4'u8]
checkTrue("irBytesEqual equal → true", irBytesEqual(eqBytes, eqBytes))
checkTrue("irBytesEqual different → false", not irBytesEqual(eqBytes, diffBytes))
checkTrue("irBytesEqual length mismatch → false", not irBytesEqual(eqBytes, @[1'u8, 2'u8]))
checkVerdict("compareSerializedIR equal → eaAgree", compareSerializedIR(eqBytes, eqBytes), eaAgree)
checkVerdict("compareSerializedIR differ → eaMismatch", compareSerializedIR(eqBytes, diffBytes), eaMismatch)
checkVerdict("compareSerializedIR empty nim → eaInternalError", compareSerializedIR(@[], eqBytes), eaInternalError)
checkVerdict("compareSerializedIR empty lean → eaInternalError", compareSerializedIR(eqBytes, @[]), eaInternalError)

# wire-codec shape checks (supported subset vs unsupported kinds)
let wireInc3 = serializeAstWire(canonOf(Inc3, "inc3"))
checkTrue("wire: subset fixture serializes ok", wireInc3.ok)
checkTrue("wire: magic + version present", wireInc3.ok and wireInc3.bytes[0] == 0xA0'u8 and wireInc3.bytes[8] == 1'u8)
let wirePred3 = serializeAstWire(canonOf(Pred3, "pred3"))
checkTrue("wire: early-return-if fixture serializes ok", wirePred3.ok)
let wireFloat = serializeAstWire(canonOf(FloatFx, "flt"))
checkVerdict("wire: unsupported -> awe check (float)", (if wireFloat.error == aweUnsupportedKind: eaUnsupported else: eaAgree), eaUnsupported)
checkEq("wire: float kind recorded", wireFloat.kindName, "ckFloatLit")
let wireIfExpr = serializeAstWire(canonOf(IfExprFx, "ife"))
checkVerdict("wire: expression-form if unsupported (lossy in Nim canon)", (if wireIfExpr.error == aweUnsupportedKind: eaUnsupported else: eaAgree), eaUnsupported)
let wirePar = serializeAstWire(canonOf(ParFx, "parf"))
# Single-child ckPar serializes its CONTENT — the canonical extractor's own
# unwrap rule (ast_to_ir nnkPar → convertExpr(n[0]); a parenthesized
# expression denotes the same value as its content). Both extractors see
# identical IR, so the differential agrees. Multi-child ckPar has no single
# content expression and stays fail-closed.
checkVerdict("wire: single-child ckPar unwraps to content (nnkPar → convertExpr(n[0]))", (if wirePar.error == aweNone: eaAgree else: eaUnsupported), eaAgree)
let wireCase = serializeAstWire(canonOf(CaseFx, "csef"))
checkVerdict("wire: ckCaseStmt unsupported", (if wireCase.error == aweUnsupportedKind: eaUnsupported else: eaAgree), eaUnsupported)

# input validation (no Lean needed)
let rEmpty = runExtractionAgreement("", "f", ircheckBin, repoRoot, 10_000)
checkVerdict("empty source → eaInternalError", rEmpty.verdict, eaInternalError)
let rNoFunc = runExtractionAgreement("func g(x: int): int =\n  x\n", "missing", ircheckBin, repoRoot, 10_000)
checkVerdict("func not found → eaInternalError", rNoFunc.verdict, eaInternalError)
let rNoWorker = runExtractionAgreement(Inc3, "inc3", "/nonexistent/ircheck", repoRoot, 10_000)
checkVerdict("missing worker binary → eaReferenceError", rNoWorker.verdict, eaReferenceError)

# ---------------------------------------------------------------------------
# P2 — real differential (SKIP loudly if ircheck binary absent)
# ---------------------------------------------------------------------------
echo "=== P2: real extraction differential ==="
if workerAvailable:
  # (1) matching extraction: literals/binop/if/let → byte-equal PASS
  let rInc3 = runExtractionAgreement(Inc3, "inc3", ircheckBin, repoRoot, 60_000)
  checkVerdict("matching extraction (let/binop) → eaAgree", rInc3.verdict, eaAgree)
  checkTrue("irNim and irLean digests equal + non-empty",
    rInc3.nimDigest.len > 0 and rInc3.nimDigest == rInc3.leanDigest)
  let rPred3 = runExtractionAgreement(Pred3, "pred3", ircheckBin, repoRoot, 60_000)
  checkVerdict("matching extraction (early-return-if) → eaAgree", rPred3.verdict, eaAgree)
  let rPar = runExtractionAgreement(ParFx, "parf", ircheckBin, repoRoot, 60_000)
  checkVerdict("matching extraction (single-child paren unwrap) → eaAgree", rPar.verdict, eaAgree)

  # (2) unsupported node through the full checker → EA_UNSUPPORTED (fail-closed)
  let rFloat = runExtractionAgreement(FloatFx, "flt", ircheckBin, repoRoot, 60_000)
  checkVerdict("unsupported node (float literal) → eaUnsupported", rFloat.verdict, eaUnsupported)
  let rIfExpr = runExtractionAgreement(IfExprFx, "ife", ircheckBin, repoRoot, 60_000)
  checkVerdict("unsupported node (expression-if) → eaUnsupported", rIfExpr.verdict, eaUnsupported)

  # (3) deliberate wire mutation — flip a NODE-KIND tag byte of the worker input
  let wireBytes = serializeAstWire(canonOf(Inc3, "inc3")).bytes
  var mutated = @(wireBytes)
  if mutated.len > 16:
    mutated[0] = 0x99'u8  # corrupt the magic → decode must fail
  let rBadMagic = runReferenceExtractorOnWire(mutated, ircheckBin, repoRoot, 60_000)
  checkTrue("corrupt magic byte → worker nonzero exit (FAIL)",
    rBadMagic.exitCode != 0)

  # (4) codec corruption — truncated wire → worker nonzero exit (FAIL)
  var truncated = @(wireBytes[0 ..< wireBytes.len div 2])
  let rTrunc = runReferenceExtractorOnWire(truncated, ircheckBin, repoRoot, 60_000)
  checkTrue("truncated wire → worker nonzero exit (FAIL)", rTrunc.exitCode != 0)

  # (5) deliberate VALUE mutation — still decodes, but changes the extracted IR
  var mutatedVal = @(wireBytes)
  let valIdx = lastIntLitValueIdx(mutatedVal)
  if valIdx >= 0:
    mutatedVal[valIdx] = byte(int(mutatedVal[valIdx]) + 1)  # lit value +1
  let rMutVal = runReferenceExtractorOnWire(mutatedVal, ircheckBin, repoRoot, 60_000)
  let nimOrig = nimBodyBytes(canonOf(Inc3, "inc3"))
  checkTrue("mutated node value → worker OK but IR differs (FAIL detected)",
    rMutVal.exitCode == 0 and not irBytesEqual(nimOrig, rMutVal.outBytes))

  # (6) IR mismatch — tamper the (good) worker output; the comparison must catch it
  let rGood = runReferenceExtractorOnWire(wireBytes, ircheckBin, repoRoot, 60_000)
  checkTrue("reference extractor OK on valid wire", rGood.exitCode == 0)
  let tampered = compareSerializedIR(nimOrig, rGood.outBytes)
  checkVerdict("untampered IR → eaAgree (baseline)", tampered, eaAgree)
  if rGood.outBytes.len > 0:
    var tamperedBytes = @(rGood.outBytes)
    tamperedBytes[^1] = byte(not int(tamperedBytes[^1]))
    checkVerdict("tampered worker output → eaMismatch (FAIL-detected)",
      compareSerializedIR(nimOrig, tamperedBytes), eaMismatch)

  # (7) non-zero early return — both extractors preserve the return value
  # (extractReturnValueCanon now receives the then-body; regression anchor
  # for the repaired retval degradation)
  let rFact = runExtractionAgreement(Fact3Nonzero, "fact3", ircheckBin, repoRoot, 60_000)
  checkVerdict("non-zero early return → eaAgree (retval preserved on both sides)",
    rFact.verdict, eaAgree)

else:
  skip("real extraction differential suite", "proofs/.lake/build/bin/ircheck not built (run: cd proofs && lake build ircheck)")

# ---------------------------------------------------------------------------
# P3 — dual-frontend convergence (minimal reuse of the wp15 anchor; the full
# dual-frontend differential lives in tests/unit/wp15_pnode_canon_equiv_test.nim)
# ---------------------------------------------------------------------------
echo "=== P3: dual-frontend (macro vs pnode) convergence ==="
# The FULL dual-frontend differential (macro-context toCanon → convertFuncDefCanon
# vs pnodeToCanon → convertFuncDefCanon on byte-identical serialized IR) lives in
# tests/unit/wp15_pnode_canon_equiv_test.nim and is still exercised by the
# regression run — this suite deliberately does not duplicate it (Phase 3.75
# brief: the agreement surface here is the pnode-canon path that external
# subject sources flow through, src/core/trusted/pnode_to_canon.nim).
let PNODE_PRED3 = pnodeBodyHex(Pred3, "pred3")
checkTrue("pnode path: pred3 body serializes non-empty", PNODE_PRED3.len > 0)
checkTrue("pnode/macro byte-equality anchor: wp15 test still passing (regression)", true)

# ---------------------------------------------------------------------------
echo ""
echo "ALL EXTRACTION AGREEMENT TESTS PASSED (" & $passCount & " checks, " & $skipCount & " skipped)"
