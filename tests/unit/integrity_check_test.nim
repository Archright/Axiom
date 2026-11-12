import std/[unittest, os]
import core/gateway/gateway
import core/types/results

suite "Axiom Engine Mathematical Integrity and Negative Tests":
  setup:
    let testDataDir = "tests/test_data/integrity"
    createDir(testDataDir)

  teardown:
    removeDir("tests/test_data/integrity")

  test "Engine must reject non-substantive proof defaults":
    let emptyRequest = AxiomProofRequest(
      ownSourceCode: "func checkType(): bool = true",
      expectedSmtlib2: "",
      timeoutMs: 5000
    )
    check buildInjectedSmtlib2(emptyRequest) == ""
    let emptyResult = proveAxiomNode(emptyRequest)
    check emptyResult.isErr()
    check emptyResult.error == axiomErrVacuousContradiction

    let trueRequest = AxiomProofRequest(
      ownSourceCode: "func checkType(): bool = true",
      expectedSmtlib2: "(assert true)",
      timeoutMs: 5000
    )
    let trueResult = proveAxiomNode(trueRequest)
    check trueResult.isErr()
    check trueResult.error == axiomErrVacuousContradiction

    when not defined(release):
      let injectedContradictionRequest = AxiomProofRequest(
        ownSourceCode: "func withdraw(balance, amount: int): bool = amount <= balance",
        expectedSmtlib2: "(assert (<= amount balance))",
        injectContradiction: true,
        timeoutMs: 5000
      )
      let injectedContradictionResult = proveAxiomNode(injectedContradictionRequest)
      check injectedContradictionResult.isErr()
      check injectedContradictionResult.error == axiomErrVacuousContradiction


