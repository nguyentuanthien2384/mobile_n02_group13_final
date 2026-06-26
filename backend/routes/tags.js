const express = require('express');
const { getFirestore } = require('../config/firebase');
const router = express.Router();

// ─── GET /api/tags ──────────────────────────────────────────
router.get('/', async (req, res) => {
  try {
    const db = getFirestore();
    const uid = req.user.uid;
    const snap = await db.collection('users').doc(uid).collection('tags').get();
    const tags = snap.docs.map(doc => ({ id: doc.id, ...doc.data() }));
    res.json({ tags });
  } catch (err) {
    console.error('[Tags] GET error:', err);
    res.status(500).json({ error: 'Không thể lấy danh sách nhãn' });
  }
});

// ─── POST /api/tags ─────────────────────────────────────────
router.post('/', async (req, res) => {
  try {
    const db = getFirestore();
    const uid = req.user.uid;
    const { name } = req.body;
    if (!name || !name.trim()) {
      return res.status(400).json({ error: 'Tên nhãn không được trống' });
    }
    const payload = {
      name: name.trim(),
      createdAt: new Date().toISOString(),
    };
    const ref = await db.collection('users').doc(uid).collection('tags').add(payload);
    res.status(201).json({ id: ref.id, ...payload });
  } catch (err) {
    console.error('[Tags] POST error:', err);
    res.status(500).json({ error: 'Không thể tạo nhãn' });
  }
});

// ─── PUT /api/tags/:id ──────────────────────────────────────
router.put('/:id', async (req, res) => {
  try {
    const db = getFirestore();
    const uid = req.user.uid;
    const { name } = req.body;
    if (!name || !name.trim()) {
      return res.status(400).json({ error: 'Tên nhãn không được trống' });
    }
    const ref = db.collection('users').doc(uid).collection('tags').doc(req.params.id);
    await ref.update({ name: name.trim() });
    res.json({ id: req.params.id, name: name.trim() });
  } catch (err) {
    console.error('[Tags] PUT error:', err);
    res.status(500).json({ error: 'Không thể cập nhật nhãn' });
  }
});

// ─── DELETE /api/tags/:id ───────────────────────────────────
router.delete('/:id', async (req, res) => {
  try {
    const db = getFirestore();
    const uid = req.user.uid;
    await db.collection('users').doc(uid).collection('tags').doc(req.params.id).delete();
    res.json({ message: 'Đã xóa nhãn' });
  } catch (err) {
    console.error('[Tags] DELETE error:', err);
    res.status(500).json({ error: 'Không thể xóa nhãn' });
  }
});

module.exports = router;
