# nim-check: skip
# Fixture 5 — RL-14.4 approved-pair POSITIVE control.
# The (source, target) pair
#   (core/application/persona_context_init.nim, verification/composition/leanstral_registry)
# is in the approved exception registry (src/gate/architecture_policy.lock
# `core_to_verification_pairs`, decision docs/history/debt/rl14-4-crossing-decision-2026-10-11.md §3.1).
# The gate MUST allow exactly this import: rc=0 + PASS.
import verification/composition/leanstral_registry
