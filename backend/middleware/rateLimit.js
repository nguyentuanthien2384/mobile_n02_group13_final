/**
 * Minimal in-memory sliding-window rate limiter (per user + route key).
 * No external dependency. For multi-instance deployments swap for Redis, but
 * for a single Node process this protects against abuse of write endpoints.
 */
const buckets = new Map();

function rateLimit({ windowMs = 60_000, max = 60, key = 'global' } = {}) {
  return (req, res, next) => {
    const id = (req.user && req.user.uid) || req.ip || 'anon';
    const bucketKey = `${key}:${id}`;
    const now = Date.now();
    let hits = buckets.get(bucketKey) || [];
    hits = hits.filter((t) => now - t < windowMs);
    if (hits.length >= max) {
      const retryAfter = Math.ceil((windowMs - (now - hits[0])) / 1000);
      res.set('Retry-After', String(retryAfter));
      return res.status(429).json({
        error: 'Bạn thao tác quá nhanh, vui lòng thử lại sau giây lát',
        retryAfter,
      });
    }
    hits.push(now);
    buckets.set(bucketKey, hits);
    next();
  };
}

// Periodic cleanup so the map doesn't grow unbounded.
setInterval(() => {
  const now = Date.now();
  for (const [k, hits] of buckets.entries()) {
    const fresh = hits.filter((t) => now - t < 300_000);
    if (fresh.length === 0) buckets.delete(k);
    else buckets.set(k, fresh);
  }
}, 300_000).unref();

module.exports = rateLimit;
