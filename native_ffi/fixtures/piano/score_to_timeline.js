// Reads a MusicXML score the way the app does (frontend/assets/osmd/score_timeline.js,
// on the bundled OSMD) and prints a summary, or writes the timeline JSON for perform.py.
//
//   npm install jsdom          (once, anywhere on NODE_PATH)
//   node fixtures/piano/score_to_timeline.js score.musicxml [timeline.json]
const fs = require('fs');
const { JSDOM, VirtualConsole } = require('jsdom');
const vc = new VirtualConsole(); // OSMD's canvas text measuring is not needed to parse
const dom = new JSDOM('<!DOCTYPE html><div id="score"></div>', { pretendToBeVisual: true, runScripts: 'outside-only', virtualConsole: vc });
const w = dom.window;
const osmdDir = require('path').join(__dirname, '../../../frontend/assets/osmd/');
w.eval(fs.readFileSync(osmdDir + 'opensheetmusicdisplay.min.js', 'utf8'));
w.eval(fs.readFileSync(osmdDir + 'score_timeline.js', 'utf8'));
const osmd = new w.opensheetmusicdisplay.OpenSheetMusicDisplay('score', { autoResize: false, backend: 'svg' });
osmd.load(fs.readFileSync(process.argv[2], 'utf8')).catch(() => {}).then(() => {
  const t = w.ScoreTimeline.extract(osmd);
  delete t.sources;
  const n = t.notes;
  const last = n[n.length - 1];
  console.log(JSON.stringify({ title: osmd.Sheet.TitleString, bpm: t.bpm, ts: t.timeSignature, instrument: t.instrument, staves: t.staves, notes: n.length,
    seconds: ((last.startMs + last.durationMs) / 1000).toFixed(1), visits: last.visit + 1, measures: osmd.Sheet.SourceMeasures.length,
    grace: n.filter(x => x.grace).length, perStaff: [0, 1, 2].map(s => n.filter(x => x.staff === s).length) }));
  if (process.argv[3]) fs.writeFileSync(process.argv[3], JSON.stringify(t));
});
