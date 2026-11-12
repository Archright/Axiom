import core/trusted/layer_declaration
axiomLayer "presentation"
{.push raises: [CatchableError].}
# axiomIoBoundary

import std/options
import std/sets

import cli/cli_types
import cli/cli_outcome
## CommandHelpEntry
## SSOT for all CLI command help text. Every ax command documents itself here.
type
  CommandHelpEntry* = object
    name*: string
    usage*: string
    description*: string

# @axiom-hint: lean="depth >= 0" smt="(assert (>= depth 0))"
# @axiom-hint: lean="ast_parse_failed_isolated" smt="(assert ast_parse_failed_isolated)"
func axCommandHelpEntries*(): seq[CommandHelpEntry] =
  @[
    CommandHelpEntry(
      name: "ax prove",
      usage: "[--limit N] [--target <sym>] [--project <dir>] [--plan <path>] [--workers N] [--smt-timeout N] [--update-lock] [--legacy-uap]",
      description: "Scan the subject source (repo kernel registry, or an external subject with --project + AXIOM_STATE_DIR), prove frontier targets in dependency waves (Z3 BMC + Lean kernel check + counterexample replay; no source is modified)."
    ),
    CommandHelpEntry(
      name: "ax report",
      usage: "[--json] | --upstream [--state-file <path>] [--dry-run] [--json]",
      description: "Generate verification report, ASI metrics, and certificate status. --upstream files upstream GitHub issues for reportable bug findings (trusted executor; GitHub accessed only through the native gh client; --dry-run runs the full preflight, fingerprint and duplicate check without any external write)."
    ),
    CommandHelpEntry(
      name: "ax seed-registry",
      usage: "[--layer N+]",
      description: "Compiler-validated algebraic property seeding for PBT infrastructure."
    ),
    CommandHelpEntry(
      name: "ax topology",
      usage: "<check|audit|explain> [args...]",
      description: "Validate topology lock compliance, audit policy drift, or explain module placement."
    ),
    CommandHelpEntry(
      name: "ax scaffold",
      usage: "<feature_name> [--force]",
      description: "Generate test stubs from a .feature file into tests/gateway/."
    ),
    CommandHelpEntry(
      name: "ax gate",
      usage: "[list|status|run] [gate-id]",
      description: "Run gate checks or manage gate state (list, status, run)."
    ),
    CommandHelpEntry(
      name: "ax lint",
      usage: "[files...]",
      description: "Run canonical hub linting on source files."
    ),
    CommandHelpEntry(
      name: "ax cert",
      usage: "[show|verify|export]",
      description: "Generate or inspect proof certificates from the reasoning ledger."
    ),
    CommandHelpEntry(
      name: "ax shadow",
      usage: "[run|compare] [args...]",
      description: "Shadow execution mode — run commands without side effects and compare output."
    ),
    CommandHelpEntry(
      name: "ax config",
      usage: "[show|validate]",
      description: "Show or validate project configuration from axiom.toml."
    ),
    CommandHelpEntry(
      name: "ax version",
      usage: "",
      description: "Print version, Nim toolchain, and environment info."
    ),
    CommandHelpEntry(
      name: "ax io",
      usage: "[list|check] [args...]",
      description: "I/O boundary operations — list axiomIoBoundary procs or check compliance."
    ),
    CommandHelpEntry(
      name: "ax dag",
      usage: "[show|run|validate] [args...]",
      description: "Task DAG visualization, execution, and validation."
    ),
    CommandHelpEntry(
      name: "ax cache",
      usage: "[--status] [--clear [--force] [--gate <id>]] [--gc] [--shadow-status]",
      description: "Cache management — show status, clear, garbage collect, or inspect shadow workers."
    ),
    CommandHelpEntry(
      name: "ax help",
      usage: "",
      description: "Show this help message and exit."
    ),
    CommandHelpEntry(
      name: "ax release",
      usage: "[--dry-run]",
      description: "Derive next semver version from conventional commits and create a tagged release."
    ),
    CommandHelpEntry(
      name: "ax observability",
      usage: "",
      description: "Read pipeline state ledger and display observability dashboard."
    ),
    CommandHelpEntry(
      name: "ax check-spec",
      usage: "[--fix]",
      description: "Verify bidirectional mapping between AGENTS.md @spec tags and code {.gate:} pragmas."
    ),
    CommandHelpEntry(
      name: "ax baseline",
      usage: "<update|check>",
      description: "Rebuild or verify the atomic baseline SSOT (data/baseline.json) from the stable vault."
    ),
    CommandHelpEntry(
      name: "ax invariants",
      usage: "<sync>",
      description: "Sync expected invariant hash from architecture_invariants.nim (cold-start bootstrap on first run)."
    ),
    CommandHelpEntry(
      name: "ax vkd",
      usage: "<sync>",
      description: "Atomic VKD lifecycle — prove (limit 25, update lock) → safe orphan cleanup → baseline update."
    ),
    CommandHelpEntry(
      name: "ax scope",
      usage: "[lock|hash]",
      description: "Compare kernel scope (default), regenerate verification_scope.lock from the compiled registry (lock), or print a deterministic scope integrity hash (hash)."
    ),
    CommandHelpEntry(
      name: "ax verify",
      usage: "[<claims-dir>]",
      description: "Verify/replay stored Claims/Attestations/Certificates — append-store claims, cert integrity, and replay engine."
    ),
    CommandHelpEntry(
      name: "ax status",
      usage: "[--json] [--history] [--gate <id>]",
      description: "Show Product State (canonical claim/artifact summary) and gate dashboard status."
    ),
    CommandHelpEntry(
      name: "ax debt",
      usage: "<sync|check|budget|ledger> [args...]",
      description: "Manage architecture debt registry — sync, check, view budgets, or inspect the debt ledger."
    ),
    CommandHelpEntry(
      name: "ax merge",
      usage: "<PR-number> [--dry-run] [--apply] [--json]",
      description: "Merge-admission controller: evaluate a PR's CI evidence and execute the Landing App CAS landing with --apply (Phase B+C; the legacy native-merge act is superseded)."
    ),
    CommandHelpEntry(
      name: "ax landing",
      usage: "--cert <path> | --pr <N> [--main-sha <sha>] [--binding <path>] [--repo owner/name] [--dry-run]",
      description: "Native MERGE thin actuator — verify certificate(B,H) → A3 preflight (main tip == B, observation) → A2 ruleset check (admission-check + strict + integration_id, fail-closed) → PUT /pulls/{n}/merge (merge_method=merge, sha=H) → post-merge continuity observation (parents(M)==[B,H], tree(M)==certTree). No self CAS, no local merge-tree; GitHub ruleset is the merge-time enforcer."
    ),
    CommandHelpEntry(
      name: "ax capability",
      usage: "[--json]",
      description: "Machine-readable capability disclosure (JSON) — committed catalog specIds with EQUIPPED/NOT_EQUIPPED status projected from the engine adapter table. Pure catalog+engine query: no subject, no AXIOM_STATE_DIR."
    ),
  ]

