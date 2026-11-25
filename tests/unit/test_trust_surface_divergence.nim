## Unit tests for tools/ci/trust_surface_divergence.nim — the VS-A trust-surface
## divergence detector and its ratchet ledger.
##
## The detector exists because Axiom carries two independent definitions of
## "trust surface": the App manifest (config/policy/trust_surface_manifest.json,
## 18 exact paths, blob-compared out of repo) and the in-repo 3-class policy
## (config/repository_surface.json, first match in resolutionOrder order, else
## defaultClass). A manifest path is CONVERGENT only when it resolves to FROZEN;
## every other resolution is a DIVERGENCE where the in-repo gates PASS while the
## App FAILs.
##
## Case (a) is the FIDELITY PIN, and it is the reason this file imports no
## resolver from tools/surface_guard.nim: it runs the detector over the REAL
## policies and asserts the measured 10 FROZEN / 8 divergent split with the 8
## exact paths. If the detector's resolution semantics ever drift from the
## guard's, this test fails loudly instead of the two silently agreeing.
##
## Hermetic: stdlib only. The single filesystem read is the detector's own
## runPaths() boundary against the shipped config; every mutation case drives
## evaluate() with in-memory fixtures, so no test edits config/**.
##
## Run from repo root:
##   nim c -r --hints:off tests/unit/test_trust_surface_divergence.nim

import std/[json, os, strutils, unittest]
import ../../tools/ci/trust_surface_divergence

const
  RealManifest = ManifestPath
  RealPolicy = PolicyPath
  RealLedger = LedgerPath

  ## The measured divergence set at HEAD: 7 CONTROLLED + 1 default-PRODUCT.
  ## Sorted, because the detector sorts its output.
  ExpectedDivergences = [
    ".github/actions/setup-axiom-toolchain/action.yml",
    ".github/workflows/admission-check.yml",
    ".github/workflows/admission-gate-v2.yml",
    ".github/workflows/certificate-mint.yml",
    ".github/workflows/publication-integrity.yml",
    "config/policy/epoch_manifest.json",
    "config/trusted_writer_set.json",
    "tests/ci/test_vs0_admission_aggregate_fail_closed.nim",
  ]

# ── fixtures ─────────────────────────────────────────────────────────────────

const
  FixturePolicy = """{
  "classes": {
    "PRODUCT": ["src/core/**"],
    "CONTROLLED": ["tests/unit/probe_controlled.nim"],
    "FROZEN": ["src/gate/**"]
  },
  "resolutionOrder": ["PRODUCT", "CONTROLLED", "FROZEN"],
  "defaultClass": "PRODUCT"
}"""

  FixtureManifest = """{"paths": ["src/gate/probe_frozen.nim", "tests/unit/probe_controlled.nim"]}"""

  FixtureLedger = """{
  "schemaVersion": 1,
  "purpose": "test fixture",
  "paths": {
    "tests/unit/probe_controlled.nim": {"rationale": "probe", "trackedAs": "probe/track"}
  }
}"""

func divergencePaths(lines: seq[string]): seq[string] =
  ## The `DIVERGENCE <path> ...` paths in output order.
  for line in lines:
    if line.startsWith("DIVERGENCE "):
      let rest = line["DIVERGENCE ".len .. ^1]
      result.add(rest.split(' ')[0])

func hasLine(lines: seq[string], prefix: string): bool =
  for line in lines:
    if line.startsWith(prefix):
      return true
  false

proc realFiles(): tuple[manifest, policy, ledger: string] =
  (readFile(RealManifest), readFile(RealPolicy), readFile(RealLedger))

proc withExtraManifestPath(path: string): string =
  ## The shipped manifest plus one injected path — the 19th-path mutation.
  var node = parseJson(readFile(RealManifest))
  node["paths"].add(%path)
  $node

proc withLedger(rawLedger: string): string = rawLedger

