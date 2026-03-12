# Redis Mastery — A Complete Feature-by-Feature Learning Project (Python)

## What is Redis?

Redis (**RE**mote **DI**ctionary **S**erver) is an **in-memory data structure store** that can
serve as a database, cache, message broker, and streaming engine. Unlike traditional databases
that read/write from disk, Redis keeps **all data in RAM**, making it extraordinarily fast
(typically **< 1ms** latency for reads/writes).

### Why Redis Matters in Production

| Use Case               | Why Redis Excels                                      |
|------------------------|-------------------------------------------------------|
| **Caching**            | Sub-millisecond reads — 100x faster than a DB query   |
| **Session Storage**    | Fast, expirable key-value pairs per user session       |
| **Rate Limiting**      | Atomic counters with TTL — perfect for API throttling  |
| **Leaderboards**       | Sorted Sets give O(log N) ranked inserts & queries     |
| **Real-time Messaging**| Pub/Sub and Streams for event-driven architectures     |
| **Distributed Locks**  | Atomic SET NX for cross-service coordination           |
| **Job/Task Queues**    | Lists with blocking pops = simple, reliable queues     |
| **Geospatial Queries** | Built-in geo indexing for "nearby" searches            |

---

## Project Structure

```
redis-mastery/
│
├── README.md                          ← You are here
├── requirements.txt                   ← Python dependencies
├── connection_helper.py               ← Shared Redis connection utility
│
├── 01_basics/
│   ├── 01_connection.py               ← Connecting to Redis
│   ├── 02_strings.py                  ← Strings: the foundation of Redis
│   └── 03_key_management.py           ← Key expiration, TTL, scanning
│
├── 02_data_structures/
│   ├── 01_lists.py                    ← Lists: queues, stacks, feeds
│   ├── 02_sets.py                     ← Sets: unique collections, tagging
│   ├── 03_sorted_sets.py              ← Sorted Sets: leaderboards, rankings
│   ├── 04_hashes.py                   ← Hashes: object-like storage
│   ├── 05_bitmaps.py                  ← Bitmaps: memory-efficient flags
│   ├── 06_hyperloglogs.py             ← HyperLogLog: approximate counting
│   └── 07_geospatial.py              ← Geo: location-based queries
│
├── 03_advanced_features/
│   ├── 01_pipelining.py               ← Pipelining: batch for performance
│   ├── 02_transactions.py             ← Transactions: MULTI/EXEC/WATCH
│   ├── 03_lua_scripting.py            ← Lua: atomic server-side scripts
│   ├── 04_pubsub.py                   ← Pub/Sub: real-time messaging
│   └── 05_streams.py                  ← Streams: durable event logs
│
└── 04_production_patterns/
    ├── 01_caching.py                  ← Cache-aside & write-through patterns
    ├── 02_rate_limiter.py             ← Token bucket / sliding window
    ├── 03_distributed_lock.py         ← Distributed locking (Redlock idea)
    ├── 04_session_store.py            ← Web session management
    ├── 05_job_queue.py                ← Reliable job/task queue (from scratch)
    └── 06_arq_task_queue.py           ← ARQ: async task queue library (complete guide)
```

## Setup

```bash
pip install redis
```

Then run any script:
```bash
python 01_basics/01_connection.py
```

Each script is **fully self-contained** — run them in any order, though the numbering
follows a logical learning path from basics → data structures → advanced → production.
Every script **cleans up after itself** so you won't pollute your Redis instance.

---

## How to Get the Most Out of This Project

1. **Read each script top-to-bottom** — every section has detailed comments explaining
   *what*, *why*, and *when to use it in production*.
2. **Run it** — watch the output, then tweak values and re-run.
3. **Open `redis-cli monitor`** in a separate terminal to see every command Redis receives
   in real time as you run scripts.
4. **Experiment** — each script ends with suggested exercises.