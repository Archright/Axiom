## test_preflight_script_scan.nim -- unit fixtures for tools/ci/preflight_script_scan.nim.
##
## Uses ASCII-only string escapes for non-ASCII UTF-8 test fixtures so this file
## itself never trips the added-lines script-scan policy.

import std/[strutils, unittest]

import ../../tools/ci/preflight_script_scan
import ../../src/core/results

suite "preflight_script_scan pure core":
  test "isHexSha validates 40-hex commits":
    check isHexSha("06e569fd3d5b20e2816f54794a0ef822878f4b20")
    check not isHexSha("06e569fd")
    check not isHexSha("06e569fd3d5b20e2816f54794a0ef822878f4b2g")

  test "semverAtLeast compares major.minor.patch":
    check semverAtLeast("14.1.0", "14.1.0")
    check semverAtLeast("2.43.0", "2.35.0")
    check not semverAtLeast("14.0.9", "14.1.0")
    check not semverAtLeast("invalid", "1.0.0")

  test "isValidUtf8 accepts valid UTF-8 and rejects overlong/truncated":
    check isValidUtf8("plain ascii")
    # UTF-8 for Hangul U+ACC4 U+D68D ("gye-hoek")
    check isValidUtf8("\xEA\xB3\x84\xED\x9A\x8D")
    # Truncated 3-byte sequence and invalid continuation
    check not isValidUtf8("\xEA\xB3")
    check not isValidUtf8("\xFF\xFE")
    # Overlong 2-byte encoding of '/'
    check not isValidUtf8("\xC0\xAF")

  test "isQuotedOrAmbiguous flags git-quoted or spaced paths":
    check not isQuotedOrAmbiguous("tools/ci/preflight_script_scan.nim")
    check isQuotedOrAmbiguous("\"quoted/path\"")
    check isQuotedOrAmbiguous("path with space.nim")
    check isQuotedOrAmbiguous("dir\\escape.nim")

  test "parseDiff keeps only added lines and ignores deletions":
    let sample = """diff --git Makefile Makefile
index 1111111..2222222 100644
--- Makefile
+++ Makefile
@@ -10,3 +10,3 @@
 unchanged
-removed pre-existing text \xEA\xB3\x84
+touched line \xEA\xB3\x84
"""
    let secs = parseDiff(sample)
    check secs.len == 1
    check secs[0].newPath == "Makefile"
    check secs[0].additions.len == 1
    check secs[0].additions[0].lineNo == 11
    check secs[0].additions[0].content.startsWith("touched line")

  test "parseDiff marks rename, binary, and submodule sections":
    let sample = """diff --git a/old.txt b/new.txt
similarity index 100%
rename from old.txt
rename to new.txt
diff --git a/blob.bin b/blob.bin
Binary files a/blob.bin and b/blob.bin differ
diff --git a/sub b/sub
Submodule sub 0000000..1111111:
"""
    let secs = parseDiff(sample)
    check secs.len == 3
    check secs[0].isRename
    check secs[0].renameFrom == "old.txt"
    check secs[0].renameTo == "new.txt"
    check secs[1].isBinary
    check secs[2].submoduleLog

  test "loadPolicy reads canonical script-scan-policy.yml":
    let pol = loadPolicy("compliance/policy/script-scan-policy.yml")
    check pol.isOk
    check pol.get.allowedScripts == @["Latin", "Greek", "Common", "Inherited"]
    check pol.get.ripgrepVersion == "14.1.0"
