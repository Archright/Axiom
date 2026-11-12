## Cross-directory determinism: the feature manifest generator must produce
## byte-identical output from different checkout locations (path-independence, §0.2).

import std/[unittest, os, tempfiles, json, strutils]
import core/types/results
import tools/feature_manifest_generator

suite "feature_manifest determinism":
  var dirA, dirB: string
  setup:
    dirA = createTempDir("axiom_feat_", "")
    dirB = createTempDir("axiom_feat_", "")
    for d in [dirA, dirB]:
      createDir(d / "tests/features")
      writeFile(d / "tests/features/one.feature",
        "@smoke\nFeature: One\n  Scenario: minimal\n    Given a feature exists")
  teardown:
    removeDir(dirA)
    removeDir(dirB)
  test "identical feature trees in different roots produce byte-identical manifests":
    let a = buildManifestJson(dirA)
    let b = buildManifestJson(dirB)
    check a.isOk
    check b.isOk
    check a.get() == b.get()
    check $a.get() == $b.get()
    check not ($a.get()).contains(dirA)
    check not ($a.get()).contains("home")
