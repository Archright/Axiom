import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
import checksums/sha2
import core/pure/json_parse
import core/results
import core/trusted/stdlib_shield
import core/types/hubs/topology_hub
import std/[os, sets, strutils, tables, times]
import std/json except parseJson
import core/axiom_pragmas
type
  ModuleHistoryEntry* = object
    path*: string
    changedAt*: string
    changeType*: string
    approvedInLock*: int

  ModuleEntry* = object
    currentPath*: string
    initialPath*: string
    history*: seq[ModuleHistoryEntry]

  ShardEntry* = object
    members*: seq[string]
    moduleType*: string
    note*: string

  TransitionalEntry* = object
    createdAt*: string
    resolvedAt*: string

  TopologyLock* = object
    schema*: string
    lockRevision*: int
    generatedFromPolicy*: string
    generatedFromRevision*: int
    generatedAt*: string
    modules*: Table[string, ModuleEntry]
    shards*: Table[string, ShardEntry]
    transitionalModules*: Table[string, TransitionalEntry]
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func parseTopologyLockJson*(jsonStr: string): Result[TopologyLock, string] {.raises: [].} =
  ## Pure: parse a topology.lock JSON string.
  try:
    let j = pureParseJson(jsonStr)
    # Validate required fields before proceeding — corrupt JSON must yield violations, not empty pass
    if not j.hasKey("_schema") or j{"_schema"}.getStr("").len == 0:
      return err("topology lock corrupt: missing _schema — failing closed per §0.9")
    var lock = TopologyLock(
      schema: j{"_schema"}.getStr(""),
      lockRevision: j{"lock_revision"}.getInt(0),
      generatedFromPolicy: j{"generated_from_policy"}.getStr("")
    )
    if j.hasKey("generated_from_revision") and j{"generated_from_revision"}.kind != JNull:
      lock.generatedFromRevision = j{"generated_from_revision"}.getInt
    lock.generatedAt = j{"generated_at"}.getStr("")

    lock.modules = initTable[string, ModuleEntry]()
    let modulesNode = j{"modules"}
    if not modulesNode.isNil and modulesNode.kind == JObject:
      for key, val in modulesNode.pairs:
        var entry = ModuleEntry(
          currentPath: val{"current_path"}.getStr(""),
          initialPath: val{"initial_path"}.getStr("")
        )
        if val.hasKey("history"):
          for h in val{"history"}:
            entry.history.add(ModuleHistoryEntry(
              path: h{"path"}.getStr(""),
              changedAt: h{"changed_at"}.getStr(""),
              changeType: h{"change_type"}.getStr(""),
              approvedInLock: h{"approved_in_lock"}.getInt(0)
            ))
        lock.modules[key] = entry

    lock.shards = initTable[string, ShardEntry]()
    let shardsNode = j{"shards"}
    if not shardsNode.isNil and shardsNode.kind == JObject:
      for key, val in shardsNode.pairs:
        var entry = ShardEntry()
        if val.hasKey("members"):
          for m in val{"members"}:
            entry.members.add(m.getStr)
        if val.hasKey("type"):
          entry.moduleType = val{"type"}.getStr
        if val.hasKey("note"):
          entry.note = val{"note"}.getStr
        lock.shards[key] = entry

    lock.transitionalModules = initTable[string, TransitionalEntry]()
    let transNode = j{"transitional_modules"}
    if not transNode.isNil and transNode.kind == JObject:
      for key, val in transNode.pairs:
        var entry = TransitionalEntry()
        if val.hasKey("created_at"):
          entry.createdAt = val{"created_at"}.getStr
        if val.hasKey("resolved_at") and val{"resolved_at"}.kind != JNull:
          entry.resolvedAt = val{"resolved_at"}.getStr
        lock.transitionalModules[key] = entry
    ok(lock)
  except CatchableError as e:
    err("topology lock JSON unreadable: " & e.msg & " — failing closed per §0.9")
# --- A. parseTopologyLock: thin I/O shell ---
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc parseTopologyLock*(path: string): Result[TopologyLock, string] {.raises: [].} =
  ## Shell: read file, delegate to pure JSON parser.
  let content =
    try: safeReadFile(path)
    except CatchableError as e:
      return err("topology lock file unreadable: " & e.msg & " — failing closed per §0.9")
  parseTopologyLockJson(content)

