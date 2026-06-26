const express = require('express');
const { getFirestore } = require('../config/firebase');
const router = express.Router();

// ─── GET /api/folders ───────────────────────────────────────
router.get('/', async (req, res) => {
  try {
    const db = getFirestore();
    const uid = req.user.uid;
    const snap = await db.collection('users').doc(uid).collection('folders').orderBy('createdAt', 'desc').get();
    const folders = snap.docs.map(doc => ({ id: doc.id, ...doc.data() }));
    res.json({ folders });
  } catch (err) {
    console.error('[Folders] GET error:', err);
    res.status(500).json({ error: 'Không thể lấy danh sách thư mục' });
  }
});

// ─── POST /api/folders ──────────────────────────────────────
router.post('/', async (req, res) => {
  try {
    const db = getFirestore();
    const uid = req.user.uid;
    const { name, color, icon } = req.body;
    if (!name || !name.trim()) {
      return res.status(400).json({ error: 'Tên thư mục không được trống' });
    }
    const payload = {
      name: name.trim(),
      color: color || 0xFF2196F3,
      icon: icon || 'folder',
      createdAt: new Date().toISOString(),
    };
    const ref = await db.collection('users').doc(uid).collection('folders').add(payload);
    res.status(201).json({ id: ref.id, ...payload });
  } catch (err) {
    console.error('[Folders] POST error:', err);
    res.status(500).json({ error: 'Không thể tạo thư mục' });
  }
});

// ─── PUT /api/folders/:id ───────────────────────────────────
router.put('/:id', async (req, res) => {
  try {
    const db = getFirestore();
    const uid = req.user.uid;
    const updates = {};
    if (req.body.name !== undefined) updates.name = req.body.name.trim();
    if (req.body.color !== undefined) updates.color = req.body.color;
    if (req.body.icon !== undefined) updates.icon = req.body.icon;
    const ref = db.collection('users').doc(uid).collection('folders').doc(req.params.id);
    await ref.update(updates);
    const doc = await ref.get();
    res.json({ id: doc.id, ...doc.data() });
  } catch (err) {
    console.error('[Folders] PUT error:', err);
    res.status(500).json({ error: 'Không thể cập nhật thư mục' });
  }
});

// ─── DELETE /api/folders/:id ────────────────────────────────
router.delete('/:id', async (req, res) => {
  try {
    const db = getFirestore();
    const uid = req.user.uid;
    // Remove folder reference from all notes in this folder
    const notesSnap = await db.collection('users').doc(uid).collection('notes')
      .where('folderId', '==', req.params.id).get();
    const batch = db.batch();
    notesSnap.docs.forEach(doc => {
      batch.update(doc.ref, { folderId: null });
    });
    batch.delete(db.collection('users').doc(uid).collection('folders').doc(req.params.id));
    await batch.commit();
    res.json({ message: 'Đã xóa thư mục' });
  } catch (err) {
    console.error('[Folders] DELETE error:', err);
    res.status(500).json({ error: 'Không thể xóa thư mục' });
  }
});

module.exports = router;
