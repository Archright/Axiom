## tests/unit/test_make_probe_integration.nim
##
## Tier-2 integration: the native `make -n` tri-state probe
## (`tools/ci/doc_path_validator.probeMakeTarget`). Unlike the pure core test,
## this exercises the REAL subprocess adapter end-to-end so the EXISTS / ABSENT /
## PROBE-ERROR classification is proven against GNU Make on the actual machine,
## with `LC_ALL=C` pinned for locale-independent "No rule to make target" text.
##
##   EXISTS      — a real committed Makefile target (`audit-dir-doc`)
##   ABSENT      — a target that is NOT in the repo Makefile (`def-invented-xyz`)
##   PROBE-ERROR — a Makefile whose rule needs a MISSING prerequisite; make fails
##                 EXIT=2 naming the PREREQUISITE (a different name than the
##                 requested target) → must NOT collapse to ABSENT (fail-closed)
##
## The EXISTS/ABSENT probes depend on the committed `tools/../Makefile` targets
## being present; the PROBE-ERROR case builds its own throwaway Makefile in a
## temp dir so it is self-contained.

import std/[unittest, os, osproc, strutils]

import ci/doc_path_validator_core
import ci/doc_path_validator

proc repoRoot(): string =
  ## Resolve the repository root from this test file (tests/unit/… → repo root).
  ## currentSourcePath() is absolute; walk up from its dir to the Makefile.
  var dir = currentSourcePath().parentDir()   # tests/unit
  dir = dir / ".." / ".."                     # repo root
  result = dir.normalizedPath()

let ROOT = repoRoot()

suite "make probe integration (real subprocess)":
  test "EXISTS — committed target `audit-dir-doc` is probed as tpExists":
    let r = probeMakeTarget(ROOT, "make audit-dir-doc")
    check r == tpExists

  test "ABSENT — non-existent target `def-invented-xyz` is probed as tpAbsent":
    let r = probeMakeTarget(ROOT, "make def-invented-xyz")
    check r == tpAbsent

  test "PROBE-ERROR — missing prerequisite (different name) is NOT collapsed to absent":
    let tmp = getTempDir() / "ax_make_probe_" & $getCurrentProcessId()
    createDir(tmp)
    defer: removeDir(tmp)
    writeFile(tmp / "Makefile",
      "probe_missing_prereq: probe_missing_file.tmp\n\t@true\n")
    # requested target exists as a rule, but its prerequisite file is missing →
    # make prints "No rule to make target 'probe_missing_file.tmp'" (DIFFERENT
    # name) → validator must return tpProbeError, never tpAbsent (fail-closed).
    let r = probeMakeTarget(tmp, "make probe_missing_prereq")
    check r == tpProbeError

  test "PROBE-ERROR — malformed target identity (not 'make <name>') is tpProbeError":
    let r = probeMakeTarget(ROOT, "audit-dir-doc")   # missing "make " prefix
    check r == tpProbeError
