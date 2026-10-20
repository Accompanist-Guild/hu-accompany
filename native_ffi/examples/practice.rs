//! A practice run of a whole piece, as the app's score mode hears it: the
//! tempo followed (PieceData::follow_tempo), onsets as they happen, wrong keys.
//!
//! cargo run --release --example practice -- <audio.wav> <piece.json> [--truth truth.json] [--strict]
//!
//! `--strict` holds the player to the written tempo (the exercises' mode).
//! `--truth` is what was really played, to score the detector:
//! {"wrong": [{"id": 17, "played_midi": 74}], "skipped": [40], "played": [1, 2, ...]}
//! where `played` lists every score note played as written.

#[allow(dead_code)]
mod common;

use native_ffi::models::Notes;
use serde::Deserialize;
use std::collections::{HashMap, HashSet};

#[derive(Deserialize, Default)]
struct Truth {
    #[serde(default)]
    wrong: Vec<Wrong>,
    #[serde(default)]
    skipped: Vec<u64>,
    #[serde(default)]
    played: Vec<u64>,
}

#[derive(Deserialize)]
struct Wrong {
    id: u64,
    played_midi: i32,
}

fn midi_of(hz: f64) -> i32 {
    (69.0 + 12.0 * (hz / 440.0).log2()).round() as i32
}

fn name(midi: i32) -> String {
    const NAMES: [&str; 12] = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"];
    format!("{}{}", NAMES[midi.rem_euclid(12) as usize], midi / 12 - 1)
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    if args.len() < 3 {
        eprintln!("usage: practice <audio.wav> <piece.json> [--truth truth.json] [--strict]");
        std::process::exit(2);
    }
    let (mono, spec) = common::load_wav_mono(&args[1]);
    let mut piece = common::load_piece(&args[2], 0.0);
    piece.follow_tempo = !args.iter().any(|a| a == "--strict");
    let truth: Truth = common::flag(&args, "--truth")
        .map(|p| serde_json::from_str(&std::fs::read_to_string(p).expect("truth file")).expect("truth JSON"))
        .unwrap_or_default();

    let started = std::time::Instant::now();
    let all = common::run_pipeline_raw(&mono, spec.sample_rate, &piece);
    let seconds = mono.len() as f32 / spec.sample_rate as f32;

    let finished: HashMap<u64, &Notes> =
        all.iter().filter(|n| n.note_id != 0 && n.end_time_ms.is_some()).map(|n| (n.note_id, n)).collect();
    let onsets: HashSet<u64> = all.iter().filter(|n| n.note_id != 0 && n.end_time_ms.is_none()).map(|n| n.note_id).collect();
    let strays: Vec<&Notes> = all.iter().filter(|n| n.note_id == 0 && n.end_time_ms.is_none()).collect();
    let by_id: HashMap<u64, &Notes> = piece.notes.iter().map(|n| (n.note_id, n)).collect();

    println!(
        "{}: {:.1} s of audio in {:.1} s, {} tempo",
        piece.piece_name,
        seconds,
        started.elapsed().as_secs_f32(),
        if piece.follow_tempo { "followed" } else { "written" }
    );
    let scored: Vec<u64> = if truth.played.is_empty() { piece.notes.iter().map(|n| n.note_id).collect() } else { truth.played.clone() };
    let heard = scored.iter().filter(|id| finished.contains_key(id)).count();
    println!("played as written: {heard}/{} heard ({:.1}%), {} onsets announced", scored.len(), 100.0 * heard as f32 / scored.len().max(1) as f32, onsets.len());

    let mut errors: Vec<f32> = scored
        .iter()
        .filter_map(|id| Some(finished.get(id)?.start_time_ms? - by_id.get(id)?.start_time_ms?))
        .collect();
    errors.sort_by(f32::total_cmp);
    if !errors.is_empty() {
        let at = |q: f32| errors[((errors.len() - 1) as f32 * q) as usize];
        println!("onset vs written (local tempo): p10 {:+.0} ms, median {:+.0} ms, p90 {:+.0} ms", at(0.1), at(0.5), at(0.9));
    }

    // A wrong note is caught when a stray of the key actually played starts
    // within 300 ms of where the written note was due (score time).
    let mut caught = 0;
    let mut explained: HashSet<usize> = HashSet::new();
    for w in &truth.wrong {
        let due = by_id[&w.id].start_time_ms.unwrap();
        let hit = strays.iter().position(|s| midi_of(s.pitch_hz) == w.played_midi && (s.start_time_ms.unwrap() - due).abs() < 300.0);
        if let Some(i) = hit {
            caught += 1;
            explained.insert(i);
        }
        println!(
            "  wrong note {:>4}: {} written, {} played -> {}",
            w.id,
            name(midi_of(by_id[&w.id].pitch_hz)),
            name(w.played_midi),
            if hit.is_some() { "caught" } else { "NOT caught" }
        );
    }
    for id in &truth.skipped {
        println!("  skipped note {id:>4}: {}", if finished.contains_key(id) { "WRONGLY heard" } else { "not heard (right)" });
    }
    let false_strays: Vec<String> = strays
        .iter()
        .enumerate()
        .filter(|(i, _)| !explained.contains(i))
        .map(|(_, s)| format!("{}@{:.0}", name(midi_of(s.pitch_hz)), s.start_time_ms.unwrap()))
        .collect();
    println!("wrong keys: {} of {} caught; {} other key(s) reported: {:?}", caught, truth.wrong.len(), false_strays.len(), false_strays);
    if std::env::var("VERBOSE").is_ok() {
        for n in &piece.notes {
            let got = finished.get(&n.note_id);
            println!(
                "{:>4} {:<4} {:>8.0} {}",
                n.note_id,
                name(midi_of(n.pitch_hz)),
                n.start_time_ms.unwrap(),
                got.map_or("-".to_string(), |g| format!("{:+.0}", g.start_time_ms.unwrap() - n.start_time_ms.unwrap()))
            );
        }
    }
}
