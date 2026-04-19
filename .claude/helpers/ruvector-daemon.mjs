#!/usr/bin/env node
// ruflo v4 — ruvector-daemon.mjs
//
// THIN ADAPTER ONLY. The daemon wraps @ruvector/sona::SonaEngine one-to-one and
// exposes its native methods over UDS IPC. No custom learning logic, no bypass,
// no threshold overrides, no step-typing, no confidence formulas. If upstream
// does not produce expected behaviour with canonical calls, REPORT upstream —
// do not patch around it. (See memory/feedback_v4_embedder_bypass.md.)
//
// All learning is done by SonaEngine. The daemon only:
//   • instantiates SonaEngine(384) and @xenova/transformers pipeline
//   • embeds text on the way in (external embedder, per feedback_onnx_xenova.md)
//   • forwards calls to SonaEngine.{begin,add,end}Trajectory / findPatterns /
//     forceLearn / tick / flush / getStats verbatim
//   • holds the active trajectory id in-process (stateful daemon, stateless hooks)

import net from 'node:net';
import fs from 'node:fs';
import path from 'node:path';

const PROJECT_DIR = process.env.CLAUDE_PROJECT_DIR || process.cwd();
const SOCKET_PATH = path.join(PROJECT_DIR, '.claude-flow', 'ruvector-daemon.sock');
const PID_PATH    = path.join(PROJECT_DIR, '.claude-flow', 'ruvector-daemon.pid');
const LOG_PATH    = path.join(PROJECT_DIR, '.claude-flow', 'data', 'daemon.log');

function log(msg) {
  const line = `${new Date().toISOString()} ${msg}\n`;
  try { fs.mkdirSync(path.dirname(LOG_PATH), { recursive: true }); fs.appendFileSync(LOG_PATH, line); } catch {}
  process.stderr.write(line);
}

// Singletons.
let sona = null;
let embedder = null;   // ruvector.AdaptiveEmbedder — canonical per SKILL.md Migration Rule #1
let db = null;         // @claude-flow/memory IMemoryBackend (SQLiteBackend) — canonical per ADR-001
let dbPath = null;     // cached path (npm SQLiteBackend has no getDbPath; the v3-repo infra one does)
let createDefaultEntry = null; // @claude-flow/memory factory (types.ts:20), captured at init
let activeTrajId = null;
let activeTrajSeed = null; // { prompt, embedding: number[], startedAt, steps } — closed into MemoryEntry on end
// Fix 18: ruvllm ReasoningBank (VerdictAnalyzer + PatternStore with metadata)
let reasoningBank = null; // JsReasoningBank from @ruvector/ruvllm-native
let tensorCompress = null; // ruvector.TensorCompress — Phase 10 CONSOLIDATE
let semanticRouter = null; // ruvector.SemanticRouter — 8/10 vs cosine 5/10
// Tier 1 ADOPT (ADR-008 + plan/20260415_tier1_2_adoption_plan.md):
let intelligence = null;  // ruvector.IntelligenceEngine — primary orchestrator (composes sona+onnx+parallel+attention+HNSW)
let substrate = null;     // ruvector.NeuralSubstrate — bundles {coherence, drift, memory, state, swarm}
let rvHelpers = null;     // cached { classifyChange, extractAllPatterns } from ruvector for Tier 2 inline calls

// C4 memory bootstrap (lifecycle, not a §3.4 phase).
// Upstream: @claude-flow/memory::createDatabase({provider:'better-sqlite3'})
//   · v3/@claude-flow/memory/src/database-provider.ts:209 (createDatabase)
//   · v3/@claude-flow/memory/src/sqlite-backend.ts (SQLiteBackend — 788 LOC prod impl, WAL + ACID)
// Explicit 'better-sqlite3' provider bypasses upstream auto-pick-RVF-first (see ADR-001 tier 1).
// Writes persist to .swarm/memory.db. Single-writer rule per feedback_single_writer.md: the
// DAEMON is the sole writer; hooks NEVER open this DB directly — they only send IPC.
async function initializeMemory() {
  const mem = await import('@claude-flow/memory');
  const { createDatabase } = mem;
  createDefaultEntry = mem.createDefaultEntry; // types.ts:20 — canonical MemoryEntry factory
  dbPath = path.join(PROJECT_DIR, '.swarm', 'memory.db');
  fs.mkdirSync(path.dirname(dbPath), { recursive: true });
  // Signature: createDatabase(path: string, options: DatabaseOptions)
  //   path is 1st positional arg; options.dbPath does NOT exist in DatabaseOptions.
  // Upstream createDatabase calls backend.initialize() internally before returning —
  // we do NOT re-initialize here (would be invention of extra safety).
  db = await createDatabase(dbPath, { provider: 'better-sqlite3', walMode: true, optimize: true });
  log(`C4 memory: SQLiteBackend ready at ${dbPath} (@claude-flow/memory, provider=better-sqlite3)`);
}

