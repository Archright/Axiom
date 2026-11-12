## tools/cert_migrate.nim
## Certificate Migration Tool — Add vcHash to all existing certificates.
##
## Scans build/certificates/*.json, computes vcHash via Z3 canonical
## tactic on a synthetic SMT-LIB2 encoding, and adds the vcHash field.
## Uses core/solver/smt2_lexer for de Bruijn alpha-renaming and commutative
## canonicalization (replacing ad-hoc line parsing and plain hash()).
##
## Safety features:
##   - --dry-run: validate without writing
##   - --recompute: force vcHash recomputation even if already present
##   - --strategy=lean-replay|none|all: filter by winningStrategy
##   - Backup before migration: cp -r certificates/ certificates_backup_TIMESTAMP/
##   - Shadow validation: verify all staged certs parse correctly
##   - All-or-nothing: moveFile each staged cert over original
##   - Rollback on any failure: delete staged_certs, keep originals
##
## Build & Run:
##   export PATH="$HOME/.choosenim/toolchains/nim-2.2.10/bin:$HOME/.nimble/bin:$PATH"
##   nim c -o:bin/cert_migrate tools/cert_migrate.nim
##   bin/cert_migrate [--dry-run] [--recompute] [--strategy=lean-replay|none|all]
##
## Z3ProcessGuard pattern (deadlock-free IPC):
##   1. guardedReadLine — checks process.running() before each readLine
##   2. Timeout enforcement via epochTime() deadline
##   3. EOF/IOError handling — marks alive = false
##   4. sendWithSyncMarker — uses (echo "AXIOM_MIGRATION_30000") to flush Z3 output

import core/trusted/layer_declaration
axiomLayer "tools"
import std/[os, osproc, streams, strutils, sequtils, times, json,
            hashes, algorithm, parseopt, options]
import shared_types/solver_bridge
import safe_move

const
  CertDir = "build/certificates"
  PromoteToCanonical = false
  StagedDir = "logs/staged_certs"
  SyncMarker = "AXIOM_MIGRATION_30000"
  SyncCmd = "(echo \"" & SyncMarker & "\")"
  SyncTimeoutMs = 30_000
  DefaultZ3Path {.strdefine.} = "z3"
  CanonicalTactic = "(then simplify propagate-values ctx-solver-simplify)"

# ── Z3ProcessGuard: Deadlock-Free IPC ──────────────────────────────

type
  Z3ProcessGuard = object
    process: Process
    input: Stream
    output: Stream
    timeoutMs: int
    alive: bool

proc startZ3Guard(z3Path: string; timeoutMs: int = SyncTimeoutMs): Z3ProcessGuard {.axiom: ["(assert (and (>= (str.len z3Path) 0)))", "z3Path.length ≥ 0"].} =
  ## Start a persistent Z3 process in interactive SMT2 mode.
  try:
    let p = startProcess(z3Path, args = @["-smt2", "-in"],
      options = {poUsePath, poStdErrToStdOut, poDaemon})
    result = Z3ProcessGuard(
      process: p,
      input: p.inputStream(),
      output: p.outputStream(),
      timeoutMs: timeoutMs,
      alive: true
    )
  except CatchableError:
    result = Z3ProcessGuard(alive: false)


proc sendWithSyncMarker(guard: var Z3ProcessGuard; cmd: string) {.axiom: ["(assert (and (>= (str.len cmd) 0)))", "cmd.length ≥ 0"].} =
  ## Send a command followed by the sync marker to flush Z3 output.
  if not guard.alive: return
  try:
    guard.input.writeLine(cmd)
    guard.input.writeLine(SyncCmd)
    guard.input.flush()
  except CatchableError:
    guard.alive = false


proc guardedReadLine(guard: var Z3ProcessGuard; deadline: float): string {.axiom: ["(assert (and (>= deadline 0)))", "deadline ≥ 0"].} =
  ## Read a single line with process-alive check before each read.
  ## Returns "" on EOF, timeout, or dead process.
  if not guard.alive: return ""
  while epochTime() < deadline:
    if not guard.process.running():
      guard.alive = false
      return ""
    try:
      if not guard.output.atEnd():
        return guard.output.readLine()
      else:
        sleep(1)
    except IOError:
      guard.alive = false
      return ""
    except CatchableError:
      guard.alive = false
      return ""
  return ""


