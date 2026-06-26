const express = require('express');
const { getFirestore } = require('../config/firebase');
const router = express.Router();

// ─── GET /api/notes ─────────────────────────────────────────
router.get('/', async (req, res) => {
  try {
    const db = getFirestore();
    const uid = req.user.uid;
    const snap = await db.collection('users').doc(uid).collection('notes').get();
    const notes = snap.docs.map(doc => ({ id: doc.id, ...doc.data() }));
    res.json({ notes });
  } catch (err) {
    console.error('[Notes] GET error:', err);
    res.status(500).json({ error: 'Không thể lấy danh sách ghi chú' });
  }
});

// ─── GET /api/notes/shared ──────────────────────────────────
router.get('/shared', async (req, res) => {
  try {
    const db = getFirestore();
    const uid = req.user.uid;
    // Find notes shared with this user
    const snap = await db.collectionGroup('shares')
      .where('sharedWith', '==', uid)
      .get();

    const notes = [];
    for (const shareDoc of snap.docs) {
      const shareData = shareDoc.data();
      const noteRef = shareDoc.ref.parent.parent;
      const noteDoc = await noteRef.get();
      if (noteDoc.exists) {
        const ownerUid = noteRef.parent.parent.id;
        notes.push({
          id: noteDoc.id,
          ...noteDoc.data(),
          sharePermission: shareData.permission,
          ownerUid,
          ownerName: shareData.ownerName || '',
          ownerPhoto: shareData.ownerPhoto || '',
        });
      }
    }
    res.json({ notes });
  } catch (err) {
    console.error('[Notes] GET shared error:', err);
    res.status(500).json({ error: 'Không thể lấy ghi chú được chia sẻ' });
  }
});

// ─── GET /api/notes/:id ─────────────────────────────────────
router.get('/:id', async (req, res) => {
  try {
    const db = getFirestore();
    const uid = req.user.uid;
    const doc = await db.collection('users').doc(uid).collection('notes').doc(req.params.id).get();
    if (!doc.exists) {
      return res.status(404).json({ error: 'Không tìm thấy ghi chú' });
    }
    res.json({ id: doc.id, ...doc.data() });
  } catch (err) {
    console.error('[Notes] GET by id error:', err);
    res.status(500).json({ error: 'Không thể lấy ghi chú' });
  }
});

// ─── POST /api/notes ────────────────────────────────────────
router.post('/', async (req, res) => {
  try {
    const db = getFirestore();
    const uid = req.user.uid;
    const { title, content, pinned, isChecklist, tags, color, folderId, isFavorite, localId } = req.body;
    const now = new Date().toISOString();
    const payload = {
      title: title || '',
      content: content || '',
      createdAt: now,
      editedAt: now,
      pinned: pinned || false,
      isChecklist: isChecklist || false,
      tags: tags || [],
      color: color || 0,
      folderId: folderId || null,
      isFavorite: isFavorite || false,
      localId: localId || null,
    };
    const docRef = await db.collection('users').doc(uid).collection('notes').add(payload);
    res.status(201).json({ id: docRef.id, ...payload });
  } catch (err) {
    console.error('[Notes] POST error:', err);
    res.status(500).json({ error: 'Không thể tạo ghi chú' });
  }
});

// ─── PUT /api/notes/:id ─────────────────────────────────────
router.put('/:id', async (req, res) => {
  try {
    const db = getFirestore();
    const uid = req.user.uid;
    const noteRef = db.collection('users').doc(uid).collection('notes').doc(req.params.id);
    const doc = await noteRef.get();
    if (!doc.exists) {
      return res.status(404).json({ error: 'Không tìm thấy ghi chú' });
    }
    const updates = {};
    const allowed = ['title', 'content', 'pinned', 'isChecklist', 'tags', 'color', 'folderId', 'isFavorite', 'localId'];
    for (const key of allowed) {
      if (req.body[key] !== undefined) updates[key] = req.body[key];
    }
    updates.editedAt = new Date().toISOString();
    await noteRef.update(updates);
    res.json({ id: req.params.id, ...doc.data(), ...updates });
  } catch (err) {
    console.error('[Notes] PUT error:', err);
    res.status(500).json({ error: 'Không thể cập nhật ghi chú' });
  }
});

// ─── DELETE /api/notes/:id ──────────────────────────────────
router.delete('/:id', async (req, res) => {
  try {
    const db = getFirestore();
    const uid = req.user.uid;
    const noteRef = db.collection('users').doc(uid).collection('notes').doc(req.params.id);
    const doc = await noteRef.get();
    if (!doc.exists) {
      return res.status(404).json({ error: 'Không tìm thấy ghi chú' });
    }
    // Also delete shares
    const shares = await noteRef.collection('shares').get();
    const batch = db.batch();
    shares.docs.forEach(s => batch.delete(s.ref));
    batch.delete(noteRef);
    await batch.commit();
    res.json({ message: 'Đã xóa ghi chú' });
  } catch (err) {
    console.error('[Notes] DELETE error:', err);
    res.status(500).json({ error: 'Không thể xóa ghi chú' });
  }
});

