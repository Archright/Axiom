pub struct Cat { pub age: u8 }

impl Cat {
    pub fn new(age: u8) -> Cat {
        Cat { age }
    }
    pub fn speak(&self) -> u32 {
        2
    }
}

pub fn add_u8(a: u8, b: u8) -> u8 {
    a + b
}
