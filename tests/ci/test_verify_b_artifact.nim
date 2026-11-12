## test_verify_b_artifact.nim — SL-08 binding-only verifier fail-closed 계약 테스트
##
## SL-08 (B/H binding): manifest build_sha == B ∧ per-file sha256 검증 —
## binding만 검사하며 build execution은 없다. 본 테스트는
## tools/ci/verify_b_artifact.sh의 exit-code 계약을 고정한다.
##
## 시나리오:
##   (a) happy path — build_sha == B ∧ 전 파일 sha256 일치 → exit 0
##   (b) per-file sha 불일치 (파일 변조) → exit 1 + sha256 mismatch
##   (c) build_sha 불일치 (B ≠ 실제) → exit 1 + build_sha
##   (d) manifest 누락 / artifact 파일 누락 → exit 1
##   (e) vacuous manifest (per-file 엔트리 0) → exit 1 (극장 방지)
##   (f) usage 오류 (인자 부족) → exit 2
##
## fixture는 임시 디렉토리(/tmp)에서 만들며 작업 저장소를 건드리지 않는다.

import std/[unittest, os, osproc, strutils]

const
  FakeB = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  OtherB = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
  ManifestName = "manifest.txt"

proc repoRootOf(): string =
  ## 테스트가 놓인 저장소 루트 (tests/ci/ → 저장소 루트).
  result = absolutePath(currentSourcePath())
  for _ in 0 ..< 3:
    result = result.parentDir()

proc sha256Of(path: string): string =
  let (outp, code) = execCmdEx("sha256sum " & quoteShell(path))
  doAssert code == 0, "sha256sum 실패: " & outp
  result = outp.splitWhitespace()[0]

proc makeFixture(): tuple[root, manifest: string] =
  ## bin/ax + ircheck 유사 fixture (빌드 없이 텍스트 파일) + 정상 manifest.
  let root = getTempDir() / "sl08_fix_" & $getCurrentProcessId()
  createDir(root)
  let files = @[
    ("bin/ax", "#!/bin/sh\necho fake ax\n"),
    ("bin/install_ax_cas", "#!/bin/sh\necho fake cas\n"),
    ("proofs/.lake/build/bin/ircheck", "fake ircheck\n"),
  ]
  var lines = @["# Axiom admission-check base-built artifact manifest",
                "build_sha = " & FakeB,
                "recipe_id = fixture@sha"]
  for (rel, content) in files:
    let full = root / rel
    createDir(parentDir(full))
    writeFile(full, content)
    lines.add(sha256Of(full) & "  " & rel)
  let manifest = root / ManifestName
  writeFile(manifest, lines.join("\n") & "\n")
  result = (root, manifest)

proc runVerifier(manifest, expectB, root: string, verifier = "tools/ci/verify_b_artifact.sh"): tuple[output: string, exitCode: int] =
  let cmd = "bash " & quoteShell(repoRootOf() / verifier) & " " &
            quoteShell(manifest) & " " & quoteShell(expectB) & " " & quoteShell(root)
  result = execCmdEx(cmd)

suite "SL-08 binding-only verifier (verify_b_artifact.sh) 계약":

  test "happy path — build_sha == B ∧ 전 파일 sha256 일치 → exit 0":
    let (root, manifest) = makeFixture()
    defer: removeDir(root)
    let r = runVerifier(manifest, FakeB, root)
    check r.exitCode == 0
    check "MANIFEST VERIFIED: verifier is built from B=" & FakeB in r.output
    check "OK: bin/ax (B-built)" in r.output
    check "OK: proofs/.lake/build/bin/ircheck (B-built)" in r.output

  test "per-file sha 불일치 (파일 변조) → exit 1 + sha256 mismatch":
    let (root, manifest) = makeFixture()
    defer: removeDir(root)
    writeFile(root / "bin/ax", "#!/bin/sh\necho TAMPERED\n")
    let r = runVerifier(manifest, FakeB, root)
    check r.exitCode != 0
    check "sha256 mismatch for bin/ax" in r.output

  test "build_sha 불일치 (B ≠ 실제) → exit 1 + build_sha":
    let (root, manifest) = makeFixture()
    defer: removeDir(root)
    let r = runVerifier(manifest, OtherB, root)
    check r.exitCode != 0
    check "manifest build_sha=" & FakeB & " != B=" & OtherB in r.output

  test "manifest 누락 → exit 1":
    let (root, manifest) = makeFixture()
    defer: removeDir(root)
    let r = runVerifier(root / "no-such-manifest.txt", FakeB, root)
    check r.exitCode != 0
    check "manifest missing" in r.output

  test "artifact 파일 누락 (manifest에만 존재) → exit 1":
    let (root, manifest) = makeFixture()
    defer: removeDir(root)
    removeFile(root / "proofs/.lake/build/bin/ircheck")
    let r = runVerifier(manifest, FakeB, root)
    check r.exitCode != 0
    check "artifact file missing: proofs/.lake/build/bin/ircheck" in r.output

  test "vacuous manifest (per-file 엔트리 0) → exit 1 (극장 방지)":
    let root = getTempDir() / "sl08_vac_" & $getCurrentProcessId()
    defer: removeDir(root)
    createDir(root)
    writeFile(root / ManifestName,
      "# Axiom admission-check base-built artifact manifest\n" &
      "build_sha = " & FakeB & "\n" &
      "recipe_id = fixture@sha\n")
    let r = runVerifier(root / ManifestName, FakeB, root)
    check r.exitCode != 0
    check "no per-file sha256 entries (vacuous binding)" in r.output

  test "usage 오류 (인자 부족) → exit 2":
    let (root, manifest) = makeFixture()
    defer: removeDir(root)
    let (outp, code) = execCmdEx("bash " & quoteShell(repoRootOf() / "tools/ci/verify_b_artifact.sh"))
    check code == 2
    check "usage:" in outp

  test "경로 이탈 manifest (../ 탈출) → exit 1":
    let (root, manifest) = makeFixture()
    defer: removeDir(root)
    # manifest가 루트 밖 파일을 결속하면 binding 오류
    let evil = root / ".." / ("sl08_evil_" & $getCurrentProcessId())
    writeFile(evil, "evil\n")
    let m2 = root / "escape.txt"
    writeFile(m2, "# manifest\n" & "build_sha = " & FakeB & "\n" &
      sha256Of(evil) & "  ../" & extractFilename(evil) & "\n")
    let r = runVerifier(m2, FakeB, root)
    check r.exitCode != 0
    check "escapes artifact root" in r.output
    removeFile(evil)