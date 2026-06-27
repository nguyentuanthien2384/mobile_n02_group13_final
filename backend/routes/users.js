const express = require('express');
const { getFirestore, getAuth } = require('../config/firebase');
const router = express.Router();

// ─── GET /api/users/profile ─────────────────────────────────
router.get('/profile', async (req, res) => {
  try {
    const db = getFirestore();
    const uid = req.user.uid;

    // Get or create user profile doc
    const profileRef = db.collection('users').doc(uid);
    const profileDoc = await profileRef.get();

    if (!profileDoc.exists) {
      // Create profile on first access
      const profile = {
        uid,
        email: req.user.email || '',
        displayName: req.user.name || '',
        photoURL: req.user.picture || '',
        bio: '',
        createdAt: new Date().toISOString(),
        settings: {
          language: 'vi',
          defaultView: 'list',
          fontSize: 'medium',
          sortMode: 'editedDesc',
          notificationsEnabled: true,
        },
      };
      await profileRef.set(profile, { merge: true });
      return res.json(profile);
    }

    res.json({ uid, ...profileDoc.data() });
  } catch (err) {
    console.error('[Users] GET profile error:', err);
    res.status(500).json({ error: 'Không thể lấy thông tin hồ sơ' });
  }
});

// ─── PUT /api/users/profile ─────────────────────────────────
router.put('/profile', async (req, res) => {
  try {
    const db = getFirestore();
    const uid = req.user.uid;
    const { displayName, bio, settings } = req.body;
    const updates = {};
    if (displayName !== undefined) updates.displayName = displayName;
    if (bio !== undefined) updates.bio = bio;
    if (settings !== undefined) updates.settings = settings;

    // Also update Firebase Auth display name
    if (displayName !== undefined) {
      try {
        await getAuth().updateUser(uid, { displayName });
      } catch (e) {
        console.warn('[Users] Could not update Auth displayName:', e.message);
      }
    }

    const profileRef = db.collection('users').doc(uid);
    await profileRef.set(updates, { merge: true });
    const doc = await profileRef.get();
    res.json({ uid, ...doc.data() });
  } catch (err) {
    console.error('[Users] PUT profile error:', err);
    res.status(500).json({ error: 'Không thể cập nhật hồ sơ' });
  }
});

// ─── GET /api/users/search?email=xxx ────────────────────────
router.get('/search', async (req, res) => {
  try {
    const { email } = req.query;
    if (!email) {
      return res.status(400).json({ error: 'Cần email để tìm kiếm' });
    }
    let user;
    try {
      user = await getAuth().getUserByEmail(email);
    } catch {
      return res.status(404).json({ error: 'Không tìm thấy người dùng' });
    }
    res.json({
      uid: user.uid,
      email: user.email,
      displayName: user.displayName || user.email,
      photoURL: user.photoURL || '',
    });
  } catch (err) {
    console.error('[Users] Search error:', err);
    res.status(500).json({ error: 'Lỗi tìm kiếm người dùng' });
  }
});

// ─── GET /api/users/stats ───────────────────────────────────
router.get('/stats', async (req, res) => {
  try {
    const db = getFirestore();
    const uid = req.user.uid;
    const snap = await db.collection('users').doc(uid).collection('notes').get();
    const notes = snap.docs.map((d) => d.data());

    const active = notes.filter((n) => !n.deleted && !n.archived);
    const wordCount = active.reduce((sum, n) => {
      let text = n.content || '';
      try {
        const parsed = JSON.parse(text);
        if (Array.isArray(parsed)) text = parsed.map((o) => (typeof o.insert === 'string' ? o.insert : '')).join('');
      } catch (_) {}
      return sum + text.split(/\s+/).filter(Boolean).length;
    }, 0);

    const profile = (await db.collection('users').doc(uid).get()).data() || {};

    res.json({
      totalNotes: active.length,
      pinned: active.filter((n) => n.pinned).length,
      favorites: active.filter((n) => n.isFavorite).length,
      published: notes.filter((n) => n.isPublished).length,
      archived: notes.filter((n) => n.archived && !n.deleted).length,
      trashed: notes.filter((n) => n.deleted).length,
      checklists: active.filter((n) => n.isChecklist).length,
      withReminder: active.filter((n) => n.reminderAt).length,
      totalLikes: notes.reduce((s, n) => s + (n.likesCount || 0), 0),
      totalComments: notes.reduce((s, n) => s + (n.commentsCount || 0), 0),
      wordCount,
      followersCount: profile.followersCount || 0,
      followingCount: profile.followingCount || 0,
    });
  } catch (err) {
    console.error('[Users] stats error:', err);
    res.status(500).json({ error: 'Không thể lấy thống kê' });
  }
});

module.exports = router;
