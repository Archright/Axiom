## CAS Promotion Engine — Git Plumbing Content-Addressable Storage promotion
## Reads JSON payload from stdin, creates git commit with promoted files.
## Supports crash recovery via --recover flag.
##
## Usage:
##   echo '{"v":"1.0","files":[...]}' | cas_promote
##   cas_promote --recover <commit_sha>
##
## Pipeline (promotion mode):
##   1. Parse JSON payload from stdin
##   2. Set GIT_INDEX_FILE to temp path (PID-isolated)
##   3. git read-tree HEAD → initialize index
##   4. For each file: base64 decode → SHA-256 verify → git hash-object → git update-index
##   5. git write-tree → tree SHA
##   6. git rev-parse HEAD → parent SHA
##   7. git commit-tree → commit SHA
##   8. git reset --hard → atomic filesystem write
##   9. posix.sync() → hardware write barrier
##  10. Cleanup temp index
##  11. Print commit SHA

import core/trusted/layer_declaration
import core/trusted/git_content_cas
axiomLayer "tools"
import std/[json, os, osproc, streams, base64, strutils, strformat, terminal]
import checksums/sha2

template axiomEffect*(e: untyped) {.pragma.}
type
  CasIoEffect* = object

type
  DebtStatus* = enum
    dsPromoted       = "PROMOTED"
    dsVerified       = "VERIFIED"
    dsFailed         = "FAILED"
    dsInductiveDebt  = "INDUCTION_DEBT"

# ---------------------------------------------------------------------------
# Types
# ---------------------------------------------------------------------------

type
  FileEntry = object
    path: string
    content: string  ## base64-encoded content
    hash: string     ## expected SHA-256 hex digest

  Payload = object
    version: string
    files: seq[FileEntry]

# ---------------------------------------------------------------------------
# Pure computations (func)
# ---------------------------------------------------------------------------

func computeSha256(data: string): string =
  ## Compute SHA-256 hex digest of data.
  var hasher = initSha_256()
  hasher.update(data)
  $hasher.digest()

func parseFileEntry(node: JsonNode): FileEntry =
  ## Parse a single file entry from JSON node.
  FileEntry(
    path: node["p"].getStr(),
    content: node["c"].getStr(),
    hash: node["h"].getStr()
  )

func parsePayload(node: JsonNode): Payload =
  ## Parse the full promotion payload from JSON.
  var files: seq[FileEntry]
  for item in node["files"]:
    files.add(parseFileEntry(item))
  Payload(version: node["v"].getStr(), files: files)

# ---------------------------------------------------------------------------
# I/O procs
# ---------------------------------------------------------------------------

proc fail(msg: string) {.noreturn.} =
  ## Print error to stderr and exit with code 1.
  stderr.writeLine("ERROR: ", msg)
  quit(1)

proc git(args: string): string =
  ## Execute git command, return trimmed stdout.
  try:
    result = execProcess("git " & args).strip()
  except CatchableError as e:
    fail("git command failed: " & args & " — " & e.msg)

proc gitWithStdin(args, input: string): string =
  ## Execute git command with piped stdin, return trimmed stdout.
  ## Uses startProcess + streams for proper stdin piping.
  var p: Process
  try:
    p = startProcess("git " & args, options = {poStdErrToStdOut, poUsePath, poEvalCommand})
    var inp = p.inputStream
    inp.write(input)
    inp.close()
    result = p.outputStream.readAll().strip()
    let exitCode = p.waitForExit()
    p.close()
    if exitCode != 0:
      fail("git command failed (exit " & $exitCode & "): " & args)
  except CatchableError as e:
    if p != nil: p.close()
    fail("git command failed: " & args & " — " & e.msg)

proc promoteToGitCAS*(content: string): string {.axiomEffect: CasIoEffect.} =
  ## Tool-side wrapper: keeps the CLI's fail-fast policy on the capability that
  ## now lives in src/core/trusted (so tests can reach it without importing
  ## tools/). See src/core/trusted/git_content_cas.nim.
  try:
    result = promoteContentToGitCAS(content)
  except CatchableError as e:
    fail("git hash-object failed: " & e.msg)