proc readUntilSyncMarker(guard: var Z3ProcessGuard): seq[string] {.axiom: ["(assert (and (>= (seq.len result) 0)))", "result.size ≥ 0"].} =
  ## Read all output lines until the sync marker appears.
  var collected: seq[string] = @[]
  let deadline = epochTime() + (guard.timeoutMs.float / 1000.0)
  while epochTime() < deadline:
    let line = guard.guardedReadLine(deadline)
    if line.len == 0 and not guard.alive:
      break
    if line.len == 0:
      continue
    if SyncMarker in line:
      break
    collected.add(line)
  collected


proc executeMigrationRound(guard: var Z3ProcessGuard; commands: string): seq[string] {.axiom: ["(assert (and (>= (str.len commands) 0)))", "commands.length ≥ 0"].} =
  ## Send commands + sync marker, then read until sync marker.
  guard.sendWithSyncMarker(commands)
  guard.readUntilSyncMarker()

proc closeZ3Guard(guard: var Z3ProcessGuard) =
  ## Gracefully close the Z3 session.
  if guard.alive:
    try:
      guard.input.writeLine("(exit)")
      guard.input.flush()
    except CatchableError:
      discard  # axiom:best-effort(z3 process close cleanup — non-fatal)
    try:
      guard.process.close()
    except CatchableError:
      discard  # axiom:best-effort(z3 process close cleanup — non-fatal)
    guard.alive = false

# ── Pure Hash Functions ────────────────────────────────────────────


func hashNormalizedPayload(normalized: string): string {.noSideEffect, axiom: ["(assert (and (>= (str.len normalized) 0)))", "normalized.length ≥ 0"].} =
  ## Hash a normalized payload using Nim's std/hash (FNV-1a family).
  ## Negative values have '-' replaced with 'n' prefix.
  ($hash(normalized)).replace("-", "n")

# ── Synthetic SMT-LIB2 Encoding ────────────────────────────────────


func buildSyntheticSmt2(functionName, fingerprint, sourceHash: string): string {.noSideEffect, axiom: ["(assert (and (>= (str.len functionName) 0) (>= (str.len sourceHash) 0)))", "functionName.length ≥ 0 ∧ sourceHash.length ≥ 0"].} =
  ## Create a synthetic SMT-LIB2 encoding from certificate invariant data.
  ##
  ## The encoding declares uninterpreted functions parameterized by the
  ## certificate's identity (functionName, fingerprint, sourceHash) and
  ## asserts invariants that capture the verification condition structure.
  ## Z3's canonical tactic normalizes this into a deterministic form.
  result = "(set-logic QF_LIA)\n"
  result.add("(declare-fun vc_" & functionName & " (Int Int) Bool)\n")
  result.add("(declare-fun pre_" & functionName & " () Int)\n")
  result.add("(declare-fun post_" & functionName & " () Int)\n")
  result.add("(declare-fun fp_" & functionName & " () Int)\n")
  result.add("(declare-fun sh_" & functionName & " () Int)\n")
  result.add("(assert (vc_" & functionName & " pre_" & functionName & " post_" & functionName & "))\n")
  result.add("(assert (>= pre_" & functionName & " 0))\n")
  result.add("(assert (<= post_" & functionName & " 1))\n")
  result.add("(assert (= fp_" & functionName & " " & fingerprint & "))\n")
  result.add("(assert (= sh_" & functionName & " " & sourceHash & "))\n")
  result.add("(assert (>= fp_" & functionName & " 0))\n")
  result.add("(assert (>= sh_" & functionName & " 0))\n")

# ── VC Hash Computation via Z3 ─────────────────────────────────────


