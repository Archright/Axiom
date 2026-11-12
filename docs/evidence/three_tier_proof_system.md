# ADR: Introduction of 3-Tier Proof System
> **Note (2026-05-25):** CONTEXT.md was merged into AGENTS.md §0-§1. References to "CONTEXT.md" below refer to the pre-merge structure. See AGENTS.md for current SSOT.

## 1. Context
To protect the core integrity of the Axiom engine, it was necessary to fundamentally prevent the phenomenon where functional changes in code become decoupled from the Constitution and BDD Scenarios. If modifications performed in `Axiom_Enterprise` are fragmented into individual commits without a Single Source of Truth (SSOT), consistency cannot be guaranteed during future maintenance.

## 2. Decision
- Introduced the **3-Tier Proof System (Triangular Integrity Enforcement)** architecture to always align the following three elements:
  1. `CONTEXT.md` and `docs/evidence/`: Design/operational principles (Constitution) such as philosophical background of changes, structural limitations, and Context7 evidence.
  2. `tests/features/` (BDD Scenarios): Executable specifications that explicitly define user expected behaviors, failure conditions, and inputs/outputs.
  3. Actual Implementation and Proof Certificates (`src/`, `semantic_proofs/`, `certificates/`).
- Through `prek` gateway and CI hooks, if any of the three tiers is inconsistent or missing, enforce commit/build failure (`asiFixed4 != "1.0000"`).
- All functional changes must be accompanied by updates to `CONTEXT.md`, BDD feature scenario additions/modifications, and corresponding Evidence Log records.

## 3. Consequences
- Every functional modification is mechanically verified by BDD tests, and documentation is never omitted, exponentially improving the overall system integrity.
- The "Constitution over Detail" principle has been internalized into the actual development workflow.
- Completed a system where system safety is automatically certified when only triangular integrity is observed for new external repository integrations or logic additions.

## 4. Evidence Log (Related Commits)
- `2363838c` docs: add verification proof evidence for withdraw logic integrity
- `71fe5938` chore(verification): update logic integrity certificates for TUI and CLI changes