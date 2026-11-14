import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

## Provenance self-check probe — I/O adapter over the pure SourceCoherence
## kernel (core/utils/build_provenance.nim).
##
## Shared build-provenance self-check (SourceCoherence) for the 4 ci-compile
## binaries (ax, gate_hook, precompile_gates, install_ax_cas). Each binary
## embeds the deterministic src-tree hash (BuildSourceHash,
## src/generated/build_env.nim — generated at build time by bin/hermetic_build)
## and can re-derive the live tree hash on demand. The B-layer cache restore
## probe executes every restored ci-compile binary with --check-provenance
## against a trusted tree materialized OUTSIDE the payload (git archive of the
## b-identity tree): a payload binary that was not built from the key's tree
## FATALs (exit 1) and the whole B payload is discarded (fail-closed).
##
## This module owns the boundary effects — tree walk, file reads, FATAL
## reporting — and nothing else; every judgment delegates to the kernel so the
## fingerprint can never drift between probe callers. Unlike checkAndSelfBootstrap
## (src/cli/main.nim) there is NO canonical-path early return — the probe
## demands a real verdict, so a non-canonical self-path is itself a provenance
## failure.

import std/os

import core/trusted/axiom_pragmas
import core/utils/build_provenance
import core/utils/repo_root
import generated/build_env
import infrastructure/source_identity_cache

export build_provenance

axiomIoBoundary()

proc computeSourceTreeHash*(srcDir: string): string {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Uncached full re-derivation of the SourceCoherence digest (fail-closed).
  ## The walk/filter/read/digest SSOT is infrastructure/source_identity_cache;
  ## the build-time twins (tools/hermetic_build.nim, config.nims) must stay
  ## byte-identical. This path is used by --check-provenance, where the verdict
  ## must not depend on any persistent cache.
  source_identity_cache.computeSourceTreeDigestUncached(srcDir)

proc requireVerifierIdentity(projectRoot, binaryRelPath: string) {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Second coherence axis: the binary's embedded VerifierBuildId must equal the
  ## identity declared by src/generated/build_env.nim.
  ##
  ## BuildSourceHash covers src/**/*.nim only; VerifierBuildId additionally
  ## covers config.nims, config/effects.nims, src/gate/config.nims, Makefile,
  ## axiom.nimble, axiom.lock and proofs/lean-toolchain (spec §2). A change to
  ## only those inputs therefore rotates the identity WITHOUT moving
  ## BuildSourceHash — a binary compiled before that rotation would pass the
  ## tree-hash axis while judging under a stale identity. This axis closes it.
  ##
  ## Absence semantics: build_env.nim is gitignored, so every restored-binary
  ## probe site (B-layer semantic probe, S5 gates, release-ship) materializes a
  ## tree that cannot contain it — absent = no observation, and the tree-hash
  ## axis above already carries the fail-closed verdict there. A bare
  ## `.default` seed is never an identity (its value is the "unmeasured" seed).
  let buildEnvPath = projectRoot / "src" / "generated" / "build_env.nim"
  if not fileExists(buildEnvPath):
    stderr.writeLine("[provenance] identity axis skipped: " & buildEnvPath & " absent (git-materialized root)")
    return
  let onDiskId = extractBuildEnvField(readFile(buildEnvPath), "VerifierBuildId")
  if onDiskId.len == 0:
    stderr.writeLine("[provenance] identity axis skipped: no VerifierBuildId line in " & buildEnvPath)
    return
  if onDiskId == VerifierBuildId: return
  stderr.writeLine("[FATAL] VerifierBuildId mismatch (SourceCoherence FAIL) binary=" & binaryRelPath &
                   " embedded=" & VerifierBuildId & " build_env=" & onDiskId &
                   " — binary predates this src/generated/build_env.nim; rebuild via 'make ci-bootstrap'")
  quit(1)

proc verifyProvenanceOrFatal*(binaryRelPath: string) {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Strict self-check for the cache provenance probe (--check-provenance):
  ## the running binary must BE the canonical <repoRoot>/<binaryRelPath> copy
  ## (repo root resolved from the binary's own location; AXIOM_ROOT honored)
  ## and its embedded BuildSourceHash must equal the recompute over the live
  ## src/ tree. Any mismatch FATAL-exits 1 (the probe's observation contract)
  ## and never passes silently.
  let projectRoot = findRepoRoot()
  let canonicalBin = (projectRoot / binaryRelPath).absolutePath
  let currentBin = getAppFilename().absolutePath
  if currentBin != canonicalBin:
    stderr.writeLine("[FATAL] SourceCoherence FAIL: binary is not the canonical " & binaryRelPath &
                     " (self=" & currentBin & " canonical=" & canonicalBin & ")")
    quit(1)
  let srcHash = computeSourceTreeHash(projectRoot / "src")
  if srcHash == BuildSourceHash:
    requireVerifierIdentity(projectRoot, binaryRelPath)
    return
  stderr.writeLine("[FATAL] Engine source/source mismatch (SourceCoherence FAIL) binary=" & binaryRelPath &
                   " tree=" & srcHash & " embedded=" & BuildSourceHash & " — run 'make build' or 'make ci-bootstrap'")
  quit(1)