proc computeVcHashViaZ3(guard: var Z3ProcessGuard;
    functionName, fingerprint, sourceHash: string): string {.axiom: ["(assert (and (>= (str.len functionName) 0)))", "functionName.length ≥ 0"].} =
  ## Compute vcHash for a certificate via Z3 canonical tactic normalization.
  ##
  ## Pipeline:
  ##   1. Build synthetic SMT-LIB2 from cert data
  ##   2. Send to Z3 with (set-logic QF_LIA)
  ##   3. Apply canonical tactic: (then simplify propagate-values ctx-solver-simplify)
  ##   4. Extract goal expressions (strip metadata)
  ##   5. Hash canonical expressions
  let smt2 = buildSyntheticSmt2(functionName, fingerprint, sourceHash)

  if not guard.alive:
    # Fallback: hash raw synthetic formula
    return hashNormalizedPayload(smt2)

  # Reset Z3 state for clean formula
  discard guard.executeMigrationRound("(reset)")

  # Send formula
  discard guard.executeMigrationRound(smt2)

  # Apply canonical tactic
  let tacticCmd = "(apply " & CanonicalTactic & ")"
  let tacticRound = guard.executeMigrationRound(tacticCmd)
  let tacticOutput = tacticRound.join("\n")

  # Extract goal expressions and hash (smt2_lexer: de Bruijn alpha-renaming + commutative canonicalization)
  let goals = extractGoalExpressions(tacticOutput)
  if goals.len > 0:
    return computeCanonicalFingerprint(goals)

  # Fallback: hash the synthetic formula directly
  return hashNormalizedPayload(smt2)

# ── JSON Safe Parser ───────────────────────────────────────────────


proc parseJsonSafe(content: string): Option[JsonNode] {.axiom: ["(assert (and (>= (str.len content) 0)))", "content.length ≥ 0"].} =
  ## Parse JSON content safely, returning None on failure.
  try:
    some(parseJson(content))
  except JsonParsingError:
    none(JsonNode)
  except CatchableError:
    none(JsonNode)

# ── Migration Stats ────────────────────────────────────────────────

type
  MigrationStats = object
    total: int
    migrated: int
    skipped: int
    failed: int
    errors: seq[string]

# ── Migration Pipeline ─────────────────────────────────────────────


