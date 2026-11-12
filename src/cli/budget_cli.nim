import core/trusted/layer_declaration
axiomLayer "presentation"
{.push raises: [CatchableError].}
# axiomIoBoundary

import std/[json, os, strutils, times, sequtils, tables]
import core/axiom_pragmas
import core/types/debt_types
import core/results
import infrastructure/logging_facade

const
  BudgetBudgetsPath = "data/debt_budgets.json"
  BudgetLedgerPath  = "data/debt_ledger.json"

type
  BudgetMetric* = object
    name*: string
    baseline*: int
    target*: int
    current*: int
    description*: string

  BudgetReport* = object
    outputJson*: string
    logLines*: seq[string]
    exitCode*: int

proc loadBudgetMetrics*(path: string): seq[BudgetMetric] {.raises: [CatchableError], axiomDecision.} =
  ## Load budget metrics from debt_budgets.json, resolving `current` from
  ## debt_ledger.json (the derived canonical snapshot per the pipeline contract).
  ## budgets.json defines only metric metadata (baseline/target/description).
  if not fileExists(path):
    return @[]
  try:
    let data = parseJson(readFile(path))
    if data.isNil or data.kind != JObject:
      return @[]
    let metricsNode = data{"metrics"}
    if metricsNode.isNil or metricsNode.kind != JObject:
      return @[]
    # Build metric→ledgerCurrent lookup from the ledger.
    var ledgerCurrentByMetric: Table[string, int]
    if fileExists(BudgetLedgerPath):
      let ledgerData = parseJson(readFile(BudgetLedgerPath))
      if ledgerData.hasKey("records") and ledgerData["records"].kind == JArray:
        for rec in ledgerData["records"]:
          let m = rec["metric"].getStr()
          ledgerCurrentByMetric[m] = rec["current"].getInt()
    for key, val in metricsNode.pairs:
      if val.kind != JObject:
        continue
      let baseline = val{"baseline"}.getInt(0)
      let target = val{"target"}.getInt(0)
      let current = ledgerCurrentByMetric.getOrDefault(key, 0)
      let description = val{"description"}.getStr("")
      result.add(BudgetMetric(
        name: key,
        baseline: baseline,
        target: target,
        current: current,
        description: description
      ))
  except CatchableError:
    return @[]

func budgetMetricToJson*(m: BudgetMetric): JsonNode {.raises: [].} =
  ## Convert a BudgetMetric to a JSON node.
  %*{
    "name": m.name,
    "baseline": m.baseline,
    "target": m.target,
    "current": m.current,
    "description": m.description
  }

proc renderBudgetStdoutLines*(report: BudgetReport): seq[string] =
  ## Render budget report as human-readable stdout lines.
  result = @["=== Axiom Budget Report ==="]
  if report.logLines.len > 0:
    for line in report.logLines:
      result.add(line)
  result.add("")

  let metrics = loadBudgetMetrics(BudgetBudgetsPath)
  if metrics.len == 0:
    result.add("No budget metrics found.")
    return

  result.add("Metric" & " ".repeat(24) & "Baseline" & " ".repeat(4) & "Target" & " ".repeat(4) & "Current" & " ".repeat(4) & "Status")
  result.add("-".repeat(70))

  for m in metrics:
    let status = if m.current <= m.target: "OK"
                 elif m.current <= m.baseline: "WARNING"
                 else: "OVER"
    result.add(m.name & " ".repeat(30 - m.name.len) & $m.baseline & " ".repeat(10 - ($m.baseline).len) & $m.target & " ".repeat(10 - ($m.target).len) & $m.current & " ".repeat(10 - ($m.current).len) & status)

  result.add("")
  let overCount = metrics.filterIt(it.current > it.target).len
  let warnCount = metrics.filterIt(it.current > it.baseline and it.current <= it.target).len
  result.add("Summary: " & $metrics.len & " metrics, " & $overCount & " over target, " & $warnCount & " over baseline")

proc runBudgetCli*(args: seq[string]): BudgetReport {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Budget CLI handler.
  ## Usage: ax budget [report|status]
  var logLines: seq[string]
  var exitCode = 0

  if args.len == 0:
    logLines.add("Usage: ax budget <report|status>")
    logLines.add("  report  - show full budget metrics report")
    logLines.add("  status  - show budget status summary")
    exitCode = 1
  else:
    let subcommand = args[0].toLowerAscii()
    case subcommand
    of "report":
      for line in renderBudgetStdoutLines(BudgetReport()):
        logLines.add(line)
    of "status":
      let metrics = loadBudgetMetrics(BudgetBudgetsPath)
      for m in metrics:
        let status = if m.current <= m.target: "OK"
                     elif m.current <= m.baseline: "WARNING"
                     else: "OVER"
        logLines.add(m.name & ": " & $m.current & "/" & $m.target & " (" & status & ")")
    else:
      logLines.add("Unknown budget subcommand: " & args[0])
      logLines.add("Available: report, status")
      exitCode = 1

  BudgetReport(
    outputJson: "",
    logLines: logLines,
    exitCode: exitCode
  )

{.pop.}