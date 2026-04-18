---
name: No RVF in ruflo scope
description: Exclude RVF (cognitive containers, MicroVm, RvfStore, eBPF) from ruflo architecture docs and integration plans — still too experimental upstream
type: feedback
originSessionId: 50639ab1-3df6-46c5-beaa-d43558500cd5
---
RVF (RuVector Format — cognitive containers, `MicroVm::launch`, `RvfStore`, `EbpfCompiler`/`EbpfManager`, `.rvf` file format, 32 eBPF symbols) must NOT be included in ruflo architecture guides, integration proposals, or dependency maps.

**Why:** Operator 2026-04-13 stated "I don't need RVF, it is still too experimental upstream." Upstream RVF crates (`crates/rvf/*`) are not yet stable enough to depend on for ruflo's self-learning cycle.

**How to apply:**
- Don't mention RVF, MicroVm, RvfStore, or eBPF-in-RVF symbols in Phase 3 / Phase 4 / Phase 5 proposals for ruflo
- When pulling foxRef content (Part01 L58–105, L233, Part02 L227–238, L661, L673), filter RVF sections out
- Witness chains / SHAKE-256 can still be referenced when they come from `prime-radiant::WitnessSource` — that's a separate, non-RVF code path
- π brain memories about RVF (e.g., *"RVF Cognitive Container - Sealed WASM Container"*) are informational only, not architecture we adopt
