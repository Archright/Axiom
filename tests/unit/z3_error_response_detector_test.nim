import core/trusted/layer_declaration

## Z3 `(error …)` response handling — a refused script must never score a verdict.
##
## Every literal transcript below was captured from the pinned Z3 4.13.3 binary
## at ~/.local/bin/z3, with stdout and stderr redirected to separate files, so
## these assertions do not depend on a solver being present to run.
##
## The shape being excluded: Z3 answers a command it REFUSES with `(error …)`
## on stdout — not stderr — and then answers the following `(check-sat)` with a
## real verdict line, exiting non-zero. A consumer that scans stdout for a
## verdict token without rejecting the error form first records an internal tool
## failure as a solver decision.

import core/results
import core/sync/sync_utils_process
import core/trusted/solver_invocation
import core/types/z3_solver_config
import std/json
import std/os
import std/options
import std/strutils
import std/tempfiles
import verification/kernel_reexecution
import verification/solver/z3_pool
import verification/solver_adapter
import verification/batch_uap/ir_pipeline_runner

proc expect(cond: bool; msg: string) =
  if not cond:
    doAssert false, msg
  echo "  OK: " & msg

type Captured = object
  label: string
  script: string
  stdout: string
  stderr: string
  exitCode: int

# ─── Measured transcripts, pinned Z3 4.13.3 ────────────────────────────────

let errorThenSat = Captured(
  label: "unknown sort: two error responses, then a real `sat`, exit 1",
  script: "(set-logic QF_BV)\n(declare-fun x () BlahSort)\n(assert (= x y))\n(check-sat)\n",
  stdout: "(error \"line 2 column 18: Invalid function declaration: unknown sort 'BlahSort'\")\n" &
          "(error \"line 3 column 11: unknown constant x\")\nsat\n",
  stderr: "",
  exitCode: 1)

let outOfScopeLet = Captured(
  label: "out-of-scope `let` reference: one error response, then `sat`, exit 1",
  script: "(set-logic QF_BV)\n(declare-fun bytesCount () (_ BitVec 8))\n" &
          "(assert (let ((a (+ bytesCount 1))) (= a #x05)))\n(check-sat)\n",
  stdout: "(error \"line 3 column 32: unknown constant + ((_ BitVec 8) Int) \")\nsat\n",
  stderr: "",
  exitCode: 1)

let sortMismatch = Captured(
  label: "ill-sorted term: error response, then `sat`, exit 1",
  script: "(set-logic QF_BV)\n(declare-fun x () (_ BitVec 8))\n(declare-fun y () (_ BitVec 8))\n" &
          "(assert (= (bvadd x #x05) #b101))\n(check-sat)\n",
  stdout: "(error \"line 4 column 31: Sorts (_ BitVec 8) and (_ BitVec 3) are incompatible\")\nsat\n",
  stderr: "",
  exitCode: 1)

let truncated = Captured(
  label: "truncated s-expression: error response, no verdict, exit 1",
  script: "(set-logic QF_BV)\n(declare-fun x () (_ BitVec 8))\n(assert (= x #x05)\n(check-sat)\n",
  stdout: "(error \"line 4 column 0: invalid assert command, ')' expected\")\n",
  stderr: "",
  exitCode: 1)

let qfBvsUfFunction = Captured(
  label: "QF_BV rejects uninterpreted functions: three errors, then `sat`, exit 1",
  script: "(set-logic QF_BV)\n(declare-fun f (Int) Int)\n(declare-fun x () Int)\n" &
          "(assert (= (f x) 0))\n(check-sat)\n",
  stdout: "(error \"line 2 column 16: Parsing function declaration. Expecting sort list '(': unknown sort 'Int'\")\n" &
          "(error \"line 3 column 18: Invalid function declaration: unknown sort 'Int'\")\n" &
          "(error \"line 4 column 14: unknown constant x\")\nsat\n",
  stderr: "",
  exitCode: 1)

let qfBvsArray = Captured(
  label: "QF_BV rejects the Array sort: error response, no verdict, exit 1",
  script: "(set-logic QF_BV)\n(declare-fun mem () (Array (_ BitVec 8) (_ BitVec 8)))\n(check-sat)\n",
  stdout: "(error \"line 2 column 21: unknown sort 'Array'\")\n",
  stderr: "",
  exitCode: 1)

