## Contract A read-only coherence gate + native source-tree hash route
## (`tools/hermetic_build.nim`: `--check-source-hash`, `--src-tree-hash`).
##
## Closes DEBT#532 (early `generateBuildEnv()` pass used to rewrite
## `src/generated/build_env.nim` before `checkSourceHash()` compared it,
## making the FAIL branch unreachable) and pins the 6-case contract:
##   C1 absent     — `build_env.nim` absent fails closed (exit 1,
##                   `reason=build_env-absent`, `embedded-empty=true`) and
##                   creates NO generated/cache files.
##   C2 clean      — coherent `build_env.nim` passes (exit 0).
##   C3 drift      — live source edit fails closed (exit 1,
##                   `embedded-empty=false`).
##   C4 zero-write — neither PASS nor FAIL alters `build_env.nim` inode,
##                   mtime_ns, or byte content.
##   C5 unreadable — unreadable source file exits 2 on BOTH
##                   `--check-source-hash` and `--src-tree-hash` with no
##                   unhandled exception / stacktrace (including root
##                   containers via `setpriv` UID drop).
##   C6 ipc-route  — `--src-tree-hash <out>` agrees byte-for-byte with the
##                   kernel `hashSourceContents`, overwrites any pre-existing
##                   stale file atomically (fresh inode), excludes
##                   `/generated/` directories, and includes `generated.nim`
##                   basenames outside `/generated/`.

import std/[unittest, os, osproc, strutils, times, posix]
import core/utils/build_provenance

proc findRepoRoot(): string =
  var dir = getCurrentDir()
  while true:
    if fileExists(dir / ".axiom_root"):
      return dir
    let parent = dir.parentDir()
    if parent == dir:
      break
    dir = parent
  raise newException(IOError, ".axiom_root not found from " & getCurrentDir())

proc ensureHermeticBuildBin(repoRoot, scratchDir: string): string =
  ## Compile `tools/hermetic_build.nim` from the live working tree into an
  ## isolated test binary so the suite always exercises the current source
  ## even when invoked under `AXIOM_HERMETIC_BUILDING=1` (`make test-fast`).
  let outBin = scratchDir / "hermetic_build_under_test"
  let nimCache = scratchDir / "nimcache_hb"
  let srcPath = repoRoot / "tools" / "hermetic_build.nim"
  let cmd = "AXIOM_HERMETIC_BUILDING=1 nim c --hints:off --warnings:off " &
            "--nimcache:" & quoteShell(nimCache) & " " &
            "-o:" & quoteShell(outBin) & " " & quoteShell(srcPath)
  let (output, rc) = execCmdEx(cmd, workingDir = repoRoot)
  if rc != 0:
    raise newException(IOError,
      "failed to compile tools/hermetic_build.nim (rc=" & $rc & "):\n" & output)
  discard chmod(outBin.cstring, 0o755)
  result = outBin

type
  FileStatSnap = tuple[ino: uint64, mtimeSec: int64, mtimeNsec: int64, content: string]

proc statSnap(path: string): FileStatSnap =
  var st: Stat
  if lstat(path.cstring, st) != 0:
    raise newException(IOError, "lstat failed for " & path)
  result.ino = uint64(st.st_ino)
  result.mtimeSec = int64(st.st_mtim.tv_sec)
  result.mtimeNsec = int64(st.st_mtim.tv_nsec)
  result.content = readFile(path)

proc newSandbox(baseDir, tag: string): string =
  result = baseDir / tag
  createDir(result / "src" / "sub")
  createDir(result / "src" / "generated")
  writeFile(result / ".axiom_root", "")
  writeFile(result / "src" / "alpha.nim", "let a* = 1\n")
  writeFile(result / "src" / "sub" / "beta.nim", "let b* = 2\n")
  writeFile(result / "src" / "generated" / "build_env.nim.default",
    "const\n  BuildSourceHash* = \"\"\n  VerifierBuildId* = \"unmeasured\"\n")
  discard chmod(result.cstring, 0o755)
  discard chmod((result / "src").cstring, 0o755)
  discard chmod((result / "src" / "sub").cstring, 0o755)
  discard chmod((result / "src" / "generated").cstring, 0o755)

proc runHb(hbBin, sandboxRoot: string; args: openArray[string];
           dropRootPrivs = false): tuple[output: string, exitCode: int] =
  var parts: seq[string] = @[]
  if dropRootPrivs and geteuid() == 0:
    parts.add("setpriv")
    parts.add("--reuid=65534")
    parts.add("--regid=65534")
    parts.add("--clear-groups")
  parts.add(quoteShell(hbBin))
  for a in args:
    parts.add(quoteShell(a))
  execCmdEx(parts.join(" "), workingDir = sandboxRoot)

