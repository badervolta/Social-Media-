// Natural voice for the spoken catch-up.
// Runs the free, open-source Kokoro voice model (Apache 2.0) inside the browser.
// The model is downloaded once from Hugging Face and cached by the browser;
// the digest text itself never leaves this computer.
import { KokoroTTS } from 'https://cdn.jsdelivr.net/npm/kokoro-js@1.2.1/dist/kokoro.web.js';

const MODEL = 'onnx-community/Kokoro-82M-v1.0-ONNX';
let ttsP = null;
let cancelGen = 0;
let chain = Promise.resolve();

// Fast path: the computer's graphics chip (WebGPU) with the full-quality model (~330 MB, once).
// Otherwise: the processor (WebAssembly) with the compact model (~90 MB, once), which is slower.
async function pickDevice() {
  try { if (self.navigator && navigator.gpu && await navigator.gpu.requestAdapter()) return 'webgpu'; } catch (e) {}
  return 'wasm';
}
function open(device) {
  return KokoroTTS.from_pretrained(MODEL, {
    dtype: device === 'webgpu' ? 'fp32' : 'q8',
    device,
    progress_callback: p => {
      if (p && p.status === 'progress' && /\.onnx$/.test(p.file || '') && p.total)
        postMessage({ type: 'progress', loaded: p.loaded, total: p.total });
    },
  });
}
function load() {
  if (!ttsP) {
    ttsP = (async () => {
      let device = await pickDevice(), tts;
      try { tts = await open(device); }
      catch (e) { if (device !== 'webgpu') throw e; device = 'wasm'; tts = await open(device); }
      postMessage({ type: 'ready', device });
      return tts;
    })();
    ttsP.catch(() => { ttsP = null; });
  }
  return ttsP;
}

const msg = e => String((e && e.message) || e);

onmessage = e => {
  const m = e.data || {};
  if (m.type === 'load') { load().catch(err => postMessage({ type: 'error', error: msg(err) })); return; }
  if (m.type === 'cancel') { cancelGen = m.gen; return; }
  if (m.type === 'speak') {
    chain = chain.then(async () => {
      if (m.gen < cancelGen) { postMessage({ type: 'skipped', id: m.id }); return; }
      try {
        const tts = await load();
        const audio = await tts.generate(m.text, { voice: m.voice });
        postMessage({ type: 'audio', id: m.id, blob: audio.toBlob() });
      } catch (err) {
        postMessage({ type: 'error', id: m.id, error: msg(err) });
      }
    });
  }
};
