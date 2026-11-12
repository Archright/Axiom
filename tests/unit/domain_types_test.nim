import std/[unittest]
import core/types/domain_types
import gate/gate_contract

suite "domain types":
  test "GateLayer enum values exist":
    check ord(glMeta) >= 0
    check ord(glFunctional) >= 0

  test "GateConfig can be instantiated":
    let cfg = GateConfig(id: "test", name: "Test Gate", layer: glMeta)
    check cfg.id == "test"
    check cfg.layer == glMeta
