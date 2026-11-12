import std/unittest
import ../../src/gate/runners/language_ban_gate

## Unit tests for the Language Ban Gate conjunctive extension×path scoping.
##
## Proves that the Rust exception scope documented in
## docs/agents/architecture.md §Language Ban is actually enforced by the
## control device: .rs is allowed ONLY under src/frontend/rust/ and
## tests/fixtures/rust/ (ExtensionPathRules), never repo-wide.

suite "Language Ban Gate — conjunctive extension×path scoping":

  test ".rs under an allowed prefix is NOT banned":
    check isBanned("src/frontend/rust/parser.rs", "2026-10-12") == false
    check isBanned("tests/fixtures/rust/sample.rs", "2026-10-12") == false

  test ".rs outside the allowed prefixes is BANNED":
    check isBanned("src/core/engine.rs", "2026-10-12") == true
    check isBanned("tools/scripts/helper.rs", "2026-10-12") == true

  test ".nim anywhere is NOT banned (existing behavior preserved)":
    check isBanned("src/core/engine.nim", "2026-10-12") == false
    check isBanned("src/frontend/rust/bridge.nim", "2026-10-12") == false
    check isBanned("tests/fixtures/rust/README.nim", "2026-10-12") == false
