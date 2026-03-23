"""
02_strings.py — Redis Strings: The Foundation
==============================================

WHAT IS A REDIS STRING?
  A Redis string is a binary-safe sequence of bytes (up to 512 MB).
  Despite the name "string", it can hold:
    - Text         ("hello world")
    - Numbers      (42, 3.14) — Redis auto-detects and allows INCR/DECR
    - Serialized   (JSON, MessagePack, Protocol Buffers)
    - Binary       (images, files — though not recommended for large ones)

  Strings are the simplest and most-used Redis type. Every other data
  structure is essentially built on top of strings.

PRODUCTION USE CASES:
  - Caching (API responses, DB query results, rendered HTML)
  - Counters (page views, API calls, rate limits)
  - Flags (feature toggles, maintenance mode)
  - Distributed locks (SET with NX and EX)
  - Session tokens
"""

import sys, os, time, json
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from connection_helper import get_redis, cleanup

PREFIX = "demo:strings:"


def main():
    r = get_redis()
    cleanup(r, PREFIX)

    print("=" * 60)
    print("REDIS STRINGS DEMO")
    print("=" * 60)

    # ──────────────────────────────────────────────────────────
    # 1. BASIC SET / GET
    # ──────────────────────────────────────────────────────────
    # SET stores a value; GET retrieves it.
    # Time complexity: O(1) — constant time regardless of value size.
    print("\n--- 1. Basic SET / GET ---")

    r.set(f"{PREFIX}greeting", "Hello, Redis!")
    value = r.get(f"{PREFIX}greeting")
    print(f"  SET + GET: {value}")

    # GET on a non-existent key returns None (not an error)
    missing = r.get(f"{PREFIX}does_not_exist")
    print(f"  Missing key returns: {missing} (type: {type(missing)})")

    # ──────────────────────────────────────────────────────────
    # 2. SET WITH OPTIONS (Critical for Production)
    # ──────────────────────────────────────────────────────────
    # SET has powerful options that make it atomic:
    #   EX  = expire in N seconds
    #   PX  = expire in N milliseconds
    #   NX  = set ONLY if key does NOT exist (used for locks!)
    #   XX  = set ONLY if key ALREADY exists (used for updates)
    print("\n--- 2. SET with Options ---")

    # EX: Auto-expire after 10 seconds (great for caching)
    r.set(f"{PREFIX}cache_item", "cached_data", ex=10)
    ttl = r.ttl(f"{PREFIX}cache_item")
    print(f"  Cached with TTL: {ttl} seconds remaining")

    # NX: Only set if it doesn't already exist — this is how you build locks!
    # First attempt succeeds (key is new)
    result1 = r.set(f"{PREFIX}lock", "owner_1", nx=True, ex=30)
    print(f"  Lock attempt 1 (NX): {result1}")  # True

    # Second attempt fails (key already exists)
    result2 = r.set(f"{PREFIX}lock", "owner_2", nx=True, ex=30)
    print(f"  Lock attempt 2 (NX): {result2}")  # None (failed!)

    # XX: Only set if it already exists — safe updates
    r.set(f"{PREFIX}config", "v1")
    r.set(f"{PREFIX}config", "v2", xx=True)  # Succeeds (key exists)
    print(f"  XX update existing: {r.get(f'{PREFIX}config')}")

    r.set(f"{PREFIX}phantom", "value", xx=True)  # Fails (key doesn't exist)
    print(f"  XX on non-existent: {r.get(f'{PREFIX}phantom')}")  # None

    # ──────────────────────────────────────────────────────────
    # 3. COUNTERS (INCR / DECR)
    # ──────────────────────────────────────────────────────────
    # Redis treats string values as integers when you use INCR/DECR.
    # These operations are ATOMIC — safe under concurrency without locks.
    #
    # PRODUCTION USE: page view counters, rate limiting, inventory tracking
    print("\n--- 3. Atomic Counters ---")

    key = f"{PREFIX}page_views"
    r.set(key, 0)

    r.incr(key)          # 0 → 1
    r.incr(key)          # 1 → 2
    r.incrby(key, 10)    # 2 → 12
    r.decr(key)          # 12 → 11
    r.decrby(key, 3)     # 11 → 8

    print(f"  Counter after operations: {r.get(key)}")

    # INCR on a non-existent key auto-initializes to 0, then increments
    r.incr(f"{PREFIX}new_counter")
    print(f"  Auto-initialized counter: {r.get(f'{PREFIX}new_counter')}")

    # Float increment
    r.set(f"{PREFIX}price", "19.99")
    r.incrbyfloat(f"{PREFIX}price", 1.50)
    print(f"  Float increment: {r.get(f'{PREFIX}price')}")

    # ──────────────────────────────────────────────────────────
    # 4. MULTI-KEY OPERATIONS (MSET / MGET)
    # ──────────────────────────────────────────────────────────
    # Set or get multiple keys in ONE round trip to Redis.
    # Network round trips are often the bottleneck — MGET/MSET
    # cut them down dramatically.
    #
    # 10 individual GETs = 10 round trips ≈ 10ms
    # 1 MGET with 10 keys = 1 round trip ≈ 1ms
    print("\n--- 4. Multi-Key Operations ---")

    r.mset({
        f"{PREFIX}user:1:name": "Alice",
        f"{PREFIX}user:1:email": "alice@example.com",
        f"{PREFIX}user:1:role": "admin",
    })

    values = r.mget(
        f"{PREFIX}user:1:name",
        f"{PREFIX}user:1:email",
        f"{PREFIX}user:1:role",
        f"{PREFIX}user:1:missing",  # Will be None
    )
    print(f"  MGET results: {values}")

    # MSETNX: set multiple keys ONLY if NONE of them exist
    result = r.msetnx({
        f"{PREFIX}unique:a": "1",
        f"{PREFIX}unique:b": "2",
    })
    print(f"  MSETNX (all new): {result}")  # True

    result = r.msetnx({
        f"{PREFIX}unique:a": "changed",  # Already exists!
        f"{PREFIX}unique:c": "3",
    })
    print(f"  MSETNX (one exists): {result}")  # False — nothing was set

    # ──────────────────────────────────────────────────────────
    # 5. STRING MANIPULATION
    # ──────────────────────────────────────────────────────────
    print("\n--- 5. String Manipulation ---")

    # APPEND: add to end of string
    r.set(f"{PREFIX}log", "2024-01-01: started")
    r.append(f"{PREFIX}log", " | 2024-01-02: updated")
    print(f"  APPEND: {r.get(f'{PREFIX}log')}")

    # STRLEN: get string length
    print(f"  STRLEN: {r.strlen(f'{PREFIX}log')} bytes")

    # GETRANGE: substring (0-indexed, inclusive on both ends)
    print(f"  GETRANGE [0:9]: {r.getrange(f'{PREFIX}log', 0, 9)}")

    # SETRANGE: overwrite at offset
    r.set(f"{PREFIX}padded", "Hello, World!")
    r.setrange(f"{PREFIX}padded", 7, "Redis!")
    print(f"  SETRANGE: {r.get(f'{PREFIX}padded')}")

    # GETSET (now GETDEL in newer Redis): get old value, set new one
    old = r.getset(f"{PREFIX}padded", "Completely new value")
    print(f"  GETSET old: '{old}', new: '{r.get(f'{PREFIX}padded')}'")

    # ──────────────────────────────────────────────────────────
    # 6. STORING JSON (Common Pattern)
    # ──────────────────────────────────────────────────────────
    # Redis strings can store serialized JSON. This is how many apps
    # cache complex objects. Serialize on write, deserialize on read.
    print("\n--- 6. Storing JSON ---")

    user = {
        "id": 42,
        "name": "Alice",
        "email": "alice@example.com",
        "preferences": {"theme": "dark", "lang": "en"},
    }

    r.set(f"{PREFIX}user:42:json", json.dumps(user), ex=3600)
    cached = json.loads(r.get(f"{PREFIX}user:42:json"))
    print(f"  Stored & retrieved JSON: {cached['name']}, theme={cached['preferences']['theme']}")

    # ──────────────────────────────────────────────────────────
    # 7. SETNX PATTERN: Feature Flags
    # ──────────────────────────────────────────────────────────
    print("\n--- 7. Feature Flags Pattern ---")

    def is_feature_enabled(r, feature_name, default="false"):
        """Check a feature flag stored in Redis."""
        key = f"{PREFIX}feature:{feature_name}"
        val = r.get(key)
        if val is None:
            # Initialize with default value if first check
            r.set(key, default)
            return default == "true"
        return val == "true"

    # Admin enables a feature
    r.set(f"{PREFIX}feature:dark_mode", "true")
    r.set(f"{PREFIX}feature:beta_ui", "false")

    print(f"  dark_mode enabled: {is_feature_enabled(r, 'dark_mode')}")
    print(f"  beta_ui enabled:   {is_feature_enabled(r, 'beta_ui')}")
    print(f"  new_feature (auto): {is_feature_enabled(r, 'new_feature')}")

    # ──────────────────────────────────────────────────────────
    # CLEANUP
    # ──────────────────────────────────────────────────────────
    cleanup(r, PREFIX)

    print("\n✅ Strings demo complete!")
    print("""
┌─────────────────────────────────────────────────────────┐
│  KEY TAKEAWAYS:                                         │
│                                                         │
│  • SET/GET is O(1) — the fastest operation in Redis     │
│  • Use EX for auto-expiring cache entries               │
│  • Use NX for locks and idempotent writes               │
│  • INCR/DECR are atomic — no race conditions            │
│  • MGET/MSET reduce network round trips                 │
│  • Store JSON for complex objects, Hashes for flat ones  │
│                                                         │
│  EXERCISES:                                             │
│  1. Build a page-view counter that resets daily          │
│  2. Implement a simple feature flag system               │
│  3. Cache an API response with 60s TTL                   │
└─────────────────────────────────────────────────────────┘
""")


if __name__ == "__main__":
    main()