suite "trust_surface_divergence — resolver semantics":

  test "classifyPath is first-match over resolutionOrder, defaultClass fallback":
    let policy = parseJson(FixturePolicy)
    check classifyPath(policy, "src/gate/anything.nim").cls == "FROZEN"
    check classifyPath(policy, "tests/unit/probe_controlled.nim").cls == "CONTROLLED"
    check classifyPath(policy, "src/core/engine.nim").cls == "PRODUCT"
    # Unmatched path falls through to defaultClass, and says so.
    let dflt = classifyPath(policy, "docs/spec/nothing_matches_this.md")
    check dflt.cls == "PRODUCT"
    check dflt.pattern == DefaultPattern

  test "resolutionOrder is read from the policy, never assumed":
    # Overlapping globs: both PRODUCT and FROZEN match src/gate/x.nim, so the
    # declared order alone decides. Reversing only resolutionOrder flips the
    # answer — the order is read from the policy, never hardcoded.
    var policy = parseJson(FixturePolicy)
    policy["classes"]["PRODUCT"] = %*["src/**"]
    # PRODUCT is declared first in resolutionOrder, so it wins the overlap.
    check classifyPath(policy, "src/gate/x.nim").cls == "PRODUCT"
    policy["resolutionOrder"] = %*["FROZEN", "PRODUCT", "CONTROLLED"]
    check classifyPath(policy, "src/gate/x.nim").cls == "FROZEN"

  test "** swallows segments, * stays inside one segment":
    let policy = parseJson(FixturePolicy)
    check classifyPath(policy, "src/gate/a/b/c.nim").cls == "FROZEN"
    var star = parseJson(FixturePolicy)
    star["classes"]["CONTROLLED"] = %*["tests/*.nim"]
    check classifyPath(star, "tests/x.nim").cls == "CONTROLLED"
    check classifyPath(star, "tests/sub/x.nim").cls == "PRODUCT"

suite "trust_surface_divergence — real repository state (fidelity pin)":

  test "(a) HEAD produces exactly the 8 registered divergences and exit 0":
    let verdict = runPaths(RealManifest, RealPolicy, RealLedger)
    check verdict.exitCode == 0

    let found = divergencePaths(verdict.lines)
    check found.len == 8
    # The pin: the measured 7 CONTROLLED + 1 default-PRODUCT set, path for path.
    for expected in ExpectedDivergences:
      check expected in found
    # 10 of the 18 manifest paths are FROZEN — the convergent remainder.
    check hasLine(verdict.lines, "SUMMARY manifest=18 convergent=10 divergent=8")
    echo "  [pin] 18 manifest paths -> 10 convergent / 8 divergent, all registered"

    # Every reported divergence names how it resolved; nothing is unexplained.
    for line in verdict.lines:
      if line.startsWith("DIVERGENCE "):
        check line.contains(" class=")
        check line.contains(" pattern=")
    echo "  [pin] each divergence carries class= and pattern="

  test "(a') ledger entries are exact paths, never wildcards":
    let ledger = parseJson(readFile(RealLedger))
    for path in ledgerPaths(ledger):
      check not path.contains('*')
      check not path.contains('?')
    echo "  [pin] all ledger entries are exact paths"