# --- B. checkTransitionalTTL: func + proc shell ---
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func checkTransitionalTTLWithTime*(lock: TopologyLock, maxAgeDays: int,
    currentTime: DateTime): seq[Violation] =
  ## Pure: check transitional module TTL against a given time.
  result = @[]
  for mid, meta in lock.transitionalModules:
    if meta.resolvedAt.len > 0:
      continue
    try:
      var created: Time
      ## [SEE: nim_effect_system_quirks.md §1.1]
      {.cast(noSideEffect).}:
        created = parseTime(meta.createdAt, "yyyy-MM-dd'T'HH:mm:sszzz", utc())
      let ageDays = (currentTime.toTime - created).inDays
      if ageDays > maxAgeDays:
        let modPath = lock.modules.getOrDefault(mid).currentPath
        result.add(Violation(
          kind: vkTransitionalExpired,
          moduleId: mid,
          path: modPath,
          message: "POLICY: Transitional module expired (" & $ageDays & "d > " &
                   $maxAgeDays & "d): " & modPath
        ))
    except TimeParseError:
      continue
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc checkTransitionalTTL*(lock: TopologyLock, maxAgeDays: int): seq[Violation] =
  ## Shell: get current time, delegate to pure TTL checker.
  result = checkTransitionalTTLWithTime(lock, maxAgeDays, now())

# --- C. checkLockCompliance: pure funcs + proc shell ---
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func checkMissingModules*(lock: TopologyLock;
    existingPaths: HashSet[string]): seq[Violation] =
  ## Pure: finds modules in lock but not in existingPaths.
  result = @[]
  for mid, modMeta in lock.modules:
    if not existingPaths.contains(modMeta.currentPath):
      result.add(Violation(
        kind: vkMissing,
        moduleId: mid,
        path: modMeta.currentPath,
        message: "LOCK: Module in lock but missing on filesystem: " &
                 modMeta.currentPath
      ))
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func checkOrphanFiles*(lock: TopologyLock;
    nimFilesOnDisk: seq[string]): seq[Violation] =
  ## Pure: finds files not in lock.
  result = @[]
  var pathToId = initTable[string, string]()
  for mid, entry in lock.modules:
    pathToId[entry.currentPath] = mid
  for relPath in nimFilesOnDisk:
    if not pathToId.hasKey(relPath):
      result.add(Violation(
        kind: vkOrphan,
        moduleId: "",
        path: relPath,
        message: "LOCK: Orphan file not in topology.lock: " & relPath
      ))
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc checkLockCompliance*(lock: TopologyLock): seq[Violation] {.raises: [TopologyIOError, ValueError, OSError].} =
  ## Shell: gather filesystem state, delegate to pure checkers.
  var existingPaths = initHashSet[string]()
  for mid, modMeta in lock.modules:
    if fileExists(modMeta.currentPath):
      existingPaths.incl(modMeta.currentPath)

  var nimFilesOnDisk: seq[string] = @[]
  let dirOk = try: safeDirExists("src") except CatchableError: false
  if dirOk:
    try:
      for path in safeWalkDirRec("src"):
        if path.endsWith(".nim"):
          nimFilesOnDisk.add(path.relativePath("."))
    except CatchableError:
      discard  # axiom:best-effort(ioboundary catch)

  result = checkMissingModules(lock, existingPaths)
  result.add(checkOrphanFiles(lock, nimFilesOnDisk))

# --- Already-pure helpers (unchanged) ---
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func generateDeterministicUuid*(namespaceUuid, name: string): string {.raises: [].} =
  ## Generate a deterministic UUID v5-like string from namespace UUID + name.
  ## Uses SHA-256 hash, formatted as UUID with version 5 and RFC 4122 variant bits.
  let digest = secureHash(Sha_256, namespaceUuid & name)
  let hash = $digest
  # Format: xxxxxxxx-xxxx-5xxx-8xxx-xxxxxxxxxxxx
  result = hash[0..7] & "-" & hash[8..11] & "-5" & hash[13..15] & "-" &
           "8" & hash[17..19] & "-" & hash[20..31]
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func addOrphanEntry*(lock: var TopologyLock; path, uuid: string) {.raises: [].} =
  ## Add a new module entry for an orphan file found on disk but missing from lock.
  lock.modules[uuid] = ModuleEntry(
    currentPath: path,
    initialPath: path,
    history: @[]
  )

# --- D. removeStaleEntries: func + proc shell ---
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func identifyStaleEntries*(lock: TopologyLock;
    existsFn: proc(p: string): bool {.noSideEffect, raises: [].}): seq[string] =
  ## Pure: returns module IDs whose files no longer exist.
  result = @[]
  for mid, entry in lock.modules:
    if not existsFn(entry.currentPath):
      result.add(mid)
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func applyStaleRemoval*(lock: var TopologyLock; staleIds: seq[string]) =
  ## Pure: remove stale entries from lock.
  for mid in staleIds:
    lock.modules.del(mid)
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func removeStaleEntries*(lock: var TopologyLock): seq[string] {.raises: [].} =
  ## Shell: wrap fileExists, delegate to pure functions.
  let existsFn = proc(p: string): bool {.noSideEffect, raises: [].} =
    ## [SEE: nim_effect_system_quirks.md §1.1]
    {.cast(noSideEffect).}:
      fileExists(p)
  let staleIds = identifyStaleEntries(lock, existsFn)
  result = @[]
  for mid in staleIds:
    result.add(lock.modules.getOrDefault(mid).currentPath)
  applyStaleRemoval(lock, staleIds)

