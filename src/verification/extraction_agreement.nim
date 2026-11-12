import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

## Extraction Agreement (certification-continuity Phase 3.75 — Tier 2).
##
## Per-run differential (contract §4.1, INV-4):
##   Nim source → canonical AST (pnodeToCanon, the sanctioned read path for
##     external subject sources — src/core/trusted/pnode_to_canon.nim)
##     → ast wire (src/verification/ast_wire.nim)
##     → Lean reference extractor (proofs/IR/ReferenceExtractor.lean via
##       `ircheck extract`) → IR_Lean bytes
##   Nim extractor (axiomBodyCanon — src/core/trusted/ast_to_ir.nim)
##     → IR_Nim bytes (ir_binary_codec serializeIRExprAligned)
##   IR_Nim == IR_Lean byte-for-byte ELSE FAIL CLOSED.
##
## Verdicts:
##   eaAgree          — byte-equal serialized IR (the only evidence-carrying
##                      verdict; contract §2)
##   eaMismatch       — both sides produced IR but the serialized forms
##                      differ (fail-closed).
##   eaUnsupported    — the wire codec rejected a canonical node outside the
##                      certified-subset wire set (fail-closed, never skip).
##   eaReferenceError — Lean worker binary missing, worker IO failure (exit
##                      2), or output file unreadable.
##   eaInternalError  — source parse / func-def lookup failure, malformed
##                      wire from OUR codec, or worker timeout.
##
## Worker channel: the AST wire and the IR output travel via temp FILES —
## only quoted paths appear on argv (QUIRK(quirk#runGitEx-argv-flattening):
## whitespace payloads are never inlined). See
## docs/spec/merge_materializer_quirks.md §2.

import std/os
import std/strutils
import core/axiom_pragmas
import core/crypto/hash_kernel
import core/parser_utils
import core/trusted/ast_to_ir
import core/trusted/pnode_to_canon
import core/utils/repo_root
import infrastructure/ir_binary_codec
import infrastructure/process_utils
import shared/canonical_ast
import verification/ast_wire

axiomIoBoundary()

type
  ExtractionAgreementVerdict* = enum
    eaAgree
    eaMismatch
    eaUnsupported
    eaReferenceError
    eaInternalError

  ExtractionAgreementResult* = object
    verdict*: ExtractionAgreementVerdict
    reason*: string
    nimDigest*: string
    leanDigest*: string

const agreementVerdictReasons: array[ExtractionAgreementVerdict, string] = [
  "Nim extractor and Lean reference extractor agree (byte-equal serialized IR)",
  "IR_Nim != IR_Lean — extractors disagree on the certified subset (fail-closed)",
  "canonical AST contains a node outside the certified-subset wire set (fail-closed)",
  "Lean reference extractor unavailable or failed at the IO level (fail-closed)",
  "internal failure during the agreement run (fail-closed)"
]

const agreementReasonCodes: array[ExtractionAgreementVerdict, string] = [
  "EA_AGREE", "EA_MISMATCH", "EA_UNSUPPORTED", "EA_REFERENCE_ERROR", "EA_INTERNAL_ERROR"
]

func agreementVerdictReason*(v: ExtractionAgreementVerdict): string {.raises: [].} =
  agreementVerdictReasons[v]

func agreementReasonCode*(v: ExtractionAgreementVerdict): string {.raises: [].} =
  agreementReasonCodes[v]

func irBytesEqual*(a, b: openArray[byte]): bool {.raises: [].} =
  ## Exact byte equality of the two serialized forms.
  if a.len != b.len:
    return false
  for i in 0 ..< a.len:
    if a[i] != b[i]:
      return false
  true

func compareSerializedIR*(nimIR, leanIR: openArray[byte]): ExtractionAgreementVerdict {.raises: [].} =
  ## Pure comparison: byte-equal → eaAgree; non-empty + different → eaMismatch;
  ## an empty side is not comparable → eaInternalError (fail-closed).
  if nimIR.len == 0 or leanIR.len == 0:
    return eaInternalError
  if irBytesEqual(nimIR, leanIR):
    eaAgree
  else:
    eaMismatch

func bytesToStr(bytes: openArray[byte]): string {.raises: [].} =
  result = newString(bytes.len)
  for i in 0 ..< bytes.len:
    result[i] = char(bytes[i])

func nimExtractionBytes*(canon: CanonNode): seq[byte] {.raises: [].} =
  ## (a) Nim extractor leg: canonical func def → body IR → serialized bytes.
  let ir = axiomBodyCanon(canon)
  serializeIRExprAligned(ir.body)

proc runReferenceExtractorOnWire*(
  wireBytes: seq[byte];
  ircheckExe: string = "";
  projectRoot: string = "";
  timeoutMs: int = 60_000
): tuple[exitCode: int, output: string, outBytes: seq[byte]] {.
  raises: [CatchableError], axiomEffect: IOEffect,
  tags: [AxiomIOEffect, IOEffect, RootEffect].}
  ## Forward declaration.

