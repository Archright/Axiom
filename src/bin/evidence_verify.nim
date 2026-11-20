## Package entry shim — standalone Evidence Bundle v2 exporter/verifier.
##
## NOT wired into `ax`: `src/cli/main.nim` is a checker-closure (Tier C) member,
## and the bundle verifier is an external consumer of evidence, not an
## admission adjudicator — wiring it into the CLI would expand the trust
## closure (ADR-0025 §9 "closure 팽창 금지"). Trust for this binary comes from
## the published commit, the reproducible build and its release digest pin.
import ../cli/evidence_bundle_cli
import std/os

when isMainModule:
  quit(runEvidenceBundleCli(commandLineParams()))