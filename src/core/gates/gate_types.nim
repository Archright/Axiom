# axiom:theater-fix(DEBT#380,#381)
## Gate Status Types — structural prevention of gate success misrepresentation.
##
## Provides GateStatusKind enum and GateResult type that make pass/fail/warn/skip
## states explicit and exhaustively checkable, preventing ok:true returns for
## non-pass conditions (always-pass theater signature §0.9).

import core/trusted/layer_declaration
domainLayer()
{.push raises: [].}

type
  ## Exhaustive gate outcome states — pure enum for compile-time exhaustiveness.
  GateStatusKind* {.pure.} = enum
    VerifiedPass         ## 100% verification success (gate passes cleanly)
    VerificationFailed   ## Verification violation detected (Fail-Closed)
    WarningViolated      ## Warning-level violations (explicit acknowledgment needed)
    SkippedInapplicable  ## No triggers evaluated (NOT a success)
    ExplicitlyDisabled   ## Configured as disabled in gate settings

  ## Normalized gate result carrying explicit status kind + reason.
  GateResult* = object
    kind*: GateStatusKind
    reason*: string

# ---------------------------------------------------------------------------
# Success misrepresentation prevention helpers
# ---------------------------------------------------------------------------

## Returns true ONLY for VerifiedPass — prevents ok:true misrepresentation
## on warning/skipped/disabled states. This is the structural gate against
## theater signature #1 (always-pass): return true without evaluating condition.
func isStrictSuccess*(res: GateResult): bool =
  return res.kind == GateStatusKind.VerifiedPass

## Returns true for states requiring audit trail logging.
## WarningViolated → violations exist but are non-blocking (audit required)
## SkippedInapplicable → gate did not evaluate (audit required for compliance)
func requiresAuditLog*(res: GateResult): bool =
  return res.kind in {GateStatusKind.WarningViolated, GateStatusKind.SkippedInapplicable}

## Returns true for definitive failure states.
## Only VerificationFailed — excludes warnings (which are advisory).
func isFailure*(res: GateResult): bool =
  return res.kind == GateStatusKind.VerificationFailed

## Convert GateStatusKind to exit code for CLI subprocess boundary.
## VerifiedPass → 0 (pass), everything else → 1 (non-pass).
## This ensures the orchestrator never sees "success" for warn/skip states.
func exitCode*(kind: GateStatusKind): int =
  case kind
  of GateStatusKind.VerifiedPass:
    0
  of GateStatusKind.VerificationFailed,
     GateStatusKind.WarningViolated,
     GateStatusKind.SkippedInapplicable,
     GateStatusKind.ExplicitlyDisabled:
    1

## Construct a verified-pass result.
func ok*(kind: GateStatusKind = GateStatusKind.VerifiedPass; reason: string = ""): GateResult =
  GateResult(kind: kind, reason: reason)

## Construct a failure result.
func fail*(reason: string): GateResult =
  GateResult(kind: GateStatusKind.VerificationFailed, reason: reason)

## Construct a warning result (non-blocking but logged).
func warn*(reason: string): GateResult =
  GateResult(kind: GateStatusKind.WarningViolated, reason: reason)

## Construct a skipped-inapplicable result.
func skip*(reason: string): GateResult =
  GateResult(kind: GateStatusKind.SkippedInapplicable, reason: reason)

## String representation for logging.
func `$`*(kind: GateStatusKind): string =
  case kind
  of GateStatusKind.VerifiedPass: "VerifiedPass"
  of GateStatusKind.VerificationFailed: "VerificationFailed"
  of GateStatusKind.WarningViolated: "WarningViolated"
  of GateStatusKind.SkippedInapplicable: "SkippedInapplicable"
  of GateStatusKind.ExplicitlyDisabled: "ExplicitlyDisabled"

func `$`*(res: GateResult): string =
  "[" & $res.kind & "] " & res.reason

{.pop.}
