## src/infrastructure/debt_audit/audit_snapshot.nim — Deterministic repository freeze into bundle.
##
## Provides freezeAuditBundle which snapshots a repo into a bundle directory
## with meta.json and files.jsonl. All sorting and digest computation is
## deterministic for reproducibility.
##
## V3 identity model:
##   freeze_time  — frozen UTC timestamp captured once at audit start (input).
##   run_id       — fresh UTC timestamp per execution (tracking only, NOT in any hash).
##   snapshot_id  — "snap:" & sha256(canonical(git_head, tracked_tree_digest,
##                   untracked_tree_digest, freeze_time)).
##   input_digest — SHA256 over canonical(repo_state, freeze_time, rules_digest,
##                   engine_semantics_digest, normative_digest, toolchain_digest).

import core/trusted/layer_declaration
import core/axiom_pragmas
axiomLayer "infrastructure"

import std/[json, os, osproc, posix, sets, strutils, sequtils, algorithm]
import checksums/sha2

# ---------------------------------------------------------------------------
# Hex conversion helpers
# ---------------------------------------------------------------------------

func byteToHex*(b: byte): string {.raises: [].} =
  ## Convert a byte to its two-character lowercase hex representation.
  const hexChars = "0123456789abcdef"
  result = ""
  result.add(hexChars[(b shr 4).int])
  result.add(hexChars[(b and 0x0F).int])

# ---------------------------------------------------------------------------
# SHA-256 hashing helpers (canonical SSOT: checksums/sha2, as hash_kernel)
# ---------------------------------------------------------------------------

func sha256Hex*(data: openArray[byte]): string {.raises: [].} =
  ## Return hex sha256 digest of the given byte data.
  result = $secureHash(Sha_256, cast[string](data))

func sha256Str*(s: string): string {.raises: [].} =
  ## Return hex sha256 digest of a string.
  $secureHash(Sha_256, s)

# ---------------------------------------------------------------------------
# Canonical serialization: sorted "key=value" lines joined with "\n"
# ---------------------------------------------------------------------------

func canonicalSerialize*(pairs: seq[(string, string)]): string {.raises: [].} =
  ## Deterministic canonical form: sorted "key=value" lines joined with "\n".
  ## Used for all composite hash inputs (no JSON insertion-order ambiguity).
  var sorted = pairs
  sorted.sort(proc(a, b: (string, string)): int = cmp(a[0], b[0]))
  result = ""
  for (k, v) in sorted:
    result.add(k & "=" & v & "\n")
  if result.len > 0:
    result = result[0 .. ^2]  # strip trailing newline

# ---------------------------------------------------------------------------
# Toolchain probing (real versions + binary sha256)
# ---------------------------------------------------------------------------

proc hashFileContent*(path: string): string {.raises: [CatchableError].} =
  ## Read file in 1 MiB chunks and return sha256 hex digest.
  ## Returns "" on failure (unreadable file).
  const chunkSize = 1 shl 20
  var f: File
  if not open(f, path, fmRead):
    return ""
  var ctx = initSha_256()
  var buf = newString(chunkSize)
  while true:
    let n = f.readBuffer(cast[pointer](addr buf[0]), buf.len)
    if n <= 0: break
    ctx.update(buf.toOpenArray(0, n - 1))
  f.close()
  result = $ctx.digest()
proc probeToolVersion*(toolName, versionCmd: string): string {.raises: [CatchableError].} =
  ## Run versionCmd, extract first dotted numeric token.
  ## Returns "" if the tool cannot be probed.
  try:
    let (outp, _) = execCmdEx(versionCmd & " 2>&1")
    for line in outp.splitLines:
      if line.len == 0: continue
      for field in line.splitWhitespace():
        if field.len > 0 and field[0].isDigit and '.' in field:
          result = field.strip(chars = {' ', ',', ';', ')', ']', ':'})
          return
  except CatchableError:
    discard
  result = ""

proc probeToolBinarySha256*(path: string): string {.raises: [CatchableError].} =
  ## Compute SHA-256 of a binary file. Returns "" on failure.
  if path.len == 0 or not fileExists(path):
    return ""
  result = hashFileContent(path)

