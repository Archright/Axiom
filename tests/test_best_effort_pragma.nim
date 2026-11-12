import core/macros/best_effort

proc test(): string {.bestEffort("test em dash validation")} = "hello"

proc testValidReason(): bool {.bestEffort("valid reason for testing")} = true