suite "hermetic_build source-hash gate & native hash route (DEBT#532)":
  let repoRoot = findRepoRoot()
  let suiteDir = getTempDir() / ("axiom_hb_gate_" & $getCurrentProcessId() & "_" & $epochTime().int)
  createDir(suiteDir)
  discard chmod(suiteDir.cstring, 0o755)
  let hbBin = ensureHermeticBuildBin(repoRoot, suiteDir)

  test "C1 absent build_env.nim fails closed (exit 1) and writes no files":
    let sb = newSandbox(suiteDir, "c1_absent")
    defer: removeDir(sb)
    let buildEnv = sb / "src" / "generated" / "build_env.nim"
    let bodyCache = sb / ".axiom" / "cache" / "build_env.body"
    check not fileExists(buildEnv)

    let (outText, rc) = runHb(hbBin, sb, ["--check-source-hash"])
    check rc == 1
    check outText.contains("[build-coherence] FAIL")
    check outText.contains("reason=build_env-absent")
    check outText.contains("(embedded-empty=true)")
    check not outText.contains("generated (content changed)")
    check not fileExists(buildEnv)
    check not fileExists(bodyCache)

  test "C2/C3/C4 clean PASS, drift FAIL, and strict zero-write (inode + mtime_ns + content)":
    let sb = newSandbox(suiteDir, "c2_c3_c4")
    defer: removeDir(sb)
    let expected = hashSourceContents(@[
      (relPath: "alpha.nim", content: "let a* = 1\n"),
      (relPath: "sub/beta.nim", content: "let b* = 2\n"),
    ])
    let buildEnv = sb / "src" / "generated" / "build_env.nim"
    writeFile(buildEnv, "const\n  BuildSourceHash* = \"" & expected & "\"\n")

    let snapBeforePass = statSnap(buildEnv)
    let (passOut, passRc) = runHb(hbBin, sb, ["--check-source-hash"])
    let snapAfterPass = statSnap(buildEnv)
    check passRc == 0
    check passOut.contains("[build-coherence] PASS tree=" & expected & " embedded=" & expected)
    check snapBeforePass == snapAfterPass

    # Inject live source drift without regenerating build_env.nim (DEBT#532 reproducer)
    writeFile(sb / "src" / "alpha.nim", "let a* = 1\n# drift probe\n")
    let (driftOut, driftRc) = runHb(hbBin, sb, ["--check-source-hash"])
    let snapAfterDrift = statSnap(buildEnv)
    check driftRc == 1
    check driftOut.contains("[build-coherence] FAIL embedded=" & expected)
    check driftOut.contains("(embedded-empty=false)")
    check not driftOut.contains("generated (content changed)")
    check snapBeforePass == snapAfterDrift

  test "C5 unreadable source exits 2 with no stacktrace on both routes":
    let sb = newSandbox(suiteDir, "c5_unreadable")
    let secretFile = sb / "src" / "unreadable.nim"
    writeFile(secretFile, "let hidden* = 42\n")
    let buildEnv = sb / "src" / "generated" / "build_env.nim"
    writeFile(buildEnv, "const\n  BuildSourceHash* = \"vs1-tree-hash/1:0\"\n")
    discard chmod(secretFile.cstring, 0o000)
    defer:
      discard chmod(secretFile.cstring, 0o600)
      removeDir(sb)

    let (gateOut, gateRc) = runHb(hbBin, sb, ["--check-source-hash"], dropRootPrivs = true)
    check gateRc == 2
    check gateOut.contains("reason=unreadable-source")
    check not gateOut.contains("Traceback")
    check not gateOut.contains("unhandled exception")

    let outFile = sb / "hash_out.txt"
    let (hashOut, hashRc) = runHb(hbBin, sb, ["--src-tree-hash", outFile], dropRootPrivs = true)
    check hashRc == 2
    check hashOut.contains("[src-tree-hash] FAIL")
    check not hashOut.contains("Traceback")
    check not fileExists(outFile)

  test "C6 --src-tree-hash matches kernel, atomically replaces stale file, honors /generated/ filter":
    let sb = newSandbox(suiteDir, "c6_ipc")
    defer: removeDir(sb)
    # `src/generated/ignored.nim` MUST be excluded; `src/generated.nim` MUST be included.
    writeFile(sb / "src" / "generated" / "ignored.nim", "let ignored* = 99\n")
    writeFile(sb / "src" / "generated.nim", "let included* = 7\n")

    let expected = hashSourceContents(@[
      (relPath: "alpha.nim", content: "let a* = 1\n"),
      (relPath: "generated.nim", content: "let included* = 7\n"),
      (relPath: "sub/beta.nim", content: "let b* = 2\n"),
    ])

    let outFile = sb / "out with space.txt"
    writeFile(outFile, expected & "\n")
    let staleIno = statSnap(outFile).ino

    let (stdoutText, rc) = runHb(hbBin, sb, ["--src-tree-hash", outFile])
    check rc == 0
    check stdoutText.strip() == expected
    let freshSnap = statSnap(outFile)
    check freshSnap.content == expected & "\n"
    # Unconditional atomic rename replaces the file even when content matched,
    # proving pre-existing files are never passively reused.
    check freshSnap.ino != staleIno
    check not fileExists(sb / "src" / "generated" / "build_env.nim")

  removeDir(suiteDir)