// Patch ruvector@0.2.22's onnx-embedder module to use @xenova/transformers under the hood.
// Documented in memory/feedback_onnx_xenova.md — ruvector ships without its ONNX WASM files
// so AdaptiveEmbedder.init() falls back to hashEmbed() (~13% non-zero, poisons all learning).
// This patch is the documented upstream workaround, not invention.
async function patchOnnxEmbedder() {
  const { pipeline } = await import('@xenova/transformers');
  const xenova = await pipeline('feature-extraction', 'Xenova/all-MiniLM-L6-v2');
  log('Xenova pipeline ready (Xenova/all-MiniLM-L6-v2)');

  const mod = await import('ruvector/dist/core/onnx-embedder.js');
  const exp = mod.default || mod;
  // Unconditional assignment — monkey-patch installs these properties on the module
  // exports object. If upstream restructures and these names become unused, the
  // subsequent AdaptiveEmbedder probe (378/384 dense ONNX verification in initialize)
  // will fail loudly and halt startup — no silent degradation.
  exp.isOnnxAvailable  = () => true;
  exp.initOnnxEmbedder = async () => true;
  exp.embed = async (text) => {
    const r = await xenova(String(text || '').slice(0, 512), { pooling: 'mean', normalize: true });
    return { embedding: Array.from(r.data), _realEmbedding: true };
  };
  exp.embedBatch = async (texts) => {
    const out = [];
    for (const t of texts) {
      const r = await xenova(String(t || '').slice(0, 512), { pooling: 'mean', normalize: true });
      out.push({ embedding: Array.from(r.data), _realEmbedding: true });
    }
    return out;
  };
  // Fix 20a: OnnxEmbedder class captures init/embed via closure — patching exports
  // alone doesn't reach class methods. Patch the prototype so ALL consumers
  // (IntelligenceEngine, AdaptiveEmbedder, any future user) get real ONNX.
  if (exp.OnnxEmbedder) {
    exp.OnnxEmbedder.prototype.init = async function() { return true; };
    exp.OnnxEmbedder.prototype.embed = async function(text) {
      const r = await xenova(String(text || '').slice(0, 512), { pooling: 'mean', normalize: true });
      return Array.from(r.data);
    };
    exp.OnnxEmbedder.prototype.embedBatch = async function(texts) {
      const out = [];
      for (const t of texts) {
        const r = await xenova(String(t || '').slice(0, 512), { pooling: 'mean', normalize: true });
        out.push(Array.from(r.data));
      }
      return out;
    };
  }
  log('ruvector onnx-embedder patched → xenova');
}

