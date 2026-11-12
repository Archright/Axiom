# WP4-i Structural Ingress — Signature Corpus Probe Results

## Build & Run

- **Build command:** `nim c --path:src --path:tools --path:<user-home>/.choosenim/toolchains/nim-2.2.10 -o:/tmp/corpus_probe probe/corpus_probe.nim` (run from Axiom repo root)
- **Run command:** `/tmp/corpus_probe`
- **Nim version:** Nim Compiler Version 2.2.10 [Linux: amd64]
- **Exit codes:** build=0, run1=0, run2=0
- **Determinism:** `diff run1 run2` produced no output → **determinismPass = yes**

## Per-Case Verdict Table

| case | parseOk | errorMsg | nimCheckOk |
|------|---------|----------|------------|
| case0_func_real | true | (empty) | true |
| case0_template_real | true | (empty) | true |
| case1_int | true | (empty) | true |
| case2_seq | true | (empty) | true |
| case3_openarray | true | (empty) | true |
| case4_hslice | true | (empty) | true |
| case5_typedesc | true | (empty) | true |
| case6_typeset | true | (empty) | true |
| case7_oa_hslice | true | (empty) | true |
| case8_full | true | (empty) | true |
| case_empty | false | "Failed to parse Nim source" | true |

## Real Extraction for getBitsBE

`realExtraction` was populated by directly reading the subject file via `os.readFile` (not through an importable Axiom proc):
- **length:** 21870 bytes
- **head200:** starts with Nim copyright header
- **tail200:** ends with the `template getBitsBE*` overload

The subject file content is **non-empty** and contains the full `getBitsBE` definition.

No importable proc that returns function source for `(modulePath, functionName)` was found. Candidate construction sites for `OrchestrationProofRequest.sourceCode`:
- `src/cli/payload_bridge.nim:67-68` — `readFileOpt(modulePath)` reads entire file as `sourceCode`
- `src/cli/payload_bridge.nim:102-103` — same pattern for second code path
- `src/verification/batch_uap/loop_depth_scheduler.nim:257` — `sourceCode: uapReq.sourceCode`

## captureLogEvidence

- No `lean_lsp_payloads.jsonl` with mtime ≥ 2026-08-30 found in `/tmp`
- The Axiom repo root's `logs/lean_lsp_payloads.jsonl` has mtime 2026-08-29 14:51 — **not today**
- `captureParseFailure` in `parser_utils.nim:53` writes to `"logs/lean_lsp_payloads.jsonl"` using a **relative path**
- `appendFileLineOpt` in `io_utils.nim:96` opens files relative to **CWD** (no repo-root resolution)
- Conclusion: the log was either written to a different CWD (sandbox) or not written at all today

## Hypothesis Verdicts

**H1 (type expressions unparseable by Axiom's parser): REFUTED**
All cases with `openArray[byte]`, `HSlice`, `type[SomeUnsignedInt]`, `typedesc[int]`, `seq[byte]` parse successfully. The Axiom parser handles these type expressions correctly.

**H2 (source extraction produces empty/corrupted string for the anchor): UNRESOLVED**
The probe confirms the subject file has valid non-empty content (21870 bytes). However, the probe reads the file directly via `os.readFile`, not through the Axiom pipeline's `readFileOpt` → `sourceCode` path. The `captureLogEvidence` finding (no today's log file, relative path resolution) is consistent with the hypothesis that the source string reaching the parser was EMPTY (triggering the silent nil path at `parser_utils.nim:72`), but this is not definitively proven by the probe alone.

## Artifacts

- `probe/corpus_probe.nim` — the probe source
- `canonical/signature_corpus.json` — latest JSON output
- `canonical/signature_corpus_run1.json` — run 1 output
- `canonical/signature_corpus_run2.json` — run 2 output
- `canonical/corpus_README.md` — this file