# The (error …) payload is free text and really does carry a verdict token:
# naming a sort `sat` puts the literal token inside the refusal itself.
let payloadCarriesSat = Captured(
  label: "error payload literally contains the token 'sat', exit 1",
  script: "(set-logic QF_BV)\n(declare-fun x () sat)\n(check-sat)\n",
  stdout: "(error \"line 2 column 18: Invalid function declaration: unknown sort 'sat'\")\nsat\n",
  stderr: "",
  exitCode: 1)

let payloadCarriesUnsat = Captured(
  label: "error payload literally contains the token 'unsat', exit 1",
  script: "(set-logic QF_BV)\n(declare-fun x () unsat)\n(check-sat)\n",
  stdout: "(error \"line 2 column 18: Invalid function declaration: unknown sort 'unsat'\")\nsat\n",
  stderr: "",
  exitCode: 1)

# Verdict BEFORE the error: Z3 answers an already-parsed (check-sat) and only
# then refuses the next command. The exit status is what disqualifies the run —
# the position of the error relative to the verdict does not.
let verdictBeforeError = Captured(
  label: "verdict first, error after: exit 1 makes the whole run un-decision-worthy",
  script: "(set-logic QF_BV)\n(declare-fun x () (_ BitVec 8))\n(assert (not (= x #x05)))\n" &
          "(check-sat)\n(declare-fun y () NopeSort)\n",
  stdout: "sat\n(error \"line 5 column 18: Invalid function declaration: unknown sort 'NopeSort'\")\n",
  stderr: "",
  exitCode: 1)

# (get-proof) without :produce-proofs — a common real path, refused AFTER a
# perfectly good verdict.
let proofNotEnabled = Captured(
  label: "get-proof without :produce-proofs: verdict, then an error response, exit 1",
  script: "(set-logic QF_BV)\n(declare-fun x () (_ BitVec 8))\n(assert (not (= x #x05)))\n" &
          "(check-sat)\n(get-proof)\n",
  stdout: "sat\n(error \"line 5 column 10: proof construction is not enabled, " &
          "use command (set-option :produce-proofs true)\")\n",
  stderr: "",
  exitCode: 1)

let unsatCoreNotEnabled = Captured(
  label: "get-unsat-core without :produce-unsat-cores: verdict, then an error, exit 1",
  script: "(set-logic QF_BV)\n(declare-fun x () (_ BitVec 8))\n(assert (not (= x #x05)))\n" &
          "(check-sat)\n(get-unsat-core)\n",
  stdout: "sat\n(error \"line 5 column 15: unsat core construction is not enabled, " &
          "use command (set-option :produce-unsat-cores true)\")\n",
  stderr: "",
  exitCode: 1)

block:
  echo "=== 1. a refused script yields NO decision, never a verdict ==="

  for cap in [errorThenSat, outOfScopeLet, sortMismatch, truncated,
              qfBvsUfFunction, qfBvsArray, payloadCarriesSat, payloadCarriesUnsat,
              verdictBeforeError, proofNotEnabled, unsatCoreNotEnabled]:
    echo "--- " & cap.label
    expect(solverStreamHasErrorResponse(cap.stdout),
      "the (error <s_expr>) response form is recognized")

    # Stream-only path (the persistent pool: no per-query exit code).
    let streamOnly = solverResponse(cap.stdout)
    expect(streamOnly == srNoDecision,
      "stream-only reading yields no decision")
    expect(not hasSolverDecision(streamOnly),
      "no-decision is not reported as a decision")
    expect(solverVerdictOf(streamOnly) == svUnknown,
      "it projects to svUnknown and never to sat or unsat")
    expect(classifySolverVerdict(cap.stdout) == svUnknown,
      "the three-token classifier cannot be bypassed into a verdict")

    # One-shot path (a real process: the exit code is evidence too).
    let withExit = solverResponse(cap.stdout, cap.exitCode)
    expect(withExit == srNoDecision, "reading with the exit code yields no decision")

    # The certification path, end to end.
    let kernel = z3ResultVerdict(cap.exitCode, false, cap.stdout)
    expect(kernel != krPassed,
      "kernel re-execution does NOT certify a refused script")
    expect(kernel == krZ3Mismatch or kernel == krZ3Error,
      "kernel re-execution lands on a fail-closed verdict")
    expect(composeKernelVerdict(krPassed, kernel, true, true) != krPassed,
      "the composed certificate verdict is not krPassed either")

