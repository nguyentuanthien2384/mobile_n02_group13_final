const express = require('express');
const { getFirestore, getFieldValue } = require('../config/firebase');
const router = express.Router();

// ─── GET /api/notifications ─────────────────────────────────
router.get('/', async (req, res) => {
  try {
    const db = getFirestore();
    const uid = req.user.uid;
    const limit = Math.min(parseInt(req.query.limit, 10) || 30, 50);
    const snap = await db.collection('users').doc(uid).collection('notifications')
      .orderBy('createdAt', 'desc').limit(limit).get();
    const notifications = snap.docs.map((d) => ({ id: d.id, ...d.data() }));
    res.json({ notifications });
  } catch (err) {
    console.error('[Notifications] list error:', err);
    res.status(500).json({ error: 'Không thể lấy thông báo' });
  }
});

// ─── GET /api/notifications/unread-count ────────────────────
router.get('/unread-count', async (req, res) => {
  try {
    const db = getFirestore();
    const uid = req.user.uid;
    const profile = await db.collection('users').doc(uid).get();
    let count = profile.exists ? (profile.data().unreadNotifications || 0) : 0;
    if (count < 0) count = 0;
    res.json({ count });
  } catch (err) {
    console.error('[Notifications] unread count error:', err);
    res.status(500).json({ error: 'Không thể đếm thông báo' });
  }
});

// ─── POST /api/notifications/:id/read ───────────────────────
router.post('/:id/read', async (req, res) => {
  try {
    const db = getFirestore();
    const uid = req.user.uid;
    const ref = db.collection('users').doc(uid).collection('notifications').doc(req.params.id);
    const doc = await ref.get();
    if (!doc.exists) return res.status(404).json({ error: 'Không tìm thấy thông báo' });
    if (!doc.data().read) {
      await ref.update({ read: true });
      await db.collection('users').doc(uid).set(
        { unreadNotifications: getFieldValue().increment(-1) }, { merge: true }
      );
    }
    res.json({ message: 'Đã đánh dấu đã đọc' });
  } catch (err) {
    console.error('[Notifications] read error:', err);
    res.status(500).json({ error: 'Không thể cập nhật thông báo' });
  }
});

// ─── POST /api/notifications/read-all ───────────────────────
router.post('/read-all', async (req, res) => {
  try {
    const db = getFirestore();
    const uid = req.user.uid;
    const snap = await db.collection('users').doc(uid).collection('notifications')
      .where('read', '==', false).get();
    const batch = db.batch();
    snap.docs.forEach((d) => batch.update(d.ref, { read: true }));
    batch.set(db.collection('users').doc(uid), { unreadNotifications: 0 }, { merge: true });
    await batch.commit();
    res.json({ message: 'Đã đánh dấu tất cả là đã đọc', updated: snap.size });
  } catch (err) {
    console.error('[Notifications] read-all error:', err);
    res.status(500).json({ error: 'Không thể cập nhật thông báo' });
  }
});

// ─── DELETE /api/notifications/:id ──────────────────────────
router.delete('/:id', async (req, res) => {
  try {
    const db = getFirestore();
    const uid = req.user.uid;
    const ref = db.collection('users').doc(uid).collection('notifications').doc(req.params.id);
    const doc = await ref.get();
    if (doc.exists && !doc.data().read) {
      await db.collection('users').doc(uid).set(
        { unreadNotifications: getFieldValue().increment(-1) }, { merge: true }
      );
    }
    await ref.delete();
    res.json({ message: 'Đã xóa thông báo' });
  } catch (err) {
    console.error('[Notifications] delete error:', err);
    res.status(500).json({ error: 'Không thể xóa thông báo' });
  }
});

module.exports = router;