proc probeToolchain*(bundleDir: string): JsonNode {.raises: [CatchableError], axiomEffect: IOEffect.} =
  ## Probe nim, z3, lean versions and binary sha256 digests.
  ## Returns a JSON object: {"tools": [...], "toolchain_digest": "..."}
  ## Each tool entry: {"tool": name, "version": ver, "path": exePath, "sha256": hash}
  ## Tools that cannot be resolved get version="<unresolved>".
  var tools: seq[JsonNode]
  let toolSpecs = @[
    ("nim", "nim --version"),
    ("z3", "z3 --version"),
    ("lean", "lean --version")
  ]
  for (name, cmd) in toolSpecs:
    let exePath = findExe(name)
    var ver = ""
    var sha = ""
    if exePath.len > 0:
      ver = probeToolVersion(name, cmd)
      sha = probeToolBinarySha256(exePath)
    else:
      ver = "<unresolved>"
    let entry = %*{
      "tool": name,
      "version": ver,
      "path": if exePath.len > 0: exePath else: "",
      "sha256": sha
    }
    tools.add(entry)
  # Sort tools by name for deterministic ordering
  tools.sort(proc(a, b: JsonNode): int = cmp(a["tool"].getStr(), b["tool"].getStr()))
  # Compute toolchain_digest: canonical form of sorted tool entries
  var tcPairs: seq[(string, string)]
  for t in tools:
    let pairs = @[
      ("path", t["path"].getStr()),
      ("sha256", t["sha256"].getStr()),
      ("tool", t["tool"].getStr()),
      ("version", t["version"].getStr())
    ]
    tcPairs.add((t["tool"].getStr(), canonicalSerialize(pairs)))
  tcPairs.sort(proc(a, b: (string, string)): int = cmp(a[0], b[0]))
  var tcLines: seq[string]
  for (_, line) in tcPairs:
    tcLines.add(line)
  let tcDigest = sha256Str(tcLines.join("\n"))
  result = %*{
    "tools": tools,
    "toolchain_digest": tcDigest
  }

# ---------------------------------------------------------------------------
# File hashing (1 MiB chunks)
# ---------------------------------------------------------------------------



# ---------------------------------------------------------------------------
# Posix helpers
# ---------------------------------------------------------------------------

func readLink*(path: string): string {.raises: [].} =
  ## Read a symbolic link target path. Returns "" on error.
  var buf: array[4096, char]
  let len = posix.readlink(path.cstring, cast[cstring](buf[0].addr), buf.len)
  if len <= 0: return ""
  result = $buf[0..<len]

proc lstatPath*(path: string): (bool, Stat) {.raises: [IOError].} =
  ## Run lstat on path; return (success, Stat buffer).
  var buf: Stat
  let ok = lstat(path, buf) == 0
  result = (ok, buf)

func mtimeNsFromStat*(buf: Stat): int64 {.raises: [].} =
  ## Extract mtime in nanoseconds from a Stat buffer.
  result = buf.st_mtim.tv_sec.int64 * 1_000_000_000.int64 +
           buf.st_mtim.tv_nsec.int64

func fileTypeFromMode*(mode: cint): string {.raises: [].} =
  ## Determine file type string from posix mode using S_IFMT.
  let kind = mode and S_IFMT
  if kind == S_IFREG: result = "REG"
  elif kind == S_IFDIR: result = "DIR"
  elif kind == S_IFLNK: result = "LNK"
  else: result = "UNKNOWN"

func isExecutable*(mode: cint): bool {.raises: [].} =
  ## Check if any execute bit is set in mode.
  result = (mode and 0o111) != 0

# ---------------------------------------------------------------------------
# Exclusion logic
# ---------------------------------------------------------------------------

func isExcluded*(path: string; excludedPrefixes: seq[string]): bool {.raises: [].} =
  ## Check if path should be excluded from the snapshot.
  result = path.startsWith(".git/")
  if not result:
    for prefix in excludedPrefixes:
      if path.startsWith(prefix):
        result = true
        break

