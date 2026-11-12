## migration_runner.nim — Transactional file-level axiomImpl migration tool
##
## Automates mass migration of {.axiom.} → {.axiom, axiomImpl.}
## across the codebase with file-level transaction isolation.
##
## Usage:
##   nim c -o:bin/migration_runner tools/migration_runner.nim
##   ./bin/migration_runner            # full migration
##   ./bin/migration_runner --dry-run  # report only

import core/trusted/layer_declaration
axiomLayer "tools"
import std/[algorithm, os, strutils, re, json, osproc]

type
  MigrationResult* = object
    file*: string
    success*: bool
    error*: string
    functionsMigrated*: int

  MigrationConfig* = object
    sourceRoot*: string
    buildCmd*: string
    commitPrefix*: string
    dryRun*: bool
    maxRetries*: int

proc scanMigrationCandidates*(root: string): seq[string] =
  ## Walk src/ recursively, find .nim files containing {.axiom. but NOT containing axiomImpl.
  for path in walkDirRec(root):
    if not path.endsWith(".nim"):
      continue
    # Skip paths within hidden directories
    if "/." in path:
      continue
    try:
      let content = readFile(path)
      if "{.axiom." in content and "axiomImpl" notin content:
        result.add(path)
    except CatchableError: # axiom:best-effort(unreadable candidate file — skip for migration)
      discard
  result.sort()

proc patchAxiomPragma*(content: string): tuple[patched: string, count: int] =
  ## Replace {.axiom.} → {.axiom, axiomImpl.} and
  ## {.raises: [], axiom.} → {.raises: [], axiom, axiomImpl.}
  ## Returns patched content and total number of replacements made.
  var patched = content
  var count = 0

  # Pattern: {.raises: [], axiom. → {.raises: [], axiom, axiomImpl.
  let raisesPat = "{.raises: [], axiom."
  let raisesRepl = "{.raises: [], axiom, axiomImpl."
  let raisesC = patched.count(raisesPat)
  if raisesC > 0:
    patched = patched.replace(raisesPat, raisesRepl)
  count += raisesC

  # Pattern: {.axiom. → {.axiom, axiomImpl. (all remaining bare axiom pragmas)
  let barePat = "{.axiom."
  let bareRepl = "{.axiom, axiomImpl."
  let bareC = patched.count(barePat)
  if bareC > 0:
    patched = patched.replace(barePat, bareRepl)
  count += bareC

  result = (patched, count)

proc execBuild*(config: MigrationConfig): int =
  ## Run the build command and return exit code.
  result = execCmd(config.buildCmd)

proc execCommit*(file: string; count: int; config: MigrationConfig) =
  ## Git add + commit the migrated file with a descriptive message.
  let baseName = extractFilename(file)
  discard execCmd("git add " & quoteShell(file))
  let msg = config.commitPrefix & " " & baseName & " (" & $count & " functions)"
  discard execCmd("git commit -m " & quoteShell(msg))

proc rollbackFile*(file: string; backup: string) =
  ## Restore file content from backup string.
  writeFile(file, backup)

proc writeDeferredReport*(results: seq[MigrationResult]) =
  ## Write deferred_migration.json with the list of failed files.
  var failed: seq[JsonNode]
  for r in results:
    if not r.success:
      failed.add(%*{"file": r.file, "functionsMigrated": r.functionsMigrated, "error": r.error})
  if failed.len == 0:
    return
  let data = %*{"tool": "migration_runner", "failed": failed}
  writeFile("deferred_migration.json", $data & "\n")

proc runMigration*(config: MigrationConfig) =
  ## Main migration loop with file-level transaction isolation.
  ##
  ## For each candidate file:
  ##   1. Read original content and compute patch
  ##   2. Write patched content
  ##   3. Run build to verify correctness
  ##   4. If build passes → git commit; if fails → rollback
  let candidates = scanMigrationCandidates(config.sourceRoot)
  echo "Found ", candidates.len, " migration candidates"

  var results: seq[MigrationResult]
  var committed, deferred: int

  for file in candidates:
    let original = readFile(file)
    let (patched, count) = patchAxiomPragma(original)

    if count == 0:
      continue

    echo "Processing: ", file, " (", count, " functions)"

    if config.dryRun:
      echo "  [DRY RUN] Would migrate ", count, " functions"
      continue

    writeFile(file, patched)
    let exitCode = execBuild(config)

    if exitCode == 0:
      execCommit(file, count, config)
      echo "  ✅ Committed (", count, " functions)"
      inc committed
      results.add(MigrationResult(file: file, success: true, functionsMigrated: count))
    else:
      rollbackFile(file, original)
      echo "  ❌ Failed — rolled back"
      inc deferred
      results.add(MigrationResult(
        file: file,
        success: false,
        functionsMigrated: count,
        error: "Build failed with exit code " & $exitCode
      ))

  echo "\n=== Summary ==="
  echo "Committed: ", committed, " files"
  echo "Deferred:  ", deferred, " files"
  writeDeferredReport(results)

when isMainModule:
  var config = MigrationConfig(
    sourceRoot: "src",
    buildCmd: "nim c --skipUserCfg --hints:off -o:/dev/null src/cli/axiom_engine.nim",
    commitPrefix: "feat(axiom): migrate leaf functions in",
    dryRun: false,
    maxRetries: 1
  )

  # Parse --dry-run flag
  for i in 1..paramCount():
    if paramStr(i) == "--dry-run":
      config.dryRun = true

  runMigration(config)
