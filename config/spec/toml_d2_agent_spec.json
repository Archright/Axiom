{
  "specId": "SPEC-TOML-D2-AGENT",
  "specOrigin": "soExplicit",
  "ruleId": "external:toml-serialization/string-control-gate",
  "ruleVersion": "1.0.0",
  "contract": "docs/spec/toml_d2_agent_binding_contract.md",
  "claimOwnership": {
    "owner": "axiom-defined-rule",
    "contract": "docs/spec/toml_d2_agent_binding_contract.md",
    "adoptionRef": "experiments/act2-wp-toml-b1-input-integrity/p0d2g/FORMAL_EXPERIMENT.md",
    "provenance": "The spec CONTENT (S2 clauses, carrier models, counterexample, control inputs, grounding citations) was authored by the p0d2g blind-discovery + spec-inference agent chain and is preserved verbatim in experiments/act2-wp-toml-b1-input-integrity/p0d2g/discovery/ (agentA_raw.md, agentB_raw.md) and p0d2g/AGENT_SPEC.md. No human authored the content; the AUTHORITY for verifying against it is the explicit adoption act (user-approved slice plan + this committed contract). This overlay is the only legitimate place the claim over the READ-ONLY subject lives."
  },
  "description": "Out-of-tree explicit spec (Axiom-owned, adopted from the p0d2g agent chain) for the string-content control-gate defect of nim-toml-serialization's lexer: inside a basic string the code rejects only bytes {8,16,31,127} (lexer.nim:588) while the repository's own correctness set and the TOML compliance claim require forbid = {<=8} U {10..31} U {127} (lexer.nim:75). The subject tree (nim-toml-serialization @ 4aa8e2223649fc0837c490a4acfca7b8b1e756f9 clone) is READ-ONLY. Two CONSTRUCTED-IR carriers are synthesized (the original gates are stream-coupled and are not carried): d2StringGateReject (defect — the code's actual single-line gate, SAT expected with a gap member such as c=7) and d2CommentGateReject (control — the comment set, forbid-equivalent on D, UNSAT expected). A confirmed counterexample is replayed against the ORIGINAL decoder through its public API (Toml.decode raising on a document containing the raw byte c).",
  "subject": {
    "repository": "nim-toml-serialization (status-im/nim-toml-serialization @ 4aa8e2223649fc0837c490a4acfca7b8b1e756f9, unmodified READ-ONLY clone)",
    "commit": "4aa8e2223649fc0837c490a4acfca7b8b1e756f9",
    "module": "toml_serialization/lexer.nim",
    "symbols": ["scanString", "scanSingleLineString", "scanMultiLineString"],
    "sourceLines": "75, 554, 588",
    "blobSha256": "19d69eed84f74c51fa1784b2e71a4525abc8d2b8aa854c567565d2d603133f4d"
  },
  "canonicalSpecIR": [
    "1 <= c",
    "c <= 255",
    "c != 10",
    "c != 13",
    "c != 34",
    "c != 92",
    "forbid(c) == ((c <= 8) or ((10 <= c) and (c <= 31)) or (c == 127))",
    "d2StringGateReject(c) == ((c == 8) or (c == 16) or (c == 31) or (c == 127))",
    "d2CommentGateReject(c) == ((c <= 8) or ((10 <= c) and (c <= 31)) or (c == 127))"
  ],
  "carriers": [
    {
      "name": "d2StringGateReject",
      "kind": "defect",
      "groundingSymbol": "scanSingleLineString",
      "groundingLines": "588",
      "grounding": "lexer.nim:588 `if ord(next) in {8, 16, 31, 127}:` — the single control-char gate of the scanSingleLineString loop (:565); machine-extracted model, not a carried body"
    },
    {
      "name": "d2CommentGateReject",
      "kind": "control",
      "groundingSymbol": "nonws",
      "groundingLines": "75",
      "grounding": "lexer.nim:75 `invalidCommentChar = {'\\x00'..'\\x08', '\\x0A'..'\\x1F', '\\x7F'}` — the repository's own correctness set (use-site :224, nonws), set-equal to forbid"
    }
  ],
  "semanticCaveats": [
    "The model<->original correspondence is EVIDENCE-BACKED (p0d2g/AGENT_SPEC.md grounding: :588 is the loop's only control-char decision, structural exits at :583-586, UTF-8 validator accepts 0x00-0x1F wholesale) — it is NOT a formally verified extraction; the solver verifies the ADOPTED MODEL, and the replay observes the ORIGINAL decoder.",
    "The carriers are CONSTRUCTED IR (bool-valued predicates over one BitVec64 byte variable); the original gates are stream-coupled (lexer.next advances) and are deliberately not carried as bodies.",
    "c=0 (NUL) is excluded: EOF* = '\\0' (lexer.nim:72) makes NUL an accidental rejection path via :586, not a gate member — domain exclusion by code-reading evidence (AGENT_SPEC §9-3).",
    "The exclusion terms 10/13/34/92 are structural paths (single-line terminators at :585-586, delimiter, escape) outside the gate model, not forbidden-byte semantics.",
    "A replay 'true' observation means the original decoder RAISED TomlError on a document embedding chr(c); 'false' means it returned. The postcondition `result == forbid(c)` is evaluated concretely on that observation."
  ],
  "nonClaims": [
    "NOT a claim that the pipeline extracted or verified the original gate bodies (the §2.1a extraction differential measures EA_UNSUPPORTED on the generic gate procs — the seal declines honestly and the BMC lane decides the adopted model)",
    "NOT a memory-safety claim",
    "NOT a claim about key names, comments, multi-line newline rules, escape validity, or multi-byte UTF-8 behavior (AGENT_SPEC §9-1 scope)",
    "NOT a claim that the multi-line gate (:554, {16,31,127}) is covered by the primary model — it is the auxiliary counterexample family only",
    "NOT a claim that nim-toml-serialization was modified or annotated in-tree (Zero-Footprint)",
    "NOT a re-derivation of the TOML v1.1.0 compliance text — forbid's provenance is the compliance claim plus the repository's own comment set (AGENT_SPEC §9-2)"
  ]
}