suite "trust_surface_divergence — mutations":

  test "(b) an unregistered CONTROLLED divergence exits 1 and names the path":
    let manifest = withExtraManifestPath("tests/unit/probe_extra_controlled.nim")
    # Register it as CONTROLLED in the real policy's terms by using a path the
    # shipped policy already classifies CONTROLLED.
    let probe = withExtraManifestPath("tests/unit/test_pareto_harness.nim")
    let (_, policy, ledger) = realFiles()
    let verdict = evaluate(probe, policy, ledger)
    check verdict.exitCode == 1
    check "tests/unit/test_pareto_harness.nim" in divergencePaths(verdict.lines)
    check hasLine(verdict.lines, "SUMMARY manifest=19")
    discard manifest
    echo "  [mut] injected CONTROLLED 19th path -> exit 1, path named"

  test "(c) a FROZEN manifest path is convergent and is not reported":
    let probe = withExtraManifestPath("src/gate/runner_probe.nim")
    let (_, policy, ledger) = realFiles()
    let verdict = evaluate(probe, policy, ledger)
    check verdict.exitCode == 0
    check "src/gate/runner_probe.nim" notin divergencePaths(verdict.lines)
    check hasLine(verdict.lines, "SUMMARY manifest=19 convergent=11 divergent=8")
    echo "  [mut] injected FROZEN 19th path -> convergent, not reported"

  test "(d) a missing manifest file exits 2 (fail closed)":
    let verdict = runPaths("build/tests/nonexistent_manifest.json", RealPolicy, RealLedger)
    check verdict.exitCode == 2
    check hasLine(verdict.lines, "INPUT-ERROR")
    echo "  [mut] missing manifest -> exit 2"

  test "(e) an unparsable repository policy exits 2":
    let (manifest, _, ledger) = realFiles()
    let verdict = evaluate(manifest, "{ not json at all", ledger)
    check verdict.exitCode == 2
    check hasLine(verdict.lines, "INPUT-ERROR unparsable repository-surface policy")
    echo "  [mut] torn policy JSON -> exit 2"

  test "(f) a dead ledger entry (no longer divergent) exits 1":
    var ledger = parseJson(readFile(RealLedger))
    ledger["paths"]["src/gate/already_frozen.nim"] =
      %*{"rationale": "stale", "trackedAs": "probe/dead"}
    let (manifest, policy, _) = realFiles()
    let verdict = evaluate(manifest, policy, $ledger)
    # The new entry is dead, and the 8 real ones are still registered.
    check verdict.exitCode == 1
    check hasLine(verdict.lines, "DEAD src/gate/already_frozen.nim")
    # The counters live on the SUMMARY line, not on a line of their own.
    check hasLine(verdict.lines, "SUMMARY manifest=18 convergent=10 divergent=8 registered=8 unregistered=0 dead=1")
    echo "  [mut] dead ledger entry -> exit 1, DEAD line emitted"

  test "(g) a wildcard ledger entry exits 2":
    var ledger = parseJson(readFile(RealLedger))
    ledger["paths"]["src/gate/**"] = %*{"rationale": "too broad", "trackedAs": "probe/wild"}
    let (manifest, policy, _) = realFiles()
    let verdict = evaluate(manifest, policy, $ledger)
    check verdict.exitCode == 2
    check hasLine(verdict.lines, "INPUT-ERROR")
    echo "  [mut] wildcard ledger entry -> exit 2"

  test "(h) a duplicate ledger entry exits 2":
    # std/json collapses duplicate object keys, so the duplicate has to be
    # reintroduced in raw text — that is the only place it is observable.
    let (manifest, policy, ledger) = realFiles()
    let dup =
      """{"schemaVersion": 1, "purpose": "dup", "paths": {""" &
      """"tests/unit/probe_controlled.nim": {"rationale": "a", "trackedAs": "a"},""" &
      """"tests/unit/probe_controlled.nim": {"rationale": "b", "trackedAs": "b"}}}"""
    let verdict = evaluate(manifest, policy, dup)
    check verdict.exitCode == 2
    check hasLine(verdict.lines, "INPUT-ERROR")
    discard ledger
    echo "  [mut] duplicate ledger key -> exit 2"

  test "(i) output is byte-identical across two runs":
    let (manifest, policy, ledger) = realFiles()
    let first = evaluate(manifest, policy, ledger)
    let second = evaluate(manifest, policy, ledger)
    check first.exitCode == second.exitCode
    check first.lines.len == second.lines.len
    check first.lines == second.lines
    # No timestamps, no locale: the summary line is the only footer.
    check first.lines[^1].startsWith("SUMMARY ")
    echo "  [pin] two evaluations -> identical stdout"

suite "trust_surface_divergence — input validation is fail-closed":

  test "empty manifest path list is an input error":
    let (_, policy, ledger) = realFiles()
    check evaluate("""{"paths": []}""", policy, ledger).exitCode == 2

  test "non-string manifest path is an input error":
    let (_, policy, ledger) = realFiles()
    check evaluate("""{"paths": ["a.nim", 7]}""", policy, ledger).exitCode == 2

  test "policy missing classes / resolutionOrder / defaultClass is an input error":
    let (manifest, _, ledger) = realFiles()
    for broken in [
      """{"resolutionOrder": ["PRODUCT"], "defaultClass": "PRODUCT"}""",
      """{"classes": {"PRODUCT": []}, "defaultClass": "PRODUCT"}""",
      """{"classes": {"PRODUCT": []}, "resolutionOrder": ["PRODUCT"]}""",
    ]:
      let verdict = evaluate(manifest, broken, ledger)
      check verdict.exitCode == 2
      check hasLine(verdict.lines, "INPUT-ERROR")

  test "a ledger value without rationale/trackedAs is an input error":
    let (manifest, policy, _) = realFiles()
    let bad =
      """{"schemaVersion": 1, "paths": {"tests/unit/probe_controlled.nim": {}}}"""
    check evaluate(manifest, policy, bad).exitCode == 2