# ---------------------------------------------------------------------------
# Git helpers
# ---------------------------------------------------------------------------

proc runGit*(repoRoot: string; args: seq[string]): (string, string, int) {.raises: [CatchableError].} =
  ## Run a git command in repoRoot and return (stdout, stderr, exitCode).
  let cmd = "git -C " & repoRoot & " " & args.join(" ")
  let (output, exitCode) = execCmdEx(cmd)
  result = (output, "", exitCode)

# ---------------------------------------------------------------------------
# Recursive directory walker with sorted children
# ---------------------------------------------------------------------------

proc walkDirSorted*(root: string): seq[string] {.raises: [CatchableError].} =
  ## Walk directory tree recursively, sorting children at each level.
  ## Returns all file and directory paths relative to root.
  var acc: seq[string]
  proc walk(dir: string) {.raises: [CatchableError].} =
    var dirEntries: seq[string]
    for entry in walkDir(dir):
      dirEntries.add(entry.path)
      if entry.kind == pcDir:
        walk(entry.path)
    dirEntries.sort()
    for path in dirEntries:
      acc.add(path)
  walk(root)
  result = acc

# ---------------------------------------------------------------------------
# File metadata collection
# ---------------------------------------------------------------------------

proc collectFileEntry*(path: string; repoRoot: string):
    (string, int64, int64, string, string, bool) {.raises: [CatchableError].} =
  ## Collect metadata for a single file. Returns
  ## (relPath, size, mtimeNs, sha256, fileType, tracked).
  let relPath = relativePath(path, repoRoot)
  var size: int64 = 0
  var mtime: int64 = 0
  var fType = "UNKNOWN"
  var exec = false
  var hash = ""

  let (ok, buf) = lstatPath(path)
  if ok:
    size = buf.st_size
    mtime = mtimeNsFromStat(buf)
    fType = fileTypeFromMode(cint(buf.st_mode))
    exec = isExecutable(cint(buf.st_mode))

  if fType == "LNK":
    # Symlink: hash the target path string (what git stores).
    try:
      let target = readLink(path)
      hash = sha256Str(target)
    except:
      hash = ""
  elif fType == "REG":
    hash = hashFileContent(path)
  elif fType == "DIR":
    hash = sha256Str("")
  # UNKNOWN and other types get empty hash

  # Append executable marker to file type if set
  if exec and fType == "REG":
    fType = "REG+X"
  elif exec and fType == "DIR":
    fType = "DIR+X"

  result = (relPath, size, mtime, hash, fType, true)

# ---------------------------------------------------------------------------
# Main freeze procedure (V3 identity model)
# ---------------------------------------------------------------------------

proc writePreSnapshot*(repoRoot, bundleDir: string; freezeTime: string)
    {.raises: [CatchableError], axiomEffect: IOEffect.} =
  ## Write `.pre_snapshot.json` inside the bundle: the (path,size,mtime) table of
  ## every repo file EXCEPT .git, the bundle dir and docs/audit (the declared
  ## approved mutation set). VERIFY-09 diffs the worktree against this to enforce
  ## the mutation boundary invariant.
  createDir(bundleDir)
  let relBundleDir = relativePath(bundleDir, repoRoot)
  var exclSet = initHashSet[string]()
  exclSet.incl(".git/")
  exclSet.incl("docs/audit/")
  if relBundleDir.len > 0 and relBundleDir != ".":
    exclSet.incl(relBundleDir & "/")
  var lines: seq[string]
  for p in walkDirSorted(repoRoot):
    if isExcluded(p, toSeq(exclSet)):
      continue
    try:
      var (ok, st) = lstatPath(p)
      if not ok or fileTypeFromMode(cint(st.st_mode)) == "DIR": continue
      # JSONL record per file — easy to parse deterministically
      let rec = %*{"p": $p, "s": st.st_size, "m": $mtimeNsFromStat(st)}
      lines.add($rec)
    except CatchableError:
      discard
  lines.sort()
  let (gitStatusRaw, _, _) = runGit(repoRoot, @["status", "--porcelain"])
  var gsArr = newJArray()
  for gline in gitStatusRaw.splitLines:
    if gline.len > 0: gsArr.add(%gline)
  var buf = ""
  buf.add($(%*{"schema": "audit-pre-snapshot/v1",
               "freeze_time": freezeTime,
               "entries": lines.len,
               "git_status": gsArr}) & "\n")
  for l in lines:
    buf.add(l)
    buf.add("\n")
  writeFile(bundleDir / ".pre_snapshot.json", buf)

