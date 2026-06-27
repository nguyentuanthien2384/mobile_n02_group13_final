const express = require('express');
const { getFirestore, getFieldValue } = require('../config/firebase');
const { ensureUserProfile, createNotification } = require('../utils/social');
const rateLimit = require('../middleware/rateLimit');
const router = express.Router();

const PAGE = (req, def = 20, cap = 50) =>
  Math.min(parseInt(req.query.limit, 10) || def, cap);

function publicProfile(uid, data, extra = {}) {
  return {
    uid,
    displayName: data.displayName || 'User',
    photoURL: data.photoURL || '',
    bio: data.bio || '',
    followersCount: data.followersCount || 0,
    followingCount: data.followingCount || 0,
    publishedCount: data.publishedCount || 0,
    createdAt: data.createdAt || null,
    ...extra,
  };
}

// ─── POST /api/social/follow/:uid ───────────────────────────
router.post('/follow/:uid', rateLimit({ key: 'follow', max: 60 }), async (req, res) => {
  try {
    const db = getFirestore();
    const me = req.user.uid;
    const target = req.params.uid;
    if (target === me) return res.status(400).json({ error: 'Không thể tự theo dõi chính mình' });

    const targetSnap = await db.collection('users').doc(target).get();
    if (!targetSnap.exists) return res.status(404).json({ error: 'Không tìm thấy người dùng' });
    const targetData = targetSnap.data();

    const followingRef = db.collection('users').doc(me).collection('following').doc(target);
    if ((await followingRef.get()).exists) {
      return res.json({ message: 'Đã theo dõi từ trước', following: true });
    }

    await ensureUserProfile(req.user);
    const meSnap = await db.collection('users').doc(me).get();
    const meData = meSnap.data() || {};

    await followingRef.set({
      uid: target,
      displayName: targetData.displayName || '',
      photoURL: targetData.photoURL || '',
      createdAt: new Date().toISOString(),
    });
    await db.collection('users').doc(target).collection('followers').doc(me).set({
      uid: me,
      displayName: meData.displayName || req.user.name || '',
      photoURL: meData.photoURL || req.user.picture || '',
      createdAt: new Date().toISOString(),
    });

    const inc = getFieldValue().increment(1);
    await db.collection('users').doc(me).set({ followingCount: inc }, { merge: true });
    await db.collection('users').doc(target).set({ followersCount: inc }, { merge: true });

    await createNotification({ recipientUid: target, type: 'follow', actor: req.user });

    res.json({ message: 'Đã theo dõi', following: true });
  } catch (err) {
    console.error('[Social] follow error:', err);
    res.status(500).json({ error: 'Không thể theo dõi người dùng' });
  }
});

// ─── DELETE /api/social/follow/:uid ─────────────────────────
router.delete('/follow/:uid', async (req, res) => {
  try {
    const db = getFirestore();
    const me = req.user.uid;
    const target = req.params.uid;

    const followingRef = db.collection('users').doc(me).collection('following').doc(target);
    if (!(await followingRef.get()).exists) {
      return res.json({ message: 'Chưa theo dõi', following: false });
    }
    await followingRef.delete();
    await db.collection('users').doc(target).collection('followers').doc(me).delete();

    const dec = getFieldValue().increment(-1);
    await db.collection('users').doc(me).set({ followingCount: dec }, { merge: true });
    await db.collection('users').doc(target).set({ followersCount: dec }, { merge: true });

    res.json({ message: 'Đã bỏ theo dõi', following: false });
  } catch (err) {
    console.error('[Social] unfollow error:', err);
    res.status(500).json({ error: 'Không thể bỏ theo dõi' });
  }
});

// ─── GET /api/social/following ──────────────────────────────
router.get('/following', async (req, res) => {
  try {
    const db = getFirestore();
    const uid = req.query.uid || req.user.uid;
    const snap = await db.collection('users').doc(uid).collection('following')
      .orderBy('createdAt', 'desc').get();
    res.json({ users: snap.docs.map((d) => ({ id: d.id, ...d.data() })) });
  } catch (err) {
    console.error('[Social] following error:', err);
    res.status(500).json({ error: 'Không thể lấy danh sách đang theo dõi' });
  }
});

// ─── GET /api/social/followers ──────────────────────────────
router.get('/followers', async (req, res) => {
  try {
    const db = getFirestore();
    const uid = req.query.uid || req.user.uid;
    const snap = await db.collection('users').doc(uid).collection('followers')
      .orderBy('createdAt', 'desc').get();
    res.json({ users: snap.docs.map((d) => ({ id: d.id, ...d.data() })) });
  } catch (err) {
    console.error('[Social] followers error:', err);
    res.status(500).json({ error: 'Không thể lấy danh sách người theo dõi' });
  }
});

// ─── GET /api/social/users/search?q= ────────────────────────
router.get('/users/search', async (req, res) => {
  try {
    const db = getFirestore();
    const q = (req.query.q || '').trim().toLowerCase();
    if (q.length < 2) return res.json({ users: [] });

    const all = await db.collection('users').get();
    const results = [];
    for (const doc of all.docs) {
      const d = doc.data();
      if (doc.id === req.user.uid) continue;
      const nameL = (d.displayNameLower || (d.displayName || '').toLowerCase());
      const emailL = (d.emailLower || (d.email || '').toLowerCase());
      if (nameL.includes(q) || emailL.includes(q)) {
        results.push(publicProfile(doc.id, d));
      }
      if (results.length >= 30) break;
    }
    res.json({ users: results });
  } catch (err) {
    console.error('[Social] user search error:', err);
    res.status(500).json({ error: 'Lỗi tìm kiếm người dùng' });
  }
});

