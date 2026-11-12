import std/unittest
import std/sets
import verification/analyzer/analyzer_shared_cert
import core/types/certificate_types

suite "analyzer_shared_cert - parseDayFromTimestamp":
  test "extracts date from ISO timestamp":
    check parseDayFromTimestamp("2024-01-15T10:30:00Z") == "2024-01-15"

  test "extracts date from timestamp with timezone":
    check parseDayFromTimestamp("2024-06-01T00:00:00+00:00") == "2024-06-01"

  test "extracts date from short string with dash":
    check parseDayFromTimestamp("2024-12-31T23:59:59") == "2024-12-31"

  test "extracts date from already 10-char string":
    check parseDayFromTimestamp("2024-01-15") == "2024-01-15"

  test "returns empty for short string":
    check parseDayFromTimestamp("2024-01") == ""

  test "handles whitespace":
    check parseDayFromTimestamp("  2024-01-15T10:30:00Z  ") == "2024-01-15"

  test "returns empty for empty input":
    check parseDayFromTimestamp("") == ""

  test "returns empty for whitespace only":
    check parseDayFromTimestamp("   ") == ""

  test "handles minimum valid length":
    check parseDayFromTimestamp("abcdefghij") == "abcdefghij"


suite "analyzer_shared_cert - inferFunctionNameFromTheorem":
  test "extracts function name from matching theorem":
    check inferFunctionNameFromTheorem("foo_solve", "foo.nim") == "solve"

  test "extracts function name from longer stem":
    check inferFunctionNameFromTheorem("my_module_verify", "my_module.nim") == "verify"

  test "returns empty for mismatched prefix":
    check inferFunctionNameFromTheorem("foo_solve", "bar.nim") == ""

  test "returns empty for empty module path":
    check inferFunctionNameFromTheorem("foo_solve", "") == ""

  test "returns empty for empty theorem name":
    check inferFunctionNameFromTheorem("", "foo.nim") == ""

  test "returns empty when theorem equals prefix":
    check inferFunctionNameFromTheorem("foo_", "foo.nim") == ""

  test "handles nested path":
    check inferFunctionNameFromTheorem("solver_check", "/path/to/solver.nim") == "check"


suite "analyzer_shared_cert - collectKnownFunctions":
  test "collects function names from certificates":
    var cert1 = FunctionCertificate(functionName: "foo")
    var cert2 = FunctionCertificate(functionName: "bar")
    var cert3 = FunctionCertificate(functionName: "foo")
    let certs = @[cert1, cert2, cert3]
    let result = collectKnownFunctions(certs)
    check "foo" in result
    check "bar" in result
    check result.len == 2

  test "skips empty function names":
    var cert1 = FunctionCertificate(functionName: "valid")
    var cert2 = FunctionCertificate(functionName: "")
    let result = collectKnownFunctions(@[cert1, cert2])
    check "valid" in result
    check result.len == 1

  test "handles empty sequence":
    let result = collectKnownFunctions(@[])
    check result.len == 0


suite "analyzer_shared_cert - computeCumulativeDefectsHealed":
  test "sums defects from multiple certificates":
    var cert1 = FunctionCertificate(recoveredDefects: @["defect1"])
    var cert2 = FunctionCertificate(recoveredDefects: @["defect2", "defect3"])
    let result = computeCumulativeDefectsHealed(@[cert1, cert2])
    check result == 3

  test "returns zero for empty sequence":
    check computeCumulativeDefectsHealed(@[]) == 0

  test "handles empty defect lists":
    var cert1 = FunctionCertificate(recoveredDefects: @[])
    var cert2 = FunctionCertificate(recoveredDefects: @[])
    let result = computeCumulativeDefectsHealed(@[cert1, cert2])
    check result == 0


suite "analyzer_shared_cert - computeAverageRetryCount":
  test "returns zero for empty sequence":
    check computeAverageRetryCount(@[]) == 0.0

  test "returns zero when only trusted verified certs":
    var cert1 = FunctionCertificate(status: certGreen, trusted: true, retryCount: 10)
    var cert2 = FunctionCertificate(status: certGreen, trusted: true, retryCount: 20)
    let result = computeAverageRetryCount(@[cert1, cert2])
    check result == 0.0

  test "counts unverified trusted certificates":
    var cert1 = FunctionCertificate(status: certRed, trusted: true, retryCount: 30)
    var cert2 = FunctionCertificate(status: certGreen, trusted: true, retryCount: 100)
    let result = computeAverageRetryCount(@[cert1, cert2])
    check result == 30.0

  test "skips non-trusted certificates":
    var cert1 = FunctionCertificate(status: certRed, trusted: true, retryCount: 50)
    var cert2 = FunctionCertificate(status: certRed, trusted: false, retryCount: 10)
    let result = computeAverageRetryCount(@[cert1, cert2])
    check result == 50.0

  test "handles single unverified trusted cert":
    var cert1 = FunctionCertificate(status: certRed, trusted: true, retryCount: 5)
    let result = computeAverageRetryCount(@[cert1])
    check result == 5.0

  test "returns zero when no unverified trusted certs":
    var cert1 = FunctionCertificate(status: certGreen, trusted: false, retryCount: 10)
    let result = computeAverageRetryCount(@[cert1])
    check result == 0.0

  test "handles all pending trusted certs":
    var cert1 = FunctionCertificate(status: certPending, trusted: true, retryCount: 10)
    let result = computeAverageRetryCount(@[cert1])
    check result == 10.0

  test "handles yellow status trusted certs":
    var cert1 = FunctionCertificate(status: certYellow, trusted: true, retryCount: 50)
    var cert2 = FunctionCertificate(status: certGreen, trusted: true, retryCount: 10)
    let result = computeAverageRetryCount(@[cert1, cert2])
    check result == 50.0
