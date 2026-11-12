import std/[json, unittest]
import ../../src/verification/verification_facade

suite "verification_facade":
  test "rebuild_assets symbols are accessible through facade":
    check declared(extractFunctionBody)
    check declared(computeFingerprint)
    check declared(parseNim)
    check declared(readJsonFile)
    check declared(writePrettyJsonFile)
    check declared(getCanonicalCertFilename)
    check declared(isProvenanceProtected)
    check declared(synchronizeAndRenderUniverse)
    check declared(validateProofStateCertificateConvergence)

  test "io_utils symbols are accessible through facade":
    check declared(readFileOpt)
    check declared(writeFileOpt)
    check declared(removeFileOpt)

  test "convergence facade is callable":
    var state = newJObject()
    check synchronizeAndRenderUniverse(state, "") == 0