proc generateVerificationArtifact*(irName, leanCode, smtQuery: string; depth: int = 20; z3Result: string = "unsat"): string {.raises: [].} =
  result = "-- Axiom Z3 BMC verification artifact\n"
  result.add &"-- ir_name: {irName}\n"
  result.add &"-- z3_result: {z3Result}\n"
  result.add &"-- depth: {depth}\n\n"
  result.add "```lean\n"
  result.add leanCode
  if not leanCode.endsWith("\n"):
    result.add "\n"
  result.add "```\n\n"
  result.add "```smt2\n"
  result.add smtQuery
  if not smtQuery.endsWith("\n"):
    result.add "\n"
  result.add "```\n"

# ---------------------------------------------------------------------------
# POSIX sync — hardware write barrier
# ---------------------------------------------------------------------------

proc sync() {.importc, header: "<unistd.h>", discardable.}
  ## Force all buffered filesystem writes to disk.

# ---------------------------------------------------------------------------
# Promotion pipeline
# ---------------------------------------------------------------------------

proc promote(payload: Payload) =
  ## Execute CAS promotion pipeline.
  let pid = getCurrentProcessId()
  let indexFile = ".git/promotion_index_" & $pid

  defer:
    # Step 10: Cleanup temp index on any exit path
    if fileExists(indexFile):
      removeFile(indexFile)
    delEnv("GIT_INDEX_FILE")

  # Step 2: Isolate index via environment
  putEnv("GIT_INDEX_FILE", indexFile)

  # Step 3: Initialize index from current HEAD
  discard git("read-tree HEAD")

  # Step 4: Process each file in payload
  for entry in payload.files:
    # 4a: Base64 decode
    var decoded: string
    try:
      decoded = base64.decode(entry.content)
    except ValueError as e:
      fail("Base64 decode failed for '" & entry.path & "': " & e.msg)

    # 4b: SHA-256 verify — decoded content hash must match declared hash
    let actualHash = computeSha256(decoded)
    if actualHash != entry.hash:
      fail("SHA-256 mismatch for '" & entry.path & "': " &
           "expected=" & entry.hash & " actual=" & actualHash)

    # 4c: Write blob to git object store via stdin pipe
    let blobSha = gitWithStdin("hash-object -w --stdin", decoded)

    # 4d: Update index with new blob
    discard git("update-index --add --cacheinfo 100644 " & blobSha & " " & entry.path)

  # Step 5: Write tree from updated index
  let treeSha = git("write-tree")

  # Step 6: Get parent commit SHA
  let parentSha = git("rev-parse HEAD")

  # Step 7: Create commit object (message piped via stdin)
  let commitSha = gitWithStdin(
    "commit-tree " & treeSha & " -p " & parentSha,
    "feat: subagent CAS promotion\n"
  )

  # Step 8: Atomic filesystem write — the ONLY write to working tree
  discard git("reset --hard " & commitSha)

  # Step 9: Hardware write barrier — flush to physical media
  sync()

  echo commitSha

# ---------------------------------------------------------------------------
# Crash recovery
# ---------------------------------------------------------------------------

proc recover(sha: string) =
  ## Execute crash recovery — idempotent reset to given commit.
  discard git("reset --hard " & sha)
  sync()
  echo "RECOVERED: ", sha

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

proc main() =
  let params = commandLineParams()

  if params.len >= 2 and params[0] == "--recover":
    if params.len != 2:
      fail("Usage: cas_promote --recover <commit_sha>")
    recover(params[1])
  elif params.len == 0:
    if isatty(stdin):
      fail("cas_promote: no promotion payload on stdin\n" &
           "  Reads JSON promotion payload from stdin")
    let raw = readAll(stdin)
    if raw.len == 0:
      fail("cas_promote: empty promotion payload on stdin")
    let node = try:
      parseJson(raw)
    except JsonParsingError as e:
      fail("Invalid JSON payload: " & e.msg)
    promote(parsePayload(node))
  else:
    fail("Usage: cas_promote [--recover <commit_sha>]\n" &
         "  Reads JSON promotion payload from stdin")

when isMainModule:
  main()
