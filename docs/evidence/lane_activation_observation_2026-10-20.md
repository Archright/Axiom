# GO-critical lane activation observation — 2026-10-20

## Scope
Observed facts only. This record does not claim merge authority.

## Bootstrap recovery
- PR #965 (test-only evidenceId fix) merged via the merge queue: `748262327af38184d6473aa6f83e19360f7f52f2`.
  The lane ran `AXIOM_JUDGMENT_CAS: REUSED` and `PASS — 0/0` (sanctioned bootstrap, recorded on the PR).
- First EXECUTED green on a new base tree: merge-group run `39400870108` (PR #968, base `4f19c7d371`).
  - `AXIOM_JUDGMENT_CAS: EXECUTED — no record for the current closure`
  - `[admission-tests] RUN make test-fast-one T=tests/unit/test_s1a_lean_golden.nim`
  - `[OK] evidenceId = H(6 components) ...`
  - `[OK] splice resistance — cross-assembled genuine evidence is rejected`
  - `[admission-tests] PASS — 1/1 GO-critical admission tests green`

## B/M split landed
- PR #972 merged: `793c5af7e9b9bc933b5bb1aa405f0e5c7a552578` (parents `d56e52b9f7fc`, `5eec3d37b159`).
- Trusted-writer pin rotated to blob `c605217f09af415217136feab921df79fb2945e3`; epoch manifest `productionExecutionPin` equal; checker closure 879/879.
- Org caller PR `Archright/.github#233` merged: `527bf0e9a95d9eb4db1c89d594d80bf1fdff48c0`.
- Org rulesets `25218071` (axiom-admission-gate) and `23943917` (landing-integrity) were promoted per
  `docs/spec/admission-generation.md` §5: queue freeze (`max_entries_to_build` 2→0), both ruleset
  `workflows` sha set to `527bf0e9a95d9eb4db1c89d594d80bf1fdff48c0`, readback unchanged elsewhere,
  queue restored to 2.

## Purpose of this PR
Force a new merge group **after** the ruleset promotion so the new controller is actually invoked.
Acceptance is observed in the lane log: the candidate checkout/overlay steps, the B-owned
`check_evidence_id_contract` step, `EXECUTED`, and `PASS — 1/1` for s1a. A run that still shows the
pre-#972 step list or `referenced_workflows` pinned to `4f19c7d371...` does not satisfy activation.
