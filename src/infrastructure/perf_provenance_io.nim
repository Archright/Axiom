import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

## Perf provenance I/O boundary — environment probes consumed by the
## perf_latest.json emit in engine/profiler.nim. This module owns the boundary
## effects (subprocess execution, pin-file read, prior-latest read/parse) and
## nothing else; the pure metric-key derivation and the emit templates stay in
## engine/profiler.nim. Every probe here is best-effort by contract and never
## raises (see the per-proc axiom:best-effort notes).

import std/[json, os, osproc, strutils]

import core/trusted/axiom_pragmas

axiomIoBoundary()

## Provenance only (never compared by the gate): the commit that produced
## this measurement, "" when unavailable (non-git deploy).
proc gitHeadCommit*(): string {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  try:
    let (outp, code) = execCmdEx("git rev-parse HEAD")
    if code == 0:
      return outp.strip()
  except CatchableError: # axiom:best-effort(provenance-only commit ref; "" when git is unavailable — never compared by the gate)
    discard
  return ""

## Comparability field: the repo-pinned Lean toolchain reference.
proc leanToolchainRef*(): string {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  try:
    return readFile("lean-toolchain").strip()
  except CatchableError: # axiom:best-effort("unknown" when the pin file is absent; the verbatim value is still env-compared by the gate)
    discard
  return "unknown"

## Merge base for accumulating per-metric measurements across profiled
## blocks in one process. Read/parse failure yields a fresh map: the gate
## (tools/perf_checker.nim) fails closed on an invalid latest file, so this
## heal cannot mask a comparison-relevant failure.
proc existingMeasurements*(path: string): JsonNode {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  try:
    let root = parseJson(readFile(path))
    if root.kind == JObject and root.hasKey("measurements") and
        root["measurements"].kind == JObject:
      return root["measurements"]
  except CatchableError: # axiom:best-effort(fresh map on unreadable prior latest — the gate fails closed on an invalid latest file, so this heal cannot mask a comparison)
    discard
  return newJObject()
