## Unit tests for cli/axiom_engine — pure data algebra and constructors.
## Tests business logic only (AGENTS.md §0.7). No I/O-dependent pipeline tests.
##
## Coverage map:
##   resolveVaultDir          — pure vault resolution priority logic
##   buildVsrLedgerJson       — pure LedgerEvent → JSON serialization
##   buildProofTask           — pure AxProveFlags → ProofTask conversion
##   initAxiomEngine          — pure constructor with adaptive budget logic
##   newGateReporter + report — pure gate event accumulation
##   persistVsrLedger         — IO: append-only ledger write (temp dir)
##   LedgerEvent fields       — pure type construction and access
##
## NOT TESTED (requires full pipeline infrastructure — tested via BDD in tests/gateway/):
##   computeGateAssessment    — depends on BatchUapReport (deep nested types)
##   executePipeline          — full UAP pipeline execution
##   runBatchVerification     — not exported; orchestrates 4-layer pipeline
##   runProofPipeline         — not exported; topology scan + verification
##   runAxiomEngineCli        — not exported; top-level CLI entry point

import std/json
import std/os
import std/strutils
import std/tables
import std/unittest

import cli/axiom_engine
import cli/cli_types
import cli/queue_limit
import core/proof/proof_budget
import core/results

suite "resolveVaultDir — priority logic":
  test "task vault dir takes precedence over env":
    var env = initTable[string, string]()
    env["AXIOM_PROVE_VAULT_DIR"] = "/env/vault"
    let result = resolveVaultDir("/task/vault", env)
    check result == "/task/vault"

  test "env vault dir used when task dir is empty":
    var env = initTable[string, string]()
    env["AXIOM_PROVE_VAULT_DIR"] = "/env/vault"
    let result = resolveVaultDir("", env)
    check result == "/env/vault"

  test "default path when both are empty":
    var env = initTable[string, string]()
    let result = resolveVaultDir("", env)
    check result == "logs" / "proof_vault"

  test "env vault dir ignored when task dir is non-empty":
    var env = initTable[string, string]()
    env["AXIOM_PROVE_VAULT_DIR"] = "/env/vault"
    let result = resolveVaultDir("custom_vault", env)
    check result == "custom_vault"

  test "empty env table with non-empty task dir":
    let env = initTable[string, string]()
    let result = resolveVaultDir("my_vault", env)
    check result == "my_vault"

  test "env key absent from table defaults correctly":
    var env = initTable[string, string]()
    env["UNRELATED_KEY"] = "something"
    let result = resolveVaultDir("", env)
    check result == "logs" / "proof_vault"