// Service registry — per-resource lifecycle discipline (ADR-ruflo-007, 2026-04-15).
// Each service declares: init (daemon-scope startup), onSessionEnd (session-scope close —
// flush/export/checkpoint only; MUST NOT close daemon-scope resources), shutdown
// (daemon-scope teardown, SIGTERM only). Any method may be async no-op.
//   onSessionEnd MAY return a `{ field: value }` blob that the IPC response aggregates —
//   lets each service contribute to the `session_end` payload without a central switch.
const services = [
  {
    name: 'memory',  // SQLiteBackend is daemon-scope — survives SessionEnd
    async init()          { await initializeMemory(); },
    async onSessionEnd()  { return {}; },  // no-op: DB open for next session (bug fix 2026-04-15)
    async shutdown()      { try { await db?.shutdown(); } catch (e) { log('memory.shutdown: ' + e.message); } },
  },
  {
    name: 'sona',
    async init() {
      const sonaMod = await import('@ruvector/sona');
      const SonaEngine = sonaMod.SonaEngine || sonaMod.default?.SonaEngine;
      if (!SonaEngine) { log('FATAL: @ruvector/sona missing SonaEngine'); process.exit(1); }
      sona = new SonaEngine(384);
      log('SonaEngine: 384-dim');
      // Phase 0 BOOT state restore · Upstream: SonaEngine.loadState (napi_simple.rs:230
      //   → coordinator.serialize_state at loops/coordinator.rs:166). Restores
      //   patterns + ewc_task_count + instant/background flags. Vendor 0.1.9-ruflo.1.
      try {
        const sf = path.join(PROJECT_DIR, '.claude-flow', 'sona', 'state.json');
        if (fs.existsSync(sf)) {
          const n = sona.loadState(fs.readFileSync(sf, 'utf8'));
          log(`SonaEngine: state restored (${n} patterns) from ${sf}`);
        } else {
          log('SonaEngine: no prior state (fresh boot)');
        }
      } catch (e) { log('SonaEngine loadState (continuing fresh): ' + e.message); }
    },
    // Loop C: forceLearn → flush → consolidateTasks → prunePatterns → saveState → metrics
    //   forceLearn at session_end = last chance to crystallize before shutdown.
    async onSessionEnd() {
      const msg = sona.forceLearn();
      sona.flush();
      try { sona.consolidateTasks(); } catch (e) { log('consolidateTasks: ' + e.message); }
      try { sona.prunePatterns(0.05, 0, 7776000); } catch (e) { log('prunePatterns: ' + e.message); }
      let statePath = null, stateBytes = 0, stateErr = null;
      try {
        const sdir = path.join(PROJECT_DIR, '.claude-flow', 'sona');
        fs.mkdirSync(sdir, { recursive: true });
        statePath = path.join(sdir, 'state.json');
        const sj = sona.saveState();
        fs.writeFileSync(statePath, sj);
        stateBytes = sj.length;
      } catch (e) { stateErr = e.message; log('saveState: ' + e.message); }
      let metricsPath = null, metricsErr = null;
      try {
        const dir = path.join(PROJECT_DIR, '.claude-flow', 'metrics');
        fs.mkdirSync(dir, { recursive: true });
        const ts = Date.now();
        const trajectoryCount = await db.count('ruflo-v4');
        const payload = { exportedAt: new Date(ts).toISOString(), sonaStats: sona.getStats(), learnStatus: msg, memoryPath: dbPath, trajectoryCount, statePath, stateBytes };
        const body = JSON.stringify(payload, null, 2);
        metricsPath = path.join(dir, `session-${ts}.json`);
        fs.writeFileSync(metricsPath, body);
        fs.writeFileSync(path.join(dir, 'session-latest.json'), body);
      } catch (e) { metricsErr = e.message; log('metrics export: ' + e.message); }
      return { msg, stats: sona.getStats(), memoryPath: dbPath, metricsPath, metricsErr, statePath, stateBytes, stateErr, degraded: 'Phase 10 CONSOLIDATE (ruvllm::MemoryCompressor) still NAPI-gap — requires rebuild of @ruvector/ruvllm (not sona). OQ-3 closed for Phase 11 FORGET + Phase 12 PRUNE.' };
    },
    async shutdown() { return; },  // sona has no kernel-level handles; process exit suffices
  },
  {
    name: 'embedder',
    async init() {
      await patchOnnxEmbedder();
      const rv = await import('ruvector');
      const AdaptiveEmbedder = rv.AdaptiveEmbedder || rv.default?.AdaptiveEmbedder;
      if (!AdaptiveEmbedder) { log('FATAL: ruvector missing AdaptiveEmbedder'); process.exit(1); }
      embedder = new AdaptiveEmbedder({ useEpisodic: true });
      await embedder.init();
      // Verify real ONNX (dense vectors >50% non-zero); hash fallback yields ~13%.
      const probe = await embedder.embed('warm-up verification');
      const arr = Array.from(probe?.embedding || probe);
      const nz = arr.filter(v => Math.abs(v) > 0.001).length;
      if (nz < arr.length * 0.5) { log(`FATAL: embedder hash-poison (${nz}/${arr.length}). Patch failed.`); process.exit(1); }
      log(`AdaptiveEmbedder ready (${arr.length}-dim, ${nz}/${arr.length} dense — real ONNX confirmed)`);
    },
    async onSessionEnd() { return {}; },
    async shutdown()     { return; },
  },
  // ─── Tier 1 NEW (ADR-008 plan 2026-04-15 — adopt ruvector orchestration) ───
  {
    name: 'intelligence',
    // ruvector.IntelligenceEngine — primary upstream orchestrator. Composes
    //   SonaEngine + onnx-embedder + ParallelIntelligence + @ruvector/attention + @ruvector/core HNSW.
    //   We DO NOT replace the `sona` service: that one owns Phase 0 BOOT save/loadState
    //   + Phase 11 consolidateTasks + Phase 12 prunePatterns (vendor 0.1.9-ruflo.1 NAPI direct).
    //   IntelligenceEngine adds Phase 3 APPLY routing + episodic memory (recordEpisode/queueEpisode/
    //   flushEpisodeBatch) + specialized tracking (recordCoEdit/recordErrorFix/getSuggestedFixes).
    async init() {
      const rv = await import('ruvector');
      const IE = rv.IntelligenceEngine || rv.default?.IntelligenceEngine;
      if (!IE) { log('intelligence.init: IntelligenceEngine not found in ruvector npm'); return; }
      try {
        intelligence = new IE({ enableOnnx: true, enableSona: true, enableParallel: false });
        // IE has granular init methods (initOnnx/initVectorDb/initDefaultWorkerMappings/initParallel),
        // not a single init(). Call the ones we need; skip parallel (single daemon).
        await intelligence.initOnnx();
        await intelligence.initVectorDb();
        intelligence.initDefaultWorkerMappings();
        log('IntelligenceEngine: ready (composes sona+onnx+parallel+attention+HNSW)');
        rvHelpers = { classifyChange: rv.classifyChange, extractAllPatterns: rv.extractAllPatterns };
      } catch (e) { log('intelligence.init failed (continuing without IE): ' + e.message); intelligence = null; }
    },
    async onSessionEnd() { return {}; },
    async shutdown() { return; },
  },
  {
    name: 'substrate',
    // ruvector.NeuralSubstrate — bundles 5 subsystems: coherence, drift, memory, state, swarm.
    //   Standalone (zero internal require). Candidate for DQ-06 task-boundary signal via
    //   coherence drift scoring. observe(embedding, tag) feeds the pipeline; report() emits
    //   {overallScore, driftScore, stabilityScore, alignmentScore, anomalies[]}.
    async init() {
      const rv = await import('ruvector');
      const NS = rv.NeuralSubstrate || rv.default?.NeuralSubstrate;
      if (!NS) { log('substrate.init: NeuralSubstrate not found in ruvector npm'); return; }
      try {
        substrate = new NS({ dimension: 384 });
        log('NeuralSubstrate: ready (coherence + drift + memory + state + swarm)');
      } catch (e) { log('substrate.init failed (continuing without): ' + e.message); substrate = null; }
    },
    async onSessionEnd() {
      // Phase 13 EXPORT addendum: snapshot coherence at session-close for metrics.
      // Pure observation; no formula. If substrate isn't ready, no-op.
      if (!substrate) return {};
      try {
        const r = substrate.coherence.report();
        return r ? { coherenceReport: r } : {};
      } catch (e) { log('substrate.coherence.report: ' + e.message); return {}; }
    },
    async shutdown() { return; },
  },
  // Fix 18: ruvllm ReasoningBank — VerdictAnalyzer + PatternStore with metadata.
  {
    name: 'reasoningBank',
    async init() {
      try {
        const { createRequire } = await import('module');
        const require2 = createRequire(import.meta.url);
        const { JsReasoningBank } = require2('@ruvector/ruvllm-native');
        const bankPath = path.join(PROJECT_DIR, '.claude-flow', 'reasoning-bank');
        fs.mkdirSync(bankPath, { recursive: true });
        reasoningBank = new JsReasoningBank(384, bankPath);
        // Restore patterns from disk
        const patternsFile = path.join(bankPath, 'patterns.json');
        try {
          if (fs.existsSync(patternsFile)) {
            const json = fs.readFileSync(patternsFile, 'utf8');
            const count = reasoningBank.importPatterns(json);
            log(`reasoningBank: restored ${count} patterns`);
          } else { log('reasoningBank: fresh (no prior patterns)'); }
        } catch (e) { log('reasoningBank restore: ' + e.message); }
      } catch (e) { log('reasoningBank: not available — ' + e.message); }
    },
    async onSessionEnd() {
      if (!reasoningBank) return {};
      try {
        const json = reasoningBank.exportPatterns();
        const bankPath = path.join(PROJECT_DIR, '.claude-flow', 'reasoning-bank');
        fs.writeFileSync(path.join(bankPath, 'patterns.json'), json);
        const stats = JSON.parse(reasoningBank.stats());
        log(`reasoningBank: persisted ${stats.total_patterns} patterns`);
        return { reasoningBankPatterns: stats.total_patterns };
      } catch (e) { log('reasoningBank persist: ' + e.message); return {}; }
    },
    async shutdown() { return; },
  },
  // Phase 10 CONSOLIDATE: TensorCompress — adaptive tensor compression.
  {
    name: 'tensorCompress',
    async init() {
      try {
        const rv = await import('ruvector');
        const TC = rv.TensorCompress || rv.default?.TensorCompress;
        if (!TC) { log('tensorCompress: not found in ruvector'); return; }
        tensorCompress = new TC({ autoCompress: false });
        const tcPath = path.join(PROJECT_DIR, '.claude-flow', 'data', 'tensor-compress.json');
        try {
          if (fs.existsSync(tcPath)) { tensorCompress.import(fs.readFileSync(tcPath, 'utf8')); log('tensorCompress: restored'); }
          else { log('tensorCompress: fresh'); }
        } catch (e) { log('tensorCompress restore: ' + e.message); }
      } catch (e) { log('tensorCompress: ' + e.message); }
    },
    async onSessionEnd() {
      if (!tensorCompress) return {};
      try {
        // Fix 20c: feed sona pattern embeddings to TC (upstream pattern: cli.js:5004).
        // TC compresses cold/infrequently-accessed embeddings for storage efficiency.
        try {
          const sf = path.join(PROJECT_DIR, '.claude-flow', 'sona', 'state.json');
          if (fs.existsSync(sf)) {
            const st = JSON.parse(fs.readFileSync(sf, 'utf8'));
            for (const p of (st.patterns || [])) {
              if (p.centroid && Array.isArray(p.centroid)) tensorCompress.store(`sona-${p.id}`, p.centroid);
            }
          }
        } catch (e) { log('tensorCompress.feed: ' + e.message); }
        const stats = tensorCompress.recompressAll();
        const tcPath = path.join(PROJECT_DIR, '.claude-flow', 'data', 'tensor-compress.json');
        fs.writeFileSync(tcPath, JSON.stringify(tensorCompress.export()));
        log(`tensorCompress: ${stats.totalTensors} tensors, ${stats.savingsPercent?.toFixed(1)}% savings`);
        return { tensorCompress: stats };
      } catch (e) { log('tensorCompress: ' + e.message); return {}; }
    },
    async shutdown() { return; },
  },
];

