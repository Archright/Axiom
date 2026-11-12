import core/trusted/layer_declaration
axiomLayer "presentation"
{.push raises: [CatchableError].}
import ../core/trusted/axiom_pragmas
import cli/action_output_cli
import cli/action_plan_cli
import cli/action_invariants_sync
import cli/axiom_cache
import cli/axiom_engine
import cli/baseline_cli
import cli/budget_cli
import cli/capability_cli
import cli/cert_cli
import cli/check_cli
import cli/check_spec_cli
import cli/cli_types
import cli/cli_outcome
import cli/commands/topology_cli
import cli/commands/observability
import cli/config_cli
import cli/cst_cli
import cli/dag_cli
import cli/evidence_cli
import cli/gate_cli
import cli/git_cli
import cli/io_cli
import cli/lint_cli
import cli/release_cli
import cli/report_cli
import cli/axiom_status
import cli/scaffold_cli
import cli/scope_cli
import cli/shadow_cli
import cli/shape_cli
import cli/version_cli
import cli/vkd_sync_cli
import cli/verify_cli
import cli/debt_cli
import cli/merge_cli
import cli/admission_cli
import cli/landing_cli
import core/results

import std/winlean
import infrastructure/logging_facade
when defined(windows):
  const cliUtf8CodePage = 65001'u32

  func setConsoleOutputCP(codePage: cuint): WINBOOL {.
    axiom: ["(assert (and (>= depth 0) ast_parse_failed_isolated))", "depth >= 0 ∧ ast_parse_failed_isolated"],
    stdcall, dynlib: "kernel32", importc: "SetConsoleOutputCP".}

  func setConsoleCP(codePage: cuint): WINBOOL {.
    axiom: ["(assert (and (>= depth 0) ast_parse_failed_isolated))", "depth >= 0 ∧ ast_parse_failed_isolated"],
    stdcall, dynlib: "kernel32", importc: "SetConsoleCP".}

let initializeCliOutputEncoding = proc () =
  when defined(windows):
    discard setConsoleOutputCP(cuint(cliUtf8CodePage))
    discard setConsoleCP(cuint(cliUtf8CodePage))
let cliOutputEncodingInitialized {.used.} = block:
  initializeCliOutputEncoding()
  true