suite "buildVsrLedgerJson — serialization":
  test "all fields present in output JSON":
    let entry = LedgerEvent(
      timestamp: "2026-07-04T12:00:00Z",
      vsr: 0.8750,
      asi: "0.9200",
      verified: 45,
      total: 50,
      delta: 5
    )
    let node = buildVsrLedgerJson(entry)
    check node.hasKey("ts")
    check node.hasKey("vsr")
    check node.hasKey("asi")
    check node.hasKey("verified")
    check node.hasKey("total")
    check node.hasKey("delta")

  test "timestamp preserved exactly":
    let entry = LedgerEvent(timestamp: "2026-01-01T00:00:00Z")
    let node = buildVsrLedgerJson(entry)
    check node["ts"].getStr() == "2026-01-01T00:00:00Z"

  test "vsr formatted to 4 decimal places":
    let entry = LedgerEvent(vsr: 0.123456)
    let node = buildVsrLedgerJson(entry)
    check node["vsr"].getStr() == "0.1235"

  test "vsr zero value":
    let entry = LedgerEvent(vsr: 0.0)
    let node = buildVsrLedgerJson(entry)
    check node["vsr"].getStr() == "0.0000"

  test "vsr one value":
    let entry = LedgerEvent(vsr: 1.0)
    let node = buildVsrLedgerJson(entry)
    check node["vsr"].getStr() == "1.0000"

  test "asi string preserved":
    let entry = LedgerEvent(asi: "0.9500")
    let node = buildVsrLedgerJson(entry)
    check node["asi"].getStr() == "0.9500"

  test "integer fields preserved":
    let entry = LedgerEvent(verified: 100, total: 200, delta: 10)
    let node = buildVsrLedgerJson(entry)
    check node["verified"].getInt() == 100
    check node["total"].getInt() == 200
    check node["delta"].getInt() == 10

  test "zero counts":
    let entry = LedgerEvent(verified: 0, total: 0, delta: 0)
    let node = buildVsrLedgerJson(entry)
    check node["verified"].getInt() == 0
    check node["total"].getInt() == 0
    check node["delta"].getInt() == 0

  test "negative delta allowed (regression)":
    let entry = LedgerEvent(delta: -3)
    let node = buildVsrLedgerJson(entry)
    check node["delta"].getInt() == -3

  test "JSON round-trip: serialize then parse":
    let entry = LedgerEvent(
      timestamp: "2026-07-04T12:00:00Z",
      vsr: 0.8750,
      asi: "0.9200",
      verified: 45,
      total: 50,
      delta: 5
    )
    let node = buildVsrLedgerJson(entry)
    let rendered = $node
    let parsed = parseJson(rendered)
    check parsed["ts"].getStr() == "2026-07-04T12:00:00Z"
    check parsed["verified"].getInt() == 45

suite "buildProofTask — flag conversion":
  test "unlimited queue when limit is 0":
    let flags = AxProveFlags(limit: 0)
    let res = buildProofTask(flags)
    check res.isOk()
    let task = res.get()
    check task.limit.kind == vbUnlimited
    check task.maxRounds == 6

  test "capped queue when limit > 0":
    let flags = AxProveFlags(limit: 42)
    let res = buildProofTask(flags)
    check res.isOk()
    let task = res.get()
    check task.limit.kind == vbCapped
    check task.limit.capValue == 42.Positive

  test "config vault dir passed through":
    let flags = AxProveFlags()
    let res = buildProofTask(flags, configVaultDir = "/custom/vault")
    check res.isOk()
    check res.get().vaultDir == "/custom/vault"

  test "empty config vault dir stays empty":
    let flags = AxProveFlags()
    let res = buildProofTask(flags, configVaultDir = "")
    check res.isOk()
    check res.get().vaultDir == ""

  test "config budget gas passed through":
    let flags = AxProveFlags()
    let res = buildProofTask(flags, configBudgetGas = 200)
    check res.isOk()
    check res.get().budgetGas == 200

  test "emitJson flag forwarded":
    let flags = AxProveFlags()
    let res = buildProofTask(flags, emitJson = true)
    check res.isOk()
    check res.get().emitJson == true

  test "emitJson false by default":
    let flags = AxProveFlags()
    let res = buildProofTask(flags)
    check res.isOk()
    check res.get().emitJson == false

  test "maxRounds always 6 regardless of input":
    let flags = AxProveFlags(limit: 10)
    let res = buildProofTask(flags)
    check res.get().maxRounds == 6

  test "all flags combined":
    let flags = AxProveFlags(limit: 100)
    let res = buildProofTask(flags, configVaultDir = "/v", configBudgetGas = 500, emitJson = true)
    check res.isOk()
    let task = res.get()
    check task.limit.kind == vbCapped
    check task.limit.capValue == 100.Positive
    check task.vaultDir == "/v"
    check task.budgetGas == 500
    check task.emitJson == true
    check task.maxRounds == 6