async function initialize() {
  for (const s of services) {
    try { await s.init(); }
    catch (e) { log(`${s.name}.init FATAL: ${e.message}`); process.exit(1); }
  }
}

async function embed(text) {
  if (!text) return new Array(384).fill(0);
  const out = await embedder.embed(text);
  return Array.from(out?.embedding || out);
}

// ─── Agent routing (ONNX cosine + SONA feedback boost) ─────────────────────
// Fix 08/12: precomputed agent pattern embeddings + learned pattern boost.
// Uses the warm AdaptiveEmbedder (embed() above) — same ONNX pipeline.
const AGENT_PATTERNS = {
  'security-architect':    'security vulnerability audit authentication authorization',
  'tester':                'test unit integration coverage spec assertion',
  'coder':                 'implement build create code function module',
  'reviewer':              'review quality check validate best practices',
  'architect':             'design architecture system structure pattern scalable',
  'devops':                'deploy infrastructure kubernetes docker ci cd pipeline',
  'frontend-developer':    'ui react css component layout style responsive',
  'backend-developer':     'api database server endpoint authentication query',
  'rust-developer':        'rust cargo crate unsafe lifetime borrow',
  'python-developer':      'python pip pytest django flask pandas',
  'typescript-developer':  'typescript type interface generic enum import',
};
const patternEmbeddings = {};

function cosine(a, b) {
  let dot = 0, na = 0, nb = 0;
  for (let i = 0; i < a.length; i++) { dot += a[i] * b[i]; na += a[i] ** 2; nb += b[i] ** 2; }
  return dot / (Math.sqrt(na) * Math.sqrt(nb) + 1e-8);
}

async function warmPatterns() {
  const t0 = Date.now();
  for (const [agent, text] of Object.entries(AGENT_PATTERNS))
    patternEmbeddings[agent] = await embed(text);
  // SemanticRouter: upstream multi-utterance routing (8/10 vs cosine 5/10).
  try {
    const rv = await import('ruvector');
    const SR = rv.SemanticRouter || rv.default?.SemanticRouter;
    if (SR) {
      semanticRouter = new SR({ dimension: 384, threshold: 0.25 });
      semanticRouter.setEmbedder(async (text) => {
        const out = await embedder.embed(text);
        return Float32Array.from(out?.embedding || out);
      });
      const routes = [
        { name: 'security-architect', utterances: ['security audit', 'vulnerability fix', 'authentication review', 'penetration test', 'secure code review', 'XSS injection'] },
        { name: 'tester', utterances: ['write tests', 'unit test', 'integration test', 'test coverage', 'create test cases', 'verify functionality'] },
        { name: 'coder', utterances: ['implement feature', 'write code', 'create function', 'build component', 'fix bug', 'refactor code'] },
        { name: 'reviewer', utterances: ['review code', 'code review', 'check quality', 'find issues', 'suggest improvements'] },
        { name: 'architect', utterances: ['design system', 'architecture', 'system structure', 'design patterns', 'plan implementation'] },
        { name: 'devops', utterances: ['deploy', 'kubernetes', 'docker', 'ci cd pipeline', 'infrastructure', 'helm charts', 'github actions'] },
        { name: 'frontend-developer', utterances: ['css layout', 'react component', 'ui design', 'responsive design', 'frontend styling'] },
        { name: 'backend-developer', utterances: ['api endpoint', 'database query', 'server implementation', 'rest api', 'graphql schema'] },
        { name: 'rust-developer', utterances: ['rust code', 'cargo build', 'borrow checker', 'lifetime annotation', 'unsafe rust'] },
        { name: 'python-developer', utterances: ['python script', 'pytest', 'pandas dataframe', 'django view', 'flask endpoint'] },
        { name: 'typescript-developer', utterances: ['typescript types', 'type interface', 'generic types', 'enum definition'] },
      ];
      for (const r of routes) await semanticRouter.addRouteAsync(r.name, r.utterances);
      log(`semanticRouter: ${routes.length} agents loaded`);
    }
  } catch (e) { log('semanticRouter: ' + e.message); }
  log(`patterns: ${Object.keys(patternEmbeddings).length} agents warm in ${Date.now() - t0}ms`);
}

