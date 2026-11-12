import std/[unittest, os]
import gate/types

suite "gate types utilities":
  test "safeMaxJobs returns positive value":
    let jobs = safeMaxJobs(16)
    check jobs > 0

  test "getMemAvailableMB returns value or -1":
    let mem = getMemAvailableMB()
    check mem > 0 or mem == -1
