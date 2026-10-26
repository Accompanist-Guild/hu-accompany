// Runs on the browser's audio thread: gathers the microphone's 128-sample blocks into chunks of
// about 20 ms and hands them, mono, straight to the engine worker (no stop on the main thread).
class Capture extends AudioWorkletProcessor {
  constructor() {
    super();
    this.chunk = new Float32Array(1024);
    this.filled = 0;
    this.out = null;
    this.port.onmessage = (e) => { if (e.data.port) this.out = e.data.port; };
  }

  process(inputs) {
    const channels = inputs[0];
    if (!channels || !channels.length || !this.out) return true;
    const n = channels[0].length;
    for (let i = 0; i < n; i++) {
      let s = 0;
      for (const ch of channels) s += ch[i];
      this.chunk[this.filled++] = s / channels.length;
      if (this.filled === this.chunk.length) {
        this.out.postMessage(this.chunk, [this.chunk.buffer]);
        this.chunk = new Float32Array(1024);
        this.filled = 0;
      }
    }
    return true;
  }
}
registerProcessor('accompanist-capture', Capture);
