#!/bin/bash
# Smoke 04 — pattern crystallization ablation (OQ-2 investigation).
#
# Purpose: submit semantically DIVERSE trajectories across 5 domains, ≥100 total,
# to exercise BOTH layers of the @ruvector/sona pattern-extraction gate:
#
#   Layer 1 — min_trajectories (=100 in @ruvector/sona@0.1.5, 10 in upstream v2.1.2)
#   Layer 2 — k-means quality + semantic diversity of trajectory embeddings
#
# Synthetic "refactor variant N" prompts (smoke-01) are too similar to form
# distinct clusters. This test uses 5 domains × 24 variants each = 120 trajectories
# with real-world prompt diversity. Expect >0 patterns at n=120 if Layer 2 is
# sensitive to prompt variety (not just count).
#
# Outputs: JSON record with per-ablation results (buffer, force_learn status,
# patterns_stored, and a sample find_patterns response on a held-out prompt).
# No assertion inverts a "0 patterns" result — the test REPORTS; OQ-2 conclusion
# is read from the result, not enforced.

set -eu
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

SOCK="/tmp/ruvflo-v4-smoke04.sock"
PID="/tmp/ruvflo-v4-smoke04.pid"
LOG="/tmp/ruvflo-v4-smoke04.log"
rm -f "$SOCK" "$PID" "$ROOT/.swarm/memory.db"
export RUVFLO_V4_SOCK="$SOCK"
export RUVFLO_V4_PID="$PID"

echo "[smoke-04] booting daemon (fresh .swarm/memory.db)"
node .claude/helpers/ruvector-daemon.mjs >"$LOG" 2>&1 &
DAEMON_PID=$!
cleanup() { kill -TERM "$DAEMON_PID" 2>/dev/null || true; wait "$DAEMON_PID" 2>/dev/null || true; rm -f "$SOCK" "$PID"; }
trap cleanup EXIT

for i in $(seq 1 60); do [ -S "$SOCK" ] && break; sleep 0.2; done
if [ ! -S "$SOCK" ]; then echo "FAIL: daemon"; tail -30 "$LOG"; exit 1; fi

python3 - <<'PY'
import socket, json, os, time, sys

def ipc(cmd, timeout=30):
    s = socket.socket(socket.AF_UNIX); s.settimeout(timeout); s.connect(os.environ["RUVFLO_V4_SOCK"])
    s.sendall((json.dumps(cmd)+"\n").encode()); buf=b""
    while b"\n" not in buf: buf += s.recv(8192)
    s.close()
    return json.loads(buf.splitlines()[0])

