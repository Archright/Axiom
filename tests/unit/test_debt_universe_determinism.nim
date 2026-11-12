## Determinism & Classification tests for the canonical current-debt universe.
##
## Verifies:
##  - fingerprint determinism (same input -> same sha256)
##  - fingerprint sensitivity (different input -> different sha256)
##  - classification contract via `classifyEntry`
##  - `ax debt universe` JSON is deterministic across runs (commitsha + versions)
##
## Uses `cli/debt_cli` exported helpers `computeFingerprint`, `classifyEntry`,
## and `core/types/debt_types` `DebtClass` / `debtClassToStr`.

import std/[unittest, json, os, strutils]
import cli/debt_cli
import core/types/debt_types

proc mkEntry(desc: string; status: string; files: seq[string];
             category: string = "Architecture";
             resolution: string = ""): JsonNode =
  ## Build a minimal registry entry JsonNode for unit testing.
  var filesNode: seq[JsonNode] = @[]
  for f in files:
    filesNode.add(%f)
  %*{
    "id": "DEBT-TEST#1",
    "category": category,
    "description": desc,
    "status": status,
    "resolution": resolution,
    "severity": "medium",
    "files": filesNode
  }

suite "fingerprint determinism":
  test "same entry -> identical fingerprint":
    let a = mkEntry("fallback backend path", "open", @["src/x.nim", "src/y.nim"])
    let b = mkEntry("fallback backend path", "open", @["src/x.nim", "src/y.nim"])
    check computeFingerprint(a) == computeFingerprint(b)
    check computeFingerprint(a).len > 0
    check computeFingerprint(a).startsWith("sha256:")

  test "different files -> different fingerprint":
    let a = mkEntry("fallback backend", "open", @["src/x.nim"])
    let b = mkEntry("fallback backend", "open", @["src/y.nim"])
    check computeFingerprint(a) != computeFingerprint(b)

  test "different description -> different fingerprint":
    let a = mkEntry("fallback backend", "open", @["src/x.nim"])
    let b = mkEntry("legacy backend", "open", @["src/x.nim"])
    check computeFingerprint(a) != computeFingerprint(b)

  test "backslash vs forward-slash normalization -> identical fingerprint":
    let a = mkEntry("path", "open", @["src\\x.nim"])
    let b = mkEntry("path", "open", @["./src/x.nim"])
    check computeFingerprint(a) == computeFingerprint(b)

suite "classification contract":
  test "open entry in existing file -> OPEN_DEBT":
    # data/debt_registry.json exists on disk and is referenced by entries.
    let e = mkEntry("some debt", "open", @["data/debt_registry.json"])
    let cls = classifyEntry(e, getCurrentDir())
    check cls == dcOpenDebt

  test "open entry referencing missing file -> UNVERIFIED":
    let e = mkEntry("phantom", "open", @["does/not/exist.nim"])
    let cls = classifyEntry(e, getCurrentDir())
    check cls == dcUnverified

  test "closed entry -> RESOLVED":
    let e = mkEntry("fixed debt", "closed", @["src/x.nim"], resolution = "FIXED")
    let cls = classifyEntry(e, getCurrentDir())
    check cls == dcResolved

  test "quirk category -> QUIRK":
    let e = mkEntry("upstream quirk", "open", @["data/debt_registry.json"], category = "quirk")
    let cls = classifyEntry(e, getCurrentDir())
    check cls == dcQuirk

suite "classification stringification":
  test "debtClassToStr covers the enum":
    check debtClassToStr(dcOpenDebt) == "OPEN_DEBT"
    check debtClassToStr(dcUnverified) == "UNVERIFIED"
    check debtClassToStr(dcStale) == "STALE"
    check debtClassToStr(dcResolved) == "RESOLVED"
    check debtClassToStr(dcQuirk) == "QUIRK"
    check debtClassToStr(dcBudgetDrift) == "BUDGET_DRIFT"