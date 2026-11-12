import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
{.push noSideEffect.}

import std/options
import core/axiom_pragmas
import core/types/vkd_types

## Display layer for Verified Kernel Density (VKD) — Kernel/Shell Scope Partitioning
##
## IsKernel(s) ⟺ s ∈ {.axiom.} ∧ IsPure(s)
##
## Deterministic compile-time predicate. No new pragmas required.
## Kernel = verification targets (axiom-annotated + pure).
## Shell = everything else (CLI, logging, infrastructure).
##
## This module is NOT the SSOT. The definition-level SSOT is
## `vkd_types.initKernelRatio` + `docs/spec/verification_density.md`.
## The percentage computed here (VKD = Verified / Total Kernel × 100) is a
## derived display value, computed via the SSOT ratio for single-source truth.

type
  ScopeKind* = enum
    ## Binary classification of a symbol's verification scope.
    skKernel,   ## {.axiom.} ∧ IsPure — formal verification target
    skShell     ## Non-verification target

  VerificationScope* = object
    ## Immutable result of kernel scope computation.
    kernelTotal*: int        ## Total kernel symbols (denominator)
    kernelVerified*: int     ## Verified kernel symbols (numerator)
    shellTotal*: int         ## Total shell symbols
    densityPct*: float       ## Display percentage = kernelVerified / kernelTotal × 100

  KernelSymbol* = object
    ## Individual kernel symbol with verification status.
    name*: string
    sourcePath*: string
    isVerified*: bool
    reason*: string          ## Verification status or failure reason

func classifyScope*(hasAxiom: bool; effectKind: AxiomEffectKind): ScopeKind {.inline.} =
  ## Deterministic compile-time predicate:
  ## IsKernel(s) ⟺ {.axiom.}(s) ∧ IsPure(s)
  if hasAxiom and effectKind == Pure:
    skKernel
  else:
    skShell

func computeDensity*(kernelVerified, kernelTotal: int): float {.inline.} =
  ## Display-layer VKD percentage derived from the SSOT ratio (vkd_types).
  ## Rate = verified / total; this module renders it as a percentage.
  ## Returns 0.0 when total is 0 (ratio is undefined).
  let ratio = initKernelRatio(kernelVerified, kernelTotal)
  if ratio.isSome: ratio.get.toFloat * 100.0
  else: 0.0

func densityStatus*(densityPct: float): string {.inline.} =
  ## Display-layer binary status derived from the VKD percentage:
  ## COMPLETE if 100%, PARTIAL otherwise.
  if densityPct >= 100.0 - 1e-9: "COMPLETE"
  else: "PARTIAL"

func buildVerificationScope*(
    kernelTotal: int,
    kernelVerified: int,
    shellTotal: int
): VerificationScope {.inline.} =
  ## Construct VerificationScope from pre-computed counts.
  ## The caller (CLI layer) is responsible for certificate scanning
  ## and status checking — this module remains effect-free.
  let density = computeDensity(kernelVerified, kernelTotal)
  VerificationScope(
    kernelTotal: kernelTotal,
    kernelVerified: kernelVerified,
    shellTotal: shellTotal,
    densityPct: density
  )

func formatDensityBar*(densityPct: float; width: int = 20): string =
  ## Display-layer Unicode block progress bar for terminal output.
  ## Renders the derived VKD percentage visually.
  ## Uses U+2588 (FULL BLOCK) for filled and U+2591 (LIGHT SHADE) for empty.
  let filled = int(densityPct / 100.0 * width.float + 0.5)
  let empty = width - filled
  result = "["
  for i in 0..<filled:
    result.add("\u2588")
  for i in 0..<empty:
    result.add("\u2591")
  result.add(']')

{.pop.} # noSideEffect
{.pop.} # raises: []