# 5 domains × 24 variants = 120 trajectories. Prompts chosen to span distinct
# semantic clusters: auth/security, API/network, data/DB, UI/frontend, testing.
domains = {
    "auth": [
        "refactor user authentication to use JWT tokens with refresh rotation",
        "migrate legacy session cookies to OAuth2 authorization code flow",
        "implement TOTP two-factor authentication during sign-in",
        "add WebAuthn passkey support to existing password login",
        "rotate API keys automatically every 90 days with revocation list",
        "enforce SAML SSO for enterprise tenants with JIT provisioning",
        "add bcrypt password hashing with configurable work factor",
        "harden CSRF tokens on state-changing endpoints",
        "implement device-binding for high-risk login attempts",
        "add rate limiting to login endpoint to prevent brute-force",
        "audit failed login attempts and trigger alerts on threshold",
        "implement account lockout after N consecutive failures",
        "add magic-link email-based passwordless login flow",
        "encrypt session tokens at rest using AES-256-GCM",
        "rotate JWT signing keys with grace period for old tokens",
        "implement GDPR-compliant session revocation on user request",
        "add biometric fallback for mobile auth flow",
        "verify email ownership via double opt-in confirmation",
        "implement OIDC discovery endpoint for federated login",
        "protect admin routes with stepped-up MFA challenge",
        "add hardware security key (FIDO2) enrollment flow",
        "implement social-login via Google, GitHub, Microsoft",
        "add risk-based auth with adaptive challenge frequency",
        "encrypt refresh tokens with user-specific HKDF-derived keys",
    ],
    "api": [
        "design REST endpoint for paginated product catalog queries",
        "add cursor-based pagination to infinite-scroll feeds",
        "write GraphQL resolver for nested order-line-items",
        "implement rate limiting per API key with token bucket",
        "add OpenAPI schema generation from code annotations",
        "version the public API with semantic versioning in URL",
        "add idempotency keys to POST endpoints for safe retries",
        "document deprecated endpoints with sunset HTTP header",
        "add CORS configuration for third-party browser clients",
        "implement webhook dispatch with exponential-backoff retry",
        "add request ID propagation through microservice hops",
        "compress large response bodies with Brotli content-encoding",
        "stream large datasets via HTTP chunked transfer encoding",
        "add conditional GET support with ETag and If-None-Match",
        "validate request payloads against JSON Schema at the edge",
        "reject requests exceeding 10MB with 413 Payload Too Large",
        "implement HATEOAS links in REST resource responses",
        "add tracing headers compatible with W3C traceparent",
        "support partial responses via fields query parameter",
        "add batch endpoint to reduce N+1 round trips",
        "protect internal-only endpoints with mTLS",
        "add circuit breaker around flaky upstream dependency",
        "return problem+json for error payloads per RFC 7807",
        "implement long polling fallback where websockets unavailable",
    ],
    "db": [
        "optimize slow query joining orders and users with 10M rows",
        "add composite index on users.email_lower and tenant_id",
        "migrate audit_log schema to partition by month",
        "add read replicas for analytics queries to offload primary",
        "implement soft-delete with deleted_at timestamp and views",
        "rebuild corrupted btree index on payments.transaction_id",
        "add fulltext search on products.description with tsvector",
        "migrate from VARCHAR(255) to TEXT for user bio fields",
        "backfill new tenant_id column with zero downtime",
        "deduplicate rows in raw_events using window function",
        "archive rows older than 2 years to cold storage",
        "add check constraint preventing negative stock_quantity",
        "optimize N+1 query by adding batch-loader in ORM",
        "migrate primary key from int to bigint before exhaustion",
        "add trigger to maintain denormalized aggregate counters",
        "replicate schema changes via logical decoding to warehouse",
        "implement row-level security for multi-tenant isolation",
        "add connection pooling with pgbouncer in transaction mode",
        "tune autovacuum thresholds for high-churn orders table",
        "migrate JSON column to JSONB with GIN index for searches",
        "rollback last migration and re-apply after fixing typo",
        "add unique partial index excluding soft-deleted rows",
        "shard large events table by tenant_id hash",
        "add database-backed job queue with skip-locked polling",
    ],
    "ui": [
        "style primary login button with rounded corners and hover",
        "add dark mode toggle persisting preference to localStorage",
        "fix responsive layout collapsing on 375px mobile viewport",
        "animate modal open/close with CSS transition not JS timer",
        "replace nested flexbox with grid for settings page",
        "add skeleton loading state while async product list fetches",
        "implement virtualized list for 10k-row admin dashboard",
        "add drag-and-drop reordering to kanban board columns",
        "fix keyboard focus trap in accessible modal dialog",
        "add debounced search input with 300ms delay before fetch",
        "persist form draft in sessionStorage across refreshes",
        "extract shared button styles into design-system tokens",
        "add progressive image loading with blurred placeholder",
        "fix flash-of-unstyled-content during critical CSS inline",
        "migrate from styled-components to Tailwind utility classes",
        "add toast notification system with stacking and timeouts",
        "implement infinite scroll with IntersectionObserver",
        "add print stylesheet for checkout receipt page",
        "fix horizontal scroll bug introduced by wide data table",
        "animate number counter from 0 to target on viewport entry",
        "implement multi-step form wizard with progress indicator",
        "add favicon with dark/light mode SVG variants",
        "fix contrast ratio issue flagged by axe accessibility scan",
        "add reduced-motion media query to disable parallax effects",
    ],
    "test": [
        "write unit tests for JSON parser covering malformed input",
        "add integration test for checkout flow including payment",
        "mock external Stripe API in billing test suite",
        "add property-based tests for pagination invariants",
        "seed test database with fixtures before each test case",
        "snapshot-test email templates against rendered HTML",
        "add performance regression test gating PR merges at 10%",
        "write smoke test for daemon startup and IPC handshake",
        "add contract test between orders-service and payment-service",
        "parameterize auth test across happy/edge/malicious paths",
        "add flaky-test detector running each test 10 times in CI",
        "write e2e test for signup through first purchase via Playwright",
        "mock system clock to exercise cron job scheduling logic",
        "add fuzz test for URL parser handling adversarial inputs",
        "verify idempotency of webhook replay with duplicate deliveries",
        "add a11y axe scan to every page in Storybook CI job",
        "test concurrent writes trigger serialization_failure properly",
        "simulate network partition to test replication catch-up",
        "add visual regression test for login page across breakpoints",
        "load-test orders endpoint at 1000 RPS sustained for 5 minutes",
        "verify logging never emits PII using redaction test helper",
        "add mutation test for critical pricing-calculation module",
        "write test that async-queue drains within SLA after backpressure",
        "add deterministic seed for all random-test helpers",
    ],
}

