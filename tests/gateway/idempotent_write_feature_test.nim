{.push raises: [CatchableError].}

## idempotent_write_feature_test.nim — Gateway test for idempotent_write
##
## Tests the deterministic write guard that prevents spurious file changes.

import std/[unittest, os, tempfiles]
import core/utils/idempotent_write

suite "Idempotent Write Guard":
  var tmpDir: string

  setup:
    tmpDir = createTempDir("axiom_idempotent_", "")

  teardown:
    removeDir(tmpDir)

  test "Identical content returns false (no write)":
    let path = tmpDir / "test.txt"
    writeFile(path, "hello world")
    check writeFileIdempotent(path, "hello world") == false

  test "Different content returns true (write occurs)":
    let path = tmpDir / "test.txt"
    writeFile(path, "old content")
    check writeFileIdempotent(path, "new content") == true
    check readFile(path) == "new content"

  test "New file returns true (write occurs)":
    let path = tmpDir / "new_file.txt"
    check writeFileIdempotent(path, "created") == true
    check readFile(path) == "created"

  test "Empty content on empty file returns false":
    let path = tmpDir / "empty.txt"
    writeFile(path, "")
    check writeFileIdempotent(path, "") == false

  test "Write failure returns false (fail-safe)":
    let path = tmpDir / "nonexistent" / "deep" / "path.txt"
    check writeFileIdempotent(path, "data") == false

{.pop.}
