//! The app's note detector, for the website's play-along: the same pitch
//! network and score follower as native_ffi, fed the browser's microphone.
//!
//! JavaScript loads a piece (the `PieceData` JSON the app sends Rust, see
//! frontend/lib/features/practice/score_timeline.dart), pushes audio as it
//! arrives and reads back the notes heard, in the same records the app gets
//! from `notesStream()`. Built by build.sh into website/engine/.

use native_ffi::audio::NeuralSession;
use native_ffi::models::PieceData;
use native_ffi::{ACTIVE_PIECE, PIECE_GENERATION, USER_DATA};
use std::sync::atomic::Ordering;
use wasm_bindgen::prelude::*;

#[wasm_bindgen]
pub struct Engine {
    session: Option<NeuralSession>,
}

#[wasm_bindgen]
impl Engine {
    /// Follows `piece_json` in audio at `sample_rate` (the AudioContext's).
    #[wasm_bindgen(constructor)]
    pub fn new(piece_json: &str, sample_rate: u32) -> Result<Engine, JsError> {
        let piece: PieceData = serde_json::from_str(piece_json)?;
        *ACTIVE_PIECE.lock().unwrap_or_else(|e| e.into_inner()) = Some(piece);
        PIECE_GENERATION.fetch_add(1, Ordering::AcqRel);
        *USER_DATA.lock().unwrap_or_else(|e| e.into_inner()) = None;
        let session = NeuralSession::new(sample_rate).map_err(|e| JsError::new(&e.to_string()))?;
        Ok(Engine { session: Some(session) })
    }

    /// The next audio, mono. Returns the notes heard since the last call, as JSON.
    pub fn push(&mut self, samples: &[f32]) -> String {
        if let Some(session) = self.session.as_mut() {
            session.push(samples);
        }
        take_heard()
    }

    /// The audio has ended: the notes still sounding, as JSON.
    pub fn finish(&mut self) -> String {
        if let Some(session) = self.session.take() {
            session.finish();
        }
        take_heard()
    }
}

/// With no Dart listening, the engine keeps what it heard in USER_DATA.
fn take_heard() -> String {
    let heard = USER_DATA.lock().unwrap_or_else(|e| e.into_inner()).take().unwrap_or_default();
    serde_json::to_string(&heard).unwrap_or_else(|_| "[]".into())
}