# @axiom-hint: lean="depth >= 0" smt="(assert (>= depth 0))"
func axUsageMessage(): string =
  result = "usage:"
  for entry in axCommandHelpEntries():
    result.add("\n  " & entry.name)
    if entry.usage.len > 0:
      result.add(" " & entry.usage)

# @axiom-hint: lean="token.length ≥ 0" smt="(assert (and (>= (str.len token) 0)))"
func parseAxSubcommandKind(token: string): Option[AxSubcommandKind] =
  case token
  of "prove":
    some(axSubcommandProve)
  of "report":
    some(axSubcommandReport)
  of "help":
    some(axSubcommandHelp)
  of "topology":
    some(axSubcommandTopology)
  of "scaffold":
    some(axSubcommandScaffold)
  of "gate":
    some(axSubcommandGate)
  of "lint":
    some(axSubcommandLint)
  of "cert":
    some(axSubcommandCert)
  of "shadow":
    some(axSubcommandShadow)
  of "config":
    some(axSubcommandConfig)
  of "version":
    some(axSubcommandVersion)
  of "io":
    some(axSubcommandIo)
  of "dag":
    some(axSubcommandDag)
  of "cache":
    some(axSubcommandCache)
  of "check":
    some(axSubcommandCheck)
  of "shape":
    some(axSubcommandShape)
  of "git":
    some(axSubcommandGit)
  of "cst":
    some(axSubcommandCst)
  of "scope":
    some(axSubcommandScope)
  of "release":
    some(axSubcommandRelease)
  of "observability":
    some(axSubcommandObservability)
  of "check-spec":
    some(axSubcommandCheckSpec)
  of "baseline":
    some(axSubcommandBaseline)
  of "invariants":
    some(axSubcommandInvariants)
  of "vkd":
    some(axSubcommandVkd)
  of "verify":
    some(axSubcommandVerify)
  of "status":
    some(axSubcommandStatus)
  of "budget":
    some(axSubcommandBudget)
  of "merge":
    some(axSubcommandMerge)
  of "admission":
    some(axSubcommandAdmission)
  of "landing":
    some(axSubcommandLanding)
  of "evidence":
    some(axSubcommandEvidence)
  of "debt":
    some(axSubcommandDebt)
  of "capability":
    some(axSubcommandCapability)
  else:
    none(AxSubcommandKind)

