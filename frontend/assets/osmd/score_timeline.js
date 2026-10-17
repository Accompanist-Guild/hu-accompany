// The notes of a loaded score as a player meets them: in time order, with
// repeats played out, ties joined, and a time in milliseconds at the written
// tempo. This is what the audio engine listens for and what feedback is
// judged against (score_osmd_view.dart turns it into both).
//
// Each note also keeps its OSMD source note (in `sources`, by id), so the
// page can find it on the engraving again after every re-render.
//
// Loaded by osmd_viewer.html. Plain ES5 + no DOM, so it can also be run in
// Node against OSMD to check a score's timeline.
(function (root) {
  // Milliseconds per whole note at `bpm` crotchets a minute.
  function wholeMs(bpm) { return 4 * 60000 / bpm; }

  // A grace note is written at the time of the note it ornaments; it is
  // played just before it.
  var GRACE_LEAD_MS = 80, GRACE_MS = 70;

  // Repeats can be written to go round for ever (a D.C. with no Fine that
  // OSMD can't resolve); a real piece is far shorter than this.
  var MAX_STEPS = 50000;

  function firstTempo(sheet) {
    var bpm = sheet.DefaultStartTempoInBpm;
    return bpm > 0 ? bpm : 100;
  }

  function timeSignature(sheet) {
    var first = sheet.SourceMeasures && sheet.SourceMeasures[0];
    var ts = first && first.ActiveTimeSignature;
    return ts && ts.Numerator > 0 && ts.Denominator > 0 ? ts.Numerator + '/' + ts.Denominator : '4/4';
  }

  // How long a note sounds, in whole notes: tied notes are one note.
  function soundingLength(note) {
    var tie = note.NoteTie;
    if (!tie || !tie.Notes || tie.Notes.length < 2) return note.Length.RealValue;
    return tie.Notes.reduce(function (sum, n) { return sum + n.Length.RealValue; }, 0);
  }

  // A tie's later notes are held, not played again.
  function isTieContinuation(note) {
    return !!(note.NoteTie && note.NoteTie.StartNote && note.NoteTie.StartNote !== note);
  }

  /**
   * osmd: an OpenSheetMusicDisplay with a score loaded (render not needed).
   * Returns {notes: [...], sources: [null, sourceNote, ...], bpm, timeSignature,
   *          instrument, staves}. Each note:
   *   {id (1-based, time order), midi, startMs, durationMs, measure (index of
   *    the written bar), measureNumber (as printed), visit (0-based count of
   *    bars played so far, repeats included), staff (0 = the top staff of the
   *    instrument), grace}
   * Only the first instrument's notes: a part for one player.
   */
  function extract(osmd) {
    var sheet = osmd.Sheet;
    var instrument = sheet.Instruments[0];
    var bpm = firstTempo(sheet);
    var it = sheet.MusicPartManager.getIterator();
    var raw = [];
    var prevTs = 0, ms = 0;
    var lastMeasure = -1, lastRepetition = null, visit = -1;

    for (var step = 0; !it.EndReached && step < MAX_STEPS; step++) {
      var ts = it.CurrentEnrolledTimestamp.RealValue;
      ms += (ts - prevTs) * wholeMs(bpm);
      prevTs = ts;
      if (it.CurrentBpm > 0) bpm = it.CurrentBpm;

      var repetition = it.CurrentRepetition;
      if (it.CurrentMeasureIndex !== lastMeasure || repetition !== lastRepetition) {
        visit++;
        lastMeasure = it.CurrentMeasureIndex;
        lastRepetition = repetition;
      }
      var measure = it.CurrentMeasure;

      (it.CurrentVoiceEntries || []).forEach(function (ve) {
        var staff = ve.ParentSourceStaffEntry && ve.ParentSourceStaffEntry.ParentStaff;
        if (!staff || staff.ParentInstrument !== instrument) return;
        var staffIndex = instrument.Staves.indexOf(staff);
        (ve.Notes || []).forEach(function (note) {
          if (note.isRest() || !note.Pitch || isTieContinuation(note)) return;
          var grace = !!ve.IsGrace;
          raw.push({
            source: note,
            midi: note.halfTone + 12,
            startMs: grace ? Math.max(0, ms - GRACE_LEAD_MS) : ms,
            durationMs: grace ? GRACE_MS : soundingLength(note) * wholeMs(bpm),
            measure: it.CurrentMeasureIndex,
            measureNumber: measure ? measure.MeasureNumber : it.CurrentMeasureIndex + 1,
            visit: visit,
            staff: Math.max(0, staffIndex),
            grace: grace,
          });
        });
      });
      it.moveToNext();
    }

    raw.sort(function (a, b) { return a.startMs - b.startMs || a.midi - b.midi; });
    var sources = [null];
    var notes = raw.map(function (n, i) {
      sources.push(n.source);
      return {
        id: i + 1, midi: n.midi,
        startMs: Math.round(n.startMs * 10) / 10, durationMs: Math.round(n.durationMs * 10) / 10,
        measure: n.measure, measureNumber: n.measureNumber, visit: n.visit, staff: n.staff, grace: n.grace,
      };
    });
    return {
      notes: notes,
      sources: sources,
      bpm: firstTempo(sheet),
      timeSignature: timeSignature(sheet),
      instrument: instrument ? instrument.Name || '' : '',
      staves: instrument ? instrument.Staves.length : 1,
    };
  }

  root.ScoreTimeline = { extract: extract };
})(typeof window !== 'undefined' ? window : this);
