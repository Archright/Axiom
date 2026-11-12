{.push raises: [].}

import std/unittest
import gate/logic_binding_gate

suite "Logic-Context Binding Gate":
  test "hasLogicBinding rejects empty nodeId":
    check hasLogicBinding("x > 0", "") == false

  test "hasLogicBinding rejects banned atom ast_parse_failed_isolated":
    check hasLogicBinding("ast_parse_failed_isolated", "someNode") == false

  test "hasLogicBinding rejects banned atom external_io_isolated":
    check hasLogicBinding("external_io_isolated", "someNode") == false

  test "hasLogicBinding passes for result-bound proposition":
    check hasLogicBinding("x > 0 and result.isOk", "someNode") == true

  test "hasLogicBinding rejects vacuous proposition":
    check hasLogicBinding("true", "someNode") == false

  test "containsBannedAtom detects banned atoms":
    check containsBannedAtom("ast_parse_failed_isolated") == true
    check containsBannedAtom("external_io_isolated") == true
    check containsBannedAtom("x > 0") == false
