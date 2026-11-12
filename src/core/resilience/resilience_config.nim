import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary

## Resilience configuration — loaded from axiom.toml [resilience] section.
## Provides compile-time defaults with runtime override via TOML or env vars.
## Follows AGENTS.md: Configuration over Hardcoding.
##
## Import encapsulation: core/resilience/ only imports from core/ and std/.
## The caller (I/O boundary) provides the TOML path; this module parses
## the flat key=value pairs inline to avoid crossing into cli/.

import std/tables
import std/os
import std/strutils
import core/types/results
import core/parsers/safe_parsers
import core/trusted/axiom_pragmas_lite
type
  ResilienceConfig* = object
    retryMaxAttempts*: int
    retryBaseDelayMs*: int
    retryMaxDelayMs*: int
    retryJitterRatio*: float
    circuitFailureThreshold*: int
    circuitResetAfterMs*: int
    dumpDir*: string
    dumpMaxAgeHours*: int
    dumpMaxCount*: int
    rateLimitBackoffMultiplier*: int

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func defaultResilienceConfig*(): ResilienceConfig {.noSideEffect.} =
  ## Compile-time defaults for resilience parameters.
  ResilienceConfig(
    retryMaxAttempts: 3,
    retryBaseDelayMs: 100,
    retryMaxDelayMs: 5000,
    retryJitterRatio: 0.1,
    circuitFailureThreshold: 5,
    circuitResetAfterMs: 30000,
    dumpDir: "logs/evidence",
    dumpMaxAgeHours: 72,
    dumpMaxCount: 500,
    rateLimitBackoffMultiplier: 3
  )

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func parseIntOrDefault(s: string; default: int): int {.noSideEffect.} =
  let r = safeParseInt(s)
  if r.isOk(): r.get() else: default

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func parseFloatOrDefault(s: string; default: float): float {.noSideEffect.} =
  let r = safeParseFloat(s)
  if r.isOk(): r.get() else: default

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc loadResilienceConfig*(tomlPath: string = "axiom.toml"): ResilienceConfig {.raises: [], axiomEffect: IOEffect.} =
  ## Load resilience config from [resilience] section in axiom.toml.
  ## Falls back to defaults for missing keys.
  ## Environment variables override TOML values:
  ##   AXIOM_RESILIENCE_RETRY_MAX_ATTEMPTS, AXIOM_RESILIENCE_CIRCUIT_FAILURE_THRESHOLD, etc.
  result = defaultResilienceConfig()

  # Minimal inline TOML parser — flat key=value only, no arrays/nested tables.
  var cfg = initTable[string, Table[string, string]]()
  try:
    let content = readFile(tomlPath)
    var currentSection = ""
    for rawLine in content.splitLines():
      let line = rawLine.strip()
      if line.len == 0 or line[0] == '#': continue
      if line[0] == '[' and line[^1] == ']':
        currentSection = line[1 .. ^2]
        if currentSection notin cfg:
          cfg[currentSection] = initTable[string, string]()
        continue
      let eqIdx = line.find('=')
      if eqIdx < 0: continue
      let key = line[0 ..< eqIdx].strip()
      let valueRaw = line[eqIdx + 1 .. ^1].strip()
      # Skip arrays and complex values
      if valueRaw.len > 0 and valueRaw[0] == '[': continue
      if currentSection.len == 0: continue
      var section = cfg.mgetOrPut(currentSection, initTable[string, string]())
      section[key] = valueRaw
  except CatchableError:
    return  # TOML not found, use defaults

  let section = cfg.getOrDefault("resilience", initTable[string, string]())
  if section.len == 0: return

  # Helper: resolve env var override, then TOML value.
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
  proc envOr(key: string; tomlKey: string): string {.axiomEffect: IOEffect.} =
    let envKey = "AXIOM_RESILIENCE_" & key.toUpperAscii()
    let envVal = getEnv(envKey, "")
    if envVal.len > 0: return envVal
    section.getOrDefault(tomlKey, "")

  let retryMaxAttempts = envOr("retry_max_attempts", "retry_max_attempts")
  if retryMaxAttempts.len > 0:
    result.retryMaxAttempts = parseIntOrDefault(retryMaxAttempts, result.retryMaxAttempts)

  let retryBaseDelayMs = envOr("retry_base_delay_ms", "retry_base_delay_ms")
  if retryBaseDelayMs.len > 0:
    result.retryBaseDelayMs = parseIntOrDefault(retryBaseDelayMs, result.retryBaseDelayMs)

  let retryMaxDelayMs = envOr("retry_max_delay_ms", "retry_max_delay_ms")
  if retryMaxDelayMs.len > 0:
    result.retryMaxDelayMs = parseIntOrDefault(retryMaxDelayMs, result.retryMaxDelayMs)

  let retryJitterRatio = envOr("retry_jitter_ratio", "retry_jitter_ratio")
  if retryJitterRatio.len > 0:
    result.retryJitterRatio = parseFloatOrDefault(retryJitterRatio, result.retryJitterRatio)

  let circuitFailureThreshold = envOr("circuit_failure_threshold", "circuit_failure_threshold")
  if circuitFailureThreshold.len > 0:
    result.circuitFailureThreshold = parseIntOrDefault(circuitFailureThreshold, result.circuitFailureThreshold)

  let circuitResetAfterMs = envOr("circuit_reset_after_ms", "circuit_reset_after_ms")
  if circuitResetAfterMs.len > 0:
    result.circuitResetAfterMs = parseIntOrDefault(circuitResetAfterMs, result.circuitResetAfterMs)

  let dumpDir = envOr("dump_dir", "dump_dir")
  if dumpDir.len > 0:
    result.dumpDir = dumpDir

  let dumpMaxAgeHours = envOr("dump_max_age_hours", "dump_max_age_hours")
  if dumpMaxAgeHours.len > 0:
    result.dumpMaxAgeHours = parseIntOrDefault(dumpMaxAgeHours, result.dumpMaxAgeHours)

  let dumpMaxCount = envOr("dump_max_count", "dump_max_count")
  if dumpMaxCount.len > 0:
    result.dumpMaxCount = parseIntOrDefault(dumpMaxCount, result.dumpMaxCount)

  let rateLimitBackoffMultiplier = envOr("rate_limit_backoff_multiplier", "rate_limit_backoff_multiplier")
  if rateLimitBackoffMultiplier.len > 0:
    result.rateLimitBackoffMultiplier = parseIntOrDefault(rateLimitBackoffMultiplier, result.rateLimitBackoffMultiplier)

{.pop.}
