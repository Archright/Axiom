import std/[json, os, strutils, unittest]
import core/results
import core/topology/policy
import core/topology/lock
import core/topology/declaration
import core/topology/suggest
import core/gateway/gateway_json

suite "DEBT#281 — topology triple fail-open chain regression":
  const corruptJson = "{corrupt"

  test "parseTopologyPolicy returns err for corrupt file":
    let tmpPath = getTempDir() / "tmp_test_corrupt_policy.json"
    writeFile(tmpPath, corruptJson)
    let res = parseTopologyPolicy(tmpPath)
    removeFile(tmpPath)
    check res.isErr
    check "unreadable" in res.err

  test "parseTopologyPolicy returns err for missing file":
    let res = parseTopologyPolicy("/nonexistent/policy.json")
    check res.isErr
    check "unreadable" in res.err

  test "parseTopologyLockJson returns err for corrupt JSON":
    let res = parseTopologyLockJson(corruptJson)
    check res.isErr
    check "unreadable" in res.err

  test "parseTopologyLock returns err for missing file":
    let res = parseTopologyLock("/nonexistent/lock.json")
    check res.isErr
    check "unreadable" in res.err

  test "parseTopologyDeclarationJson returns err for corrupt JSON":
    let res = parseTopologyDeclarationJson(corruptJson)
    check res.isErr
    check "unreadable" in res.err

  test "jsonParseSafe returns err for corrupt JSON — regression DEBT#282":
    check jsonParseSafe("{invalid").isErr
    check jsonParseSafe("not json").isErr
    check jsonParseSafe("").isErr
