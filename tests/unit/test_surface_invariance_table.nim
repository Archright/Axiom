## tests/unit/test_surface_invariance_table.nim — unit tests for the pure core of
## tools/ci/surface_invariance_table.nim.
##
## Hermetic: the file reads no file, spawns no process, and consults no
## environment. Every input is constructed in memory. The only shipped-policy
## read is the same `loadPolicy("config/repository_surface.json")` the sibling
## surface-guard test already performs, and that read is the point of the two
## shipped-policy tests at the end.
##
## Run:
##   nim c -r --hints:off --skipParentCfg --skipProjCfg --skipUserCfg \
##     --noNimblePath --nimcache:build/nimcache/tsit -o:build/tsit \
##     tests/unit/test_surface_invariance_table.nim

import std/[json, unittest, strutils]
import ../../tools/ci/surface_invariance_table
import ../../tools/surface_guard

proc policy(classes: JsonNode): JsonNode =
  ## Minimal structurally valid policy: schemaVersion 1, all three classes
  ## present, the three rule rows, a defaultClass and the declared order.
  %* {
    "schemaVersion": 1,
    "policyVersion": 1,
    "classes": classes,
    "defaultClass": "PRODUCT",
    "rules": {
      "PRODUCT": {"ADD": "PASS", "MODIFY": "PASS", "DELETE": "PASS"},
      "CONTROLLED": {"ADD": "PASS", "MODIFY": "PASS", "DELETE": "PASS"},
      "FROZEN": {"ADD": "FAIL", "MODIFY": "FAIL", "DELETE": "FAIL"}
    },
    "resolutionOrder": ["PRODUCT", "CONTROLLED", "FROZEN"]
  }

suite "surface invariance — transition classification":
  test "identical class is SAME":
    check classifyTransition("FROZEN", "FROZEN") == tkSame
    check classifyTransition("CONTROLLED", "CONTROLLED") == tkSame
    check classifyTransition("PRODUCT", "PRODUCT") == tkSame
    echo "  [transition] identical classes are SAME"

  test "FROZEN -> anything else is LOOSENED":
    check classifyTransition("FROZEN", "CONTROLLED") == tkLoosened
    check classifyTransition("FROZEN", "PRODUCT") == tkLoosened
    echo "  [transition] leaving FROZEN is LOOSENED in both directions"

  test "anything else -> FROZEN is TIGHTENED":
    check classifyTransition("CONTROLLED", "FROZEN") == tkTightened
    check classifyTransition("PRODUCT", "FROZEN") == tkTightened
    echo "  [transition] entering FROZEN is TIGHTENED"

  test "PRODUCT <-> CONTROLLED is SAME because the rule rows are identical":
    # Both classes carry ADD/MODIFY/DELETE = PASS in the shipped table, so the
    # verdict for every op is unchanged. Reporting this pair as a security
    # change would make the tool cry wolf on a declaration-only edit.
    check classifyTransition("PRODUCT", "CONTROLLED") == tkSame
    check classifyTransition("CONTROLLED", "PRODUCT") == tkSame
    echo "  [transition] PRODUCT <-> CONTROLLED is verdict-neutral"

  test "the class ladder is ordered weakest to strongest":
    check rankOf("PRODUCT") == 0
    check rankOf("CONTROLLED") == 1
    check rankOf("FROZEN") == 2
    check rankOf("NOT-A-CLASS") == -1
    echo "  [transition] class ladder order is pinned"

suite "surface invariance — path list parsing":
  test "blank lines and comments are skipped":
    let got = parsePathList("""
# a comment
.github/CODEOWNERS

  .github/workflows/admission-check.yml
   # indented comment
AGENTS.md
""")
    check got == @[".github/CODEOWNERS",
                   ".github/workflows/admission-check.yml",
                   "AGENTS.md"]
    echo "  [paths] blanks and comments are skipped, order preserved"

  test "an all-comment list yields nothing":
    check parsePathList("# only\n\n   \n").len == 0
    echo "  [paths] an empty list is detectable (caller exits 2)"

suite "surface invariance — differential rows":
  test "rows use the guard's own resolver, not a private copy":
    # The old policy leaves `.github/**` FROZEN; the new one registers one exact
    # CONTROLLED path. The row must show the loosening for that path only.
    let oldP = policy(%* {"PRODUCT": [], "CONTROLLED": [], "FROZEN": [".github/**"]})
    let newP = policy(%* {"PRODUCT": [],
                          "CONTROLLED": [".github/workflows/ci.yml"],
                          "FROZEN": [".github/**"]})
    # newP is structurally INVALID (an exact CONTROLLED entry crosses a FROZEN
    # glob without a frozenExceptions registration) — that is exactly why the
    # rows are computed from resolveClass, which is pure pattern matching and
    # does not require validity. Validity is asserted separately by the caller.
    let rows = rowsFor(oldP, newP,
      @[".github/workflows/ci.yml", ".github/workflows/other.yml", "docs/x.md"])
    check rows.len == 3
    check rows[0].oldClass == "FROZEN"
    check rows[0].newClass == "CONTROLLED"
    check rows[0].kind == tkLoosened
    check rows[1].kind == tkSame
    check rows[2].oldClass == "PRODUCT"
    check rows[2].kind == tkSame
    echo "  [rows] only the registered path loosens; the rest hold"

  test "a path absent from every pattern falls through to defaultClass":
    let p = policy(%* {"PRODUCT": [], "CONTROLLED": [], "FROZEN": []})
    let rows = rowsFor(p, p, @["unmatched/path.nim"])
    check rows[0].oldClass == "PRODUCT"
    check rows[0].kind == tkSame
    echo "  [rows] defaultClass applies when nothing matches"

suite "surface invariance — shipped policy":
  test "the shipped policy is structurally valid as seen through classify":
    let loaded = loadPolicy("config/repository_surface.json")
    check loaded.ok
    check not loaded.invalidContent
    check structuralError(loaded.node, "shipped", "config/repository_surface.json") == ""
    echo "  [shipped] classify() does not report POLICY_INVALID"

  test "a policy compared with itself produces zero transitions":
    # This is the anti-theater assertion: the tool must be capable of saying
    # "nothing changed". A differential table that reported a transition for
    # two byte-identical policies would be measuring itself, not the policies.
    let loaded = loadPolicy("config/repository_surface.json")
    check loaded.ok
    let rows = rowsFor(loaded.node, loaded.node, @[
      ".github/CODEOWNERS",
      ".github/workflows/admission-check.yml",
      "AGENTS.md",
      "src/gate/gateway.nim",
      "docs/spec/repository_surface_contract.md",
      "tools/surface_guard.nim",
      "vendor/ed25519",
    ])
    for r in rows:
      check r.kind == tkSame
      check r.oldClass == r.newClass
    echo "  [shipped] self-comparison yields 0 transitions over 7 paths"
