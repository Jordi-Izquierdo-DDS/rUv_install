---
name: SONA NAPI — Use napi_simple.rs API (Integer IDs), Not napi.rs (TrajectoryBuilder)
description: @ruvector/sona compiles napi_simple.rs which uses integer trajectory IDs, NOT napi.rs which returns TrajectoryBuilder objects. The daemon must use beginTrajectory()→u32, addTrajectoryStep(id,...), endTrajectory(id,quality). Check via GitNexus context on napi_simple.rs.
type: feedback
originSessionId: b7bb4897-dbbb-4c84-b86c-d85f3160dbbd
---
Two NAPI files exist in ruvector sona crate:
- `napi.rs` — full API with TrajectoryBuilder objects. DEAD CODE (not compiled).
- `napi_simple.rs` — simplified API with integer IDs. THIS IS WHAT'S COMPILED (`lib.rs:67`).

**The daemon MUST use the napi_simple API:**
- `sona.beginTrajectory(embedding)` → returns `u32` (NOT TrajectoryBuilder)
- `sona.addTrajectoryStep(id, activations, attention, reward)` (NOT `builder.addStep()`)
- `sona.endTrajectory(id, quality)` (NOT `sona.endTrajectory(builder, quality)`)

**How to apply:** Before writing SONA daemon code, check `lib.rs` to see which NAPI module is compiled. Use GitNexus `context({name: "SonaEngine", file_path: "crates/sona/src/napi_simple.rs"})` to see the actual API.