block:
  echo "=== 2. the transcript that would have been scored is real ==="

  # If any of these stdout strings did NOT carry a bare verdict line, the
  # rejections above would be vacuous — a stream with nothing to misread proves
  # nothing about the detector.
  for cap in [errorThenSat, outOfScopeLet, sortMismatch, qfBvsUfFunction,
              payloadCarriesSat, payloadCarriesUnsat]:
    var sawBareVerdict = false
    for line in cap.stdout.splitLines():
      if line.strip() == "sat" or line.strip() == "unsat" or line.strip() == "unknown":
        sawBareVerdict = true
    expect(sawBareVerdict,
      "this transcript really does contain a bare verdict line: " & cap.label)

  expect(errorThenSat.stderr.len == 0 and outOfScopeLet.stderr.len == 0,
    "stderr was empty: the refusal is on stdout, so a stderr-only reader misses it")
  expect(payloadCarriesSat.stdout.contains("unknown sort 'sat'"),
    "the error payload really does contain the token 'sat'")

block:
  echo "=== 3. positive controls: well-formed streams still classify correctly ==="

  expect(solverResponse("unsat\n", 0) == srUnsat, "a clean unsat is unsat")
  expect(solverResponse("sat\n", 0) == srSat, "a clean sat is sat")
  expect(solverResponse("unknown\n", 0) == srUnknown,
    "a clean unknown is unknown — a real answer, distinct from no decision")
  expect(hasSolverDecision(srUnknown) and not hasSolverDecision(srNoDecision),
    "solver-said-unknown and solver-never-answered stay distinguishable")

  # A proof term mentioning `unsat` — measured: the named assertion is
  # `a_unsat_core_entry` and the response is still unsat.
  let proofStream =
    "unsat\n((set-logic QF_BV)\n(proof\n(unit-resolution " &
    "(asserted (= x (_ bv5 8))) (asserted (not (= x (_ bv5 8)))) false)))\n"
  expect(proofStream.contains("unsat"), "the proof transcript really does contain 'unsat'")
  expect(solverResponse(proofStream, 0) == srUnsat,
    "a proof term containing 'unsat' does not change the verdict")
  expect(z3ResultVerdict(0, false, proofStream) == krPassed,
    "a legitimate unsat WITH a proof term still certifies")

  # An unsat core whose assertion names contain `unsat` — measured.
  let coreStream = "unsat\n(unsat_core_member)\n"
  expect(solverResponse(coreStream, 0) == srUnsat,
    "an unsat core entry containing 'unsat' is not mistaken for a response")

  # A model after a sat: elaboration of that answer, not a second answer.
  let modelStream = "sat\n(\n  (define-fun x () (_ BitVec 8)\n    #x05)\n)\n"
  expect(solverResponse(modelStream, 0) == srSat,
    "a model following the verdict leaves the verdict intact")

  # Z3's own free-text diagnostics, which arrive on stderr and are merged into
  # the stream by every caller in this codebase. None of them is a response.
  expect(solverResponse("unsat\nunsupported\n; nonsense-command line: 6 position: 23\n", 0) == srUnsat,
    "merged stderr comments never displace the verdict")
  expect(solverResponse("sat\nunsupported\n; sat line: 5 position: 4\n", 0) == srSat,
    "a merged stderr comment containing 'sat' is not a response")
  expect(solverResponse("unsupported\n", 0) == srNoDecision,
    "an unsupported command with no check-sat answer is no decision")

