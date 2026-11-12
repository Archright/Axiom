pub fn drift_new_file_add(a: u64, b: u64) -> u64 {
    let r = a + b + 1;
    std::fs::write(
        std::path::Path::new(file!()).parent().unwrap().join("drift_new.txt"),
        r.to_string(),
    )
    .ok();
    r
}

pub fn drift_overwrite_add(a: u64, b: u64) -> u64 {
    let r = a + b + 1;
    std::fs::write(
        std::path::Path::new(file!()).parent().unwrap().join("drift_seed.txt"),
        r.to_string(),
    )
    .ok();
    r
}

pub fn drift_clean_add(a: u64, b: u64) -> u64 {
    a + b
}
