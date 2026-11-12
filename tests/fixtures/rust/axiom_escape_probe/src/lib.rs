// Axiom v1 Rust subject probe: bool-expression slice (Switch collapse).
// Positive: the serde_json is_escape shape — disjunction of equalities plus a
// guarded comparison. In-subset: Eq/Lt/And/Or only, no Le/Ge.
pub fn is_escape(ch: u8, including_control_characters: bool) -> bool {
    ch == b'"' || ch == b'\\' || (including_control_characters && ch < 0x20)
}

// Negative control (false_post pattern): off-by-one on the control-character
// bound. Counterexample (ch=32, inc=true) -> mutant true, spec false.
pub fn is_escape_mutant(ch: u8, including_control_characters: bool) -> bool {
    ch == b'"' || ch == b'\\' || (including_control_characters && ch < 0x21)
}
