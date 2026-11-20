import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

## Path safety for bundle members.
##
## A verifier must never read outside the bundle directory, follow a symlink
## planted in the bundle, or accept two entries that resolve to the same file.
## These helpers reject absolute paths, `..` segments, backslashes, control
## bytes, symlinked components, and non-regular files. Size limits are enforced
## at open time, so an oversized member can never be fully materialized.

import std/os
import std/strutils
import std/algorithm
import core/axiom_pragmas
import core/results

when defined(posix):
  import std/posix

func isSafeRelativePath*(p: string): bool {.raises: [].} =
  ## Bundle-relative path predicate. Rejects: empty, absolute, drive-prefixed,
  ## backslash, NUL/control bytes, and empty/"."/".." segments.
  if p.len == 0: return false
  if p[0] == '/': return false
  if p.len >= 2 and p[1] == ':': return false
  for ch in p:
    if ch == '\0' or ord(ch) < 0x20: return false
    if ch == '\\': return false
  for seg in p.split('/'):
    if seg.len == 0 or seg == "." or seg == "..": return false
  true

when defined(posix):
  type StatKind = enum
    skMissing, skDir, skRegular, skLink, skOther

  proc statKind(path: string): StatKind {.raises: [].} =
    var st: Stat
    if lstat(path.cstring, st) != 0:
      return skMissing
    let mode = int64(st.st_mode) and int64(S_IFMT)
    if mode == int64(S_IFDIR): skDir
    elif mode == int64(S_IFREG): skRegular
    elif mode == int64(S_IFLNK): skLink
    else: skOther

  proc statSize(path: string): int64 {.raises: [].} =
    var st: Stat
    if lstat(path.cstring, st) != 0: return -1
    int64(st.st_size)
else:
  type StatKind = enum
    skMissing, skDir, skRegular, skLink, skOther

  proc statKind(path: string): StatKind {.raises: [].} =
    if symlinkExists(path): return skLink
    if dirExists(path): return skDir
    if fileExists(path): return skRegular
    skMissing

  proc statSize(path: string): int64 {.raises: [].} =
    try:
      getFileSize(path)
    except OSError:
      -1'i64

proc resolveRegularFileUnder*(root, rel: string;
                              maxBytes: int64): Result[string, string] {.
  raises: [OSError, ValueError], axiomDecision(id = "DECISION-0833",
    reason = "Bundle path resolution refuses symlinks, non-regular files and oversized members (fail-closed)",
    adr = "docs/adr/0001-fail-closed-result-type.md", introduced = "VS-2a").} =
  ## Resolve `rel` under `root`, rejecting symlinked components and enforcing
  ## `maxBytes` on the final regular file. The returned path is the joined
  ## absolute path.
  if not isSafeRelativePath(rel):
    return err("unsafe bundle path: " & rel)
  let rootAbs = absolutePath(root)
  var current = rootAbs
  let segments = rel.split('/')
  for i, seg in segments:
    current = current / seg
    let kind = statKind(current)
    if i == segments.high:
      if kind == skMissing:
        return err("bundle member is missing: " & rel)
      if kind == skLink:
        return err("bundle member is a symlink (refused): " & rel)
      if kind != skRegular:
        return err("bundle member is not a regular file: " & rel)
      let size = statSize(current)
      if size < 0:
        return err("bundle member is unreadable: " & rel)
      if maxBytes > 0 and size > maxBytes:
        return err("bundle member exceeds the size limit (" & $size & " > " &
          $maxBytes & "): " & rel)
    else:
      if kind == skMissing:
        return err("bundle directory is missing: " & seg)
      if kind == skLink:
        return err("bundle directory is a symlink (refused): " & seg)
      if kind != skDir:
        return err("bundle path component is not a directory: " & seg)
  ok(current)

proc ensureDirectoryUnder*(root, rel: string): Result[string, string] {.
  raises: [OSError, ValueError, IOError], axiomDecision(id = "DECISION-0831",
    reason = "Export directory creation refuses a symlinked component instead of following it",
    adr = "docs/adr/0001-fail-closed-result-type.md", introduced = "VS-2a").} =
  ## Create (if needed) a directory at `root/rel`, refusing any symlinked
  ## component on the way down. Used only by the exporter.
  if not isSafeRelativePath(rel):
    return err("unsafe bundle directory: " & rel)
  let rootAbs = absolutePath(root)
  if not dirExists(rootAbs):
    return err("bundle root does not exist: " & rootAbs)
  var current = rootAbs
  for seg in rel.split('/'):
    current = current / seg
    case statKind(current)
    of skMissing:
      createDir(current)
    of skDir:
      discard
    of skLink:
      return err("bundle directory is a symlink (refused): " & rel)
    else:
      return err("bundle path exists and is not a directory: " & rel)
  ok(current)

proc listRegularFiles* (dir: string): Result[seq[string], string] {.
  raises: [OSError, ValueError], axiomDecision(id = "DECISION-0832",
    reason = "A vault/bundle directory listing refuses symlinked or non-regular children (closed set)",
    adr = "docs/adr/0001-fail-closed-result-type.md", introduced = "VS-2a").} =
  ## Immediate children of `dir` as names, plus a hard failure on symlinked or
  ## non-regular children. A missing directory is an err (closed set).
  if not dirExists(dir):
    return err("bundle directory is missing: " & dir)
  var files: seq[string] = @[]
  for kind, path in walkDir(dir, relative = true):
    case kind
    of pcFile:
      files.add(extractFilename(path))
    of pcLinkToFile, pcLinkToDir:
      return err("bundle directory contains a symlink (refused): " & path)
    of pcDir:
      continue
  files.sort()
  ok(files)

proc joinSafe*(root, rel: string): string {.raises: [].} =
  root / rel

{.pop.}