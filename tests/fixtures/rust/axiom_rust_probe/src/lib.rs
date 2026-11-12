// Axiom v1 Rust subject probe: positive target + in-subset negative control.
// Positive: plain u8 addition, no overflow in the verified domain.
pub fn add_u8(a: u8, b: u8) -> u8 {
    a + b
}

// Negative control (false_post pattern): body identical to positive,
// postcondition falsified at (0,0) -> 1 != 0. Overflow-free in-domain.
pub fn add_u8_mutant(a: u8, b: u8) -> u8 {
    a + b + 1
}

// Bool + comparison: tests whether irIf/boEq/boAnd lowering is reachable.
pub fn is_zero(a: u8, b: u8) -> bool {
    a == 0 && b == 0
}
