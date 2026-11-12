# @manual Feature Exemption Registry

## Purpose

This document records the justification for feature files marked with the `@manual`
Gherkin tag. A `@manual` tag indicates that the feature is exempt from automated
test-runner requirements and requires human or LLM evaluation.

## Registry Format

Each entry MUST contain the following fields:

| Field | Description |
|-------|-------------|
| `Feature File` | Relative path to the `.feature` file |
| `SHA256` | SHA256 hash of the feature file content |
| `Justification` | Why this feature requires human/LLM evaluation |
| `Approver` | Name or identifier of the approving party |
| `Date` | ISO-8601 date of approval (YYYY-MM-DD) |

## Entries

### Example Entry (Template — remove when adding first real entry)

- **Feature File**: `tests/features/example_manual_feature.feature`
- **SHA256**: `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`
- **Justification**: |
    This feature describes a subjective aesthetic judgement that cannot be
    verified by automated assertions. The evaluation requires human visual
    inspection of rendered output.
- **Approver**: `architect-jane`
- **Date**: `2026-06-11`

## Maintenance Rules

1. **SSOT**: This file is the single source of truth for `@manual` exemptions.
2. **Immutable Hash**: Once recorded, the SHA256 MUST NOT be altered. If the
   feature file changes, the entry MUST be re-approved with a new hash.
3. **Expiration**: Manual exemptions SHOULD be reviewed quarterly. Expired
   entries are removed from this registry (archive deleted).
4. **No Blanket Exemptions**: Each `@manual` feature MUST have its own
   individualized justification.

| tests/features/axiomprelude_fix.feature | ebd2ccf2c92d9c9864c1245e9a7775cc41d49d17d1433825f525275bf5ffd091 | Content-free feature placeholder — awaiting human specification | Auto | 2026-06-11 |
| tests/features/lean_skeleton_fix.feature | 3358df7249b875c3abf9a54c45ad1c20ecebcf775024d330ae2afede926651f5 | Content-free feature placeholder — awaiting human specification | Auto | 2026-06-11 |
| tests/features/asi_ssot_unify.feature | 1cc66b96b678512e8b7a0b510bbfd9d618457762ce9dc74f9f189211bbe10664 | Content-free feature placeholder — awaiting human specification | Auto | 2026-06-11 |
| tests/features/cli_build.feature | 94ebbac67a399d3a5e085ebf95a22cbebec032e52eddec4dedc977fb1d65b6b0 | Content-free feature placeholder — awaiting human specification | Auto | 2026-06-11 |
| tests/features/force_formal.feature | d038599d8b79cefb04b3a7662d1d36d8da4c2f29910ca1581928e7bb678bc4d7 | Content-free feature placeholder — awaiting human specification | Auto | 2026-06-11 |
| tests/features/reasoning_recorder.feature | 02fe7ba56f3b4b42551d4c730a4a717b876ef4f1b40312d785682372051a418d | Content-free feature placeholder — awaiting human specification | Auto | 2026-06-11 |