## test_nimble_pkg_path_failclosed.nim - DEBT#509 fail-closed contract
##
## Subject: the Nimble package paths that feed NIM_TOOL_FLAGS
## (ci/checker.mk CHECKSUMS_PATH / FUSION_PATH, consumed by both
## `make -f ci/checker.mk <target>` and the Makefile targets).
##
## Defect (measured 2026-10-27, registry DEBT#509):
## `CHECKSUMS_PATH := $(wildcard $(NIMBLE_PKGS)/checksums-*)` expands to the
## EMPTY STRING when the package is absent. Interpolated as
## `--path:$(CHECKSUMS_PATH)` that is a no-op for the Nim compiler, so a
## missing dependency could not fail closed at the argument layer and the
## compile died later with a misleading `cannot open file: checksums/sha2`.
##
## Contract pinned here (both directions - a guard that rejects the healthy
## input is a dead gate sec.0.8, one that accepts the broken input is theater
## sec.0.9):
##
##   (a) absent package  -> non-zero make exit AND a message naming the
##       missing package and its install command; no empty `--path:` argument
##       is ever emitted;
##   (b) present package -> exit 0 and the resolved directory appears as
##       `--path:<dir>` (the normal single-match case keeps working);
##   (c) the guard is immediate: with a package absent, EVERY target of both
##       entry points aborts while the makefile is parsed, including targets
##       that never compile. That is deliberate - NIM_TOOL_FLAGS stays an
##       immediately-expanded variable because .githooks/pre-push derives the
##       gate build identity from `make -pn` (grep '^NIM_TOOL_FLAGS := ') and a
##       recursive variable is printed as '=', which the hook rejects;
##   (d) the two consumers cannot drift: the Makefile does not redefine the
##       package paths, and its tool flag set is the checker.mk set verbatim
##       plus its own nimcache.
##
## Everything is measured by running the real make in a subprocess; the
## fixtures are temp dirs outside the repository (HOME override), so the
## working tree is never touched.

import std/[unittest, os, osproc, strutils, strtabs]

const
  CheckerMk = "ci/checker.mk"
  Makefile = "Makefile"
  ## A target whose recipe expands NIM_TOOL_FLAGS: a compile prerequisite
  ## under `make -n` only prints the command (nothing is executed).
  CompileTarget = "bin/setup-hooks"
  ## A target that never expands NIM_TOOL_FLAGS.
  NonCompileTarget = "help"

proc repoRoot(): string =
  result = absolutePath(currentSourcePath())
  for _ in 0 ..< 3:
    result = result.parentDir()

var fixtureCounter = 0

proc mktempDir(prefix: string): string =
  ## Empty temp directory outside the repository.
  inc fixtureCounter
  result = getTempDir() / (prefix & "_" & $getCurrentProcessId() & "_" & $fixtureCounter)
  if dirExists(result):
    removeDir(result)
  createDir(result)

proc makeDryRun(makefile, target: string; extraArgs: seq[string] = @[];
                home: string): tuple[outp: string; code: int] =
  ## `make -n` in the repository root with HOME overridden - -n prints a
  ## recipe instead of running it, so this measures make's own evaluation.
  var cmd = "make -f " & quoteShell(makefile) & " -n " & quoteShell(target)
  for a in extraArgs:
    cmd.add(" " & quoteShell(a))
  let cmdEnv = newStringTable(modeCaseInsensitive)
  for k, v in envPairs():
    if k != "HOME":
      cmdEnv[k] = v
  cmdEnv["HOME"] = home
  let (outp, code) = execCmdEx(cmd, options = {poUsePath, poStdErrToStdOut},
                               env = cmdEnv, workingDir = repoRoot())
  result.outp = outp
  result.code = code

proc lastNonEmptyLine(s: string): string =
  for line in s.splitLines():
    if line.strip() != "":
      result = line.strip()

proc nimblePkgDir(home, pkg: string): string =
  ## Materialize a single-match package directory under the given HOME.
  let pkgs = home / ".nimble" / "pkgs2"
  createDir(pkgs)
  result = pkgs / (pkg & "-9.9.9-0000000000000000000000000000000000000000")
  createDir(result)

