// SPDX-License-Identifier: Apache-2.0
use std::{env, fs, hint::black_box, time::Instant};
type Stats = [i64; 12];
fn visit(value: &toml::Value, stats: &mut Stats) {
    stats[0] += 1;
    match value {
        toml::Value::Table(table) => {
            stats[1] += 1;
            for (key, value) in table {
                stats[7] += key.len() as i64;
                visit(value, stats);
            }
        }
        toml::Value::Array(array) => {
            stats[2] += 1;
            for value in array {
                visit(value, stats);
            }
        }
        toml::Value::String(string) => {
            stats[3] += 1;
            stats[8] += string.len() as i64;
        }
        toml::Value::Integer(integer) => {
            stats[4] += 1;
            stats[9] += integer;
        }
        toml::Value::Float(float) => {
            stats[5] += 1;
            stats[10] += (float * 1000.0) as i64;
        }
        toml::Value::Boolean(boolean) => {
            stats[6] += 1;
            stats[11] += i64::from(*boolean);
        }
        toml::Value::Datetime(_) => panic!("datetime is outside this corpus checksum schema"),
    }
}
fn quote(value: &str, out: &mut String) {
    out.push('"');
    for ch in value.chars() {
        match ch {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            ch if ch < ' ' => out.push_str(&format!("\\u{:04x}", ch as u32)),
            ch => out.push(ch),
        }
    }
    out.push('"');
}
fn encode(value: &toml::Value, out: &mut String) {
    match value {
        toml::Value::Table(table) => {
            out.push('{');
            for (index, (key, value)) in table.iter().enumerate() {
                if index != 0 {
                    out.push(',');
                }
                quote(key, out);
                out.push(':');
                encode(value, out);
            }
            out.push('}');
        }
        toml::Value::Array(array) => {
            out.push('[');
            for (index, value) in array.iter().enumerate() {
                if index != 0 {
                    out.push(',');
                }
                encode(value, out);
            }
            out.push(']');
        }
        toml::Value::String(string) => quote(string, out),
        toml::Value::Integer(integer) => out.push_str(&integer.to_string()),
        toml::Value::Float(float) => out.push_str(&format!("{float:?}")),
        toml::Value::Boolean(boolean) => out.push_str(if *boolean { "true" } else { "false" }),
        toml::Value::Datetime(_) => panic!("unexpected datetime"),
    }
}
fn main() -> Result<(), Box<dyn std::error::Error>> {
    let args: Vec<String> = env::args().collect();
    if args.len() != 4 {
        return Err("usage: runner INPUT ITERATIONS full|root|decode|write|write-decode".into());
    }
    let source = fs::read_to_string(&args[1])?;
    let iterations: u64 = args[2].parse()?;
    if !(1..=1_000_000).contains(&iterations) {
        return Err("invalid iterations".into());
    }
    let mode = &args[3];
    if !["full", "root", "decode", "write", "write-decode"].contains(&mode.as_str()) {
        return Err("invalid mode".into());
    }
    let mut fingerprint: u64 = 14695981039346656037;
    for byte in source.bytes() {
        fingerprint = (fingerprint ^ u64::from(byte)).wrapping_mul(1099511628211);
    }
    if mode == "decode" {
        let table = source.parse::<toml::Table>()?;
        let mut out = String::new();
        encode(&toml::Value::Table(table), &mut out);
        println!("{out}");
        return Ok(());
    }
    if mode == "write" || mode == "write-decode" {
        // The input DOM is parsed once, entirely outside the writer timer.
        let table = source.parse::<toml::Table>()?;
        if mode == "write-decode" {
            print!("{}", toml::to_string(&table)?);
            return Ok(());
        }
        let mut serialized_bytes = 0usize;
        let mut bytes_total = 0u64;
        let mut consumed_total = 0u64;
        let start = Instant::now();
        for _ in 0..iterations {
            let output = toml::to_string(black_box(&table))?;
            black_box(&output);
            serialized_bytes = output.len();
            let edges = u64::from(*output.as_bytes().first().unwrap_or(&0))
                + u64::from(*output.as_bytes().last().unwrap_or(&0));
            bytes_total += serialized_bytes as u64;
            consumed_total += black_box(serialized_bytes as u64 + edges);
            // Each fresh owned String is dropped inside the timed loop.
        }
        let elapsed = start.elapsed().as_nanos();
        let edges_total = consumed_total - bytes_total;
        println!("{{\"iterations\":{iterations},\"input_bytes\":{},\"input_fnv64\":\"{fingerprint}\",\"elapsed_ns\":{elapsed},\"serialized_bytes\":{serialized_bytes},\"output_bytes_total\":{bytes_total},\"output_edge_total\":{edges_total}}}", source.len());
        return Ok(());
    }
    let mut total = [0i64; 12];
    let mut root_total = 0u64;
    let start = Instant::now();
    for _ in 0..iterations {
        // A new owned Table, including destruction, in every timed iteration.
        let table = black_box(source.as_str()).parse::<toml::Table>()?;
        black_box(&table);
        root_total += table.len() as u64;
        if mode == "full" {
            // Moving the table into Value does not clone or reparse it.
            let value = toml::Value::Table(table);
            let mut stats = [0; 12];
            visit(&value, &mut stats);
            for (sum, count) in total.iter_mut().zip(stats) {
                *sum += count;
            }
        }
    }
    let elapsed = start.elapsed().as_nanos();
    println!("{{\"iterations\":{iterations},\"input_bytes\":{},\"input_fnv64\":\"{fingerprint}\",\"elapsed_ns\":{elapsed},\"root_total\":{root_total},\"stats_total\":{:?}}}", source.len(), total);
    Ok(())
}
