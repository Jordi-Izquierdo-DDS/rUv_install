---
name: Measurement Discipline — p50 of ≥10 samples, drop first 2
description: Never trust a single-shot latency measurement when deciding whether to patch something. Take ≥10 samples, drop the first 2 as warmup, take p50. Otherwise you'll waste an hour fixing a problem that doesn't exist.
type: feedback
originSessionId: b7bb4897-dbbb-4c84-b86c-d85f3160dbbd
---
**Rule:** Never patch an MCP call, SQL query, or hook path based on a single-shot latency measurement. Always collect ≥10 samples, drop the first 2 as warmup, and report p50 (median) — not average or worst-case.

**Why:** This rule exists because I (Claude) once reported "memory_list is 10.7 ms warm, should be ~2 ms, needs patching". That 10.7 ms was a single outlier from an earlier warm-up window. Proper measurement over 10 samples showed:

```
memory_list{namespace:'mailbox'} (empty):
  samples (drop first 2): 5.2, 5.6, 5.7, 6.2, 6.4, 6.5, 6.5, 6.9, 7.0, 8.4
  p50: 6.5 ms   ← normal
  p95: 8.4 ms
```

Baseline for comparison (same warm MCP session):
- `agentdb_health`: p50 = 1.2 ms (MCP HTTP+JSON-RPC floor with no real work)
- `hooks_intelligence_stats`: p50 = 1.8 ms (in-memory counter read, no DB)
- `memory_list`: p50 = 6.5 ms (2 SQL SELECTs on memory_entries)
- `agentdb_pattern-search`: p50 = 10.0 ms (BM25 + HNSW search)

**How to apply:** Before proposing a performance patch, measure with this node snippet:

```javascript
const http = require('http');
async function call(name, args) {
  const body = JSON.stringify({jsonrpc:"2.0",id:1,method:"tools/call",params:{name,arguments:args}});
  const t0 = Number(process.hrtime.bigint())/1e6;
  return new Promise((res)=>{
    const req = http.request({hostname:"127.0.0.1",port:PORT,path:"/rpc",method:"POST",
      headers:{"Content-Type":"application/json","Content-Length":Buffer.byteLength(body)}},(r)=>{
      let d="";r.on("data",c=>d+=c);r.on("end",()=>res({ms:Number(process.hrtime.bigint())/1e6-t0}));
    });
    req.write(body);req.end();
  });
}
// Run ≥10 iterations, drop first 2, sort, take middle = p50
```

**Project-wide target:** 1-digit ms for warm MCP calls that hit SQLite is normal. 2-digit ms starts being a smell. 3-digit ms means something is broken or cold (first-call overhead, missing index, or fallback path taken).