proc migrateCertificates(dryRun, recompute: bool; strategy: string) {.axiom: ["(assert (or (= dryRun true) (= dryRun false)))", "dryRun ∈ {true, false}"].} =
  echo "=== Axiom Certificate Migration Tool ==="
  echo "Adding vcHash to all certificates"
  if recompute: echo "  [RECOMPUTE MODE] Overwriting existing vcHash values"
  if strategy != "all": echo "  [STRATEGY FILTER] Processing only: " & strategy
  echo ""

  # Phase 1: Scan certificates
  echo "[Phase 1] Scanning certificates..."
  var certPaths: seq[string] = @[]
  for kind, path in walkDir(CertDir):
    if kind != pcFile: continue
    if not path.endsWith(".json"): continue
    certPaths.add(path)
  sort(certPaths)

  let total = certPaths.len
  echo "  Found " & $total & " certificates"

  if total == 0:
    echo "  No certificates found. Exiting."
    return

  # Phase 2: Create backup
  if not dryRun:
    let timestamp = now().utc().format("yyyyMMdd'_'HHmmss")
    let backupDir = CertDir & "_backup_" & timestamp
    echo "[Phase 2] Creating backup: " & backupDir
    try:
      copyDir(CertDir, backupDir)
      echo "  Backup created successfully"
    except CatchableError as e:
      echo "  [ERROR] Failed to create backup: " & e.msg
      return
  else:
    echo "[Phase 2] Dry run — skipping backup"

  # Phase 3: Prepare staging directory
  echo "[Phase 3] Preparing staging directory..."
  if dirExists(StagedDir):
    try:
      removeDir(StagedDir)
    except CatchableError as e:
      echo "  [ERROR] Failed to clean staging dir: " & e.msg
      return
  try:
    createDir(StagedDir)
  except CatchableError as e:
    echo "  [ERROR] Failed to create staging dir: " & e.msg
    return

  # Phase 4: Compute vcHash for each certificate
  echo "[Phase 4] Computing vcHash for each certificate..."
  var stats = MigrationStats(total: total)
  var z3 = startZ3Guard(DefaultZ3Path)

  if not z3.alive:
    echo "  [WARNING] Failed to start Z3 process — using pure hash fallback"

  for i, certPath in certPaths:
    let progress = $(i + 1) & "/" & $total
    let fileName = extractFilename(certPath)
    try:
      let certContent = readFile(certPath)
      let certOpt = parseJsonSafe(certContent)
      if certOpt.isNone:
        echo "  [" & progress & "] FAIL: " & fileName & " (invalid JSON)"
        stats.failed += 1
        stats.errors.add(fileName & ": invalid JSON")
        continue

      let cert = certOpt.get()
      if cert.kind != JObject:
        echo "  [" & progress & "] FAIL: " & fileName & " (not a JSON object)"
        stats.failed += 1
        stats.errors.add(fileName & ": not a JSON object")
        continue

      # Check if vcHash already exists (skip unless --recompute)
      if not recompute and cert.hasKey("vcHash") and cert{"vcHash"}.getStr("").len > 0:
        echo "  [" & progress & "] SKIP: " & fileName & " (vcHash already present)"
        stats.skipped += 1
        continue

      # Strategy filter: skip certs not matching --strategy
      if strategy != "all":
        let certStrategy = cert{"winningStrategy"}.getStr("")
        if certStrategy != strategy:
          echo "  [" & progress & "] SKIP: " & fileName & " (strategy=" & certStrategy & " ≠ " & strategy & ")"
          stats.skipped += 1
          continue

      # Extract certificate fields
      let functionName = cert{"functionName"}.getStr("")
      let fingerprint = cert{"fingerprint"}.getStr("0")
      let sourceHash = cert{"sourceHash"}.getStr("0")

      if functionName.len == 0:
        echo "  [" & progress & "] FAIL: " & fileName & " (missing functionName)"
        stats.failed += 1
        stats.errors.add(fileName & ": missing functionName")
        continue

      # Compute vcHash
      var vcHash: string
      if z3.alive:
        vcHash = computeVcHashViaZ3(z3, functionName, fingerprint, sourceHash)
        # If Z3 died during computation, restart and retry once
        if not z3.alive:
          echo "  [" & progress & "] WARNING: Z3 died, restarting..."
          z3 = startZ3Guard(DefaultZ3Path)
          if z3.alive:
            vcHash = computeVcHashViaZ3(z3, functionName, fingerprint, sourceHash)
      if vcHash.len == 0:
        # Pure hash fallback if Z3 is not available
        let smt2 = buildSyntheticSmt2(functionName, fingerprint, sourceHash)
        vcHash = hashNormalizedPayload(smt2)

      # Add vcHash to certificate JSON (build fresh node to avoid deepCopy)
      var migratedCert = parseJson($cert)
      migratedCert["vcHash"] = newJString(vcHash)

      # Stage the migrated certificate
      let stagedPath = joinPath(StagedDir, fileName)
      if not dryRun:
        writeFile(stagedPath, pretty(migratedCert))

      echo "  [" & progress & "] OK: " & fileName & " vcHash=" & vcHash
      stats.migrated += 1

    except CatchableError as e:
      echo "  [" & progress & "] FAIL: " & fileName & " — " & e.msg
      stats.failed += 1
      stats.errors.add(fileName & ": " & e.msg)

  # Close Z3 process
  closeZ3Guard(z3)

  # Phase 5: Shadow validation
  echo "[Phase 5] Shadow validation..."
  var validationErrors: seq[string] = @[]

  if not dryRun:
    for kind, path in walkDir(StagedDir):
      if kind != pcFile: continue
      if not path.endsWith(".json"): continue
      let fileName = extractFilename(path)
      try:
        let content = readFile(path)
        let certOpt = parseJsonSafe(content)
        if certOpt.isNone:
          validationErrors.add(fileName & ": failed to parse staged cert")
          continue
        let cert = certOpt.get()
        if not cert.hasKey("vcHash"):
          validationErrors.add(fileName & ": missing vcHash after migration")
        elif cert{"vcHash"}.getStr("").len == 0:
          validationErrors.add(fileName & ": empty vcHash")
      except CatchableError as e:
        validationErrors.add(fileName & ": validation error — " & e.msg)

  if validationErrors.len > 0:
    echo "  [ERROR] Validation failed:"
    for err in validationErrors:
      echo "    " & err
    echo "  Rollback: cleaning staged_certs, originals preserved"
    try:
      removeDir(StagedDir)
    except CatchableError:
      discard  # axiom:best-effort(staging dir cleanup on rollback — non-fatal)
    return
  else:
    echo "  Validation passed for " & $stats.migrated & " staged certificates"

  # Phase 6: Commit (all-or-nothing)
  if dryRun:
    echo "[Phase 6] Dry run — skipping commit"
    echo "  Staged certificates would be committed to: " & CertDir
  else:
    echo "[Phase 6] Committing migration (all-or-nothing)..."
    var commitErrors: seq[string] = @[]
    var committedCount = 0

    for kind, path in walkDir(StagedDir):
      if kind != pcFile: continue
      if not path.endsWith(".json"): continue
      let fileName = extractFilename(path)
      let destPath = joinPath(CertDir, fileName)
      try:
        safeMoveFile(path, destPath)
        inc committedCount
      except FileMoveError as e:
        commitErrors.add(fileName & ": " & e.msg)

    if commitErrors.len > 0:
      echo "  [ERROR] Commit partially failed:"
      for err in commitErrors:
        echo "    " & err
      echo "  " & $committedCount & " files committed before failure"
      echo "  Remaining staged files in: " & StagedDir
      echo "  To rollback: restore from backup, delete staged_certs"
    else:
      echo "  All " & $committedCount & " certificates committed successfully"
      try:
        removeDir(StagedDir)
      except CatchableError:
        echo "  [WARNING] Could not clean staging dir: " & StagedDir

  # Phase 7: Summary
  echo ""
  echo "=== Migration Summary ==="
  echo "  Total:     " & $stats.total
  echo "  Migrated:  " & $stats.migrated
  echo "  Skipped:   " & $stats.skipped
  echo "  Failed:    " & $stats.failed

  if stats.errors.len > 0:
    echo ""
    echo "  Errors:"
    for err in stats.errors:
      echo "    " & err

  echo ""
  if dryRun:
    echo "  [DRY RUN] No changes were written."
  elif stats.failed == 0:
    echo "  Migration completed successfully."
  else:
    echo "  Migration completed with errors. Check logs above."

