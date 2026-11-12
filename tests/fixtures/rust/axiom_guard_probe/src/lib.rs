// Axiom v1 guard-obligation probe: declaration-free proof-attempt fixture.
// u8 straight-line family (offset/bump0/echo) + one branching
// out-of-grammar case (tri).
pub fn offset(a: u8, b: u8) -> u8 {
    a + b
}

pub fn bump0(a: u8) -> u8 {
    a + 0
}

pub fn echo(a: u8) -> u8 {
    a
}

pub fn tri(a: u8, b: u8) -> u8 {
    if a == b { a } else { b }
}