# @axiom-hint: lean="args.size ≥ 0 ∧ (∀ (argsIdx : Fin args.size), (args.get argsIdx).length ≥ 0)" smt="(assert (and (>= (seq.len args) 0) (forall ((argsIdx Int)) (=> (and (>= argsIdx 0) (< argsIdx (seq.len args))) (>= (str.len (seq.nth args argsIdx)) 0)))))"
func dispatchCommandAction(commandKind: CliCommandKind; args: seq[string]): CliAction =
  CliAction(kind: cliDispatchCommand, commandKind: commandKind, args: args)

## Plan Ax Actions.
# @axiom-hint: lean="args.size ≥ 0 ∧ ∀ (i : Fin args.size), (args.get i).length ≥ 0" smt="(assert (and (>= (seq.len args) 0) (forall ((i Int)) (=> (and (>= i 0) (< i (seq.len args))) (>= (str.len (seq.nth args i)) 0)))))"
func stripGlobalFlags*(args: seq[string]): (seq[string], HashSet[string]) =
  result = (@[], initHashSet[string]())
  for arg in args:
    if arg == "--cached":
      result[1].incl("cached")
    else:
      result[0].add(arg)

## hasHelpFlag — detect --help / -h in a seq of args.
## Used to short-circuit flag parsing for subcommands that receive
## unknown flags (e.g. --help) and instead emit usage + exit 0.
func hasHelpFlag*(args: seq[string]): bool =
  for arg in args:
    if arg == "--help" or arg == "-h":
      return true
  false

