## test_quality_guard.nim — Compile-time test quality enforcement
## Part of the Guard Ring system for Axiom-core.
##
## Enforces:
## - Tier 1 core modules MUST have test files
## - Test files with >50% `check true` density are rejected as stubs
## - {temporaryStub} annotated tests are exempt from density checks
##   but subject to TTL expiry enforcement
## - Only active under -d:axiomStrict to allow gradual rollout

import core/trusted/layer_declaration
axiomLayer "domain"
import std/macros
import std/strutils
import core/trusted/architecture_invariants
import core/parsers/safe_parsers
import core/results
{.push raises: [].}

const
  MaxStubDensity* = 0.5  ## check true density above this = stub rejection

  Tier1Modules* = [
    "axiom_engine",
    "gate_memo",
    "state_ledger",
    "import_parser",
    "z3_interactive",
    "pipeline_context",
    "orchestrator_hook",
    "batch_uap",
    "gate_registry",
    "coverage_bridge"
  ]

  TemporaryStubPattern* = "{temporaryStub:"

func parseTemporaryStubAnnotation*(content: string): (bool, string, int) {.compileTime.} =
  ## Scan file content for {temporaryStub: [ttl: N, debtID: "DEBT#xxx"]} annotation
  ## in header comments. Returns (isTemporary, debtID, ttl).
  let tagStart = content.find(TemporaryStubPattern)
  if tagStart < 0:
    return (false, "", 0)

  # Extract the block between {temporaryStub: ... }
  let blockStart = tagStart + TemporaryStubPattern.len
  let blockEnd = content.find('}', blockStart)
  if blockEnd < 0:
    return (false, "", 0)

  let blk = content[blockStart ..< blockEnd]

  # Parse debtID
  var debtID = ""
  let debtIDKey = "debtID:"
  let debtIDIdx = blk.find(debtIDKey)
  if debtIDIdx >= 0:
    var valStart = debtIDIdx + debtIDKey.len
    # Skip whitespace
    while valStart < blk.len and blk[valStart] in {' ', '\t'}:
      inc valStart
    # Skip opening quote
    if valStart < blk.len and blk[valStart] == '"':
      inc valStart
    var valEnd = valStart
    while valEnd < blk.len and blk[valEnd] notin {'"', ',', '}', '\n'}:
      inc valEnd
    debtID = blk[valStart ..< valEnd]

  # Parse ttl
  var ttl = 0
  let ttlKey = "ttl:"
  let ttlIdx = blk.find(ttlKey)
  if ttlIdx >= 0:
    var valStart = ttlIdx + ttlKey.len
    while valStart < blk.len and blk[valStart] in {' ', '\t'}:
      inc valStart
    var valEnd = valStart
    while valEnd < blk.len and blk[valEnd] in {'0'..'9'}:
      inc valEnd
    if valEnd > valStart:
      let ttlRes = safeParseInt(blk[valStart ..< valEnd])
      if ttlRes.isOk:
        ttl = ttlRes.get

  if debtID.len > 0:
    return (true, debtID, ttl)
  return (false, "", 0)

macro enforceTestQuality*(testPath: static string): untyped =
  ## Compile-time assertion density check for test files.
  ## Rejects files where >50% of assertions are bare `check true`.
  ## Files annotated with {temporaryStub: ...} are exempt from density
  ## checks but receive a compile-time warning.
  when defined(axiomStrict):
    if not fileExists(testPath):
      error("TEST QUALITY: Missing test file: " & testPath &
            ". All Tier 1 modules require test files.")

    let content = staticRead(testPath)

    # Check for temporary stub annotation first
    let (isTemporary, debtID, ttl) = parseTemporaryStubAnnotation(content)

    if isTemporary:
      # Enforce TTL expiry — will emit compile error if the stub has exceeded its TTL
      debtTTL(debtID, 366, ttl)
      warning("TEMPORARY STUB: " & testPath &
              " (" & debtID & ", ttl=" & $ttl & " commits remaining)")
    else:
      # Only enforce density check for non-annotated files
      let lines = content.splitLines()
      var checkTrueCount = 0
      var totalChecks = 0

      for line in lines:
        let stripped = line.strip()
        if stripped.startsWith("check "):
          inc totalChecks
          if stripped == "check true" or stripped == "check true:" or
             stripped == "check(true)" or stripped == "check(true):":
            inc checkTrueCount

      if totalChecks > 0:
        let density = checkTrueCount.float / totalChecks.float
        if density > MaxStubDensity:
          error("TEST QUALITY: Stub test detected in " & testPath &
                ". check-true density = " & $(density * 100).int &
                "% (max allowed: " & $(MaxStubDensity * 100).int & "%). " &
                "Replace stubs with real assertions that test actual behavior.")

      if totalChecks == 0:
        warning("TEST QUALITY: No assertions found in " & testPath &
                ". Test file has zero check/assert statements.")

  result = newEmptyNode()

macro enforceTemporaryStubExpiry*(testPath: static string): untyped =
  ## Compile-time TTL enforcement for {temporaryStub} annotated tests.
  ## Reads the test file, parses the annotation, and calls debtTTL()
  ## to verify the stub has not exceeded its allowed lifetime.
  when defined(axiomStrict):
    if not fileExists(testPath):
      return newEmptyNode()

    let content = staticRead(testPath)
    let (isTemporary, debtID, ttl) = parseTemporaryStubAnnotation(content)

    if isTemporary and ttl > 0:
      # baselineCommit 366 = commit count at debt registration time
      debtTTL(debtID, 366, ttl)

  result = newEmptyNode()

macro enforceCoreTestCoverage*(): untyped =
  ## Compile-time check that all Tier 1 core modules have test files.
  ## Only enforced under -d:axiomStrict for gradual rollout.
  when defined(axiomStrict):
    for module in Tier1Modules:
      let primaryPath = "tests/gateway/" & module & "_test.nim"
      let altPath = "tests/" & module & "_test.nim"
      let integrationPath = "tests/integration/" & module & "_test.nim"

      if not fileExists(primaryPath) and
         not fileExists(altPath) and
         not fileExists(integrationPath):
        error("TEST QUALITY: No test file found for Tier 1 core module: " & module &
              ". Searched: " & primaryPath & ", " & altPath & ", " & integrationPath)

  result = newEmptyNode()

{.pop}