# --- E. syncLockToFilesystem: extract findOrphanPaths ---
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func findOrphanPaths*(lock: TopologyLock;
    nimFilesOnDisk: seq[string]): seq[string] =
  ## Pure: finds .nim files not in lock.
  result = @[]
  var pathToId = initTable[string, string]()
  for mid, entry in lock.modules:
    pathToId[entry.currentPath] = mid
  for path in nimFilesOnDisk:
    if not pathToId.hasKey(path):
      result.add(path)
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc syncLockToFilesystem*(lock: var TopologyLock; srcDir: string;
                           namespaceUuid: string) {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Synchronize the lock with the filesystem: add orphans, remove stale entries.
  ## Increments lockRevision and updates generatedAt.
  try:
    # 1. Remove stale entries (files in lock but missing on disk)
    discard removeStaleEntries(lock)

    # 2. Collect nim files on disk
    var nimFilesOnDisk: seq[string] = @[]
    let dirOk = try: safeDirExists(srcDir) except CatchableError: false
    if dirOk:
      try:
        for path in safeWalkDirRec(srcDir):
          if path.endsWith(".nim"):
            nimFilesOnDisk.add(path.relativePath("."))
      except CatchableError:
        discard  # axiom:best-effort(ioboundary catch)

    # 3. Add orphan files via pure detection
    let orphans = findOrphanPaths(lock, nimFilesOnDisk)
    for relPath in orphans:
      let uuid = generateDeterministicUuid(namespaceUuid, relPath)
      lock.addOrphanEntry(relPath, uuid)
  except CatchableError:
    discard  # Best-effort sync; gate will report remaining violations  # axiom:best-effort(ioboundary catch)

  # 4. Bump revision and timestamp
  lock.lockRevision = lock.lockRevision + 1
  lock.generatedAt = $now()

# --- F. reconcileLockModel: bidirectional reconcile ---
type
  ReconcileReport* = object
    added*: seq[string]
    warnings*: seq[string]
    unchanged*: int
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc reconcileLockModel*(lock: var TopologyLock; srcDir: string;
                         dryRun: bool): ReconcileReport {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Bidirectional reconcile: scan disk vs lock, report and optionally fix.
  ## dryRun=true: report only, no lock modification.
  ## dryRun=false: add orphans, remove stale, bump revision.
  result = ReconcileReport(added: @[], warnings: @[], unchanged: 0)
  try:
    # 1. Collect nim files on disk
    var nimFilesOnDisk: seq[string] = @[]
    let dirOk = try: safeDirExists(srcDir) except CatchableError: false
    if dirOk:
      try:
        for path in safeWalkDirRec(srcDir):
          if path.endsWith(".nim"):
            nimFilesOnDisk.add(path.relativePath("."))
      except CatchableError:
        discard  # axiom:best-effort(ioboundary catch)

    # 2. Find orphans (on disk but not in lock)
    let orphans = findOrphanPaths(lock, nimFilesOnDisk)
    for relPath in orphans:
      if dryRun:
        stdout.writeLine("[DRY-RUN] Would add: " & relPath)
      else:
        let uuid = generateDeterministicUuid(
          "6ba7b810-9dad-11d1-80b4-00c04fd430c8", relPath)
        lock.addOrphanEntry(relPath, uuid)
      result.added.add(relPath)

    # 3. Find stale (in lock but not on disk) and warn
    var staleIds: seq[string] = @[]
    for mid, entry in lock.modules:
      if not fileExists(entry.currentPath):
        stdout.writeLine("[WARN] Lock entry missing from disk: " &
                         entry.currentPath)
        result.warnings.add(entry.currentPath)
        staleIds.add(mid)

    # 4. Remove stale entries if not dry-run
    if not dryRun:
      applyStaleRemoval(lock, staleIds)

    # 5. Count unchanged
    result.unchanged = lock.modules.len

    # 6. Bump revision if changes were made
    if not dryRun and (result.added.len > 0 or staleIds.len > 0):
      lock.lockRevision = lock.lockRevision + 1
      lock.generatedAt = $now()
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)

{.pop.}