block:
  echo "=== 4. the exit-code path is not advisory ==="

  expect(solverResponse("unsat\n", 1) == srNoDecision,
    "unsat with a non-zero exit is not a decision")
  expect(solverResponse("sat\n", 1) == srNoDecision,
    "sat with a non-zero exit is not a decision")
  expect(solverResponse("unknown\n", 1) == srNoDecision,
    "unknown with a non-zero exit is not a decision")
  expect(solverResponse("unsat\n", -9) == srNoDecision,
    "a killed process is not a decision")

  # The fail-closed direction is what makes this safe: with a timeout the
  # verdict is a timeout, and a non-zero exit can only ever remove a verdict.
  expect(z3ResultVerdict(1, false, "unsat\n") != krPassed,
    "a non-zero exit can never certify a kernel pass")
  expect(z3ResultVerdict(-9, false, "unsat\n") != krPassed,
    "a killed process can never certify a kernel pass")
  expect(z3ResultVerdict(1, true, "unsat\n") == krTimeout,
    "a timeout is still reported as a timeout")

block:
  echo "=== 5. the error-form matcher cannot be fooled by look-alikes ==="

  expect(not solverStreamHasErrorResponse("errors\n"),
    "'errors' is not the error response form")
  expect(not solverStreamHasErrorResponse("(errors \"boom\")\n"),
    "'(errors …)' is not the error response form")
  expect(not solverStreamHasErrorResponse("(error_msg 1)\n"),
    "'(error_msg 1)' is not the error response form")
  expect(not solverStreamHasErrorResponse("; (error \"this is a comment\")\n"),
    "an error form inside a comment is not a response")
  expect(not solverStreamHasErrorResponse("(proof (asserted (error 0)))\n"),
    "an (error …) term nested inside another s-expression is not a response")
  expect(solverStreamHasErrorResponse("  (error \"boom\")\n"),
    "leading whitespace does not hide the response form")
  expect(solverStreamHasErrorResponse("(error (some-symbolic-error-value))\n"),
    "a non-string error payload is still the error response form")

block:
  echo "=== 6. live pinned binary: end-to-end through the real Z3 ==="

  let z3Bin = resolveZ3Path()
  if z3Bin.len == 0 or not fileExists(z3Bin):
    echo "  SKIP: no resolvable z3 binary; the transcript assertions above stand alone"
  else:
    var ranLive = 0
    for cap in [errorThenSat, outOfScopeLet, sortMismatch, truncated,
                qfBvsUfFunction, qfBvsArray]:
      let path = getTempDir() / ("axiom_z3err_" & $getCurrentProcessId() & "_" & $ranLive & ".smt2")
      try:
        writeFile(path, cap.script)
        let res = runProcessWithTimeout(z3Bin, @["-smt2", path], 30_000)
        try: removeFile(path)
        # A scratch file that cannot be removed must not fail the assertion
        # about what z3 said; the leftover lives under the system temp dir.
        except CatchableError: discard  # axiom:best-effort(ioboundary catch)

        if solverResponse(res.output, res.exitCode) != srNoDecision:
          echo "  FAIL: live z3 stream was scored: " & cap.label & "\n" & res.output
          doAssert false, "live z3 produced a decision for a refused script: " & cap.label
        if res.exitCode == 0 and not solverStreamHasErrorResponse(res.output):
          echo "  NOTE: live z3 accepted: " & cap.label
        if z3ResultVerdict(res.exitCode, res.timedOut, res.output) == krPassed:
          doAssert false, "live z3 produced a kernel pass for a refused script: " & cap.label
        inc ranLive
        echo "  OK: live z3 yields no decision — " & cap.label
      except CatchableError as e:
        echo "  SKIP: live run failed (" & e.msg & ") for " & cap.label

    expect(ranLive > 0, "the live section exercised the real binary at least once")

    # The verified-pool boundary: a refused script must not come back `ok`.
    let pool = initVerifiedZ3Pool()
    if pool.isSome:
      expect(execZ3Verified(pool.get(), "(set-logic QF_BV)\n" &
        "(declare-fun x () BlahSort)\n(assert (= x y))\n(check-sat)\n").isErr,
        "execZ3Verified refuses a script Z3 rejected — it never returns ok(sat)")
      expect(execZ3Verified(pool.get(),
        "(set-logic QF_BV)\n(declare-fun bytesCount () (_ BitVec 8))\n" &
        "(assert (let ((a missingCount)) (= a #x05)))\n(check-sat)\n").isErr,
        "execZ3Verified refuses the out-of-scope `let` script")
      expect(execZ3Verified(pool.get(),
        "(set-logic QF_BV)\n(declare-fun bytesCount () (_ BitVec 8))\n" &
        "(assert (= bytesCount #x05))\n(assert (not (= bytesCount #x05)))\n(check-sat)\n").isOk,
        "a well-formed contradiction through the same boundary still proves")
    else:
      echo "  SKIP: z3 health probe failed; pool-boundary assertions not exercised"