proc freezeAuditBundle*(
    repoRoot: string
  , bundleDir: string
  , excludedPrefixes: seq[string]
  , rulesDigest: string
  , engineVersion: string
  , freezeTime: string
  , runId: string
  ): string {.raises: [CatchableError], axiomEffect: IOEffect.} =
  ## Deterministically freeze the repository into bundleDir.
  ## Returns the snapshot_id. Writes meta.json and files.jsonl.
  ## V3 identity model: snapshot_id uses freeze_time (not rulesDigest/engineVersion/auditDate).
  ## freezeTime is a frozen input (ISO UTC); runId is tracking-only (not in any hash).

  createDir(bundleDir)

  # Git HEAD
  let (gitHeadRaw, _, _) = runGit(repoRoot, @["rev-parse", "HEAD"])
  let gitHeadStr = gitHeadRaw.strip()

  # Dirty status
  let (gitStatusRaw, _, _) = runGit(repoRoot, @["status", "--porcelain"])
  let dirty = gitStatusRaw.strip().len > 0

  # Get tracked files via git ls-files -z
  let (trackedRaw, _, _) = runGit(repoRoot, @["ls-files", "-z"])
  let trackedPaths = trackedRaw.split('\0').filterIt(it.len > 0)

  # Get untracked files via git ls-files --others --exclude-standard -z
  let (untrackedRaw, _, _) = runGit(repoRoot,
      @["ls-files", "--others", "--exclude-standard", "-z"])
  let untrackedPaths = untrackedRaw.split('\0').filterIt(it.len > 0)

  # Build exclusion set: .git/, bundleDir relative, and excludedPrefixes
  let relBundleDir = relativePath(bundleDir, repoRoot)
  var exclSet = initHashSet[string]()
  exclSet.incl(".git/")
  if relBundleDir.len > 0 and relBundleDir != ".":
    exclSet.incl(relBundleDir & "/")
  for prefix in excludedPrefixes:
    exclSet.incl(prefix)

  # Filter tracked paths
  var filteredTracked: seq[string]
  for p in trackedPaths:
    if p in exclSet: continue
    var skip = false
    for prefix in exclSet:
      if p.startsWith(prefix):
        skip = true
        break
    if not skip:
      filteredTracked.add(p)

  # Filter untracked paths
  var filteredUntracked: seq[string]
  for p in untrackedPaths:
    if p in exclSet: continue
    var skip = false
    for prefix in exclSet:
      if p.startsWith(prefix):
        skip = true
        break
    if not skip:
      filteredUntracked.add(p)

  # Sort all paths deterministically
  filteredTracked.sort()
  filteredUntracked.sort()

  # Compute tracked_digest: sha256 of sorted tracked paths joined with "\n"
  var trackedConcat = ""
  for p in filteredTracked:
    trackedConcat.add(p & "\n")
  let trackedDigest = sha256Str(trackedConcat)

  # Process untracked files for digest
  var untrackedLines: seq[string]
  for p in filteredUntracked:
    let fullPath = repoRoot / p
    let (ok, buf) = lstatPath(fullPath)
    if not ok: continue
    let size = buf.st_size
    let fType = fileTypeFromMode(cint(buf.st_mode))
    let exec = isExecutable(cint(buf.st_mode))
    var hash = ""
    if fType == "LNK":
      try:
        let target = readLink(fullPath)
        hash = sha256Str(target)
      except:
        hash = ""
    elif fType == "REG":
      hash = hashFileContent(fullPath)
    elif fType == "DIR":
      hash = sha256Str("")
    untrackedLines.add(p & "\0" & $size & "\0" & hash & "\n")
  untrackedLines.sort()
  let untrackedDigest = sha256Str(untrackedLines.join(""))

  # Build file entries for all files (tracked + untracked)
  var allEntries: seq[(string, int64, int64, string, string, bool)]

  for p in filteredTracked:
    let fullPath = repoRoot / p
    let (ok, buf) = lstatPath(fullPath)
    if not ok: continue
    let size: int64 = buf.st_size.int64
    let mtime = mtimeNsFromStat(buf)
    let fType = fileTypeFromMode(cint(buf.st_mode))
    let exec = isExecutable(cint(buf.st_mode))
    var hash = ""
    if fType == "LNK":
      try:
        let target = readLink(fullPath)
        hash = sha256Str(target)
      except:
        hash = ""
    elif fType == "REG":
      hash = hashFileContent(fullPath)
    elif fType == "DIR":
      hash = sha256Str("")
    var ft = fType
    if exec and fType == "REG": ft = "REG+X"
    elif exec and fType == "DIR": ft = "DIR+X"
    allEntries.add((p, size, mtime, hash, ft, true))

  for p in filteredUntracked:
    let fullPath = repoRoot / p
    let (ok, buf) = lstatPath(fullPath)
    if not ok: continue
    let size: int64 = buf.st_size.int64
    let mtime = mtimeNsFromStat(buf)
    let fType = fileTypeFromMode(cint(buf.st_mode))
    let exec = isExecutable(cint(buf.st_mode))
    var hash = ""
    if fType == "LNK":
      try:
        let target = readLink(fullPath)
        hash = sha256Str(target)
      except:
        hash = ""
    elif fType == "REG":
      hash = hashFileContent(fullPath)
    elif fType == "DIR":
      hash = sha256Str("")
    var ft = fType
    if exec and fType == "REG": ft = "REG+X"
    elif exec and fType == "DIR": ft = "DIR+X"
    allEntries.add((p, size, mtime, hash, ft, false))

  # Sort all entries by path
  allEntries.sort(proc(a, b: (string, int64, int64, string, string, bool)): int =
    cmp(a[0], b[0]))

  # Write files.jsonl
  let filesJsonlPath = bundleDir / "files.jsonl"
  var filesJsonl = ""
  for entry in allEntries:
    let j = %*{
      "path": entry[0],
      "size": entry[1],
      "mtime_ns": entry[2],
      "sha256": entry[3],
      "file_type": entry[4],
      "tracked": entry[5]
    }
    filesJsonl.add($j & "\n")
  writeFile(filesJsonlPath, filesJsonl)

  # Compute files_observations_digest (sha256 over files.jsonl content)
  let filesObsDigest = sha256Str(filesJsonl)

  # Compute snapshot_id V3: "snap:" & sha256(canonical(git_head, tracked_tree_digest,
  # untracked_tree_digest, freeze_time)). Rules digest, engine version, and audit date
  # are NO LONGER part of the snapshot identity.
  let snapPairs = @[
    ("freeze_time", freezeTime),
    ("git_head", gitHeadStr),
    ("tracked_tree_digest", trackedDigest),
    ("untracked_tree_digest", untrackedDigest)
  ]
  let snapshotId = "snap:" & sha256Str(canonicalSerialize(snapPairs))

  # Probe toolchain (real versions + binary sha256)
  let tcNode = probeToolchain(bundleDir)

  # Write meta.json (V3 format)
  let meta = %*{
    "schema": "audit-meta/v1",
    "snapshot_id": snapshotId,
    "label": freezeTime[0 .. 9],  # YYYY-MM-DD portion for human readability
    "audit_date": freezeTime,
    "git_head": gitHeadStr,
    "git_status_dirty": dirty,
    "tracked_digest": trackedDigest,
    "untracked_digest": untrackedDigest,
    "files_observations_digest": filesObsDigest,
    "freeze_time": freezeTime,
    "run_id": runId,
    "toolchain": tcNode,
    "rule_catalog_digest": rulesDigest,
    "engine_version": engineVersion,
    "excluded": excludedPrefixes
  }
  let metaPath = bundleDir / "meta.json"
  writeFile(metaPath, $meta & "\n")

  result = snapshotId
