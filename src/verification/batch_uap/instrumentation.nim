## instrumentation.nim — Compile-time and runtime timing instrumentation
##
## Provides templates for wrapping code blocks with monotonic timing.
## Records wall-clock elapsed time using MonoTime for deterministic
## measurement across CPU frequency scaling and system load.
##
## Usage:
##   let elapsedMs = timedBlock("cache-prime"):
##     primeTransitiveFingerprintCache(...)
##
##   withProofTimer:
##     runBatchUapOrchestration(...)

import core/trusted/layer_declaration
axiomLayer "infrastructure"
import std/monotimes
import std/strutils

type
  AxiomTimingEntry* = object
    ## A single timing record.
    label*: string
    elapsedMs*: float

  AxiomTimingLog* = object
    ## Accumulator for timing entries during a pipeline run.
    entries*: seq[AxiomTimingEntry]
    pipelineStartTicks*: int64

proc initTimingLog*(): AxiomTimingLog {.raises: [].} =
  ## Create a new timing log with pipeline start marker.
  AxiomTimingLog(
    entries: @[],
    pipelineStartTicks: getMonoTime().ticks
  )

func recordEntry*(log: var AxiomTimingLog, label: string, elapsedMs: float) {.raises: [].} =
  ## Append a timing entry to the log.
  log.entries.add(AxiomTimingEntry(label: label, elapsedMs: elapsedMs))

proc pipelineElapsedMs*(log: AxiomTimingLog): float {.raises: [].} =
  ## Return total pipeline wall-clock time in milliseconds.
  float(getMonoTime().ticks - log.pipelineStartTicks) / 1_000_000

proc formatTimingReport*(log: AxiomTimingLog): string {.raises: [].} =
  ## Format all timing entries as a human-readable report string.
  result = "Timing Report (" & $log.entries.len & " entries):\n"
  for entry in log.entries:
    result &= "  " & entry.label & ": " &
              formatFloat(entry.elapsedMs, ffDecimal, 2) & "ms\n"
  result &= "  Pipeline total: " &
            formatFloat(log.pipelineElapsedMs(), ffDecimal, 2) & "ms"

template timedBlock*(label: static[string], body: untyped): float =
  ## Execute body and return elapsed wall-clock time in milliseconds.
  ## Uses MonoTime for high-resolution, monotonic measurement.
  let tStart = getMonoTime().ticks
  body
  let tElapsed = float(getMonoTime().ticks - tStart) / 1_000_000
  tElapsed

template timedBlockMs*(label: static[string], body: untyped): int64 =
  ## Execute body and return elapsed wall-clock time as int64 milliseconds.
  ## Suitable for OrchestrationExecutionStats fields.
  let tStartMs = getMonoTime().ticks div 1_000_000
  body
  let tEndMs = getMonoTime().ticks div 1_000_000
  if tEndMs >= tStartMs: tEndMs - tStartMs
  else: 0'i64

template withProofTimer*(body: untyped): float =
  ## Top-level proof pipeline timing wrapper.
  ## Returns total elapsed wall-clock time in milliseconds.
  let proofStart = getMonoTime().ticks
  body
  float(getMonoTime().ticks - proofStart) / 1_000_000

proc nodeTimingMs*(startTicks: int64): float {.raises: [].} =
  ## Compute elapsed milliseconds from a monotonic tick start.
  ## Used by per-node timing in the depth loop.
  float(getMonoTime().ticks - startTicks) / 1_000_000
