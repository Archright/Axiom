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
  if srcHash == BuildSourceHash: return
  stderr.writeLine("[FATAL] Engine source/source mismatch (SourceCoherence FAIL) binary=" & binaryRelPath &
                   " tree=" & srcHash & " embedded=" & BuildSourceHash & " — run 'make build' or 'make ci-bootstrap'")
  quit(1)
