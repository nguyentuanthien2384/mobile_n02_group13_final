const express = require('express');
const { getFirestore, getAuth } = require('../config/firebase');
const { createNotification } = require('../utils/social');
const router = express.Router();

const userDoc = (db, uid) => db.collection('users').doc(uid);
const foldersCol = (db, uid) => userDoc(db, uid).collection('folders');
const notesCol = (db, uid) => userDoc(db, uid).collection('notes');

async function resolveUserByEmail(db, email) {
  const normalizedEmail = email.trim().toLowerCase();
  const idx = await db
    .collection('users')
    .where('emailLower', '==', normalizedEmail)
    .limit(1)
    .get();
  if (!idx.empty) {
    const d = idx.docs[0];
    return {
      uid: d.id,
      email,
      displayName: d.data().displayName || email,
    };
  }

  const user = await getAuth().getUserByEmail(email);
  return {
    uid: user.uid,
    email: user.email || email,
    displayName: user.displayName || email,
  };
}

// ─── GET /api/folders ───────────────────────────────────────
router.get('/', async (req, res) => {
  try {
    const db = getFirestore();
    const uid = req.user.uid;
    const snap = await foldersCol(db, uid).orderBy('createdAt', 'desc').get();
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
    const { name, color, icon, localId } = req.body;
    if (!name || !name.trim()) {
      return res.status(400).json({ error: 'Tên thư mục không được trống' });
    }
    const payload = {
      name: name.trim(),
      color: color || 0xFF2196F3,
      icon: icon || 'folder',
      localId: localId ?? null,
      createdAt: new Date().toISOString(),
    };
    const ref = await foldersCol(db, uid).add(payload);
    res.status(201).json({ id: ref.id, ...payload });
  } catch (err) {
    console.error('[Folders] POST error:', err);
    res.status(500).json({ error: 'Không thể tạo thư mục' });
  }
});

// ─── GET /api/folders/shared ────────────────────────────────
router.get('/shared', async (req, res) => {
  try {
    const db = getFirestore();
    const uid = req.user.uid;
    const snap = await db.collectionGroup('folderShares').where('sharedWith', '==', uid).get();
    const folders = [];

    for (const shareDoc of snap.docs) {
      const shareData = shareDoc.data();
      const folderRef = shareDoc.ref.parent.parent;
      const folderDoc = await folderRef.get();
      if (!folderDoc.exists) continue;
      const ownerUid = folderRef.parent.parent.id;
      folders.push({
        id: folderDoc.id,
        ...folderDoc.data(),
        sharePermission: shareData.permission,
        ownerUid,
        ownerName: shareData.ownerName || '',
        ownerPhoto: shareData.ownerPhoto || '',
      });
    }

    res.json({ folders });
  } catch (err) {
    console.error('[Folders] GET shared error:', err);
    res.status(500).json({ error: 'Không thể lấy thư mục được chia sẻ' });
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
    if (req.body.localId !== undefined) updates.localId = req.body.localId;
    const ref = foldersCol(db, uid).doc(req.params.id);
    await ref.update(updates);
    const doc = await ref.get();
    res.json({ id: doc.id, ...doc.data() });
  } catch (err) {
    console.error('[Folders] PUT error:', err);
    res.status(500).json({ error: 'Không thể cập nhật thư mục' });
  }
});

