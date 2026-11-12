import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}
## ProofCertificate ADT — Unified proof lifecycle record.
##
## Replaces fragmented IrPipelineResult / bool / string handling with a
## single value type that captures the full verification provenance,
## solver method, metrics, and outcome for every proof obligation.
##
## Design:
##   Pure value types only — no I/O, no refs, no exceptions.
##   Naming avoids collision with core/types/certificate_types.nim
##   (which uses CertificateStatus for on-disk certificates).
##
## Relationships:
##   IrPipelineResult  →  ProofCertificate  (via toProofCertificate)
##   FfiSolverResult    →  SolverMetrics     (via ffiResultToMetrics)
##   ProofCertificate   →  CertificateBatch  (via ProofAggregator)

import core/types/proof_status
export proof_status
import core/types/certificate_types
import verification/obligation/obligation_ir

# ---------------------------------------------------------------------------
# SolverMethod — Which verification backend produced the result
# ---------------------------------------------------------------------------

type
  SolverMethod* = enum
    smFFI               ## Z3 C API direct call (z3_solver_wrapper.solveViaFFI)
    smCLI               ## Z3 subprocess via persistent pool (z3_pool.z3ExecPersistent)
    smLean              ## Lean 4 kernel type-checking
    smTypeLevel         ## Type-level encoding fast-path (trivial_lean_router)
    smSpacer            ## Spacer CHC bypass (spacer_chc_router)
    smTrivial           ## Trivial proof (pre-sieve / type-directed)
    smNone              ## No solver invoked (error / skip)

# ---------------------------------------------------------------------------
# SolverMetrics — Granular solver telemetry
# ---------------------------------------------------------------------------

  SolverMetrics* = object
    wallTimeMs*: float        ## Wall-clock time for this proof obligation
    cpuTimeMs*: float         ## CPU time (if available from solver)
    solverConflicts*: uint64  ## Z3 conflicts counter
    solverDecisions*: uint64  ## Z3 decisions counter
    solverPropagations*: uint64  ## Z3 propagations counter
    memoryPeakBytes*: int64   ## Peak memory usage (if available)

# ---------------------------------------------------------------------------
# ProofCertificate — The core ADT
# ---------------------------------------------------------------------------

  ProofCertificate* = object
    functionName*: string         ## Verified function name
    sourceFile*: string           ## Source file path (module path)
    status*: ProofStatus          ## Proof outcome
    solverMethod*: SolverMethod   ## Which backend produced the result
    metrics*: SolverMetrics       ## Solver telemetry
    smtScript*: string            ## SMT-LIB2 script (if Z3 was invoked)
    leanSource*: string           ## Lean 4 source (if Lean was invoked)
    irHash*: string               ## SHA-256 hash of the IR (CAS key)
    provenance*: string           ## Human-readable provenance trace
    counterExample*: seq[string]  ## Counter-example bindings (if psFail)
    error*: string                ## Error message (if psError)
    crossValidated*: bool         ## Whether IR→SMT/Lean structural check passed
    pbtMetrics*: PbtMetrics       ## PBT/empirical verification metrics
    obligationVerdict*: ObligationGenerationResultKind  ## P5: obligation generator verdict for cert JSON

# ---------------------------------------------------------------------------
# CertificateBatch — Aggregate results for a verification run
# ---------------------------------------------------------------------------

  CertificateBatch* = object
    certificates*: seq[ProofCertificate]
    totalWallTimeMs*: float
    passCount*: int
    failCount*: int
    timeoutCount*: int
    skipCount*: int
    errorCount*: int

func isTrusted*(cert: ProofCertificate): bool =
  ## Derived state: certificate is actually verified
  cert.status == psPass and
  cert.irHash.len > 0

# ---------------------------------------------------------------------------
# Pure functions — no side effects
# ---------------------------------------------------------------------------

func statusToExitCode*(s: ProofStatus): int {.inline.} =
  case s
  of psPass, psNoObligation: 0
  of psFail:            1
  of psTimeout:         2
  of psSkip:            0
  of psError:           3
  of psVacuousTrivial:  0
  of psVacuousCounter:  1

func statusToDisplayChar*(s: ProofStatus): string {.inline.} =
  case s
  of psPass:            "P"
  of psFail:            "F"
  of psTimeout:         "T"
  of psSkip:            "S"
  of psError:           "E"
  of psVacuousTrivial:  "V"
  of psVacuousCounter:  "X"
  of psNoObligation:    "N"

func methodDisplayName*(m: SolverMethod): string {.inline.} =
  ## Human-readable solver method name.
  case m
  of smFFI:         "Z3-FFI"
  of smCLI:         "Z3-CLI"
  of smLean:        "Lean"
  of smTypeLevel:   "TypeLevel"
  of smSpacer:      "Spacer"
  of smTrivial:     "Trivial"
  of smNone:        "None"

func formatCertificate*(cert: ProofCertificate): string =
  let statusStr = case cert.status
    of psPass:            "✅ PASS"
    of psFail:            "[FAIL] FAIL"
    of psTimeout:         "⏰ TIMEOUT"
    of psSkip:            "⏭️  SKIP"
    of psError:           "[WARN]  ERROR"
    of psVacuousTrivial:  "🔲 VACUOUS"
    of psVacuousCounter:  "🔲 VACUOUS-C"
    of psNoObligation:    "🔲 NO-OB"

  result = cert.functionName
  result &= " [" & methodDisplayName(cert.solverMethod) & "] "
  result &= statusStr
  if cert.metrics.wallTimeMs > 0:
    result &= " (" & $cert.metrics.wallTimeMs.int & "ms)"
  if cert.error.len > 0:
    result &= " err=" & cert.error

func formatSummary*(batch: CertificateBatch): string =
  ## Multi-line batch summary for CLI output.
  result = "── Proof Summary ──\n"
  result &= "  Total: " & $batch.certificates.len & "\n"
  result &= "  Pass:  " & $batch.passCount & "\n"
  result &= "  Fail:  " & $batch.failCount & "\n"
  result &= "  TO:    " & $batch.timeoutCount & "\n"
  result &= "  Skip:  " & $batch.skipCount & "\n"
  result &= "  Error: " & $batch.errorCount & "\n"
  result &= "  Time:  " & $batch.totalWallTimeMs.int & "ms"

{.pop.}