suite "initAxiomEngine — adaptive budget":
  test "budgetGas > 0 uses explicit gas limit":
    let engine = initAxiomEngine(startMono = 1_000_000, budgetGas = 200)
    check engine.budget.gasTotal == 200

  test "expectedNodeCount > 0 scales by MaxGasCostPerNode":
    let nodeCount = 10
    let engine = initAxiomEngine(startMono = 1_000_000, expectedNodeCount = nodeCount)
    check engine.budget.gasTotal == nodeCount * MaxGasCostPerNode

  test "both zero falls back to maxTotalSolverInvocations":
    let engine = initAxiomEngine(startMono = 1_000_000)
    check engine.budget.gasTotal == maxTotalSolverInvocations

  test "budgetGas takes precedence over expectedNodeCount":
    let engine = initAxiomEngine(startMono = 1_000_000, budgetGas = 50, expectedNodeCount = 100)
    check engine.budget.gasTotal == 50

  test "startMono is recorded in budget":
    let mono = int64(42_000_000)
    let engine = initAxiomEngine(startMono = mono)
    check engine.budget.startMono == mono

  test "gasRemaining equals gasTotal at init":
    let engine = initAxiomEngine(startMono = 0, budgetGas = 30)
    check engine.budget.gasRemaining == engine.budget.gasTotal

  test "invocations starts at 0":
    let engine = initAxiomEngine(startMono = 0, budgetGas = 10)
    check engine.budget.invocations == 0

  test "single node count scales correctly":
    let engine = initAxiomEngine(startMono = 0, expectedNodeCount = 1)
    check engine.budget.gasTotal == 1 * MaxGasCostPerNode

  test "large node count scales correctly":
    let engine = initAxiomEngine(startMono = 0, expectedNodeCount = 1000)
    check engine.budget.gasTotal == 1000 * MaxGasCostPerNode

suite "GateReporter — event accumulation":
  test "newGateReporter starts empty":
    let reporter = newGateReporter()
    check reporter.events.len == 0

  test "single report adds one event":
    var reporter = newGateReporter()
    reporter.report("pre-commit", true, "structural validation", 1000)
    check reporter.events.len == 1

  test "event fields preserved":
    var reporter = newGateReporter()
    reporter.report("pre-push", false, "verification failed", 2000)
    let ev = reporter.events[0]
    check ev.gateName == "pre-push"
    check ev.passed == false
    check ev.detail == "verification failed"
    check ev.timestamp == 2000

  test "multiple reports accumulate in order":
    var reporter = newGateReporter()
    reporter.report("gate-1", true, "ok", 100)
    reporter.report("gate-2", false, "fail", 200)
    reporter.report("gate-3", true, "ok", 300)
    check reporter.events.len == 3
    check reporter.events[0].gateName == "gate-1"
    check reporter.events[1].gateName == "gate-2"
    check reporter.events[2].gateName == "gate-3"

  test "passed=true event":
    var reporter = newGateReporter()
    reporter.report("ci-cd", true, "budget healthy", 500)
    check reporter.events[0].passed == true

  test "empty detail string":
    var reporter = newGateReporter()
    reporter.report("test-gate", true, "", 0)
    check reporter.events[0].detail == ""

  test "large timestamp preserved":
    var reporter = newGateReporter()
    let bigTs = int64(9_999_999_999_999)
    reporter.report("gate", true, "detail", bigTs)
    check reporter.events[0].timestamp == bigTs

  test "ten reports accumulate correctly":
    var reporter = newGateReporter()
    for i in 0 ..< 10:
      reporter.report("gate-" & $i, i mod 2 == 0, "detail-" & $i, i.int64)
    check reporter.events.len == 10
    check reporter.events[9].gateName == "gate-9"
    check reporter.events[9].passed == false  # 9 mod 2 == 1, so i mod 2 == 0 is false
    check reporter.events[8].passed == true  # 8 mod 2 == 0

suite "LedgerEvent — type construction":
  test "all fields settable":
    let e = LedgerEvent(
      timestamp: "t", vsr: 0.5, asi: "0.6",
      verified: 10, total: 20, delta: 5
    )
    check e.timestamp == "t"
    check e.vsr == 0.5
    check e.asi == "0.6"
    check e.verified == 10
    check e.total == 20
    check e.delta == 5

  test "default construction via literal":
    let e = LedgerEvent()
    check e.timestamp.len == 0
    check e.vsr == 0.0
    check e.asi.len == 0
    check e.verified == 0
    check e.total == 0
    check e.delta == 0

