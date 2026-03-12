"""
connection_helper.py — Shared Redis Connection Utility
=====================================================

This module provides a single function to create a Redis connection
that all demo scripts import. Change the host/port/db here once,
and every script picks it up.
"""

import redis

def get_redis(host="localhost", port=6379, db=0, decode_responses=True):
    """
    Create and return a Redis client.

    Parameters:
    -----------
    host : str
        Redis server hostname. Default is localhost.
    port : int
        Redis server port. Default is 6379.
    db : int
        Redis database number (0-15). Each is an isolated namespace.
        Using db=0 for all demos. In production, you might use different
        DBs for different concerns (caching in db=0, sessions in db=1, etc.)
    decode_responses : bool
        When True, Redis returns Python strings instead of raw bytes.
        Almost always what you want for application code.

    Returns:
    --------
    redis.Redis client instance
    """

    client = redis.Redis(
        host=host,
        port=port,
        db=db,
        decode_responses=decode_responses,
        # Production settings we'd add:
        # socket_timeout=5,          # Timeout for socket operations (seconds)
        # socket_connect_timeout=5,  # Timeout for initial connection
        # retry_on_timeout=True,     # Auto-retry on timeout
        # health_check_interval=30,  # Periodic health check
    )

    client.ping()
    return client

def cleanup(client, prefix):
    """
    Delete all keys matching a prefix. Used by demo scripts to clean up.
    NEVER use KEYS in production — use SCAN instead (shown in 01_basics/03).
    For demos, KEYS on a small dataset is fine.
    """
    keys = client.keys(f"{prefix}*")
    if keys:
        client.delete(*keys)