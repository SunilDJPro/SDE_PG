"""
01_connection.py — Connecting to Redis
======================================

WHAT THIS COVERS:
  - Creating a basic Redis connection
  - Connection pooling (critical for production)
  - Checking server info and health
  - Understanding the Redis threading model

WHY IT MATTERS:
  In production, your app might have hundreds of concurrent requests.
  Each one needs a Redis connection. Creating a new TCP connection per
  request is slow and wasteful. Connection pools solve this by keeping
  a set of reusable connections ready to go.
"""

import sys, os

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

import redis
from connection_helper import get_redis

def main():
    print("REDIS CONNECTION DEMO")

    # ──────────────────────────────────────────────────────────
    # 1. BASIC CONNECTION
    # ──────────────────────────────────────────────────────────
    # The simplest way to connect. Behind the scenes, the redis-py
    # library automatically creates a connection pool for you.
    print("\n--- 1. Basic Connection ---")

    r = get_redis()
    print(f"Connected! PING -> {r.ping()}") # True means we're connected

    # ──────────────────────────────────────────────────────────
    # 2. CONNECTION POOLING (Production Essential)
    # ──────────────────────────────────────────────────────────
    # A connection pool maintains a fixed number of TCP connections
    # to Redis. When your code calls r.get("key"), the library:
    #   1. Borrows a connection from the pool
    #   2. Sends the command
    #   3. Returns the connection to the pool
    #
    # This avoids the overhead of TCP handshake on every command.
    print("\n--- 2. Connection Pooling ---")

    pool = redis.ConnectionPool(
        host = "localhost",
        port = 6379,
        db = 0,
        decode_responses = True,
        max_connections = 20, # Max simultaneous connections
        # In production, set this based on your concurrency needs.
        # Too low → commands queue up waiting for a connection.
        # Too high → you waste server file descriptors.
        # Rule of thumb: match your app's max concurrent Redis users.
    )

    # Multiple clients can share the same pool
    client_a = redis.Redis(connection_pool=pool)
    client_b = redis.Redis(connection_pool=pool)

    client_a.set("pool_test", "hello from A")
    result = client_b.get("pool_test")

    print(f"Client A wrote, Client B read: '{result}'")
    print(f"Both share the same pool: {client_a.connection_pool is client_b.connection_pool}")

    # Cleanup
    client_a.delete("pool_test")

    # ──────────────────────────────────────────────────────────
    # 3. SERVER INFO
    # ──────────────────────────────────────────────────────────
    # The INFO command gives you a goldmine of operational data.
    # In production, you'd monitor these metrics with tools like
    # Grafana, Datadog, or Prometheus.
    print("\n--- 3. Server Info ---")

    info = r.info()

    print(f"  Redis version:        {info['redis_version']}")
    print(f"  OS:                   {info.get('os', 'N/A')}")
    print(f"  Connected clients:    {info['connected_clients']}")
    print(f"  Used memory (human):  {info['used_memory_human']}")
    print(f"  Total commands:       {info['total_commands_processed']}")
    print(f"  Uptime (seconds):     {info['uptime_in_seconds']}")
    print(f"  Keyspace hits:        {info.get('keyspace_hits', 0)}")
    print(f"  Keyspace misses:      {info.get('keyspace_misses', 0)}")

    # Hit rate = hits / (hits + misses). Aim for > 90% in caching.
    hits = info.get("keyspace_hits", 0)
    misses = info.get("keyspace_misses", 0)
    if hits + misses > 0:
        hit_rate = hits / (hits + misses) * 100
        print(f" Cache hit rate:    {hit_rate:.1f}%")

    
    # ──────────────────────────────────────────────────────────
    # 4. DATABASE SELECTION
    # ──────────────────────────────────────────────────────────
    # Redis has 16 databases by default (0-15). They share the
    # same server process and memory but are logically isolated.
    # Think of them as lightweight namespaces.
    #
    # PRODUCTION NOTE: Most teams use db=0 only and separate
    # concerns via key prefixes (e.g., "cache:", "session:").
    # Redis Cluster does NOT support multiple databases.
    print("\n--- 4. Database Selection ---")

    r0 = redis.Redis(host="localhost", post=6379, db=0, decode_responses=True)
    r1 = redis.Redis(host="localhost", port=6379, db=1, decode_responses=True)

    r0.set("db_test", "I'm in DB 0")
    r1.set("db_test", "I'm in DB 1")

    print(f" DB 0: {r0.get('db_test')}")
    print(f" DB 1: {r1.get('db_test')}")
    print(" Same key name, but completely isolated data!")

    # ──────────────────────────────────────────────────────────
    # 5. CONNECTION FROM URL (Common in Deployments)
    # ──────────────────────────────────────────────────────────
    # Cloud providers (Heroku, AWS ElastiCache, Railway, etc.)
    # give you a Redis URL like: redis://:password@hostname:port/db
    print("\n--- 5. Connection from URL ---")

    url_client = redis.from_url(
        "redis://localhost:6379/0",
        decode_responses=True
    )

    print(f"  URL-based connection PING -> {url_client.ping()}")

    print("\n All Connection demos complete!")

    print("""
┌─────────────────────────────────────────────────────────┐
│  KEY TAKEAWAYS:                                         │
│                                                         │
│  • Always use connection pooling in production           │
│  • Monitor INFO stats (memory, hit rate, clients)       │
│  • Use decode_responses=True for string data            │
│  • Prefer key prefixes over multiple databases          │
│  • Set socket_timeout to avoid hanging connections       │
└─────────────────────────────────────────────────────────┘
""")