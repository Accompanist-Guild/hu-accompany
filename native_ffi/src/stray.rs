//! Keys played that the score doesn't have there: wrong notes.
//!
//! The tracker only ever asks about the notes the score expects, so a wrong
//! key is invisible to it: the written note just never arrives. Here every key
//! of the pitch network's output is watched, and a fresh attack on a key the
//! score has neither due nor sounding at that moment is reported as a stray,
//! so the app can say "you played D, not D#" instead of only "D# is missing".
//!
//! Only with the neural evidence: it rates all 88 keys every frame, where the
//! DSP analyser only measures the pitches it is asked about.

use crate::run_onnx::{key_index, KEYS, LOWEST_MIDI};

/// A key is armed (may report a new attack) once it reads below this.
const QUIET: f32 = 0.2;
/// ...and starts when it reads at least this in ON_FRAMES frames in a row
/// (~35 ms). Set well above the spill-over a sounding note leaves on its
/// neighbours (~0.1-0.3), since a false wrong note costs the player more
/// than a missed one.
const ON: f32 = 0.5;
const ON_FRAMES: u8 = 3;
/// ...and ends after OFF_FRAMES frames below OFF.
const OFF: f32 = 0.25;
const OFF_FRAMES: u8 = 4;
/// Harmonics and sub-octaves the network sometimes credits to a sounding
/// note (octave, twelfth, double octave): never reported as strays of it.
const RELATED_SEMITONES: [i32; 7] = [0, -12, 12, 19, -19, 24, -24];

#[derive(Clone, Copy, Default)]
struct Key {
    armed: bool,
    run: u8,
    /// Frame the current run of loud frames began on (ms, stream time).
    run_start_ms: f32,
    sounding: bool,
    /// The attack was a stray (reported), so its end is reported too.
    stray: bool,
    quiet_run: u8,
}

/// A stray key's attack (`end_ms` None) or release, in stream time.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct StrayKey {
    pub midi: i32,
    pub start_ms: f32,
    pub end_ms: Option<f32>,
}

impl StrayKey {
    pub fn pitch_hz(&self) -> f64 {
        440.0 * 2f64.powf((self.midi - 69) as f64 / 12.0)
    }
}

pub struct StrayKeys {
    keys: [Key; KEYS],
}

impl Default for StrayKeys {
    fn default() -> Self {
        Self::new()
    }
}

impl StrayKeys {
    pub fn new() -> Self {
        Self { keys: [Key::default(); KEYS] }
    }

    /// One network frame starting at `frame_ms` (stream time). `allowed` are
    /// the pitches the score has due or sounding now (NoteTracker::pitches_near):
    /// attacks on those keys, or on their RELATED_SEMITONES, are not strays.
    pub fn update(&mut self, frame_ms: f32, activations: &[f32; KEYS], allowed: &[f64]) -> Vec<StrayKey> {
        let mut allowed_keys = [false; KEYS];
        for &hz in allowed {
            let Some(k) = key_index(hz) else { continue };
            for offset in RELATED_SEMITONES {
                let j = k as i32 + offset;
                if (0..KEYS as i32).contains(&j) {
                    allowed_keys[j as usize] = true;
                }
            }
        }
        let mut out = Vec::new();
        for (k, key) in self.keys.iter_mut().enumerate() {
            let level = activations[k];
            let midi = k as i32 + LOWEST_MIDI;
            if key.sounding {
                if level < OFF {
                    key.quiet_run += 1;
                    if key.quiet_run >= OFF_FRAMES {
                        if key.stray {
                            out.push(StrayKey { midi, start_ms: key.run_start_ms, end_ms: Some(frame_ms) });
                        }
                        *key = Key { armed: level < QUIET, ..Key::default() };
                    }
                } else {
                    key.quiet_run = 0;
                }
                continue;
            }
            if level < QUIET {
                key.armed = true;
                key.run = 0;
                continue;
            }
            if !key.armed || level < ON {
                key.run = 0;
                continue;
            }
            if key.run == 0 {
                key.run_start_ms = frame_ms;
            }
            key.run += 1;
            if key.run >= ON_FRAMES {
                key.sounding = true;
                key.armed = false;
                key.stray = !allowed_keys[k];
                if key.stray {
                    out.push(StrayKey { midi, start_ms: key.run_start_ms, end_ms: None });
                }
            }
        }
        out
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn frame(levels: &[(i32, f32)]) -> [f32; KEYS] {
        let mut keys = [0.0; KEYS];
        for &(midi, level) in levels {
            keys[(midi - LOWEST_MIDI) as usize] = level;
        }
        keys
    }

    const E5: f64 = 659.26;
    const DS5: i32 = 75;

    /// Feeds `frames` 10 ms apart; returns everything reported.
    fn feed(strays: &mut StrayKeys, frames: &[[f32; KEYS]], allowed: &[f64]) -> Vec<StrayKey> {
        frames.iter().enumerate().flat_map(|(i, f)| strays.update(i as f32 * 10.0, f, allowed)).collect()
    }

    #[test]
    fn test_a_wrong_key_is_reported_on_its_attack_and_its_release() {
        let mut strays = StrayKeys::new();
        let mut frames = vec![frame(&[]); 2];
        frames.extend(vec![frame(&[(DS5, 0.8)]); 10]);
        frames.extend(vec![frame(&[]); 6]);
        let out = feed(&mut strays, &frames, &[E5]);
        assert_eq!(
            out,
            vec![
                StrayKey { midi: DS5, start_ms: 20.0, end_ms: None },
                StrayKey { midi: DS5, start_ms: 20.0, end_ms: Some(150.0) },
            ]
        );
    }

    #[test]
    fn test_the_written_note_and_its_octaves_are_not_strays() {
        let mut strays = StrayKeys::new();
        let mut frames = vec![frame(&[]); 2];
        frames.extend(vec![frame(&[(76, 0.9), (88, 0.6), (64, 0.55)]); 10]);
        assert!(feed(&mut strays, &frames, &[E5]).is_empty());
    }

    #[test]
    fn test_spill_over_onto_a_neighbour_is_not_a_stray() {
        let mut strays = StrayKeys::new();
        let mut frames = vec![frame(&[]); 2];
        frames.extend(vec![frame(&[(76, 0.9), (DS5, 0.35)]); 10]);
        assert!(feed(&mut strays, &frames, &[E5]).is_empty());
    }

    #[test]
    fn test_a_key_already_ringing_is_not_a_new_attack() {
        // Held from before it was listened for (pedal): never quiet, never armed.
        let mut strays = StrayKeys::new();
        let frames = vec![frame(&[(DS5, 0.8)]); 12];
        assert!(feed(&mut strays, &frames, &[E5]).is_empty());
    }

    #[test]
    fn test_a_click_shorter_than_the_attack_rule_is_ignored() {
        let mut strays = StrayKeys::new();
        let mut frames = vec![frame(&[]); 2];
        frames.extend(vec![frame(&[(DS5, 0.9)]); 2]);
        frames.extend(vec![frame(&[]); 4]);
        assert!(feed(&mut strays, &frames, &[E5]).is_empty());
    }
}
