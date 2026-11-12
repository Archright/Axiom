{.push raises: [CatchableError].}

## Cert Fingerprinter Tests — Unit tests for verification/cert_fingerprinter.nim
## Tests fingerprintFunction with real .nim files on disk.

import std/[unittest, os, strutils, times]
import verification/cert_fingerprinter

# ---------------------------------------------------------------------------
# fingerprintFunction
# ---------------------------------------------------------------------------

suite "fingerprintFunction":
  test "returns non-empty fingerprint for valid source":
    let tmpDir = getTempDir() / "axiom_test_fpf_" & $epochTime().int
    createDir(tmpDir)
    defer: removeDir(tmpDir)
    let srcPath = tmpDir / "sample.nim"
    writeFile(srcPath, "func myFunc*(x: int): int =\n  x + 1\n")
    let (fingerprint, body) = fingerprintFunction(srcPath, "myFunc")
    check fingerprint.len > 0
    check body.len > 0

  test "fingerprint is deterministic":
    let tmpDir = getTempDir() / "axiom_test_fpf_det_" & $epochTime().int
    createDir(tmpDir)
    defer: removeDir(tmpDir)
    let srcPath = tmpDir / "det.nim"
    writeFile(srcPath, "func foo(): string = \"hello\"\n")
    let (fp1, _) = fingerprintFunction(srcPath, "foo")
    let (fp2, _) = fingerprintFunction(srcPath, "foo")
    check fp1 == fp2

  test "different sources produce different fingerprints":
    let tmpDir = getTempDir() / "axiom_test_fpf_diff_" & $epochTime().int
    createDir(tmpDir)
    defer: removeDir(tmpDir)
    let src1 = tmpDir / "a.nim"
    let src2 = tmpDir / "b.nim"
    writeFile(src1, "func foo(): int = 1\n")
    writeFile(src2, "func foo(): int = 2\n")
    let (fp1, _) = fingerprintFunction(src1, "foo")
    let (fp2, _) = fingerprintFunction(src2, "foo")
    check fp1 != fp2

  test "body contains source when function not extracted":
    let tmpDir = getTempDir() / "axiom_test_fpf_body_" & $epochTime().int
    createDir(tmpDir)
    defer: removeDir(tmpDir)
    let srcPath = tmpDir / "full.nim"
    let content = "let x = 42\nlet y = x + 1\n"
    writeFile(srcPath, content)
    let (_, body) = fingerprintFunction(srcPath, "nonexistent_func")
    # When function not found, body falls back to source content (up to 2000 chars)
    check body.len > 0
    check "42" in body

  test "non-existent file returns empty body and hash fingerprint":
    let (fingerprint, body) = fingerprintFunction("/nonexistent/file.nim", "foo")
    check fingerprint.len > 0  # fingerprint is still computed
    check body.len == 0

  test "large source truncates body to 2000 chars":
    let tmpDir = getTempDir() / "axiom_test_fpf_large_" & $epochTime().int
    createDir(tmpDir)
    defer: removeDir(tmpDir)
    let srcPath = tmpDir / "large.nim"
    var bigContent = ""
    for i in 0 ..< 3000:
      bigContent.add("x")
    writeFile(srcPath, bigContent)
    let (_, body) = fingerprintFunction(srcPath, "nonexistent")
    check body.len <= 2000

{.pop.}
