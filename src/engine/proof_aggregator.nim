import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}
## ProofAggregator — Collects ProofCertificates into a CertificateBatch.
##
## Usage:
##   var agg = initAggregator()
##   agg.record(cert1)
##   agg.record(cert2)
##   agg.finalize()
##   echo agg.batch.formatSummary()
##
## Design:
##   Value-type aggregation with deterministic finalization.
##   Wall-clock timing is captured at init/finalize boundaries.
##   Thread-safe: each worker owns its own aggregator; merge via
##   mergeAggregators() at the batch boundary.

import std/monotimes
import proof_certificate
import core/trusted/axiom_pragmas_lite
export proof_certificate

# ---------------------------------------------------------------------------
# Aggregator state
# ---------------------------------------------------------------------------

type
  ProofAggregator* = object
    batch*: CertificateBatch
    startTimeNs*: int64

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

proc initAggregator*(): ProofAggregator {.raises: [], axiomEffect: IOEffect.} =
  ## Create a fresh aggregator with monotonic start time.
  result.batch = CertificateBatch()
  result.startTimeNs = getMonoTime().ticks

func record*(agg: var ProofAggregator, cert: ProofCertificate) =
  agg.batch.certificates.add(cert)
  case cert.status
  of psPass:
    inc agg.batch.passCount
  of psFail, psVacuousCounter:
    inc agg.batch.failCount
  of psTimeout:
    inc agg.batch.timeoutCount
  of psSkip, psNoObligation:
    inc agg.batch.skipCount
  of psError:
    inc agg.batch.errorCount
  of psVacuousTrivial:
    inc agg.batch.skipCount

proc finalize*(agg: var ProofAggregator) {.raises: [], axiomEffect: IOEffect.} =
  ## Compute aggregate metrics (wall time). Call once after all records.
  let elapsedNs = getMonoTime().ticks - agg.startTimeNs
  agg.batch.totalWallTimeMs = elapsedNs.float / 1_000_000.0

func mergeAggregators*(a, b: ProofAggregator): CertificateBatch =
  ## Merge two aggregators into a single CertificateBatch.
  ## Use when parallel workers each maintain their own aggregator.
  result.certificates = a.batch.certificates & b.batch.certificates
  result.passCount = a.batch.passCount + b.batch.passCount
  result.failCount = a.batch.failCount + b.batch.failCount
  result.timeoutCount = a.batch.timeoutCount + b.batch.timeoutCount
  result.skipCount = a.batch.skipCount + b.batch.skipCount
  result.errorCount = a.batch.errorCount + b.batch.errorCount
  result.totalWallTimeMs = a.batch.totalWallTimeMs + b.batch.totalWallTimeMs

func countByMethod*(batch: CertificateBatch): array[SolverMethod, int] =
  ## Count certificates per solver method.
  ## Useful for solver utilization reporting.
  for cert in batch.certificates:
    inc result[cert.solverMethod]

{.pop.}