proc agreementFromWire*(canon: CanonNode; wire: AstWireResult; ircheckExe, projectRoot: string; timeoutMs: int): ExtractionAgreementResult {.
  raises: [CatchableError], axiomEffect: IOEffect,
  tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Steps (a)+(c)+(d): Nim extractor bytes, Lean reference via the worker,
  ## byte-compare. wire is the already-validated serialization from stage (b).
  var nimBytes = nimExtractionBytes(canon)
  result = ExtractionAgreementResult(verdict: eaInternalError, reason: "", nimDigest: "", leanDigest: "")
  result.nimDigest = sha256Hex(bytesToStr(nimBytes))
  let lean = runReferenceExtractorOnWire(wire.bytes, ircheckExe, projectRoot, timeoutMs)
  if lean.exitCode == -2:
    result.verdict = eaReferenceError
    result.reason = "reference extractor binary unavailable: " & lean.output
    return
  if lean.exitCode == -1:
    result.reason = "ircheck extract timed out or failed to start: " & lean.output
    return
  if lean.exitCode == 2:
    result.verdict = eaReferenceError
    result.reason = "reference extractor IO failure: " & lean.output
    return
  if lean.exitCode != 0:
    result.verdict = eaUnsupported
    result.reason = "reference extractor rejected the wire (unsupported construct or malformed bytes): " & lean.output
    return
  if lean.outBytes.len == 0:
    result.verdict = eaReferenceError
    result.reason = "reference extractor produced no output file"
    return
  result.leanDigest = sha256Hex(bytesToStr(lean.outBytes))
  result.verdict = compareSerializedIR(nimBytes, lean.outBytes)
  result.reason = agreementVerdictReason(result.verdict)

proc runReferenceExtractorOnWire*(
  wireBytes: seq[byte];
  ircheckExe: string = "";
  projectRoot: string = "";
  timeoutMs: int = 60_000
): tuple[exitCode: int, output: string, outBytes: seq[byte]] {.
  raises: [CatchableError], axiomEffect: IOEffect,
  tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## (c) Reference-extractor leg: write the AST wire to a temp FILE, invoke
  ## `ircheck extract --ast <file> --out <file>` (temp-FILE channel for BOTH
  ## payloads — QUIRK(quirk#runGitEx-argv-flattening)), read the IR output.
  ## exitCode: -1 = timeout, 0 = worker OK, 1 = extraction failure,
  ## 2 = worker IO failure. outBytes empty on any non-zero exit.
  result = (exitCode: -1, output: "", outBytes: @[])
  let root = if projectRoot.len > 0: projectRoot else: resolveRepoRoot()
  let worker =
    if ircheckExe.len > 0:
      ircheckExe
    elif getEnv("AXIOM_IRCHECK_CMD", "").len > 0:
      getEnv("AXIOM_IRCHECK_CMD", "")
    else:
      root / "proofs" / ".lake" / "build" / "bin" / "ircheck"
  if not fileExists(worker):
    # Sentinel -2: worker binary unavailable (distinct from timeout -1).
    result.exitCode = -2
    result.output = "ircheck reference-extractor binary not found: " & worker
    return
  var payload = bytesToStr(wireBytes)
  var astPath = ""
  var outPath = ""
  try:
    astPath = getTempDir() / ("axiom_astwire_" & sha256Hex(payload) & ".bin")
    outPath = getTempDir() / ("axiom_irlean_" & sha256Hex(payload) & ".bin")
    writeFile(astPath, payload)
    let (output, code) = execCmdWithTimeout(
      quoteShell(worker) & " extract --ast " & quoteShell(astPath) & " --out " &
      quoteShell(outPath), timeoutMs = timeoutMs)
    result.output = output
    result.exitCode = code
    if code == 0 and fileExists(outPath):
      let text = readFile(outPath)
      var bytes: seq[byte] = @[]
      for i in 0 ..< text.len:
        bytes.add(byte(text[i]))
      result.outBytes = bytes
  except CatchableError:
    result.output = "ircheck extract invocation failed"
  finally:
    if astPath.len > 0:
      try: removeFile(astPath)
      except CatchableError: discard # axiom:best-effort(ioboundary catch) temp cleanup
    if outPath.len > 0:
      try: removeFile(outPath)
      except CatchableError: discard # axiom:best-effort(ioboundary catch) temp cleanup

proc runExtractionAgreement*(
  funcSource: string;
  funcName: string;
  ircheckExe: string = "";
  projectRoot: string = "";
  timeoutMs: int = 60_000
): ExtractionAgreementResult {.
  raises: [CatchableError], axiomEffect: IOEffect,
  tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Full per-run differential for ONE function (contract §4.1 Tier 2).
  ## Steps: (b) wire the canonical AST (unsupported node → eaUnsupported);
  ## (a) Nim extractor → IR_Nim bytes; (c) Lean reference via the worker;
  ## (d) byte-compare. Fail-closed at every step.
  result = ExtractionAgreementResult(verdict: eaInternalError, reason: "", nimDigest: "", leanDigest: "")
  if funcSource.len == 0 or funcName.len == 0:
    result.reason = "empty source or func name"
    return
  let ast = parseStringAST(funcSource)
  if ast.isNil:
    result.reason = "source failed to parse"
    return
  let defNode = findFuncDefP(ast, funcName, "")
  if defNode.isNil:
    result.reason = "func '" & funcName & "' not found in source"
    return
  let canon = pnodeToCanon(defNode)
  let wire = serializeAstWire(canon)
  if not wire.ok:
    result.verdict = eaUnsupported
    result.reason = "unsupported AST node (" & wire.kindName & ") outside the certified-subset wire set"
    return
  result = agreementFromWire(canon, wire, ircheckExe, projectRoot, timeoutMs)

{.pop.}