{.push raises: [CatchableError].}

## test_english_audit_inventory.nim — Phase 1 inventory contract test.
##
## Builds tools/ci/english_audit_inventory.nim through the production nim
## invocation and runs it against an isolated temp git repository. The fixture
## pins the classification contract:
##   * one Korean text file          -> matched, 1 line / 5 code points
##   * one English-only text file    -> scanned, not matched
##   * one NUL-containing binary     -> binarySkipped, never silently passed
##   * one empty text file           -> scanned, not matched
##   * data/i18n/ko.json             -> separate koJson block, not in totals
##   * vendor/skip.txt               -> excluded by the exact prefix rule
##   * ignored.txt (tracked, ignored)-> included and reported gitIgnored=true
## A second commit adds invalid UTF-8, which must produce exit 2 UNKNOWN while
## still writing the factual report. Two runs to different --out paths must be
## byte-identical (no time- or path-dependent content).

import std/[algorithm, json, os, osproc, strutils, unittest]

const
  ## UTF-8 bytes of Hangul syllables, written as escapes so this test source
  ## stays free of non-ASCII literals.
  KoreanHello = "\xEC\x95\x88\xEB\x85\x95\xED\x95\x98\xEC\x84\xB8\xEC\x9A\x94"
  KoreanOne = "\xEC\x95\x88"

let
  RepoRoot = block:
    var dir = currentSourcePath().parentDir()
    while dir.len > 0 and not fileExists(dir / ".axiom_root"):
      let parent = dir.parentDir()
      if parent == dir: break
      dir = parent
    dir
  TempRoot = getTempDir() / ("axiom_english_inventory_" & $getCurrentProcessId())
  Fixture = TempRoot / "repo"
  ToolBin = TempRoot / "english_audit_inventory"

proc mustRun(cmd, workDir: string): string =
  let outcome = execCmdEx(cmd, workingDir = workDir)
  if outcome.exitCode != 0:
    raise newException(IOError, "command failed (" & $outcome.exitCode & "): " &
      cmd & "\n" & outcome.output)
  result = outcome.output

proc buildTool() =
  createDir(TempRoot)
  let cmd = "nim c --hints:off --path:. --path:src " &
    "--nimcache:" & quoteShell(TempRoot / "nimcache") & " " &
    "-o:" & quoteShell(ToolBin) & " " &
    quoteShell(RepoRoot / "tools/ci/english_audit_inventory.nim")
  discard mustRun(cmd, RepoRoot)

proc pinnedRg(): string =
  let fromEnv = getEnv("AXIOM_RG")
  if fromEnv.len > 0: fromEnv else: "/tmp/rgpin/rg"

proc runTool(outPath: string): tuple[output: string, exitCode: int] =
  putEnv("AXIOM_RG", pinnedRg())
  execCmdEx(quoteShell(ToolBin) & " --base HEAD --out " &
    quoteShell(outPath) & " --check", workingDir = Fixture)

proc write(path, content: string) =
  createDir(path.parentDir())
  writeFile(path, content)

proc initFixture() =
  if dirExists(TempRoot): removeDir(TempRoot)
  createDir(Fixture)
  discard mustRun("git init -q", Fixture)
  discard mustRun("git config user.email test@example.com", Fixture)
  discard mustRun("git config user.name test", Fixture)
  write(Fixture / ".gitignore", "ignored.txt\n")
  write(Fixture / "english.txt", "plain english line\n")
  write(Fixture / "korean.txt", "title\n" & KoreanHello & "\n")
  write(Fixture / "ignored.txt", KoreanOne & "\n")
  write(Fixture / "empty.txt", "")
  write(Fixture / "binary.bin", "\x00\x01\x02\xFF")
  write(Fixture / "vendor/skip.txt", KoreanHello & "\n")
  write(Fixture / "data/i18n/ko.json",
        "{\n  \"word\": \"" & KoreanHello & "\"\n}\n")
  discard mustRun("git add -A", Fixture)
  discard mustRun("git add -f ignored.txt vendor/skip.txt", Fixture)
  discard mustRun("git commit -qm fixture", Fixture)

suite "english audit inventory":
  test "fixture totals, exclusions, koJson separation, determinism":
    if not fileExists(pinnedRg()):
      skip()
    else:
      initFixture()
      buildTool()

      let firstPath = TempRoot / "first.json"
      let firstRun = runTool(firstPath)
      check firstRun.exitCode == 0
      check "check OK" in firstRun.output
      check fileExists(firstPath)

      let report = parseFile(firstPath)
      let totals = report["totals"]
      check totals["scannedFiles"].getInt() == 5
      check totals["binarySkipped"].getInt() == 1
      check totals["invalidUtf8"].getInt() == 0
      check totals["unknownFiles"].getInt() == 0
      check totals["matchedFiles"].getInt() == 2
      check totals["matchedFilesWithFindings"].getInt() == 2
      check totals["matchedLines"].getInt() == 2
      check totals["codePoints"].getInt() == 6
      check totals["emptyTextFiles"].getInt() == 1
      check totals["gitIgnoredTrackedTextFiles"].getInt() == 1
      check totals["gitIgnoredMatchedFiles"].getInt() == 1
      check totals["gitIgnoredMatchedLines"].getInt() == 1
      check totals["gitIgnoredCodePoints"].getInt() == 1

      let ko = report["koJson"]
      check ko["path"].getStr() == "data/i18n/ko.json"
      check ko["codePoints"].getInt() == 5
      check ko["matchedLines"].getInt() == 1
      check ko["totalLines"].getInt() == 3

      var paths: seq[string] = @[]
      var ignoredMatched = false
      for entry in report["perFile"]:
        let path = entry["path"].getStr()
        paths.add path
        check entry["text"].getBool()
        check entry["utf8"].getBool()
        check entry["findingsCount"].getInt() == entry["matchedLines"].getInt()
        if path == "ignored.txt":
          ignoredMatched = true
          check entry["gitIgnored"].getBool()
          check entry["matchedLines"].getInt() == 1
      check paths == sorted(paths)
      check "vendor/skip.txt" notin paths
      check "data/i18n/ko.json" notin paths
      check "binary.bin" notin paths
      check ignoredMatched

      let firstBytes = readFile(firstPath)
      let secondPath = TempRoot / "second.json"
      let secondRun = runTool(secondPath)
      check secondRun.exitCode == 0
      check readFile(secondPath) == firstBytes

      # Invalid UTF-8 is UNKNOWN: the factual report is still written, exit 2.
      write(Fixture / "bad.txt", "\xFF\n")
      discard mustRun("git add bad.txt", Fixture)
      discard mustRun("git commit -qm bad-utf8", Fixture)
      let badPath = TempRoot / "bad.json"
      let badRun = runTool(badPath)
      check badRun.exitCode == 2
      check fileExists(badPath)
      let badTotals = parseFile(badPath)["totals"]
      check badTotals["invalidUtf8"].getInt() == 1
      check badTotals["unknownFiles"].getInt() == 1
      check badTotals["scannedFiles"].getInt() == 6

      if dirExists(TempRoot): removeDir(TempRoot)