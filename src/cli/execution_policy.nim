import core/trusted/layer_declaration
axiomLayer "presentation"
{.push raises: [].}
# axiomIoBoundary

## Execution Policy — Domain-layer SSOT for ax prove / ax report configuration.
##
## INVARIANT: This module MUST NOT import src/verification/ or src/cli/.
## It is the bridge between CLI flag parsing (Presentation) and engine execution
## (Infrastructure). All engine dispatch decisions flow through this object.

type
  ExecutionPolicy* = object
    ## Immutable policy for a single `ax prove` invocation.
    limit*: int
    budgetGas*: int

  ReportPolicy* = object
    ## Immutable policy for a single `ax report` invocation.
    stateFile*: string
    jsonOutput*: bool
    summary*: bool
    verbose*: bool
    certDir*: string
    calculateAsi*: bool
    purity*: bool
    autoRepairFingerprints*: bool

func defaultProvePolicy*(): ExecutionPolicy {.raises: [].} =
  ExecutionPolicy(
    limit: 0,
    budgetGas: 0
  )

func defaultReportPolicy*(): ReportPolicy {.raises: [].} =
  ReportPolicy(
    stateFile: "",
    jsonOutput: false,
    summary: false,
    verbose: false,
    certDir: "",
    calculateAsi: false,
    purity: false,
    autoRepairFingerprints: false
  )
{.pop.}