async function route(taskText) {
  const t0 = Date.now();
  // P1-6: reuse embedding from begin_trajectory if available (avoids 2x ONNX inference)
  const emb = activeTrajSeed?.embedding || await embed(taskText);

  // SemanticRouter (primary, 8/10) → cosine fallback (5-7/10)
  let scores;
  let routeSource = 'cosine';
  if (semanticRouter) {
    try {
      const srResult = await semanticRouter.matchTopK(taskText, 3);
      if (srResult.length > 0 && srResult[0].score > 0.25) {
        // Build scores array from SemanticRouter results + fill remaining agents
        const srAgents = new Set(srResult.map(r => r.route));
        scores = [
          ...srResult.map(r => ({ agent: r.route, confidence: r.score })),
          ...Object.keys(patternEmbeddings).filter(a => !srAgents.has(a)).map(a => ({ agent: a, confidence: 0.1 })),
        ].sort((a, b) => b.confidence - a.confidence);
        routeSource = 'semantic';
      }
    } catch (e) { log('route.semantic: ' + e.message); }
  }
  // Fallback: cosine against AGENT_PATTERNS
  if (!scores) {
    scores = Object.entries(patternEmbeddings)
      .map(([agent, pe]) => ({ agent, confidence: cosine(emb, pe) }))
      .sort((a, b) => b.confidence - a.confidence);
  }

  // Fix 17: Consult SonaEngine learned patterns (foxref canonical path).
  // Patterns now carry modelRoute (from setTrajectoryRoute → k-means → NAPI).
  let priorBoost = null;
  try {
    const patterns = sona.findPatterns(emb, 5);
    if (Array.isArray(patterns) && patterns.length > 0) {
      const adjusted = new Set();
      for (const pat of patterns) {
        const learnedAgent = pat.modelRoute;
        if (!learnedAgent || adjusted.has(learnedAgent)) continue;
        adjusted.add(learnedAgent);
        const match = scores.find(s => s.agent === learnedAgent);
        if (!match) continue;
        // Quality-aware: high quality → boost, low quality → penalize
        const delta = pat.avgQuality >= 0.5 ? +0.05 : -0.05;
        match.confidence = Math.max(0, Math.min(1.0, match.confidence + delta));
      }
      if (adjusted.size > 0) {
        scores.sort((a, b) => b.confidence - a.confidence);
        priorBoost = { found: patterns.length, adjusted: adjusted.size };
      }
    }
  } catch (e) { log('route.patterns: ' + e.message); }

  // rbank provides quality context to the priorBoost (doesn't modify scores directly).
  // sona is primary for routing decisions (has modelRoute). rbank adds quality metadata.
  if (reasoningBank && priorBoost) {
    try {
      const rbPatterns = reasoningBank.searchSimilar(Array.from(emb), 3);
      const relevant = rbPatterns.filter(p => p.similarity > 0.5);
      const rbAvgQ = relevant.reduce((s, p) => s + p.avgQuality, 0) / (relevant.length || 1);
      priorBoost.rbankQuality = rbAvgQ;
      priorBoost.rbankCount = rbPatterns.length;
      // Fix 22: capture rbank pattern IDs for record_usage() at end_trajectory.
      if (activeTrajSeed) activeTrajSeed.rbankIds = relevant.map(p => p.id);
    } catch (e) { log('route.rbank: ' + e.message); }
  }

  // Fix 17: Tell SonaEngine which agent was FINALLY routed (feeds Loop A/B/C).
  if (activeTrajId != null) {
    try { sona.setTrajectoryRoute(activeTrajId, scores[0].agent); } catch {}
  }
  // Fix 18: Record routed agent in seed for VerdictAnalyzer at end_trajectory.
  if (activeTrajSeed) activeTrajSeed.routedAgent = scores[0].agent;

  return {
    agent: scores[0].agent,
    confidence: scores[0].confidence,
    reason: `${routeSource} (${(scores[0].confidence * 100).toFixed(1)}%)${priorBoost ? ` +${priorBoost.found} prior` : ''}`,
    alternatives: scores.slice(1, 4),
    _embedding: 'onnx-384-warm',
    _learning: priorBoost || { found: 0 },
    _ms: Date.now() - t0,
  };
}