block:
  echo "=== 7. verdict-minting classifiers: an error-bearing stream is never SAT ==="

  # The IR-pipeline classifier (runZ3CheckViaIR → classifyZ3Output) minted
  # sosSat from the transcripts above before the DECISION-0824/0825 gate was
  # wired in — it skipped the `(error …)` lines and read the trailing bare
  # `sat` (calcDynamicTimeoutCore incident). These assertions pin the gate on
  # the SAME measured transcripts.

  for cap in [errorThenSat, outOfScopeLet, sortMismatch, qfBvsUfFunction,
              payloadCarriesSat, payloadCarriesUnsat, verdictBeforeError]:
    expect(classifyZ3Output(cap.stdout, 0, 30_000) == solver_adapter.sosUnknown,
      "error-bearing stream is UNKNOWN, never SAT — " & cap.label)
    expect(classifyZ3Output(cap.stdout, 0, 30_000) != solver_adapter.sosSat,
      "the SAT mint is unreachable for — " & cap.label)

  # A stream with NO verdict at all stays UNKNOWN, and Z3's `unsupported`
  # response never reads as SAT either.
  expect(classifyZ3Output(truncated.stdout, 0, 30_000) == solver_adapter.sosUnknown,
    "a truncated script with no verdict is UNKNOWN")
  expect(classifyZ3Output("unsupported\n", 0, 30_000) == solver_adapter.sosUnknown,
    "an unsupported-token stream is UNKNOWN, never SAT")
  expect(classifyZ3Output("(error \"line 2 column 18: unknown sort 'BlahSort'\")\nunsupported\n",
    0, 30_000) == solver_adapter.sosUnknown,
    "an error response followed by `unsupported` is UNKNOWN, never SAT")

  # Regression: clean streams classify exactly as before — the gate sits on
  # the SAT mint only.
  expect(classifyZ3Output("sat\n", 0, 30_000) == solver_adapter.sosSat,
    "a clean sat is SAT (regression)")
  expect(classifyZ3Output("unsat\n", 0, 30_000) == solver_adapter.sosUnsat,
    "a clean unsat is UNSAT (regression)")
  expect(classifyZ3Output("unknown\n", 0, 30_000) == solver_adapter.sosUnknown,
    "a clean unknown is UNKNOWN (regression)")
  expect(classifyZ3Output("sat\n(\n  (define-fun x () (_ BitVec 8)\n    #x05)\n)\n",
    0, 30_000) == solver_adapter.sosSat,
    "a model following the verdict does not disturb the SAT mint (regression)")

  # A timed-out run keeps its timeout classification; the gate never turns a
  # timeout into an UNKNOWN.
  expect(classifyZ3Output("timeout\n", 30_000, 30_000) == solver_adapter.sosTimeout,
    "a timeout is still a timeout (regression)")

