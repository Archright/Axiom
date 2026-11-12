import std/unittest
import std/os
import core/io/io_utils
import core/results

suite "IO utility exception-safe wrappers":
  test "readFileOpt returns ok for existing file":
    let tmpPath = getTempDir() / "axiom_io_utils_test.txt"
    writeFile(tmpPath, "hello")
    let res = readFileOpt(tmpPath)
    check res.isOk
    check res.get() == "hello"
    removeFile(tmpPath)

  test "readFileOpt returns err for missing file":
    let res = readFileOpt("/tmp/nonexistent_file_12345.xyz")
    check res.isErr

  test "getFileInfoOpt returns ok for existing file":
    let tmpPath = getTempDir() / "axiom_io_utils_info.txt"
    writeFile(tmpPath, "test")
    let res = getFileInfoOpt(tmpPath)
    check res.isOk
    removeFile(tmpPath)

  test "getFileInfoOpt returns err for missing file":
    let res = getFileInfoOpt("/tmp/nonexistent_file_12345.xyz")
    check res.isErr

  test "walkDirRecOpt returns entries for existing dir":
    let tmpDir = getTempDir() / "axiom_io_utils_dir"
    createDir(tmpDir)
    writeFile(tmpDir / "a.txt", "a")
    let res = walkDirRecOpt(tmpDir)
    check res.isOk
    check res.get().len >= 1
    removeFile(tmpDir / "a.txt")
    removeDir(tmpDir)

  test "walkDirRecOpt returns ok with empty seq for missing dir":
    let res = walkDirRecOpt("/tmp/nonexistent_dir_12345")
    check res.isOk
    check res.get().len == 0