// ─── GET /api/social/suggestions ────────────────────────────
router.get('/suggestions', async (req, res) => {
  try {
    const db = getFirestore();
    const me = req.user.uid;
    const followingSnap = await db.collection('users').doc(me).collection('following').get();
    const followingIds = new Set(followingSnap.docs.map((d) => d.id));
    followingIds.add(me);

    const all = await db.collection('users').orderBy('followersCount', 'desc').limit(40).get();
    const out = [];
    for (const doc of all.docs) {
      if (followingIds.has(doc.id)) continue;
      out.push(publicProfile(doc.id, doc.data()));
      if (out.length >= PAGE(req, 10, 20)) break;
    }
    res.json({ users: out });
  } catch (err) {
    console.error('[Social] suggestions error:', err);
    res.status(500).json({ error: 'Không thể lấy gợi ý' });
  }
});

// ─── GET /api/social/profile/:uid ───────────────────────────
router.get('/profile/:uid', async (req, res) => {
  try {
    const db = getFirestore();
    const me = req.user.uid;
    const target = req.params.uid;

    const snap = await db.collection('users').doc(target).get();
    if (!snap.exists) return res.status(404).json({ error: 'Không tìm thấy người dùng' });

    const isFollowing = (await db.collection('users').doc(me)
      .collection('following').doc(target).get()).exists;
    const followsMe = (await db.collection('users').doc(target)
      .collection('following').doc(me).get()).exists;

    // Their published notes (from the denormalized feed collection).
    const feedSnap = await db.collection('feed')
      .where('authorUid', '==', target)
      .orderBy('publishedAt', 'desc')
      .limit(PAGE(req, 20))
      .get();
    const posts = feedSnap.docs.map((d) => ({ id: d.id, ...d.data() }));

    res.json({
      profile: publicProfile(target, snap.data(), {
        isFollowing,
        followsMe,
        isMe: me === target,
      }),
      posts,
    });
  } catch (err) {
    console.error('[Social] profile error:', err);
    res.status(500).json({ error: 'Không thể lấy hồ sơ' });
  }
});

// ─── GET /api/social/explore ────────────────────────────────
// Most recent published notes from everyone.
router.get('/explore', async (req, res) => {
  try {
    const db = getFirestore();
    const limit = PAGE(req, 20);
    let query = db.collection('feed').orderBy('publishedAt', 'desc');
    const snap = await query.limit(limit + (req.query.after ? 1 : 0) + 50).get();

    let docs = snap.docs;
    if (req.query.after) {
      const idx = docs.findIndex((d) => d.id === req.query.after);
      if (idx >= 0) docs = docs.slice(idx + 1);
    }
    docs = docs.slice(0, limit);

    const posts = await decoratePosts(db, req.user.uid, docs);
    res.json({ posts, nextCursor: posts.length === limit ? posts[posts.length - 1].id : null });
  } catch (err) {
    console.error('[Social] explore error:', err);
    res.status(500).json({ error: 'Không thể tải khám phá' });
  }
});

// ─── GET /api/social/trending ───────────────────────────────
router.get('/trending', async (req, res) => {
  try {
    const db = getFirestore();
    const limit = PAGE(req, 20);
    const snap = await db.collection('feed').orderBy('likesCount', 'desc').limit(limit).get();
    const posts = await decoratePosts(db, req.user.uid, snap.docs);
    res.json({ posts });
  } catch (err) {
    console.error('[Social] trending error:', err);
    res.status(500).json({ error: 'Không thể tải xu hướng' });
  }
});

// ─── GET /api/social/feed ───────────────────────────────────
// Published notes from people the current user follows.
router.get('/feed', async (req, res) => {
  try {
    const db = getFirestore();
    const me = req.user.uid;
    const limit = PAGE(req, 20);

    const followingSnap = await db.collection('users').doc(me).collection('following').get();
    const ids = followingSnap.docs.map((d) => d.id);
    if (ids.length === 0) return res.json({ posts: [], empty: true });

    let docs = [];
    if (ids.length <= 10) {
      const snap = await db.collection('feed')
        .where('authorUid', 'in', ids)
        .orderBy('publishedAt', 'desc')
        .limit(limit)
        .get();
      docs = snap.docs;
    } else {
      // Fall back to scanning recent feed and filtering by following set.
      const idSet = new Set(ids);
      const snap = await db.collection('feed').orderBy('publishedAt', 'desc').limit(200).get();
      docs = snap.docs.filter((d) => idSet.has(d.data().authorUid)).slice(0, limit);
    }

    const posts = await decoratePosts(db, me, docs);
    res.json({ posts });
  } catch (err) {
    console.error('[Social] feed error:', err);
    res.status(500).json({ error: 'Không thể tải bảng tin' });
  }
});

/** Attach `liked` / `bookmarked` flags for the current viewer to feed docs. */
async function decoratePosts(db, uid, docs) {
  const out = [];
  for (const doc of docs) {
    const data = doc.data();
    const liked = (await db.collection('feed').doc(doc.id)
      .collection('likes').doc(uid).get()).exists;
    const bookmarked = (await db.collection('users').doc(uid)
      .collection('bookmarks').doc(doc.id).get()).exists;
    out.push({ id: doc.id, ...data, liked, bookmarked });
  }
  return out;
}

module.exports = router;
