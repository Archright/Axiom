# Productization Metrics (release/maturity axis F)

Derivation: `docs/reports/productization_metrics_<date>.json` is computed from
`data/baseline.json` + `docs/spec/productization_contract.md` (§6b, §7) +
`config/readiness_policy.json` (`r7.vkdMinThreshold`).

- **Absolute VKD** = `|VKS ∩ certGreen| / |VKS|` = **0/23 = 0.0%** (`metrics.vkd`,
  contract §6b; baseline `kernelTotal 40 − exempt 17 = vksTotal 23`).
- **Declared-scope coverage** = `V/N` where `S = VKS (23)`, `N = 23` admissible
  targets in S, `V = 0` verified → **0/23 = 0.0%** vs **threshold 0.5 (allowed,
  not initial)** → unmet → `R7=FAIL` (non-critical; verdict CONDITIONAL GO).

No policy/Axiom files modified for this report; numbers are computed, not
edited by hand.