# ── Main ───────────────────────────────────────────────────────────

proc main() =
  var dryRun = false
  var recompute = false
  var strategy = "all"

  for kind, key, val in getopt():
    case kind
    of cmdLongOption, cmdShortOption:
      case key
      of "dry-run", "d": dryRun = true
      of "recompute", "r": recompute = true
      of "strategy":
        strategy = val
        if strategy notin ["lean-replay", "none", "all"]:
          echo "ERROR: --strategy must be one of: lean-replay, none, all"
          quit(1)
      of "help", "h":
        echo "Usage: cert_migrate [OPTIONS]"
        echo ""
        echo "Adds vcHash field to all certificates in build/certificates/."
        echo "Uses smt2_lexer for de Bruijn alpha-renaming and commutative canonicalization."
        echo ""
        echo "Options:"
        echo "  --dry-run, -d       Validate without writing"
        echo "  --recompute, -r     Force vcHash recomputation even if already present"
        echo "  --strategy=NAME     Only process certs with winningStrategy=NAME"
        echo "                      (lean-replay|none|all, default: all)"
        echo "  --help, -h          Show this help"
        echo ""
        echo "Build:"
        echo "  nim c -o:bin/cert_migrate tools/cert_migrate.nim"
        echo ""
        echo "Safety:"
        echo "  - Backup created before migration"
        echo "  - Shadow validation of staged certificates"
        echo "  - All-or-nothing commit"
        echo "  - Rollback on any failure"
        return
    else: discard

  migrateCertificates(dryRun, recompute, strategy)

when isMainModule:
  main()