// ─── POST /api/folders/:id/share ────────────────────────────
router.post('/:id/share', async (req, res) => {
  try {
    const db = getFirestore();
    const uid = req.user.uid;
    const { email, permission, localFolderId } = req.body;
    if (!email) return res.status(400).json({ error: 'Cần email để chia sẻ thư mục' });

    const folderRef = foldersCol(db, uid).doc(req.params.id);
    const folderDoc = await folderRef.get();
    if (!folderDoc.exists) return res.status(404).json({ error: 'Không tìm thấy thư mục' });

    let targetUser;
    try {
      targetUser = await resolveUserByEmail(db, email);
    } catch {
      return res.status(404).json({
        error: 'Không tìm thấy người dùng với email này. Người nhận cần đăng nhập ứng dụng ít nhất một lần.',
      });
    }
    if (targetUser.uid === uid) return res.status(400).json({ error: 'Không thể chia sẻ với chính mình' });

    const folder = folderDoc.data();
    const folderLocalId = folder.localId ?? localFolderId;
    if (folderLocalId == null) {
      return res.status(400).json({ error: 'Thiếu mã thư mục cục bộ để xác định ghi chú trong thư mục' });
    }
    if (folder.localId == null) {
      await folderRef.set({ localId: folderLocalId }, { merge: true });
    }

    const sharePayload = {
      sharedWith: targetUser.uid,
      sharedWithEmail: email,
      sharedWithName: targetUser.displayName || email,
      permission: permission || 'view',
      ownerUid: uid,
      ownerName: req.user.name,
      ownerPhoto: req.user.picture || '',
      folderId: req.params.id,
      folderLocalId,
      folderName: folder.name || 'Thư mục',
      sharedAt: new Date().toISOString(),
    };

    await folderRef.collection('folderShares').doc(targetUser.uid).set(sharePayload);

    const notesSnap = await notesCol(db, uid)
      .where('folderId', '==', folderLocalId)
      .get();
    const batch = db.batch();
    notesSnap.docs
      .filter((doc) => !doc.data().deleted)
      .forEach((doc) => {
        batch.set(doc.ref.collection('shares').doc(targetUser.uid), {
          ...sharePayload,
          noteId: doc.id,
          noteTitle: doc.data().title || '',
          sharedViaFolder: true,
        });
      });
    await batch.commit();

    await createNotification({
      recipientUid: targetUser.uid,
      type: 'folder_share',
      actor: req.user,
      noteId: null,
      noteTitle: folder.name,
      text: folder.name,
    });

    res.json({
      message: `Đã chia sẻ thư mục với ${email}`,
      sharedWith: { uid: targetUser.uid, email, name: targetUser.displayName },
      sharedNotesCount: notesSnap.docs.filter((doc) => !doc.data().deleted).length,
    });
  } catch (err) {
    console.error('[Folders] Share error:', err);
    res.status(500).json({ error: 'Không thể chia sẻ thư mục' });
  }
});

router.get('/:id/shares', async (req, res) => {
  try {
    const db = getFirestore();
    const snap = await foldersCol(db, req.user.uid).doc(req.params.id).collection('folderShares').get();
    res.json({ shares: snap.docs.map((d) => ({ id: d.id, ...d.data() })) });
  } catch (err) {
    console.error('[Folders] GET shares error:', err);
    res.status(500).json({ error: 'Không thể lấy danh sách chia sẻ thư mục' });
  }
});

router.delete('/:id/share/:targetUid', async (req, res) => {
  try {
    const db = getFirestore();
    const uid = req.user.uid;
    const folderRef = foldersCol(db, uid).doc(req.params.id);
    const folderDoc = await folderRef.get();
    if (!folderDoc.exists) return res.status(404).json({ error: 'Không tìm thấy thư mục' });

    const folderLocalId = folderDoc.data().localId ?? req.query.localFolderId;
    await folderRef.collection('folderShares').doc(req.params.targetUid).delete();

    if (folderLocalId != null) {
      const notesSnap = await notesCol(db, uid).where('folderId', '==', Number(folderLocalId)).get();
      const batch = db.batch();
      notesSnap.docs.forEach((doc) => {
        batch.delete(doc.ref.collection('shares').doc(req.params.targetUid));
      });
      await batch.commit();
    }

    res.json({ message: 'Đã hủy chia sẻ thư mục' });
  } catch (err) {
    console.error('[Folders] Delete share error:', err);
    res.status(500).json({ error: 'Không thể hủy chia sẻ thư mục' });
  }
});

// ─── DELETE /api/folders/:id ────────────────────────────────
router.delete('/:id', async (req, res) => {
  try {
    const db = getFirestore();
    const uid = req.user.uid;
    const folderRef = foldersCol(db, uid).doc(req.params.id);
    const folderDoc = await folderRef.get();
    if (!folderDoc.exists) return res.status(404).json({ error: 'Không tìm thấy thư mục' });
    const folderLocalId = folderDoc.data().localId ?? req.query.localFolderId;

    // Remove folder reference from all notes in this folder
    const notesSnap = folderLocalId == null
      ? { docs: [] }
      : await notesCol(db, uid).where('folderId', '==', Number(folderLocalId)).get();
    const batch = db.batch();
    notesSnap.docs.forEach(doc => {
      batch.update(doc.ref, { folderId: null });
    });
    batch.delete(folderRef);
    await batch.commit();
    res.json({ message: 'Đã xóa thư mục' });
  } catch (err) {
    console.error('[Folders] DELETE error:', err);
    res.status(500).json({ error: 'Không thể xóa thư mục' });
  }
});

module.exports = router;