// ─── IPC command handlers — each is a one-to-one passthrough to upstream ────
// Every handler below is annotated with the 4-axis trace required by
// memory/feedback_cycle_phases_no_ambiguity.md (phase × loop × tier × upstream
// symbol with package + file:line). ADR ref: doc/adr/000-DDD.md §3.4.
const H = {
  // Lifecycle ping — no §3.4 phase. Includes memory observability from @claude-flow/memory.
  //   Upstream: SonaEngine.getStats (@ruvector/sona · crates/sona/src/napi_simple.rs)
  //           + SQLiteBackend.getStats (@claude-flow/memory · sqlite-backend.ts)
  //     getStats already returns { totalEntries, entriesByNamespace, entriesByType,
  //     memoryUsage, ... } — no separate count() needed.
  // try/catch wrap is an operator-accepted exception for observability (2026-04-14).
  async status() {
    let memory;
    try       { memory = { path: dbPath, stats: await db.getStats() }; }
    catch (e) { memory = { path: dbPath, error: e.message }; }
    // Fix 23: EWC++ telemetry — samples_seen progress toward 50-sample task-boundary gate.
    let ewc = null;
    try { ewc = JSON.parse(sona.ewcStats()); } catch {}
    return { ok: true, data: { uptime: process.uptime(), sona: sona.getStats(), ewc, activeTrajectoryId: activeTrajId, memory } };
  },
  // Embedding primitive — §3 self-improving path, not a §3.4 phase.
  //   Upstream: AdaptiveEmbedder.embed (ruvector · core/adaptive-embedder; the
  //   package's ONNX hook is monkey-patched at init to use @xenova/transformers
  //   — see memory/feedback_onnx_xenova.md).
  async embed(c) { return { ok: true, data: { embedding: await embed(c.text || '') } }; },
  // Phase 1 CAPTURE (prompt-level open) · Loop A · reactive
  //   Upstream: SonaEngine.beginTrajectory(queryEmbedding)
  //   @ruvector/sona · crates/sona/src/napi_simple.rs:70 (napi_simple API —
  //   Integer ID returned; see memory/feedback_napi_simple.md).
  async begin_trajectory(c) {
    const vec = await embed(c.text || '');
    activeTrajId = sona.beginTrajectory(vec);
    // Capture seed for Phase 6 STORE at end_trajectory. embedding reused (no re-embed).
    activeTrajSeed = { prompt: c.text || '', embedding: vec, startedAt: Date.now(), steps: 0, stepActions: [], filePaths: [], rbankIds: [], routedAgent: null };
    return { ok: true, data: { trajectoryId: activeTrajId } };
  },
  // Phase 1 CAPTURE (pre/post tool step) · Loop A · reactive
  //   Upstream: SonaEngine.addTrajectoryStep(id, activations, attention, reward)
  //   @ruvector/sona · crates/sona/src/napi_simple.rs:89 — activations is the
  //   step embedding (384-dim); attention is [] when caller has none (v3
  //   precedent; Array type required — feedback_napi_simple.md).
  async add_step(c) {
    if (activeTrajId == null) return { ok: false, error: 'no active trajectory' };
    const vec = await embed(c.text || '');
    sona.addTrajectoryStep(activeTrajId, vec, [], c.reward ?? 0);
    if (activeTrajSeed) {
      activeTrajSeed.steps += 1;
      // Fix 18: collect step data for VerdictAnalyzer
      const success = (c.reward ?? 0) >= 0;
      activeTrajSeed.stepActions.push({
        action: c.text || 'step', success,
        confidence: Math.abs(c.reward ?? 0.5),
        error: success ? '' : (c.text || 'failed'),
        rationale: '',
      });
      // Fix 20b: accumulate file paths for classifyChange diff context.
      if (c.filePath) activeTrajSeed.filePaths.push(c.filePath);
    }
    return { ok: true };
  },
  // Phases 4 JUDGE + 5 DISTILL + 6 STORE + 7 REINFORCE · Loop B · — (no tier)
  //   Upstream: SonaEngine.endTrajectory(id, quality) + SonaEngine.forceLearn()
  //   @ruvector/sona · crates/sona/src/napi_simple.rs. forceLearn internally
  //   invokes ruvllm::VerdictAnalyzer (verdicts.rs:314), ruvllm::EpisodicMemory
  //   .extract_patterns (episodic_memory.rs:309), ruvllm::PatternStore.insert
  //   (pattern_store.rs), and ruvllm::QualityScoringEngine.
  //   Known upstream behaviour: returns "skipped: insufficient trajectories"
  //   until buffer ≥ pattern_clusters (default 100, types.rs:387). OQ-2.
  async end_trajectory(c) {
    if (activeTrajId == null) return { ok: false, error: 'no active trajectory' };
    const id = activeTrajId, seed = activeTrajSeed;
    activeTrajId = null; activeTrajSeed = null;
    const reward = c.reward ?? 0.5;

    // P1: VerdictAnalyzer FIRST — get nuanced quality before feeding SonaEngine.
    let verdict = null;
    if (reasoningBank && seed?.embedding) {
      try {
        verdict = reasoningBank.storeAndAnalyze(
          Array.from(seed.embedding), seed.stepActions || [], reward, seed.routedAgent || '',
        );
      } catch (e) { log('verdict: ' + e.message); }
    }
    // VerdictAnalyzer.qualityScore is binary (0 or 1, threshold at reward=0.5).
    // Using it here destroyed the handler's gradient quality signal — all patterns
    // ended up avgQuality=1 (quality=0 ones were dropped by sona's 0.05 threshold).
    // Fix: use the handler's gradient quality (1 - fails/steps) for sona learning;
    // VerdictAnalyzer metadata (rootCause, lessons, improvements) still feeds rbank.
    const quality = reward;

    sona.endTrajectory(id, quality);
    // Loop A (MicroLoRA) fires automatically inside instant.on_trajectory — no daemon call needed.
    // Loop B deferred to session_end forceLearn (canonical per foxref §1.2; hourly cadence at
    // session scale = once per session). Fix 25: removed per-trajectory tick() — after 1hr
    // daemon uptime it drained the buffer into run_cycle(force=false) which dropped trajectories
    // when count < min_trajectories (=10). forceLearn with force=true at session_end has no such gate.
    const learnStatus = null;

    // Fix 22: record usage feedback on rbank patterns retrieved during route().
    // Closes the explicit feedback loop per upstream PatternStore::record_usage design.
    if (reasoningBank && seed?.rbankIds?.length) {
      const wasSuccessful = quality >= 0.5;
      for (const pid of seed.rbankIds) {
        try { reasoningBank.recordUsage(pid, wasSuccessful, quality); } catch (e) { log('recordUsage: ' + e.message); break; }
      }
    }

    // Tier 1: feed substrate.coherence.observe(prompt-embedding, sessionTag) — drift/coherence pipeline.
    //   Pure observation; no formula. Used at session-end via substrate.onSessionEnd report().
    //   DQ-06 candidate signal: drift spike between trajectories may proxy task-boundary.
    if (substrate && seed?.embedding) {
      try { substrate.coherence.observe(seed.embedding, `traj-${id}`); }
      catch (e) { log('substrate.coherence.observe: ' + e.message); }
    }

    // Tier 2: classify trajectory using upstream ruvector.classifyChange (real classifier returning
    //   feature/bugfix/refactor/docs/test/config/unknown). Output → MemoryEntry tags as
    //   DQ-03 partial workaround. Pre-existing C4 tags contract; zero invention.
    // Fix 20b: classifyChange(diff, message) — diff = file paths for extension matching,
    // message = user prompt for keyword matching. Was (prompt, '') — args swapped, no diff data.
    let category = 'unknown';
    if (rvHelpers?.classifyChange && seed?.prompt) {
      try {
        const diff = (seed?.filePaths || []).join('\n');
        category = rvHelpers.classifyChange(diff, seed.prompt) || 'unknown';
      } catch (e) { log('classifyChange: ' + e.message); }
    }

    // Phase 6 STORE · Loop B · — (no tier)
    //   Upstream: @claude-flow/memory::SQLiteBackend.store (sqlite-backend.ts:58)
    //   entry built via createDefaultEntry (types.ts:20) — canonical factory.
    //   embedding field is Float32Array per MemoryEntry interface (types.d.ts:36).
    //   try/catch per feedback_try_catch_observability.md: DB write is a boundary
    //   call; failure must not crash the daemon — log + return structured result.
    let stored = false, storeErr = null;
    const outcome = quality > 0.6 ? 'positive' : quality < 0.4 ? 'negative' : 'neutral';
    try {
      const entry = createDefaultEntry({
        key: `trajectory/${id}`,
        content: seed?.prompt || '',
        type: 'episodic',
        namespace: 'ruflo-v4',
        tags: ['trajectory', outcome, `category:${category}`],
        metadata: { trajectoryId: id, reward, category, steps: seed?.steps ?? 0, learnStatus, startedAt: seed?.startedAt ?? null },
        accessLevel: 'private',
      });
      if (seed?.embedding) entry.embedding = Float32Array.from(seed.embedding);
      await db.store(entry);
      stored = true;
      log('C4 stored: ' + entry.key + ' quality=' + quality);
    } catch (e) {
      storeErr = e.message;
      log('end_trajectory store FAILED: ' + e.message);
    }
    return { ok: true, data: { trajectoryId: id, category, learnStatus, stored, storeErr, verdict, quality } };
  },
  // Tier 2 EXTENSION — IPC for hook-handler to fetch upstream code-analysis on demand.
  //   Pure passthrough to ruvector.extractAllPatterns (returns {functions, classes, imports, todos}).
  //   Hook-handler can invoke at PreToolUse/PostToolUse with a file path; daemon does the parse work.
  async analyze_file(c) {
    if (!rvHelpers?.extractAllPatterns) return { ok: false, error: 'ruvector.extractAllPatterns unavailable' };
    if (!c.path) return { ok: false, error: 'path required' };
    try {
      let content = c.content;
      if (content == null) {
        try { content = fs.readFileSync(c.path, 'utf8'); }
        catch (e) { return { ok: false, error: 'read failed: ' + e.message }; }
      }
      return { ok: true, data: rvHelpers.extractAllPatterns(c.path, content) };
    } catch (e) { log('analyze_file: ' + e.message); return { ok: false, error: e.message }; }
  },
  // Phase 2 RETRIEVE (cross-session restore) · Loop A · —
  //   Upstream: @claude-flow/memory::SQLiteBackend.query (sqlite-backend.ts:188)
  //   Used by hook SessionStart (observability) and handler (inline intelligence
  //   block formatting). Caps limit defensively at a
  //   boundary value (100) because this crosses IPC from hook; not D1 invention
  //   (upstream has no cap, we set a sane UDS-message ceiling).
  async memory_query(c) {
    const limit = Math.max(1, Math.min(c.limit ?? 10, 1000));
    const q = { type: 'exact', limit };
    if (c.namespace)  q.namespace = c.namespace;
    if (Array.isArray(c.tags) && c.tags.length) q.tags = c.tags;
    if (c.memoryType) q.memoryType = c.memoryType;
    try {
      const entries = await db.query(q);
      // Strip Float32Array embeddings from IPC payload (binary → JSON is lossy/heavy).
      const slim = entries.map(e => ({ id: e.id, key: e.key, content: e.content, type: e.type, tags: e.tags, metadata: e.metadata, createdAt: e.createdAt }));
      return { ok: true, data: { count: slim.length, entries: slim } };
    } catch (e) {
      log('memory_query: ' + e.message);
      return { ok: false, error: e.message };
    }
  },
  // Phase 2 RETRIEVE · Loop A (same tick as CAPTURE) · reactive
  //   Upstream: SonaEngine.findPatterns(embedding, k) → JsLearnedPattern[]
  //   @ruvector/sona · crates/sona/src/napi_simple.rs.
  async find_patterns(c) {
    const vec = await embed(c.text || '');
    const patterns = sona.findPatterns(vec, c.k ?? 5);
    // Fix 21: retrieval telemetry — visibility into "did findPatterns actually find anything?"
    const topQ = patterns[0]?.avgQuality ?? 0;
    const topR = patterns[0]?.modelRoute ?? 'none';
    log(`findPatterns: q="${(c.text||'').slice(0,40)}" hits=${patterns.length} top=${topR}@q${topQ.toFixed(2)}`);
    return { ok: true, data: patterns };
  },
  // Loop-B background check (buffer/time gate) · Upstream: SonaEngine.tick
  //   returns Option<String>; @ruvector/sona.
  // Agent routing — ONNX cosine against precomputed agent patterns + SONA boost.
  //   Not a §3.4 phase — adapter-layer routing that uses upstream embeddings.
  async route(c) {
    const taskText = c.task || c.text || c.prompt || '';
    if (!taskText) return { ok: true, msg: 'no task' };
    return { ok: true, data: await route(taskText) };
  },
  async tick()        { const msg = sona.tick();       return { ok: true, data: { msg, stats: sona.getStats() } }; },
  async force_learn() { const msg = sona.forceLearn(); return { ok: true, data: { msg, stats: sona.getStats() } }; },
  // Instant-loop flush (MicroLoRA pending updates) · Upstream: SonaEngine.flush
  //   @ruvector/sona. NOT a §3.4 phase — sub-primitive of Loop A.
  async flush()       { sona.flush();      return { ok: true, data: sona.getStats() }; },
  // Loop C session-close · Phases 11 FORGET + 12 PRUNE + 0 SAVE + 13 EXPORT
  //   Delegated to services[].onSessionEnd() per ADR-ruflo-007. Each service contributes
  //   its own slice of the response payload; the handler aggregates and returns.
  //   CRITICAL invariant: NO service.shutdown() runs here. Daemon-scope teardown is
  //   ONLY in SIGTERM handler (main.shutdown). Pre-2026-04-15 dogfood bug: this used
  //   to call db.shutdown() inline → daemon survived the SessionEnd with a closed DB,
  //   silently degrading C4 storage for the rest of its lifetime. ADR-007 fixed it.
  async session_end() {
    const merged = {};
    for (const s of services) {
      try {
        const contrib = await s.onSessionEnd?.();
        if (contrib && typeof contrib === 'object') Object.assign(merged, contrib);
      } catch (e) {
        log(`${s.name}.onSessionEnd: ${e.message}`);
        merged[`${s.name}Err`] = e.message;
      }
    }
    return { ok: true, data: merged };
  },
};