assert sum(len(v) for v in domains.values()) >= 100, "need ≥100 trajectories"

print(f"[smoke-04] submitting {sum(len(v) for v in domains.values())} diverse trajectories "
      f"across {len(domains)} domains")

t0 = time.time()
n = 0
for domain, prompts in domains.items():
    for prompt in prompts:
        ipc({"command":"begin_trajectory", "text": prompt})
        ipc({"command":"add_step", "text": f"pre:Read context for {domain}", "reward": 0})
        ipc({"command":"add_step", "text": f"post:Edit:ok implementing {domain} change", "reward": 0.1})
        ipc({"command":"add_step", "text": f"post:Bash:ok tests passed for {domain}", "reward": 0.1})
        # quality = mix: 60% high (0.9), 30% mid (0.5), 10% low (0.2)
        q = 0.9 if n % 10 < 6 else 0.5 if n % 10 < 9 else 0.2
        ipc({"command":"end_trajectory", "reward": q, "forceLearn": False})
        n += 1
print(f"[smoke-04] {n} trajectories submitted in {time.time()-t0:.1f}s")

stats = ipc({"command":"status"})["data"]["sona"]
print(f"[smoke-04] buffer state pre-force: {stats}")

# Force learn once with the full buffer (≥100 clears Layer 1)
r = ipc({"command":"force_learn"})
print(f"[smoke-04] force_learn: {r['data']['msg']}")
post = ipc({"command":"status"})["data"]["sona"]
print(f"[smoke-04] buffer state post-force: {post}")

# Sample find_patterns on a NEW prompt — does anything come back?
probe = "add JWT refresh-token rotation to auth service"
fp = ipc({"command":"find_patterns", "text": probe, "k": 5})
print(f"[smoke-04] find_patterns for '{probe}' k=5:")
print(json.dumps(fp["data"], indent=2) if fp.get("ok") else fp)

# C4 STORE verification (independent of learning layer)
q = ipc({"command":"memory_query", "namespace": "ruflo-v4", "tags": ["trajectory"], "limit": 200})
count = q.get("data",{}).get("count", 0)
print(f"[smoke-04] C4 STORE: {count} trajectories in .swarm/memory.db")

# Parse forceLearn to decide status. DO NOT fail the test on "0 patterns" — that's
# the measurement we're reporting. Only fail on unexpected errors.
msg = r["data"]["msg"]
if "skipped:" in msg:
    print(f"[smoke-04] RESULT: Layer 1 gate NOT cleared → {msg}")
    sys.exit(0)

import re
m = re.match(r"Forced learning: (\d+) trajectories -> (\d+) patterns", msg)
if m:
    traj, pats = int(m.group(1)), int(m.group(2))
    print(f"[smoke-04] RESULT: traj={traj} patterns={pats}")
    if pats > 0:
        print(f"[smoke-04] CRYSTALLIZED — Layer 2 cleared with diverse prompts")
    else:
        print(f"[smoke-04] Layer 1 cleared, Layer 2 still 0 patterns "
              f"— likely pattern-quality threshold vs. our reward/embedding spread")
PY

echo "[smoke-04] DONE (daemon cleanup on exit)"
