pub mod m1;
pub mod m2;

pub fn free_add_u8(a: u8, b: u8) -> u8 {
    a.wrapping_add(b)
}