func planAxActions*(args: seq[string]): seq[CliAction] =
  if args.len == 0:
    result.add(CliAction(kind: cliWriteStderrLine, message: axUsageMessage()))
    result.add(CliAction(kind: cliQuit, exitCode: CliOutcome.INVALID_INPUT.exitCode()))
    return
  let parsedSubcommand = parseAxSubcommandKind(args[0])
  if parsedSubcommand.isNone():
    if args[0] == "heal":
      result.add(CliAction(kind: cliWriteStderrLine, message: "'ax heal' is removed. Use 'ax prove --heal' instead."))
    else:
      result.add(CliAction(kind: cliWriteStderrLine, message: "unknown ax subcommand: " & args[0]))
    result.add(CliAction(kind: cliPrintUsage))
    result.add(CliAction(kind: cliQuit, exitCode: CliOutcome.INVALID_INPUT.exitCode()))
    return
  let subArgs = if args.len > 1: args[1 .. ^1] else: @[]
  case parsedSubcommand.get()
  of axSubcommandProve:
    if hasHelpFlag(subArgs):
      result.add(CliAction(kind: cliPrintUsage))
      result.add(CliAction(kind: cliQuit, exitCode: 0))
      return
    result.add(CliAction(kind: cliRunAxiomEngine, args: subArgs))
    return
  of axSubcommandReport:
    if hasHelpFlag(subArgs):
      result.add(CliAction(kind: cliPrintUsage))
      result.add(CliAction(kind: cliQuit, exitCode: 0))
      return
    result.add(dispatchCommandAction(cliCommandReport, subArgs))
    return
  of axSubcommandHelp:
    result.add(CliAction(kind: cliPrintUsage))
    result.add(CliAction(kind: cliQuit, exitCode: 0))
    return
  of axSubcommandTopology:
    result.add(dispatchCommandAction(cliCommandTopology, subArgs))
    return
  of axSubcommandScaffold:
    result.add(dispatchCommandAction(cliCommandScaffold, subArgs))
    return
  of axSubcommandGate:
    result.add(dispatchCommandAction(cliCommandGate, subArgs))
    return
  of axSubcommandLint:
    result.add(dispatchCommandAction(cliCommandLint, subArgs))
    return
  of axSubcommandCert:
    result.add(dispatchCommandAction(cliCommandCert, subArgs))
    return
  of axSubcommandShadow:
    result.add(dispatchCommandAction(cliCommandShadow, subArgs))
    return
  of axSubcommandConfig:
    result.add(dispatchCommandAction(cliCommandConfig, subArgs))
    return
  of axSubcommandVersion:
    result.add(dispatchCommandAction(cliCommandVersion, subArgs))
    return
  of axSubcommandIo:
    result.add(dispatchCommandAction(cliCommandIo, subArgs))
    return
  of axSubcommandDag:
    result.add(dispatchCommandAction(cliCommandDag, subArgs))
    return
  of axSubcommandCache:
    result.add(dispatchCommandAction(cliCommandCache, subArgs))
    return
  of axSubcommandCheck:
    result.add(dispatchCommandAction(cliCommandCheck, subArgs))
    return
  of axSubcommandShape:
    result.add(dispatchCommandAction(cliCommandShape, subArgs))
    return
  of axSubcommandGit:
    result.add(dispatchCommandAction(cliCommandGit, subArgs))
    return
  of axSubcommandCst:
    result.add(dispatchCommandAction(cliCommandCst, subArgs))
    return
  of axSubcommandScope:
    result.add(dispatchCommandAction(cliCommandScope, subArgs))
    return
  of axSubcommandRelease:
    result.add(dispatchCommandAction(cliCommandRelease, subArgs))
    return
  of axSubcommandObservability:
    result.add(dispatchCommandAction(cliCommandObservability, subArgs))
    return
  of axSubcommandCheckSpec:
    result.add(dispatchCommandAction(cliCommandCheckSpec, subArgs))
    return
  of axSubcommandBaseline:
    result.add(dispatchCommandAction(cliCommandBaseline, subArgs))
    return
  of axSubcommandInvariants:
    result.add(dispatchCommandAction(cliCommandInvariants, subArgs))
    return
  of axSubcommandVkd:
    result.add(dispatchCommandAction(cliCommandVkd, subArgs))
    return
  of axSubcommandVerify:
    result.add(dispatchCommandAction(cliCommandVerify, subArgs))
    return
  of axSubcommandStatus:
    result.add(dispatchCommandAction(cliCommandStatus, subArgs))
    return
  of axSubcommandDebt:
    result.add(dispatchCommandAction(cliCommandDebt, subArgs))
    return
  of axSubcommandBudget:
    result.add(dispatchCommandAction(cliCommandBudget, subArgs))
    return
  of axSubcommandMerge:
    result.add(dispatchCommandAction(cliCommandMerge, subArgs))
    return
  of axSubcommandAdmission:
    result.add(dispatchCommandAction(cliCommandAdmission, subArgs))
    return
  of axSubcommandLanding:
    result.add(dispatchCommandAction(cliCommandLanding, subArgs))
    return
  of axSubcommandEvidence:
    result.add(dispatchCommandAction(cliCommandEvidence, subArgs))
    return
  of axSubcommandCapability:
    result.add(dispatchCommandAction(cliCommandCapability, subArgs))
    return

  ## Usage Lines.
# @axiom-hint: lean="depth >= 0" smt="(assert (>= depth 0))"
func axUsageLines*(): seq[string] =
  result = @["usage:"]
  for entry in axCommandHelpEntries():
    let line = "  " & entry.name &
      (if entry.usage.len > 0: " " & entry.usage else: "") &
      "  " & entry.description
    result.add(line)

## Main Loop.
# `ax` is the sole CLI entry point. All commands route through planAxActions.
func mainLoop*(args: seq[string]; executableName: string): seq[CliAction] =
  result.add(CliAction(kind: cliInitializeOutputEncoding))
  if args.len == 0:
    result.add(CliAction(kind: cliPrintUsage))
    result.add(CliAction(kind: cliQuit, exitCode: CliOutcome.INVALID_INPUT.exitCode()))
    return
  # All entry points (ax, axiom, main) route to planAxActions.
  # axiom/main are backward-compatible redirects to ax.
  result.add(planAxActions(args))
{.pop.}

