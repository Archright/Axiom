import core/trusted/layer_declaration
axiomLayer "presentation"
{.push raises: [CatchableError].}
# axiomIoBoundary

type
  AxCommandCliResult* = object
    outputJson*: string
    logLines*: seq[string]
    exitCode*: int
    emitJson*: bool

  AxViewBinding* = object
    name*: string
    hexValue*: string

  AxViewEvidence* = object
    symbol*: string
    violatedSpec*: string
    bindings*: seq[AxViewBinding]

  AxTraceStep* = object
    depth*: int
    marker*: char
    label*: string
    delta*: string

  VerifyWorkflowCliResult* = object
    outputJson*: string
    logLines*: seq[string]
    exitCode*: int

  VerifyTopologyCliResult* = object
    outputJson*: string
    logLines*: seq[string]
    exitCode*: int

  AuditProofBinaryCliResult* = object
    outputJson*: string
    exitCode*: int

  CliActionKind* = enum
    cliInitializeOutputEncoding,
    cliDispatchCommand,
    cliRunAxiomEngine,
    cliPrintUsage,
    cliWriteStderrLine,
    cliQuit

  CliCommandKind* = enum
    cliCommandReport,
    cliCommandTopology,
    cliCommandScaffold,
    cliCommandGate,
    cliCommandLint,
    cliCommandCert,
    cliCommandShadow,
    cliCommandConfig,
    cliCommandVersion,
    cliCommandIo,
    cliCommandDag,
    cliCommandCache,
    cliCommandCheck,
    cliCommandShape,
    cliCommandGit,
    cliCommandCst,
    cliCommandScope,
    cliCommandRelease,
    cliCommandObservability,
    cliCommandCheckSpec,
    cliCommandBaseline,
    cliCommandInvariants,
    cliCommandVkd,
    cliCommandVerify,
    cliCommandStatus,
    cliCommandDebt,
    cliCommandBudget,
    cliCommandMerge,
    cliCommandAdmission,
    cliCommandLanding,
    cliCommandEvidence,
    cliCommandCapability,
 
  AxSubcommandKind* = enum
    axSubcommandProve,
    axSubcommandReport,
    axSubcommandHelp,
    axSubcommandTopology,
    axSubcommandScaffold,
    axSubcommandGate,
    axSubcommandLint,
    axSubcommandCert,
    axSubcommandShadow,
    axSubcommandConfig,
    axSubcommandVersion,
    axSubcommandIo,
    axSubcommandDag,
    axSubcommandCache,
    axSubcommandCheck,
    axSubcommandShape,
    axSubcommandGit,
    axSubcommandCst,
    axSubcommandScope,
    axSubcommandRelease,
    axSubcommandObservability,
    axSubcommandCheckSpec,
    axSubcommandBaseline,
    axSubcommandInvariants,
    axSubcommandVkd,
    axSubcommandVerify,
    axSubcommandStatus,
    axSubcommandDebt,
    axSubcommandBudget,
    axSubcommandMerge,
    axSubcommandAdmission,
    axSubcommandLanding,
    axSubcommandEvidence,
    axSubcommandCapability,
 
  CommandContext* = object
    axiomRoot*: string
    gitHash*: string
    buildTimestamp*: string
    subcommand*: string
    dryRun*: bool
    logPath*: string

  CliAction* = object
    kind*: CliActionKind
    commandKind*: CliCommandKind
    args*: seq[string]
    message*: string
    exitCode*: int
    commandContext*: CommandContext

  AxProofStatus* = enum
    axProofVerified,
    axProofCounterExampleFound,
    axProofTimedOut,
    axProofUnverifiable,
    axProofUnattempted,
    axProofVacuousContradiction,
    axProofBlocked,
    axProofUnknown
## CLI Surface ADT Types
## These enums define mutually exclusive flag regions for the parser.
## See src/cli/cli_surface_generated.nim for the generated parser procs.

## Flag Object Definitions
## Each object is processed by generateCliSurface at compile time to produce:
##   parseXxxFlags*(args: seq[string]): Result[T, string]
##   validateXxxFlags*(flags: T): Result[void, string]
##   xxxHelp*(): string

type
  # CLI Flag Identity — compile-time enum for type safety
  # If a flag is deleted from this enum, all references become compile errors
  AxProveFlag* = enum
    apLimit = "--limit"
    apLegacyUap = "--legacy-uap"
    apWorkers = "--workers"
    apSmtTimeout = "--smt-timeout"
    apUpdateLock = "--update-lock"
    apTarget = "--target"
    apProject = "--project"
    apPlan = "--plan"
    apProposals = "--proposals"

  AxProveFlags* = object
    ## ax prove — scan the subject source, prove frontier targets in waves
    limit*: int = 0                    ## --limit N — batch size cap
    legacyUap*: bool = false           ## --legacy-uap — use legacy UAP path
    workers*: int = 0                  ## --workers N — parallel worker count (0=env/default)
    smtTimeout*: int = 0               ## --smt-timeout N — SMT solver timeout cap in ms (0=default)
    updateLock*: bool = false          ## --update-lock — write data/universe_merkle.lock to disk (canonical runs only)
    target*: string = ""               ## --target <symbol> — verify specific symbol only
    project*: string = ""              ## --project <dir> — explicit subject root (fail-closed w/o AXIOM_STATE_DIR)
    plan*: string = ""                 ## --plan <path> — consume an ExecutionPlan JSON (fail-closed: parse error or tampered plan rejects)
    proposals*: string = ""            ## --proposals <path> — BYO-Agent propositions intake JSON (fail-closed: schema/reason exit 3)

  AxReportFlag* = enum
    arJson = "--json"

  AxReportFlags* = object
    ## ax report — Generate VKD and integrity reports
    json*: bool = false                ## --json

  AxVkdSyncFlag* = enum
    avsSync = "sync"

  AxVkdSyncFlags* = object
    ## ax vkd — composite VKD lifecycle commands
    vkdSync*: bool = false             ## sync — prove (limit 25, update lock) → safe orphan cleanup → baseline update
    sync*: bool = false                ## sync subcommand marker
{.pop.}
# E2E exercise note (2026-09-12): non-trust-surface, exercises full production landing path.
