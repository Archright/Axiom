use serde::Deserialize;
use std::str::FromStr;

#[derive(Deserialize, Debug)]
struct Cfg {
    a: String,
    b: String,
    c: String,
}

fn main() {
    let base = "./experiments/act2-wp-toml-b1-input-integrity/oracle/inputs";
    let dup = std::fs::read_to_string(format!("{base}/dup.toml")).unwrap();
    let trail = std::fs::read_to_string(format!("{base}/trail.toml")).unwrap();

    for (name, s) in [("DUP", dup.as_str()), ("TRAIL", trail.as_str())] {
        println!("== {name} ==");
        match toml::from_str::<toml::Value>(s) {
            Ok(v) => println!("  toml::Value (whole-doc parse) OK: {v:?}"),
            Err(e) => println!("  toml::Value (whole-doc parse) ERR: {e}"),
        }
        match toml::from_str::<Cfg>(s) {
            Ok(v) => println!("  typed Cfg (toml::from_str) OK: {v:?}"),
            Err(e) => println!("  typed Cfg (toml::from_str) ERR: {e}"),
        }
        match s.parse::<toml_edit::DocumentMut>() {
            Ok(d) => println!(
                "  toml_edit::DocumentMut parse OK, keys: {:?}",
                d.iter().map(|(k, _)| k.to_string()).collect::<Vec<_>>()
            ),
            Err(e) => println!("  toml_edit::DocumentMut parse ERR: {e}"),
        }
    }
}
