# axiom:theater-prevention(DEBT# Phase 4-C: GateStatusKind metrics)
## CI metrics tool: parses gate execution JSONL logs and counts results by
## status kind. Maps legacy JSONL result strings to GateStatusKind-equivalent
## categories so downstream dashboards can consume a unified view.
##
## Input:  .axiom/gate_history.jsonl  (or any .jsonl file with gate records)
## Output: summary table + exit code (0 = all passed, 1 = non-pass detected)
##
## Usage:
##   nim c -r tools/gate_status_metrics.nim                    # default path
##   nim c -r tools/gate_status_metrics.nim -- .axiom/foo.jsonl

import std/[json, os, strutils, tables, strformat]

# ─── GateStatusKind — mirrors core/gates/gate_types.nim ─────────────────────
type
  GateStatusKind* = enum
    VerifiedPass            ## 100% verification success
    VerificationFailed      ## Violation detected (Fail-Closed)
    WarningViolated         ## Warning-level violations
    SkippedInapplicable     ## No triggers evaluated
    ExplicitlyDisabled      ## Configured as disabled

  GateStatusCounts* = Table[GateStatusKind, int]

# ─── JSONL Result → GateStatusKind mapping ─────────────────────────────────
## The persisted gate_history.jsonl uses flat strings; this maps them back
## to the rich enum so callers can reason in terms of GateStatusKind.
proc jsonlResultToKind(s: string): GateStatusKind =
  case s.strip().toLowerAscii()
  of "pass", "verifiedpass":   VerifiedPass
  of "fail", "verificationfailed": VerificationFailed
  of "warn", "warningviolated": WarningViolated
  of "skip", "skippedinapplicable": SkippedInapplicable
  of "disabled", "explicitlydisabled": ExplicitlyDisabled
  else:
    ## Unknown result — treat as VerificationFailed to avoid silent passes.
    VerificationFailed

# ─── Core parsing ──────────────────────────────────────────────────────────

proc collectGateMetrics(logPath: string): GateStatusCounts =
  ## Parse a JSONL gate-history file and tally each record's status.
  result = initTable[GateStatusKind, int]()
  # Seed all keys so getOrDefault always returns 0.
  for k in GateStatusKind: result[k] = 0

  if not fileExists(logPath):
    echo "[WARN] Log file not found: " & logPath
    return

  var totalLines = 0
  var parseErrors = 0
  for line in lines(logPath):
    let trimmed = line.strip()
    if trimmed.len == 0 or trimmed[0] != '{': continue
    inc totalLines

    try:
      let node = parseJson(trimmed)
      if node.hasKey("result"):
        let kind = jsonlResultToKind(node["result"].getStr())
        result[kind] = result.getOrDefault(kind, 0) + 1
      else:
        inc parseErrors
    except CatchableError:
      inc parseErrors

  if parseErrors > 0:
    echo "[WARN] Failed to parse " & $parseErrors & "/" & $totalLines & " lines"

proc generateMetricsReport(counts: GateStatusCounts) =
  ## Print a human-readable metrics table and decide CI pass/fail.
  echo ""
  echo "═══════════════════════════════════════"
  echo "  Gate Status Metrics Report"
  echo "═══════════════════════════════════════"
  echo ""
  echo "  VerifiedPass:          ", counts.getOrDefault(VerifiedPass, 0)
  echo "  VerificationFailed:    ", counts.getOrDefault(VerificationFailed, 0)
  echo "  WarningViolated:       ", counts.getOrDefault(WarningViolated, 0)
  echo "  SkippedInapplicable:   ", counts.getOrDefault(SkippedInapplicable, 0)
  echo "  ExplicitlyDisabled:    ", counts.getOrDefault(ExplicitlyDisabled, 0)

  var total = 0
  for v in counts.values(): total += v
  echo ""
  echo "  Total gates:           ", total

  if total == 0:
    echo ""
    echo "  [INFO] No gate records found."
    return

  let passRate = 100.0 * float(counts.getOrDefault(VerifiedPass, 0)) / float(total)
  echo "  Pass rate:             ", fmt"{passRate:0.1f}%"
  echo ""

  # Theater prevention: fail CI if non-strict-success gates exist.
  # WarningViolated and SkippedInapplicable are NOT passes — they require audit.
  let nonPass = counts.getOrDefault(WarningViolated, 0) +
                counts.getOrDefault(SkippedInapplicable, 0) +
                counts.getOrDefault(VerificationFailed, 0) +
                counts.getOrDefault(ExplicitlyDisabled, 0)

  if nonPass > 0:
    echo "  ⚠  Non-pass gates detected: ", nonPass
    echo "     Review required — theater prevention (§0.9) active."
    echo ""
    echo "═══════════════════════════════════════"
    quit(1)
  else:
    echo "  ✓ All gates strictly verified."
    echo ""
    echo "═══════════════════════════════════════"

# ─── Main ──────────────────────────────────────────────────────────────────

when isMainModule:
  let logPath = if paramCount() > 0: paramStr(1)
                else: ".axiom/gate_history.jsonl"
  let counts = collectGateMetrics(logPath)
  generateMetricsReport(counts)
