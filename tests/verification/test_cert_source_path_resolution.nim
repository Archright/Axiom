import std/[json, os, tempfiles, unittest]
import ../../src/core/proof/source_fingerprint
import ../../src/verification/certificate_verifier

## Issue #218 regression: `ax cert verify --project <subjectRoot>` must read
## the subject's module bytes when the certificate records an ABSOLUTE
## modulePath. Nim's `/` is joinPath and concatenates an absolute tail onto the
## head ("usr/" / "/lib" == "usr/lib"), so the historical
## `projectRoot / certModulePath` double-joined the absolute path and every
## freshly issued absolute-path certificate resolved to dvcNotCurrent.
## Contract: docs/spec/cert_lifecycle_contracts.md §5 (source-staleness leg
## reads the module bytes at `projectRoot`).

suite "Certificate source path resolution (#218)":

  proc certNode(modulePath, sourceHash: string): JsonNode =
    %*{"modulePath": modulePath, "sourceHash": sourceHash}

  test "absolute modulePath is read as-is, not re-rooted under projectRoot":
    let subjectRoot = createTempDir("axiom-218-", "")
    defer: removeDir(subjectRoot)
    let modulePath = subjectRoot / "subject_module.nim"
    let sourceContent = "proc subjectProbe(x: int): int = x + 1"
    writeFile(modulePath, sourceContent)
    let matchingHash = computeStableSourceFingerprint(sourceContent)

    # A projectRoot that is NOT the module's repo. The path does not exist on
    # purpose: under the old double-join it could only ever be unreadable.
    let foreignRoot = subjectRoot / "different-project-root"

    check certSourceHashMatchesSource(certNode(modulePath, matchingHash), foreignRoot)
    check not certSourceHashMatchesSource(certNode(modulePath, "0000000000000000"), foreignRoot)

  test "relative modulePath still resolves under projectRoot":
    let subjectRoot = createTempDir("axiom-218-rel-", "")
    defer: removeDir(subjectRoot)
    let relativeModulePath = "nested/subject_module.nim"
    let sourceContent = "proc subjectProbe(x: int): int = x + 2"
    createDir(subjectRoot / "nested")
    writeFile(subjectRoot / relativeModulePath, sourceContent)
    let matchingHash = computeStableSourceFingerprint(sourceContent)

    check certSourceHashMatchesSource(certNode(relativeModulePath, matchingHash), subjectRoot)
    # The relative tail must remain anchored to projectRoot — a different root
    # does not carry the module file, so the cert is not current there.
    check not certSourceHashMatchesSource(
      certNode(relativeModulePath, matchingHash), subjectRoot / "elsewhere")