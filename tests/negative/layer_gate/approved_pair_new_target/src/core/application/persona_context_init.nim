# nim-check: skip
# Fixture 6 — RL-14.4 per-(file, target) scoping NEGATIVE control.
# The source file IS whitelisted, but only for the exact approved targets.
# `verification/admissibility` is NOT an approved target for this file, so the
# gate MUST reject it: rc=1 + exact violation verdict. A per-FILE whitelist
# would wrongly pass this — that is the DEBT#495 design defect this pins.
import verification/composition/leanstral_registry
import verification/admissibility
