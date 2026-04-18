// Pure Node probe — no daemon. Instantiate SonaCoordinator with varying thresholds,
// store same patterns, query same prompts, report hits + max-similarity at each threshold.
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);
const { SonaCoordinator } = require('@ruvector/ruvllm');
const { pipeline } = await import('@xenova/transformers');
const xenova = await pipeline('feature-extraction', 'Xenova/all-MiniLM-L6-v2');
const embed = async (t) => Array.from((await xenova(t, {pooling: 'mean', normalize: true})).data);

// Canonical stored content — what a trajectory step would carry.
const stored = ["pre:Read auth module", "post:Edit:ok wrote jwt handler"];
// Varying query proximities.
const queries = {
  'same-text':      "post:Edit:ok wrote jwt handler",
  'near-paraphrase':"edit ok wrote jwt handler",
  'similar-topic':  "add JWT-based login",
  'related':        "authentication with tokens",
  'unrelated':      "sort array by timestamp",
};

// First: measure raw cosine sim at every pair (threshold-independent).
function cos(a, b) { let d=0,na=0,nb=0; for (let i=0;i<a.length;i++){d+=a[i]*b[i]; na+=a[i]*a[i]; nb+=b[i]*b[i];} return d/Math.sqrt(na*nb); }

const stEmb = await Promise.all(stored.map(embed));
console.log('raw cosine sim (query x stored):');
for (const [label, q] of Object.entries(queries)) {
  const qe = await embed(q);
  const sims = stEmb.map(s => cos(qe, s).toFixed(3));
  console.log(`  ${label.padEnd(18)} -> ${sims.join(',')}`);
}

// Now sweep threshold, count hits for each query.
console.log('\nhits by threshold (k=5):');
const thresholds = [0.3, 0.5, 0.6, 0.7, 0.75, 0.8, 0.85];
const header = '  threshold  | ' + Object.keys(queries).map(l => l.padEnd(16)).join(' | ');
console.log(header);
console.log('  ' + '-'.repeat(header.length - 2));
for (const th of thresholds) {
  const coord = new SonaCoordinator({ patternThreshold: th });
  const rb = coord.getReasoningBank();
  for (const s of stored) rb.store('query_response', await embed(s));
  const row = [];
  for (const q of Object.values(queries)) {
    const h = rb.findSimilar(await embed(q), 5);
    row.push(`${h.length}`.padEnd(16));
  }
  console.log(`  ${th.toFixed(2).padEnd(10)} | ${row.join(' | ')}`);
}
