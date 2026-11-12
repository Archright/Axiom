import std/unittest
import core/results

suite "Result[T,E] basic contract":
  test "ok result reports isOk=true and isErr=false":
    let r = Result[int, string](ok: true, value: 42)
    check r.isOk()
    check not r.isErr()

  test "err result reports isOk=false and isErr=true":
    let r = Result[int, string](ok: false, err: "failure")
    check not r.isOk()
    check r.isErr()

  test "get returns value for ok result":
    let r = Result[int, string](ok: true, value: 42)
    check r.get == 42

  test "error returns message for err result":
    let r = Result[int, string](ok: false, err: "failure")
    check r.error == "failure"

  test "mapErr transforms error value":
    let r = Result[int, string](ok: false, err: "fail")
    let mapped = r.mapErr(proc (e: string): string = "mapped: " & e)
    check mapped.isErr()
    check mapped.error == "mapped: fail"

  test "mapErr preserves ok value":
    let r = Result[int, string](ok: true, value: 42)
    let mapped = r.mapErr(proc (e: string): string = "mapped: " & e)
    check mapped.isOk()
    check mapped.get == 42