suite "persistVsrLedger — IO append":
  test "creates file and writes entry":
    let tmpDir = getTempDir() / "axiom_test_ledger_" & $getCurrentProcessId()
    let ledgerPath = tmpDir / "vsr_ledger.jsonl"
    let entry = LedgerEvent(
      timestamp: "2026-07-04T12:00:00Z",
      vsr: 0.8750,
      asi: "0.9200",
      verified: 45,
      total: 50,
      delta: 5
    )
    persistVsrLedger(ledgerPath, entry)
    let content = readFile(ledgerPath)
    let parsed = parseJson(content.strip())
    check parsed["ts"].getStr() == "2026-07-04T12:00:00Z"
    check parsed["verified"].getInt() == 45
    # cleanup
    removeFile(ledgerPath)
    removeDir(tmpDir)

  test "appends multiple entries":
    let tmpDir = getTempDir() / "axiom_test_ledger_append_" & $getCurrentProcessId()
    let ledgerPath = tmpDir / "vsr_ledger.jsonl"
    for i in 1 .. 3:
      let entry = LedgerEvent(
        timestamp: "ts" & $i,
        verified: i,
        total: 10,
        delta: i
      )
      persistVsrLedger(ledgerPath, entry)
    let lines = readFile(ledgerPath).strip().splitLines()
    check lines.len == 3
    let first = parseJson(lines[0])
    let last = parseJson(lines[2])
    check first["verified"].getInt() == 1
    check last["verified"].getInt() == 3
    # cleanup
    removeFile(ledgerPath)
    removeDir(tmpDir)

  test "creates parent directory if missing":
    let tmpDir = getTempDir() / "axiom_test_nested_" & $getCurrentProcessId()
    let ledgerPath = tmpDir / "sub" / "dir" / "ledger.jsonl"
    let entry = LedgerEvent(timestamp: "t1", verified: 1, total: 1, delta: 1)
    persistVsrLedger(ledgerPath, entry)
    check fileExists(ledgerPath)
    # cleanup
    removeFile(ledgerPath)
    removeDir(tmpDir / "sub" / "dir")
    removeDir(tmpDir / "sub")
    removeDir(tmpDir)

  test "entry survives serialize-then-parse round trip":
    let tmpDir = getTempDir() / "axiom_test_roundtrip_" & $getCurrentProcessId()
    let ledgerPath = tmpDir / "ledger.jsonl"
    let entry = LedgerEvent(
      timestamp: "2026-07-04T23:59:59Z",
      vsr: 0.0001,
      asi: "1.0000",
      verified: 999,
      total: 1000,
      delta: 1
    )
    persistVsrLedger(ledgerPath, entry)
    let parsed = parseJson(readFile(ledgerPath).strip())
    check parsed["ts"].getStr() == "2026-07-04T23:59:59Z"
    check parsed["vsr"].getStr() == "0.0001"
    check parsed["asi"].getStr() == "1.0000"
    check parsed["verified"].getInt() == 999
    check parsed["total"].getInt() == 1000
    check parsed["delta"].getInt() == 1
    # cleanup
    removeFile(ledgerPath)
    removeDir(tmpDir)

suite "ProofTask — field access":
  test "fields accessible after construction":
    let flags = AxProveFlags(limit: 10)
    let res = buildProofTask(flags, configVaultDir = "/v", configBudgetGas = 50, emitJson = true)
    let task = res.get()
    # Verify all fields are accessible and correct
    check task.limit.kind == vbCapped
    check task.vaultDir == "/v"
    check task.emitJson == true
    check task.maxRounds == 6
    check task.budgetGas == 50
