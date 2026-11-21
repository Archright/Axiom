import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary

import std/json
import std/os
import std/strutils
import core/trusted/axiom_pragmas

type
  Z3TelemetryRecord* = object
    ts*: string          ## ISO timestamp
    queryType*: string   ## "bmc", "cegar", "k_induction", etc.
    rlimit*: int         ## Injected rlimit value
    result*: string      ## "sat", "unsat", "unknown", "timeout", "error"
    timeMs*: int         ## Wall-clock time in milliseconds
    memoryMb*: int       ## Peak memory in megabytes
    cegarIters*: int       ## CEGAR iterations if applicable, else 0
    baseCaseResult*: string ## "unsat" | "sat" | "unknown" | ""
    stepCaseResult*: string ## "unsat" | "sat" | "unknown" | ""
    canonicalEnvelopeDigest*: string ## H(pre-sentinel envelope bytes)
    transportPayloadDigest*: string  ## H(full payload incl sentinel)
    workerAcquireMs*: int        ## start -> lease + readiness barrier (0 = no lease)
    workerRoundtripMs*: int      ## write -> sentinel/result; one-shot: start -> exit (0 = never dispatched)
    executionPath*: string       ## "persistent" | "one_shot_file" | "none" (empty serializes as "none")
    workerPid*: int              ## PID that ran the query (0 = none)
    rssBeforeKb*: int            ## VmRSS of workerPid at first dispatch (0 = sample failed)
    rssAfterKb*: int             ## VmRSS of workerPid at defer time (0 = failed or exited)
    rssDeltaValid*: bool         ## true only for a persistent PID spanning both samples
    getModelRequested*: bool     ## final payload contains "(get-model)"

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc appendZ3Telemetry*(record: Z3TelemetryRecord) {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Append a Z3 telemetry record to logs/z3_telemetry.jsonl.
  ## Fails silently on I/O errors to avoid disrupting solver execution.
  ## A zero-initialized `executionPath` serializes as "none" (the honest
  ## default: no process was dispatched).
  try:
    let executionPath =
      if record.executionPath.len == 0: "none" else: record.executionPath
    let jsonObj = %*{
      "ts": record.ts,
      "query_type": record.queryType,
      "rlimit": record.rlimit,
      "result": record.result,
      "time_ms": record.timeMs,
      "memory_mb": record.memoryMb,
      "cegar_iters": record.cegarIters,
      "base_case_result": record.baseCaseResult,
      "step_case_result": record.stepCaseResult,
      "canonical_envelope_digest": record.canonicalEnvelopeDigest,
      "transport_payload_digest": record.transportPayloadDigest,
      "worker_acquire_ms": record.workerAcquireMs,
      "worker_roundtrip_ms": record.workerRoundtripMs,
      "execution_path": executionPath,
      "worker_pid": record.workerPid,
      "rss_before_kb": record.rssBeforeKb,
      "rss_after_kb": record.rssAfterKb,
      "rss_delta_valid": record.rssDeltaValid,
      "get_model_requested": record.getModelRequested
    }
    let line = $jsonObj & "\n"
    # WP2-a: stateRoot routing for subject immutability.
    let path = block:
      let v = getEnv("AXIOM_STATE_DIR", "").strip()
      if v.len > 0: joinPath(v, "logs", "z3_telemetry.jsonl")
      else: "logs/z3_telemetry.jsonl"
    let dir = parentDir(path)
    if dir.len > 0 and not dirExists(dir):
      createDir(dir)
    let f = open(path, fmAppend)
    f.write(line)
    f.close()
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)

{.pop.}