## interpret Cli Actions variable.
let interpretCliActions* = proc (actions: seq[CliAction]) {.raises: [CatchableError, Exception, IOEffect], warning[BareExcept]: off, axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  for action in actions:
    case action.kind
    of cliInitializeOutputEncoding:
      initializeCliOutputEncoding()
    of cliDispatchCommand:
      case action.commandKind
      of cliCommandReport:
        let reportRes = runReportCli(action.args)
        if reportRes.isErr():
          logError("action_interpreter_cli", "[ERROR] " & reportRes.error)
          exitWith(INVALID_INPUT)
        let output = reportRes.get()
        for line in renderReportStdoutLines(output):
          stdout.writeLine(line)
        if output.exitCode != 0:
          quit(output.exitCode)
      of cliCommandTopology:
        let exitCode = topology_cli.main(action.args)
        if exitCode != 0:
          quit(exitCode)
      of cliCommandScaffold:
        let exitCode = runScaffoldCli(action.args)
        if exitCode != 0:
          quit(exitCode)
      of cliCommandGate:
        let exitCode = runGateCli(action.args)
        if exitCode != 0:
          quit(exitCode)
      of cliCommandLint:
        let exitCode = runLintCli(action.args)
        if exitCode != 0:
          quit(exitCode)
      of cliCommandCert:
        let exitCode = runCertCli(action.args)
        if exitCode != 0:
          quit(exitCode)
      of cliCommandShadow:
        let exitCode = runShadowCli(action.args)
        if exitCode != 0:
          quit(exitCode)
      of cliCommandConfig:
        let exitCode = runConfigCli(action.args)
        if exitCode != 0:
          quit(exitCode)
      of cliCommandVersion:
        let exitCode = runVersionCli(action.args)
        if exitCode != 0:
          quit(exitCode)
      of cliCommandIo:
        let exitCode = runIoCli(action.args)
        if exitCode != 0:
          quit(exitCode)
      of cliCommandDag:
        let exitCode = runDagCli(action.args)
        if exitCode != 0:
          quit(exitCode)
      of cliCommandCache:
        runCacheCli(action.args)
      of cliCommandCheck:
        check_cli.run(action.args)
      of cliCommandShape:
        shape_cli.run(action.args)
      of cliCommandGit:
        let exitCode = git_cli.runGitCli(action.args)
        if exitCode != 0:
          quit(exitCode)
      of cliCommandCst:
        let exitCode = runCstCli(action.args)
        if exitCode != 0:
          quit(exitCode)
      of cliCommandScope:
        let exitCode = runScopeCli(action.args)
        if exitCode != 0:
          quit(exitCode)
      of cliCommandRelease:
        let exitCode = runReleaseCommand(action.args)
        if exitCode != 0:
          quit(exitCode)
      of cliCommandObservability:
        let exitCode = runObservabilityCmd(action.args)
        if exitCode != 0:
          quit(exitCode)
      of cliCommandCheckSpec:
        check_spec_cli.runCheckSpec(action.args)
      of cliCommandBaseline:
        let exitCode = runBaselineCli(action.args)
        if exitCode != 0:
          quit(exitCode)
      of cliCommandInvariants:
        let exitCode = runInvariantsCli(action.args)
        if exitCode != 0:
          quit(exitCode)
      of cliCommandVkd:
        let exitCode = runVkdCli(action.args)
        if exitCode != 0:
          quit(exitCode)
      of cliCommandVerify:
        let exitCode = runVerifyCli(action.args)
        if exitCode != 0:
          quit(exitCode)
      of cliCommandStatus:
        let exitCode = runStatusCli(action.args)
        if exitCode != 0:
          quit(exitCode)
      of cliCommandBudget:
        let budgetRes = runBudgetCli(action.args)
        for line in budgetRes.logLines:
          logInfo("budget_cli", line)
        if budgetRes.exitCode != 0:
          quit(budgetRes.exitCode)
      of cliCommandDebt:
        let exitCode = runDebtCli(action.args)
        if exitCode != 0:
          quit(exitCode)
      of cliCommandMerge:
        let exitCode = mergeCli(action.args)
        if exitCode != 0:
          quit(exitCode)
      of cliCommandAdmission:
        let exitCode = runAdmissionCli(action.args)
        if exitCode != 0:
          quit(exitCode)
      of cliCommandLanding:
        let exitCode = runLandingCli(action.args)
        if exitCode != 0:
          quit(exitCode)
      of cliCommandEvidence:
        let exitCode = runEvidenceCli(action.args)
        if exitCode != 0:
          quit(exitCode)
      of cliCommandCapability:
        let exitCode = runCapabilityCli(action.args)
        if exitCode != 0:
          quit(exitCode)
    of cliRunAxiomEngine:
      let engineRes = try:
        runAxiomEngineCli(action.args)
      except Exception as e:
        logError("action_interpreter_cli", "[ERROR] " & e.msg)
        let st = e.getStackTrace()
        if st.len > 0:
          logError("action_interpreter_cli", "[STACK] " & st)
        exitWith(INTERNAL_ERROR)
      if engineRes.isErr():
        logError("action_interpreter_cli", "[ERROR] " & engineRes.error.msg)
        exitWithCliError(engineRes.error)
      let report = engineRes.get()
      emitAxShortcutResult(Result[AxCommandCliResult, string](
        ok: true,
        value: AxCommandCliResult(
          outputJson: report.outputJson,
          logLines: report.logLines,
          exitCode: report.exitCode,
          emitJson: report.emitJson
        )
      ), action.args)
    of cliPrintUsage:
      for line in axUsageLines():
        logInfo("action_interpreter_cli", line)
    of cliWriteStderrLine:
      logInfo("action_interpreter_cli", action.message)
    of cliQuit:
      quit(action.exitCode)
  quit(0)
{.pop.}

