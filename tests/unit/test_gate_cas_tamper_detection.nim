## DEBT#524 unit test — CAS digest sidecar makes the reuse verdict fail-closed.
##
## Four verdicts, proven with real filesystem operations in a temp repoRoot:
##   (a) binary + matching sidecar            → HIT  (resolve returns the CAS path)
##   (b) binary bytes changed after the store → MISS + a tamper logError on the
##       production logging path
##   (c) binary without a sidecar             → MISS (sidecar-missing logError)
##   (d) malformed sidecar (wrong length / non-hex / uppercase) → MISS
##
## Oracle independence: every expected digest is computed by the coreutils
## `sha256sum` subprocess (std/osproc) — never by the production hash_kernel —
## so a broken production hasher cannot make this test pass vacuously.
## Tamper-log proof: the production logError path (logging_hub →
## logging_facade → stderr) is observed on the real filesystem by redirecting
## fd 2 (posix dup2) to a file during the resolve call and reading it back.
## Every MISS scenario starts from a machine-verified HIT state, so a MISS
## assertion can never pass because the entry was never a hit to begin with.

import std/[os, strutils, osproc]
import std/posix
import core/gate/gate_cas

proc sha256sumOracle(path: string): string =
  ## Independent digest oracle — coreutils sha256sum, NOT hash_kernel.
  let (outp, code) = execCmdEx("sha256sum " & quoteShell(path))
  if code != 0:
    raise newException(OSError, "sha256sum oracle failed (exit " & $code &
      ") for " & path & ": " & outp)
  let digest = outp.strip().split(' ')[0]
  if digest.len != 64 or not allCharsInSet(digest, {'0'..'9', 'a'..'f'}):
    raise newException(ValueError, "sha256sum oracle returned a malformed " &
      "digest for " & path & ": " & outp)
  digest

type StderrRedirect = tuple[fd: cint, saved: cint]

proc redirectStderrTo(logPath: string): StderrRedirect =
  discard tryRemoveFile(logPath)
  let fd = posix.open(cstring(logPath), posix.O_CREAT or posix.O_WRONLY or
    posix.O_TRUNC, 0o644)
  doAssert fd >= 0, "stderr-capture open failed: " & logPath
  let saved = posix.dup(2.cint)
  doAssert saved >= 0, "stderr-capture dup failed"
  doAssert posix.dup2(fd, 2.cint) >= 0, "stderr-capture dup2 failed"
  (fd: fd, saved: saved)

proc restoreStderr(r: StderrRedirect) =
  flushFile(stderr)
  doAssert posix.dup2(r.saved, 2.cint) >= 0, "stderr-capture restore failed"
  discard posix.close(r.fd)
  discard posix.close(r.saved)

type CasEntry = tuple[gateId, casBinary, sourceFile, sourceHash: string]

proc makeCasEntry(repoRoot, gateId, binaryBytes: string): CasEntry =
  ## Store a CAS entry the way the production pipeline addresses one: a fake
  ## gate source (its sha256sum is the source identity), the production
  ## resolveCasPath derives the CAS directory, and the binary bytes land at
  ## <casDir>/binary. The sidecar is NOT written here — each scenario owns it.
  let srcDir = repoRoot / "gate_src"
  createDir(srcDir)
  let sourceFile = srcDir / (gateId & ".nim")
  writeFile(sourceFile, "## fake gate source for " & gateId & "\n")
  let sourceHash = sha256sumOracle(sourceFile)
  let casBinary = resolveCasPath(gateId, sourceHash, repoRoot)
  doAssert casBinary.len > 0, "resolveCasPath returned no path for " & gateId
  createDir(casBinary.parentDir)
  writeFile(casBinary, binaryBytes)
  (gateId: gateId, casBinary: casBinary, sourceFile: sourceFile,
    sourceHash: sourceHash)

proc reuseVerdict(repoRoot: string; entry: CasEntry): string =
  ## The production reuse verdict (the precompile_gates resolve path).
  resolveCasBinaryPathWithHash(entry.gateId, entry.sourceFile, repoRoot,
    entry.sourceHash)