// ─── IPC server (UDS, JSON-line delimited) ──────────────────────────────────
function handleConnection(sock) {
  let buf = '';
  sock.on('data', async (chunk) => {
    buf += chunk.toString();
    let idx;
    while ((idx = buf.indexOf('\n')) !== -1) {
      const line = buf.slice(0, idx); buf = buf.slice(idx + 1);
      if (!line.trim()) continue;
      let resp;
      try {
        const cmd = JSON.parse(line);
        const fn = H[cmd.command];
        resp = fn ? await fn(cmd) : { ok: false, error: 'unknown command: ' + cmd.command };
      } catch (e) { resp = { ok: false, error: e.message }; }
      sock.write(JSON.stringify(resp) + '\n');
    }
  });
  sock.on('error', () => {});
}

// ─── Singleton enforcement (Fix 14a, per @claude-flow/cli worker-daemon.js pattern) ──
if (fs.existsSync(PID_PATH)) {
  try {
    const existingPid = parseInt(fs.readFileSync(PID_PATH, 'utf8').trim(), 10);
    process.kill(existingPid, 0); // throws if process is dead
    console.error(`ruvector-daemon: already running (PID ${existingPid}), exiting`);
    process.exit(0);
  } catch { try { fs.unlinkSync(PID_PATH); } catch {} }
}

