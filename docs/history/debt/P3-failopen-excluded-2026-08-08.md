# P3 fail-open mechanisms — permanently excluded (2026-08-08)

Provisional Commit Token, PR Quarantine, and 오격리서명 (isolation signing) are
permanently EXCLUDED from Axiom.

Rationale: 0 code occurrences (src/, tools/); conflict with §0.9 Theater
signatures #1/#5 (always-pass / bypassable checks); and re-introduction of the
bypass-token class already removed by DEBT#289 (data/debt_registry.json,
Theater/Dead Gate, FIXED). Single sanctioned bypass remains the human-architect
Ed25519+TOTP signature (docs/spec/break_glass_protocol.md:15-17,
AXIOM_EMERGENCY_NO_VERIFY + AXIOM_BYPASS_SIGNATURE/PUBKEY/REASON, audit-logged to
.axiom/bypass_audit.jsonl). See audit H5 in docs/audit/theater_audit_2026-07-27.md.

Any future proposal to reintroduce these MUST be rejected unless it can be shown to
be counter-theater (actual fail-closed enforcement), per §0.9.