suite "DEBT#509 - absent Nimble package path fails closed":

  test "negative: ci/checker.mk aborts and names the missing package":
    let home = mktempDir("ax509_empty_home")
    defer: removeDir(home)
    # NIMBLE_PKGS is overridden explicitly so the check does not depend on
    # the packages installed for the real HOME (the path stays inside the
    # throwaway fixture either way).
    let r = makeDryRun(CheckerMk, CompileTarget,
                       @["NIMBLE_PKGS=" & (home / "no-pkgs")], home)
    check r.code != 0
    check "DEBT#509" in r.outp
    check "checksums" in r.outp
    check "nimble install checksums" in r.outp
    # The defect itself: an empty --path: argument must not survive.
    check "--path:" notin r.outp
    check not r.outp.contains("--path: ")
    echo "[negative/checker.mk] exit=", r.code, " msg=",
         lastNonEmptyLine(r.outp)

  test "negative: Makefile (same idiom, no second definition to drift)":
    let home = mktempDir("ax509_empty_home_mk")
    defer: removeDir(home)
    let r = makeDryRun(Makefile, CompileTarget,
                       @["NIMBLE_PKGS=" & (home / "no-pkgs")], home)
    check r.code != 0
    check "DEBT#509" in r.outp
    check "nimble install checksums" in r.outp
    check "--path:" notin r.outp
    echo "[negative/Makefile] exit=", r.code, " msg=",
         lastNonEmptyLine(r.outp)

  test "negative: fusion absent fails closed with its own name":
    let home = mktempDir("ax509_fusion_home")
    defer: removeDir(home)
    discard nimblePkgDir(home, "checksums")
    let r = makeDryRun(CheckerMk, CompileTarget, @[], home)
    check r.code != 0
    check "Nimble package 'fusion' is missing" in r.outp
    check "nimble install fusion" in r.outp
    check "--path:" notin r.outp
    echo "[negative/fusion] exit=", r.code, " msg=",
         lastNonEmptyLine(r.outp)

  test "positive: present package resolves to a real --path: directory":
    let home = mktempDir("ax509_ok_home")
    defer: removeDir(home)
    let checksums = nimblePkgDir(home, "checksums")
    let fusion = nimblePkgDir(home, "fusion")
    let r = makeDryRun(CheckerMk, CompileTarget, @[], home)
    check r.code == 0
    check ("--path:" & checksums) in r.outp
    check ("--path:" & fusion) in r.outp
    # No bare `--path:` next to a real one either.
    check "--path: " notin r.outp
    echo "[positive/checker.mk] exit=", r.code
    echo "[positive/checker.mk] resolved checksums=", checksums

  test "positive: Makefile emits the checker.mk paths plus its nimcache":
    let home = mktempDir("ax509_ok_home_mk")
    defer: removeDir(home)
    let checksums = nimblePkgDir(home, "checksums")
    discard nimblePkgDir(home, "fusion")
    let r = makeDryRun(Makefile, CompileTarget, @[], home)
    check r.code == 0
    check ("--path:" & checksums) in r.outp
    check "--nimcache:build/nimcache/tools" in r.outp
    echo "[positive/Makefile] exit=", r.code

  test "guard is immediate: a non-compiling target aborts too":
    # Deliberate: NIM_TOOL_FLAGS must stay immediately expanded for the
    # pre-push identity extractor, so the $(error) cannot be deferred to the
    # recipe. Every target therefore fails closed on a host without the
    # nimble closure, which is the point of DEBT#509.
    let home = mktempDir("ax509_help_home")
    defer: removeDir(home)
    let r = makeDryRun(Makefile, NonCompileTarget,
                       @["NIMBLE_PKGS=" & (home / "no-pkgs")], home)
    check r.code != 0
    check "DEBT#509" in r.outp
    check "nimble install checksums" in r.outp
    echo "[non-compile] ", NonCompileTarget, " exit=", r.code

  test "single source of truth: Makefile does not redefine the paths":
    let text = readFile(repoRoot() / Makefile)
    # A second wildcard definition is exactly the drift DEBT#509 is about.
    check "wildcard $(NIMBLE_PKGS)/checksums-*" notin text
    check "wildcard $(NIMBLE_PKGS)/fusion-*" notin text
    # The Makefile consumes the checker.mk definitions instead.
    check "include ci/checker.mk" in text
    check "NIM_TOOL_FLAGS += --nimcache:build/nimcache/tools" in text
    # The guard lives in exactly one place and names both packages.
    let checker = readFile(repoRoot() / CheckerMk)
    check "AXIOM_NIMBLE_PKG" in checker
    check "$(call AXIOM_NIMBLE_PKG,checksums)" in checker
    check "$(call AXIOM_NIMBLE_PKG,fusion)" in checker
    echo "[ssot] checker.mk is the only definition point"