async function main() {
  // Ensure directories exist
  for (const p of [path.dirname(SOCKET_PATH), path.dirname(LOG_PATH)])
    fs.mkdirSync(p, { recursive: true });
  try { fs.unlinkSync(SOCKET_PATH); } catch {}

  await initialize();
  await warmPatterns();

  // Fix 25: no setInterval tick() — after 1hr uptime every tick drained the instant buffer
  // into run_cycle(force=false) which dropped trajectories when count < min_trajectories.
  // forceLearn at session_end is the canonical Loop B trigger (force=true, no min gate).

  const server = net.createServer(handleConnection);
  server.listen(SOCKET_PATH, () => {
    try { fs.chmodSync(SOCKET_PATH, 0o600); } catch {}
    fs.writeFileSync(PID_PATH, String(process.pid));
    log(`daemon ready on ${SOCKET_PATH} (PID ${process.pid})`);
  });
  // SIGTERM/SIGINT — daemon-scope teardown only. Per ADR-ruflo-007: services[].shutdown()
  //   runs HERE (real process exit), never in session_end.
  const shutdown = async () => {
    for (const s of services) {
      try { await s.shutdown?.(); }
      catch (e) { log(`${s.name}.shutdown: ${e.message}`); }
    }
    try { server.close(); } catch {}
    try { fs.unlinkSync(SOCKET_PATH); } catch {}
    try { fs.unlinkSync(PID_PATH); } catch {}
    process.exit(0);
  };
  process.on('SIGTERM', shutdown); process.on('SIGINT', shutdown);
}

main().catch(e => { log('FATAL: ' + e.message); process.exit(1); });
