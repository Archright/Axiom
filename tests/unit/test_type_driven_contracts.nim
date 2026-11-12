import std/unittest
import core/contract/contract_param_util

suite "Type-Driven Contract Synthesis":
  test "nat/uint params generate >= 0 invariant":
    let params = @[("n", "nat"), ("x", "uint64")]
    let contracts = generateTypeDrivenContracts(params)
    check contracts.len == 2
    check contracts[0] == "(assert (>= n 0))"
    check contracts[1] == "(assert (>= x 0))"

  test "string params generate str.len >= 0 invariant":
    let params = @[("s", "string")]
    let contracts = generateTypeDrivenContracts(params)
    check contracts.len == 1
    check contracts[0] == "(assert (>= (str.len s) 0))"

  test "seq/array/openarray params generate seq.len >= 0 invariant":
    let params = @[("a", "seq[int]"), ("b", "array[5,int]"), ("c", "openarray[int]")]
    let contracts = generateTypeDrivenContracts(params)
    check contracts.len == 3
    check contracts[0] == "(assert (>= (seq.len a) 0))"
    check contracts[1] == "(assert (>= (seq.len b) 0))"
    check contracts[2] == "(assert (>= (seq.len c) 0))"

  test "int/bool/float params generate no contracts":
    let params = @[("i", "int"), ("b", "bool"), ("f", "float")]
    let contracts = generateTypeDrivenContracts(params)
    check contracts.len == 0

  test "mixed params generate correct subset":
    let params = @[("n", "nat"), ("s", "string"), ("i", "int")]
    let contracts = generateTypeDrivenContracts(params)
    check contracts.len == 2
    check "(assert (>= n 0))" in contracts
    check "(assert (>= (str.len s) 0))" in contracts
