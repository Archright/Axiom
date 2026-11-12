# axiom.run-manifest.v1 — deterministic join of one verification run.
#
# Inputs (all passed by the caller):
#   $cert       slurpfile: the canonical certificate JSON
#   $st         slurpfile: logs/ax_proof_state.json (the run's persisted state)
#   $rep        slurpfile: logs/verify_contract_e2e_report.json (ax report --json)
#   $certPath   string: path of the certificate used for the kernel replay
#   $scopeHash  string: ax scope hash
#   $gitHead    string: git rev-parse HEAD
#   $binSha     string: sha256 of bin/ax (the binary that produced the run)
#   $engineBuild  string: VerifierBuildId compiled into bin/ax
#               (src/generated/build_env.nim; measured by bin/hermetic_build)
#   $buildSourceHash  string: live src-tree hash from the binary's own
#               `bin/ax --check-provenance` OK verdict (expected==actual there)
#   $lockSha    string: sha256 of data/verification_scope.lock
#   $canon      string: ax report --canonical-digest
#   $certSha    string: sha256 of the certificate file
#   $node       string: module::function
#   $proveExit / $reportExit / $kernelExit   numbers
#   $kernelOut  string: ax cert verify --kernel stdout
#
# The caller serializes with `jq -S -c -j` (sorted keys, no trailing newline)
# and hashes the bytes. Timestamps, run ids, paths, cache state, and runtime
# telemetry are deliberately excluded; they are not identity.

{
  schemaVersion: "axiom.run-manifest.v1",
  target: {
    nodeId: $node,
    symbol: ($cert[0].functionName // ""),
    modulePath: ($cert[0].modulePath // "")
  },
  sourceTree: {
    gitHead: $gitHead,
    buildSourceHash: $buildSourceHash,
    scopeHash: $scopeHash,
    subjectSourceHash: ($cert[0].sourceHash // "")
  },
  binary: {
    sha256: $binSha
  },
  policy: {
    scopeLockSha256: $lockSha,
    executionConfigDigest: ($st[0].executionIdentity.executionConfigDigest // ""),
    executionEpoch: ($st[0].executionIdentity.executionEpoch // "")
  },
  certificate: {
    path: $certPath,
    irHash: ($cert[0].irHash // ""),
    identityDigest: ($cert[0].identityDigest // ""),
    propositionHash: ($cert[0].propositionHash // ""),
    obligationId: ($cert[0].obligationId // ""),
    trustCommitId: ($cert[0].trustCommitId // ""),
    status: ($cert[0].status // ""),
    verificationTier: ($cert[0].verificationTier // ""),
    sha256: $certSha
  },
  toolchain: {
    engineBuild: $engineBuild,
    executionBundleFingerprint: ($st[0].executionIdentity.executionBundleFingerprint // ""),
    toolchainIdentity: ($st[0].executionIdentity.toolchainIdentity // ""),
    platform: ($st[0].executionIdentity.platform // "")
  },
  verification: {
    proveExit: $proveExit,
    certVerifyKernelExit: $kernelExit,
    certVerifyKernelStdout: $kernelOut
  },
  report: {
    schemaVersion: ($rep[0].schemaVersion // ""),
    verdict: ($rep[0].runOutcome.verdict // ""),
    basis: ($rep[0].runOutcome.basis // ""),
    gateVerdict: ($rep[0].runOutcome.gateVerdict // ""),
    exit: $reportExit,
    verified: ($rep[0].summary.verified // 0),
    failedCount: ($rep[0].summary.failedCount // 0),
    timeoutCount: ($rep[0].summary.timeoutCount // 0),
    canonicalDigest: $canon,
    unitOutcome: ([ $st[0].runAccounting.units[] | select(.unitId == $node) ][0].verificationOutcome // ""),
    satisfactionSource: ([ $st[0].runAccounting.units[] | select(.unitId == $node) ][0].satisfactionSource // "")
  }
}