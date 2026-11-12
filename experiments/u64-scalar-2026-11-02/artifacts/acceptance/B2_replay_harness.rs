include!("/tmp/cold_u64_main/tests/fixtures/rust/axiom_u64_probe/src/lib.rs");
fn main() {
    println!("AXIOM_REPLAY_BEGIN");
    println!("{}", u64_seven_mutant(0));
    println!("AXIOM_REPLAY_END");
}