// ─── POST /api/notes/:id/share ──────────────────────────────
router.post('/:id/share', async (req, res) => {
  try {
    const db = getFirestore();
    const uid = req.user.uid;
    const { email, permission, isPublic } = req.body;
    const noteRef = db.collection('users').doc(uid).collection('notes').doc(req.params.id);
    const noteDoc = await noteRef.get();
    if (!noteDoc.exists) {
      return res.status(404).json({ error: 'Không tìm thấy ghi chú' });
    }

    // Public link sharing
    if (isPublic) {
      const { v4: uuidv4 } = require('uuid');
      const shareToken = uuidv4();
      await noteRef.update({
        publicShareToken: shareToken,
        publicSharePermission: permission || 'view',
      });
      return res.json({
        message: 'Đã tạo link chia sẻ công khai',
        shareToken,
        shareUrl: `${req.protocol}://${req.get('host')}/api/notes/public/${shareToken}`,
      });
    }

    // Share with specific user by email
    if (!email) {
      return res.status(400).json({ error: 'Cần email hoặc chọn chia sẻ công khai' });
    }

    // Find user by email
    const { getAuth } = require('../config/firebase');
    let targetUser;
    try {
      targetUser = await getAuth().getUserByEmail(email);
    } catch {
      return res.status(404).json({ error: 'Không tìm thấy người dùng với email này' });
    }

    if (targetUser.uid === uid) {
      return res.status(400).json({ error: 'Không thể chia sẻ với chính mình' });
    }

    await noteRef.collection('shares').doc(targetUser.uid).set({
      sharedWith: targetUser.uid,
      sharedWithEmail: email,
      sharedWithName: targetUser.displayName || email,
      permission: permission || 'view',
      ownerUid: uid,
      ownerName: req.user.name,
      ownerPhoto: req.user.picture || '',
      sharedAt: new Date().toISOString(),
    });

    res.json({
      message: `Đã chia sẻ với ${email}`,
      sharedWith: { uid: targetUser.uid, email, name: targetUser.displayName },
    });
  } catch (err) {
    console.error('[Notes] Share error:', err);
    res.status(500).json({ error: 'Không thể chia sẻ ghi chú' });
  }
});

// ─── GET /api/notes/public/:token ───────────────────────────
router.get('/public/:token', async (req, res) => {
  try {
    const db = getFirestore();
    const snap = await db.collectionGroup('notes')
      .where('publicShareToken', '==', req.params.token)
      .limit(1)
      .get();

    if (snap.empty) {
      return res.status(404).json({ error: 'Link chia sẻ không hợp lệ hoặc đã hết hạn' });
    }
    const doc = snap.docs[0];
    const data = doc.data();
    // Only return safe fields
    res.json({
      id: doc.id,
      title: data.title,
      content: data.content,
      createdAt: data.createdAt,
      editedAt: data.editedAt,
      permission: data.publicSharePermission || 'view',
    });
  } catch (err) {
    console.error('[Notes] Public share error:', err);
    res.status(500).json({ error: 'Không thể truy cập ghi chú' });
  }
});

// ─── POST /api/notes/:id/comments ───────────────────────────
router.post('/:id/comments', async (req, res) => {
  try {
    const db = getFirestore();
    const uid = req.user.uid;
    const { text, noteOwnerUid } = req.body;
    if (!text || !text.trim()) {
      return res.status(400).json({ error: 'Nội dung bình luận không được trống' });
    }

    // Determine the note owner - could be current user or another user (for shared notes)
    const ownerUid = noteOwnerUid || uid;
    const noteRef = db.collection('users').doc(ownerUid).collection('notes').doc(req.params.id);
    const noteDoc = await noteRef.get();
    if (!noteDoc.exists) {
      return res.status(404).json({ error: 'Không tìm thấy ghi chú' });
    }

    const comment = {
      userId: uid,
      userName: req.user.name,
      userPhoto: req.user.picture || '',
      text: text.trim(),
      createdAt: new Date().toISOString(),
    };
    const ref = await noteRef.collection('comments').add(comment);
    res.status(201).json({ id: ref.id, ...comment });
  } catch (err) {
    console.error('[Notes] Comment error:', err);
    res.status(500).json({ error: 'Không thể thêm bình luận' });
  }
});

// ─── GET /api/notes/:id/comments ────────────────────────────
router.get('/:id/comments', async (req, res) => {
  try {
    const db = getFirestore();
    const uid = req.user.uid;
    const ownerUid = req.query.ownerUid || uid;
    const noteRef = db.collection('users').doc(ownerUid).collection('notes').doc(req.params.id);
    const snap = await noteRef.collection('comments').orderBy('createdAt', 'desc').get();
    const comments = snap.docs.map(d => ({ id: d.id, ...d.data() }));
    res.json({ comments });
  } catch (err) {
    console.error('[Notes] GET comments error:', err);
    res.status(500).json({ error: 'Không thể lấy bình luận' });
  }
});

// ─── DELETE /api/notes/:id/share/:targetUid ─────────────────
router.delete('/:id/share/:targetUid', async (req, res) => {
  try {
    const db = getFirestore();
    const uid = req.user.uid;
    const noteRef = db.collection('users').doc(uid).collection('notes').doc(req.params.id);
    await noteRef.collection('shares').doc(req.params.targetUid).delete();
    res.json({ message: 'Đã hủy chia sẻ' });
  } catch (err) {
    console.error('[Notes] Delete share error:', err);
    res.status(500).json({ error: 'Không thể hủy chia sẻ' });
  }
});

// ─── GET /api/notes/:id/shares ──────────────────────────────
router.get('/:id/shares', async (req, res) => {
  try {
    const db = getFirestore();
    const uid = req.user.uid;
    const noteRef = db.collection('users').doc(uid).collection('notes').doc(req.params.id);
    const snap = await noteRef.collection('shares').get();
    const shares = snap.docs.map(d => ({ id: d.id, ...d.data() }));
    res.json({ shares });
  } catch (err) {
    console.error('[Notes] GET shares error:', err);
    res.status(500).json({ error: 'Không thể lấy danh sách chia sẻ' });
  }
});

module.exports = router;
