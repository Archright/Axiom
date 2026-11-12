import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
## gate_resolver.nim — SSOT for gate source path resolution.
##
## Single source of truth shared by ALL components that map a manifest
## `entry` to an on-disk Nim source file:
##   - gateway fail-close CAS counter   (src/gate/gateway.nim)
##   - orchestrator executor/memo       (src/gate/orchestrator/hook/*)
##   - AOT precompiler                  (src/cli/precompile_gates.nim)
##
## Rationale (2026-07-27): the cache producer (precompiler) and consumer
## (gateway) previously used divergent resolution logic, which made
## "gateway counts a gate as missing while the precompiler cannot compile
## it" deadlocks possible. Content-addressed caching requires the key
## derivation to be computed identically on both sides.
##
## Layer: core — importable from both the gate layer and the presentation
## layer per src/core/trusted/layer_rules.nim.
import std/os

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func normalizeGateEntryName*(name: string): string =
  ## Manifest gate ids use '-', Nim modules use '_'.
  result = newString(name.len)
  for i in 0 ..< name.len:
    result[i] = if name[i] == '-': '_' else: name[i]

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func gateSourceCandidates*(entry: string): seq[string] =
  ## Ordered candidate source paths for a manifest entry (pure, no IO).
  ## Mirror of the historical orchestrator fallback chain.
  ## `.nim`-suffixed entries are accepted as-is: the suffix is stripped once
  ## so candidates never double-append ".nim" (foo.nim.nim), which previously
  ## made every `.nim` manifest entry unresolvable (executor fell back to
  ## exec'ing the source file -> EACCES).
  if entry.len == 0:
    return @[]
  let base =
    if entry.len >= 5 and entry[entry.len - 4 .. ^1] == ".nim": entry[0 .. ^5]
    else: entry
  result.add(base & ".nim")
  let rawName = extractFilename(base)
  let normalizedName = normalizeGateEntryName(rawName)
  if rawName == normalizedName:
    result.add("src/gate/runners/" & rawName & ".nim")
    result.add("scripts/" & rawName & ".nim")
    result.add("src/cli/" & rawName & ".nim")
  else:
    result.add("src/gate/runners/" & normalizedName & ".nim")
    result.add("src/gate/runners/" & rawName & ".nim")
    result.add("scripts/" & normalizedName & ".nim")
    result.add("scripts/" & rawName & ".nim")
    result.add("src/cli/" & normalizedName & ".nim")
    result.add("src/cli/" & rawName & ".nim")

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc resolveGateSourcePath*(entry: string): string =
  ## Resolve a manifest entry to an existing source path relative to the
  ## current working directory (repo root). Returns "" when nothing exists.
  for c in gateSourceCandidates(entry):
    if fileExists(c):
      return c
  return ""

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc resolveGateSourcePath*(entry: string; repoRoot: string): string =
  ## Same resolution, anchored at an explicit repo root. Returns the path
  ## RELATIVE to repoRoot (or "" when nothing exists) so cache keys remain
  ## stable regardless of caller working directory.
  for c in gateSourceCandidates(entry):
    if fileExists(repoRoot / c):
      return c
  return ""
{.pop.}