proc main() =
  var passed = 0
  var failed = 0

  template check(name: string, cond: bool) =
    if cond:
      inc passed
      echo "  PASS: " & name
    else:
      inc failed
      echo "  FAIL: " & name

  let base = getTempDir() / ("axiom_gate_cas_tamper_" & $getCurrentProcessId())
  if dirExists(base):
    removeDir(base)
  let repoRoot = base / "repo"
  createDir(repoRoot)
  let logRoot = base / "logs"
  createDir(logRoot)

  # ── (a) binary + matching sidecar → HIT ─────────────────────────────
  try:
    let entry = makeCasEntry(repoRoot, "vs524_hit", "AXIOM-CAS-BINARY-HIT-\x00\x01\x02")
    let oracleDigest = sha256sumOracle(entry.casBinary)
    let written = writeCasBinarySidecar(entry.casBinary)
    check "(a) production sidecar writer returns the oracle digest",
      written == oracleDigest
    check "(a) sidecar file content is <oracle digest> + newline",
      readFile(entry.casBinary & CasSidecarSuffix) == oracleDigest & "\n"
    check "(a) matching sidecar → reuse verdict HIT (CAS path returned)",
      reuseVerdict(repoRoot, entry) == entry.casBinary
  except CatchableError as e:
    inc failed
    echo "  FAIL: (a) unexpected exception: " & e.msg

  # ── (b) binary tampered after the store → MISS + tamper logError ────
  try:
    let entry = makeCasEntry(repoRoot, "vs524_tamper", "AXIOM-CAS-BINARY-TAMPER-ORIGINAL")
    discard writeCasBinarySidecar(entry.casBinary)
    check "(b) pre-tamper verdict is HIT (guards against vacuous MISS)",
      reuseVerdict(repoRoot, entry) == entry.casBinary
    writeFile(entry.casBinary, "AXIOM-CAS-BINARY-TAMPER-MUTATED-PAYLOAD")
    let logPath = logRoot / "tamper.log"
    let redir = redirectStderrTo(logPath)
    let verdict = reuseVerdict(repoRoot, entry)
    restoreStderr(redir)
    check "(b) tampered binary → reuse verdict MISS (empty string)",
      verdict == ""
    let captured = readFile(logPath)
    check "(b) tamper MISS is logged on the production logError path",
      "DEBT#524 TAMPER DETECTED" in captured and "vs524_tamper" in captured
  except CatchableError as e:
    inc failed
    echo "  FAIL: (b) unexpected exception: " & e.msg

  # ── (c) binary without a sidecar → MISS ─────────────────────────────
  try:
    let entry = makeCasEntry(repoRoot, "vs524_nosidecar", "AXIOM-CAS-BINARY-NO-SIDECAR")
    discard writeCasBinarySidecar(entry.casBinary)
    check "(c) with sidecar the verdict is HIT (guards against vacuous MISS)",
      reuseVerdict(repoRoot, entry) == entry.casBinary
    removeFile(entry.casBinary & CasSidecarSuffix)
    let logPath = logRoot / "nosidecar.log"
    let redir = redirectStderrTo(logPath)
    let verdict = reuseVerdict(repoRoot, entry)
    restoreStderr(redir)
    check "(c) sidecar-less binary → reuse verdict MISS (empty string)",
      verdict == ""
    let captured = readFile(logPath)
    check "(c) sidecar-less MISS is logged on the production logError path",
      "DEBT#524" in captured and "digest sidecar missing" in captured
  except CatchableError as e:
    inc failed
    echo "  FAIL: (c) unexpected exception: " & e.msg

  # ── (d) malformed sidecar (wrong length / non-hex / uppercase) → MISS
  try:
    let entry = makeCasEntry(repoRoot, "vs524_malformed", "AXIOM-CAS-BINARY-MALFORMED")
    let oracleDigest = sha256sumOracle(entry.casBinary)
    let sidecarPath = entry.casBinary & CasSidecarSuffix

    # verified-HIT baseline for this entry
    writeFile(sidecarPath, oracleDigest & "\n")
    check "(d) well-formed sidecar for the same entry is a HIT " &
      "(guards against vacuous MISS)", reuseVerdict(repoRoot, entry) == entry.casBinary

    let logPath = logRoot / "malformed.log"
    let redir = redirectStderrTo(logPath)
    # wrong length: 63 hex chars
    writeFile(sidecarPath, oracleDigest[0 ..< 63] & "\n")
    let missLen = reuseVerdict(repoRoot, entry)
    # non-hex: 64 chars outside the hex alphabet
    writeFile(sidecarPath, 'z'.repeat(64) & "\n")
    let missNonHex = reuseVerdict(repoRoot, entry)
    # uppercase hex: strict lowercase format contract
    writeFile(sidecarPath, oracleDigest.toUpperAscii() & "\n")
    let missUpper = reuseVerdict(repoRoot, entry)
    restoreStderr(redir)
    check "(d) wrong-length sidecar (63 hex chars) → MISS", missLen == ""
    check "(d) non-hex sidecar ('z' x 64) → MISS", missNonHex == ""
    check "(d) uppercase-hex sidecar → MISS (strict lowercase format)", missUpper == ""
    let captured = readFile(logPath)
    check "(d) malformed sidecars are logged on the production logError path",
      "malformed digest sidecar" in captured
  except CatchableError as e:
    inc failed
    echo "  FAIL: (d) unexpected exception: " & e.msg

  # ── (e) compile-layer reuse verdict shares the same guard ───────────
  # compileGateToCasWithHash with allowJit=false: an intact entry must be
  # returned as a compile skip (HIT); a tampered entry must fail closed to
  # "" with a CAS MISS log instead of silently reusing the binary.
  try:
    let entry = makeCasEntry(repoRoot, "vs524_compile", "AXIOM-CAS-BINARY-COMPILE-LAYER")
    discard writeCasBinarySidecar(entry.casBinary)
    let skipHit = compileGateToCasWithHash("vs524_compile", "bin/vs524_fake_entry",
      entry.sourceFile, entry.sourceHash, "", repoRoot, allowJit = false)
    check "(e) intact entry → compile-layer skip HIT (CAS path returned)",
      skipHit == entry.casBinary
    writeFile(entry.casBinary, "AXIOM-CAS-BINARY-COMPILE-TAMPERED")
    let logPath = logRoot / "compile_layer.log"
    let redir = redirectStderrTo(logPath)
    let skipMiss = compileGateToCasWithHash("vs524_compile", "bin/vs524_fake_entry",
      entry.sourceFile, entry.sourceHash, "", repoRoot, allowJit = false)
    restoreStderr(redir)
    check "(e) tampered entry → compile-layer fail-closed MISS (empty string)",
      skipMiss == ""
    let captured = readFile(logPath)
    check "(e) compile-layer tamper MISS is logged on the production logError path",
      "CAS MISS" in captured and "vs524_compile" in captured
  except CatchableError as e:
    inc failed
    echo "  FAIL: (e) unexpected exception: " & e.msg

  try:
    removeDir(base)
  except CatchableError:
    discard  # best-effort temp cleanup

  if failed > 0:
    echo "test_gate_cas_tamper_detection: " & $failed & " check(s) FAILED"
    quit(1)
  echo "test_gate_cas_tamper_detection: ALL " & $passed & " checks PASSED"

main()

