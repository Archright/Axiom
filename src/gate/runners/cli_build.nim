import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [CatchableError].}

## DEBT#434: bin/ax release binary is produced only as a transitive side effect of
## ci-unit-tests -> nimble build -> nim c -d:release, with no explicit build step and
## no job running product E2E (ax prove -> evidence -> report).

## CLI Build Verification Gate
##
## Verifies that the CLI binary is fresh relative to its source files.
## If stale, logs a warning and optionally rebuilds.
## Part of L2 Functional gate layer.
import core/axiom_pragmas
const cliBuildDebtMarker {.axiomDebt: "DEBT#434".} = true
import std/os
import core/trusted/axiom_pragmas_lite
import core/utils/repo_root

import gate/runners/binary_freshness_gate
import infrastructure/logging_facade

# axiomIoBoundary

proc main() {.axiomEffect: IOEffect.} =
  # Check binary freshness before building
  let repoRoot = findRepoRoot()
  setCurrentDir(repoRoot)
  let fr = checkBinaryFreshness(DefaultBinaryPath, CliSourcePaths)
  if fr.isStale:
    # Freshness is enforced by binary-freshness-gate (fail-closed on CAS miss /
    # source fingerprint drift). Making cli-build rebuild here would be a
    # duplicate, non-deterministic debug compile that never refreshes bin/ax
    # (no -o:bin/ax) and risks the 30s SLA. The canonical artifact is built by
    # `make ci-bootstrap` (nim c -d:release -o:bin/ax src/cli/main.nim); defer
    # to that boundary instead of re-compiling here.
    logInfo("cli_build", formatFreshnessReport(fr))
    logWarn("cli_build", "[cli-build] WARN: bin/ax is stale relative to CLI sources; run `make ci-bootstrap` to rebuild the release binary.")
  else:
    logInfo("cli_build", formatFreshnessReport(fr))

  # Also install globally to prevent stale binary usage
  let homeBin = joinPath(getHomeDir(), ".local", "bin")
  if dirExists(homeBin):
    let srcBin = joinPath(getCurrentDir(), "bin", "ax")
    let dstBin = joinPath(homeBin, "ax")
    if fileExists(srcBin):
      try: copyFile(srcBin, dstBin) except CatchableError: discard  # axiom:best-effort(ioboundary catch)

when isMainModule:
  main()

{.pop.}

