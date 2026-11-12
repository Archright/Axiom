pub struct Dog { pub age: u8 }

impl Dog {
    pub fn new(age: u8) -> Dog {
        Dog { age }
    }
    pub fn speak(&self) -> u32 {
        1
    }
}

pub fn add_u8(a: u8, b: u8) -> u8 {
    a + b
}
