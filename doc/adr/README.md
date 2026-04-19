# Architecture Decision Records — ruflo v5 (clean unified)

Seven active ADRs, one decision each. No amendments, no supersessions, no iterative noise. Previous iterative ADRs archived in `zz_archive/adr_iterative_backup/` for archaeology.

| # | Decision | File |
|---|---|---|
| 001 | Domain + 3-layer architecture + Protocol 2 research discipline | [001-domain-and-protocol.md](001-domain-and-protocol.md) |
| 002 | Learning cycle — 7 phases × 3 loops (foxref-aligned) | [002-learning-cycle.md](002-learning-cycle.md) |
| 003 | Memory persistence — 5 layers with graceful degradation | [003-memory-persistence.md](003-memory-persistence.md) |
| 004 | REFINE phase (MinCut/GNN) deferred | [004-refine-deferred.md](004-refine-deferred.md) |
| 005 | Vendor NAPI overlay pattern — upstream gaps fixed via maintained patches | [005-vendor-napi-overlay.md](005-vendor-napi-overlay.md) |
| 006 | Daemon service lifecycle — session-scope vs daemon-scope discipline | [006-daemon-lifecycle.md](006-daemon-lifecycle.md) |
| 007 | LOC cap + composition discipline — 1200 LOC, no invention | [007-loc-cap-composition.md](007-loc-cap-composition.md) |

## Reading order

- **Architects / reviewers:** 001 → 002 → 005 (the three big shape decisions)
- **Implementers:** 006 → 007 → 003 (how code is structured + constrained)
- **Consumers:** 002 + 004 (the cycle + what's deferred)

## What each ADR answers

- **001:** Why does ruflo exist and how do we decide what to wire?
- **002:** What are the learning phases and how do they map to code?
- **003:** Where is state stored and what happens when layers fail?
- **004:** Why isn't MinCut/GNN wired and when would we reconsider?
- **005:** How do we extend upstream without forking? (4 current patches documented)
- **006:** How does the daemon survive across sessions without state bugs?
- **007:** How do we prevent reinvention while allowing composition?