block:
  echo "=== 8. telemetry records the answer and the transport separately (#349) ==="

  # The reported defect: an `unsat` run whose `(get-model)` is refused. The
  # verdict path reads `unsat` (block 7 above), and the telemetry row used to
  # read `result:"error"` because `solverResponse` rejects the WHOLE stream once
  # an `(error …)` response is present — the right rule for a verdict and the
  # wrong one for a record of what happened.
  #
  # The row is the observable surface, so this block runs the real persistent
  # pool (the only producer on this path) with AXIOM_STATE_DIR aimed at a scratch
  # directory and reads back logs/z3_telemetry.jsonl — no internals inspected.
  # `result` must be the answer the verdict path reads; `transport_error` must
  # carry the refused-command fact on its own axis.

  let z3Bin = resolveZ3Path()
  if z3Bin.len == 0 or not fileExists(z3Bin):
    echo "  SKIP: no resolvable z3 binary; the telemetry row cannot be produced"
  else:
    type TelemetryCase = object
      label: string
      query: string
      result: string
      transportError: string

    # Every stream below was measured on the pinned Z3 4.13.3 binary:
    #   (assert false) (check-sat) (get-model)
    #     → unsat
    #     → (error "line 3 column 10: model is not available")
    #   (declare-fun x () sat) (check-sat)
    #     → (error "line 1 column 18: … unknown sort 'sat'")
    #     → sat
    # The second case is why the SAT gate cannot be dropped: the transport was
    # refused, so the verdict path mints no SAT, and the record must not either.
    let cases = [
      TelemetryCase(label: "unsat, then (get-model) refused",
        query: "(assert false)\n(check-sat)\n(get-model)\n",
        result: "unsat", transportError: "error-response"),
      TelemetryCase(label: "refused declaration, then a bare sat",
        query: "(declare-fun x () sat)\n(check-sat)\n",
        result: "unknown", transportError: "error-response"),
      TelemetryCase(label: "clean sat, nothing refused",
        query: "(declare-fun x () Int)\n(assert (= x 1))\n(check-sat)\n",
        result: "sat", transportError: "")
    ]

    let stateDir = getTempDir() / ("axiom_349_telemetry_" & $getCurrentProcessId())
    try: removeDir(stateDir)
    except CatchableError: discard  # axiom:best-effort(ioboundary catch)
    createDir(stateDir)
    let prevStateDir = getEnv("AXIOM_STATE_DIR", "")
    putEnv("AXIOM_STATE_DIR", stateDir)
    defer:
      if prevStateDir.len > 0: putEnv("AXIOM_STATE_DIR", prevStateDir)
      else: delEnv("AXIOM_STATE_DIR")
      try: removeDir(stateDir)
      except CatchableError: discard  # axiom:best-effort(ioboundary catch)

    for c in cases:
      var envelopeDigest, payloadDigest: string
      let res = z3ExecPersistent(c.query, desiredWorkers = 1,
        canonicalEnvelopeDigest = envelopeDigest, transportPayloadDigest = payloadDigest)
      expect(res.isOk, "the pool still returns the solver's answer — " & c.label)
      if res.isOk:
        # The verdict path is untouched: whatever it reads is what the row must
        # record. This is the equivalence the split is required to keep.
        let verdict = classifyZ3Output(res.get(), 0, 10_000)
        case c.result
        of "unsat": expect(verdict == solver_adapter.sosUnsat,
          "verdict path reads unsat — " & c.label)
        of "sat": expect(verdict == solver_adapter.sosSat,
          "verdict path reads sat — " & c.label)
        else: expect(verdict != solver_adapter.sosUnsat and verdict != solver_adapter.sosSat,
          "verdict path mints no verdict — " & c.label)

    let logPath = stateDir / "logs" / "z3_telemetry.jsonl"
    expect(fileExists(logPath), "the pool wrote a telemetry row per query")
    var rows: seq[JsonNode] = @[]
    if fileExists(logPath):
      for line in readFile(logPath).splitLines():
        if line.strip().len == 0:
          continue
        rows.add(parseJson(line))
    expect(rows.len == cases.len,
      "one row per query: " & $rows.len & " rows for " & $cases.len & " queries")

    for i in 0 ..< min(rows.len, cases.len):
      let c = cases[i]
      let row = rows[i]
      echo "  ROW: " & $row
      expect(row{"schema"}.getStr("") == "axiom-z3-telemetry/2",
        "the row declares which definition of `result` it uses — " & c.label)
      expect(row{"result"}.getStr("") == c.result,
        "result is the solver's answer, not the transport outcome — " & c.label &
        " (got '" & row{"result"}.getStr("") & "')")
      expect(row{"transport_error"}.getStr("") == c.transportError,
        "transport_error carries the refused-command fact — " & c.label &
        " (got '" & row{"transport_error"}.getStr("") & "')")

  echo "=== Z3 Error Response Detector OK ==="