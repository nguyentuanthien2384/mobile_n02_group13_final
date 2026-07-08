const express = require('express');
const { v4: uuidv4 } = require('uuid');
const { getFirestore, getFieldValue, getAuth } = require('../config/firebase');
const {
  ensureUserProfile,
  createNotification,
  getProfileMeta,
  extractMentions,
  upsertFeedDoc,
  removeFeedDoc,
  bumpFeedCounter,
} = require('../utils/social');
const rateLimit = require('../middleware/rateLimit');
const router = express.Router();

const MAX_VERSIONS = 20;
const PAGE = (req, def = 30, cap = 100) =>
  Math.min(parseInt(req.query.limit, 10) || def, cap);

const notesCol = (db, uid) => db.collection('users').doc(uid).collection('notes');

// ════════════════════════════════════════════════════════════
//  COLLECTION-LEVEL ROUTES  (must precede "/:id")
// ════════════════════════════════════════════════════════════

// ─── GET /api/notes ─────────────────────────────────────────
// Active notes by default. ?filter=trash|archived|all
router.get('/', async (req, res) => {
  try {
    const db = getFirestore();
    const uid = req.user.uid;
    const filter = req.query.filter || 'active';
    const snap = await notesCol(db, uid).get();
    let notes = snap.docs.map((d) => ({ id: d.id, ...d.data() }));

    if (filter === 'trash') notes = notes.filter((n) => n.deleted);
    else if (filter === 'archived') notes = notes.filter((n) => n.archived && !n.deleted);
    else if (filter === 'active') notes = notes.filter((n) => !n.deleted && !n.archived);
    // 'all' → everything

    res.json({ notes });
  } catch (err) {
    console.error('[Notes] GET error:', err);
    res.status(500).json({ error: 'Không thể lấy danh sách ghi chú' });
  }
});

// ─── GET /api/notes/search?q= ───────────────────────────────
router.get('/search', async (req, res) => {
  try {
    const db = getFirestore();
    const uid = req.user.uid;
    const q = (req.query.q || '').trim().toLowerCase();
    if (!q) return res.json({ notes: [] });
    const snap = await notesCol(db, uid).get();
    const notes = snap.docs
      .map((d) => ({ id: d.id, ...d.data() }))
      .filter((n) => !n.deleted)
      .filter((n) =>
        (n.title || '').toLowerCase().includes(q) ||
        (n.content || '').toLowerCase().includes(q)
      );
    res.json({ notes });
  } catch (err) {
    console.error('[Notes] search error:', err);
    res.status(500).json({ error: 'Không thể tìm kiếm ghi chú' });
  }
});

// ─── GET /api/notes/trash ───────────────────────────────────
router.get('/trash', async (req, res) => {
  try {
    const db = getFirestore();
    const uid = req.user.uid;
    const snap = await notesCol(db, uid).get();
    const notes = snap.docs.map((d) => ({ id: d.id, ...d.data() })).filter((n) => n.deleted);
    res.json({ notes });
  } catch (err) {
    console.error('[Notes] trash error:', err);
    res.status(500).json({ error: 'Không thể lấy thùng rác' });
  }
});

// ─── DELETE /api/notes/trash/empty ──────────────────────────
router.delete('/trash/empty', async (req, res) => {
  try {
    const db = getFirestore();
    const uid = req.user.uid;
    const snap = await notesCol(db, uid).get();
    const trashed = snap.docs.filter((d) => d.data().deleted);
    for (const d of trashed) await purgeNote(db, uid, d.id, d.data());
    res.json({ message: 'Đã dọn thùng rác', deleted: trashed.length });
  } catch (err) {
    console.error('[Notes] empty trash error:', err);
    res.status(500).json({ error: 'Không thể dọn thùng rác' });
  }
});

// ─── GET /api/notes/archived ────────────────────────────────
router.get('/archived', async (req, res) => {
  try {
    const db = getFirestore();
    const uid = req.user.uid;
    const snap = await notesCol(db, uid).get();
    const notes = snap.docs.map((d) => ({ id: d.id, ...d.data() }))
      .filter((n) => n.archived && !n.deleted);
    res.json({ notes });
  } catch (err) {
    console.error('[Notes] archived error:', err);
    res.status(500).json({ error: 'Không thể lấy ghi chú lưu trữ' });
  }
});

// ─── GET /api/notes/bookmarks ───────────────────────────────
router.get('/bookmarks', async (req, res) => {
  try {
    const db = getFirestore();
    const uid = req.user.uid;
    const snap = await db.collection('users').doc(uid).collection('bookmarks')
      .orderBy('bookmarkedAt', 'desc').get();
    res.json({ posts: snap.docs.map((d) => ({ id: d.id, ...d.data() })) });
  } catch (err) {
    console.error('[Notes] bookmarks error:', err);
    res.status(500).json({ error: 'Không thể lấy ghi chú đã lưu' });
  }
});

// ─── GET /api/notes/shared ──────────────────────────────────
router.get('/shared', async (req, res) => {
  try {
    const db = getFirestore();
    const uid = req.user.uid;
    const snap = await db.collectionGroup('shares').where('sharedWith', '==', uid).get();
    const notes = [];
    for (const shareDoc of snap.docs) {
      const shareData = shareDoc.data();
      const noteRef = shareDoc.ref.parent.parent;
      const noteDoc = await noteRef.get();
      if (noteDoc.exists && !noteDoc.data().deleted) {
        const ownerUid = noteRef.parent.parent.id;
        notes.push({
          id: noteDoc.id,
          ...noteDoc.data(),
          sharePermission: shareData.permission,
          ownerUid,
          ownerName: shareData.ownerName || '',
          ownerPhoto: shareData.ownerPhoto || '',
          sharedViaFolder: shareData.sharedViaFolder || false,
          sharedFolderId: shareData.folderId || null,
          sharedFolderName: shareData.folderName || '',
        });
      }
    }
    res.json({ notes });
  } catch (err) {
    console.error('[Notes] GET shared error:', err);
    res.status(500).json({ error: 'Không thể lấy ghi chú được chia sẻ' });
  }
});

// ─── GET /api/notes/public/:token ───────────────────────────
router.get('/public/:token', async (req, res) => {
  try {
    const db = getFirestore();
    const snap = await db.collectionGroup('notes')
      .where('publicShareToken', '==', req.params.token).limit(1).get();
    if (snap.empty) return res.status(404).json({ error: 'Link chia sẻ không hợp lệ hoặc đã hết hạn' });
    const doc = snap.docs[0];
    const data = doc.data();
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

// ─── POST /api/notes ────────────────────────────────────────
router.post('/', rateLimit({ key: 'note-write', max: 120 }), async (req, res) => {
  try {
    const db = getFirestore();
    const uid = req.user.uid;
    const b = req.body;
    const now = new Date().toISOString();
    const payload = {
      title: b.title || '',
      content: b.content || '',
      createdAt: now,
      editedAt: now,
      pinned: b.pinned || false,
      isChecklist: b.isChecklist || false,
      tags: b.tags || [],
      color: b.color || 0,
      folderId: b.folderId || null,
      isFavorite: b.isFavorite || false,
      localId: b.localId || null,
      reminderAt: b.reminderAt || null,
      coverImage: b.coverImage || '',
      collaborators: b.collaborators ?? null,
      sharedExternally: b.sharedExternally ?? 0,
      deleted: false,
      archived: false,
      isPublished: false,
      likesCount: 0,
      commentsCount: 0,
    };
    const ref = await notesCol(db, uid).add(payload);
    res.status(201).json({ id: ref.id, ...payload });
  } catch (err) {
    console.error('[Notes] POST error:', err);
    res.status(500).json({ error: 'Không thể tạo ghi chú' });
  }
});

// ════════════════════════════════════════════════════════════
//  SINGLE-NOTE ROUTES
// ════════════════════════════════════════════════════════════

// ─── GET /api/notes/:id ─────────────────────────────────────
router.get('/:id', async (req, res) => {
  try {
    const db = getFirestore();
    const uid = req.user.uid;
    const doc = await notesCol(db, uid).doc(req.params.id).get();
    if (!doc.exists) return res.status(404).json({ error: 'Không tìm thấy ghi chú' });
    res.json({ id: doc.id, ...doc.data() });
  } catch (err) {
    console.error('[Notes] GET by id error:', err);
    res.status(500).json({ error: 'Không thể lấy ghi chú' });
  }
});

// ─── PUT /api/notes/:id ─────────────────────────────────────
router.put('/:id', rateLimit({ key: 'note-write', max: 240 }), async (req, res) => {
  try {
    const db = getFirestore();
    const uid = req.user.uid;
    const noteRef = notesCol(db, uid).doc(req.params.id);
    const doc = await noteRef.get();
    if (!doc.exists) return res.status(404).json({ error: 'Không tìm thấy ghi chú' });
    const before = doc.data();

    // Snapshot a version when the content/title actually changes.
    const contentChanged =
      (req.body.content !== undefined && req.body.content !== before.content) ||
      (req.body.title !== undefined && req.body.title !== before.title);
    if (contentChanged) await saveVersion(db, uid, req.params.id, before);

    const updates = {};
    const allowed = ['title', 'content', 'pinned', 'isChecklist', 'tags', 'color',
      'folderId', 'isFavorite', 'localId', 'reminderAt', 'coverImage',
      'collaborators', 'sharedExternally'];
    for (const key of allowed) if (req.body[key] !== undefined) updates[key] = req.body[key];
    updates.editedAt = new Date().toISOString();
    await noteRef.update(updates);

    // Keep the public feed copy in sync if this note is published.
    if (before.isPublished) {
      const author = await getProfileMeta(uid);
      await upsertFeedDoc({ id: req.params.id, ...before, ...updates }, author);
    }

    res.json({ id: req.params.id, ...before, ...updates });
  } catch (err) {
    console.error('[Notes] PUT error:', err);
    res.status(500).json({ error: 'Không thể cập nhật ghi chú' });
  }
});

// ─── DELETE /api/notes/:id  (soft delete → trash) ───────────
router.delete('/:id', async (req, res) => {
  try {
    const db = getFirestore();
    const uid = req.user.uid;
    const noteRef = notesCol(db, uid).doc(req.params.id);
    const doc = await noteRef.get();
    if (!doc.exists) return res.status(404).json({ error: 'Không tìm thấy ghi chú' });

    if (req.query.permanent === 'true') {
      await purgeNote(db, uid, req.params.id, doc.data());
      return res.json({ message: 'Đã xóa vĩnh viễn' });
    }

    await noteRef.update({
      deleted: true,
      deletedAt: new Date().toISOString(),
      isPublished: false,
    });
    if (doc.data().isPublished) await removeFeedDoc(req.params.id);
    res.json({ message: 'Đã chuyển vào thùng rác' });
  } catch (err) {
    console.error('[Notes] DELETE error:', err);
    res.status(500).json({ error: 'Không thể xóa ghi chú' });
  }
});

// ─── POST /api/notes/:id/restore ────────────────────────────
router.post('/:id/restore', async (req, res) => {
  try {
    const db = getFirestore();
    const uid = req.user.uid;
    const noteRef = notesCol(db, uid).doc(req.params.id);
    if (!(await noteRef.get()).exists) return res.status(404).json({ error: 'Không tìm thấy ghi chú' });
    await noteRef.update({ deleted: false, deletedAt: null });
    res.json({ message: 'Đã khôi phục ghi chú' });
  } catch (err) {
    console.error('[Notes] restore error:', err);
    res.status(500).json({ error: 'Không thể khôi phục ghi chú' });
  }
});

// ─── POST /api/notes/:id/archive  &  /unarchive ─────────────
router.post('/:id/archive', async (req, res) => {
  try {
    const db = getFirestore();
    const noteRef = notesCol(db, req.user.uid).doc(req.params.id);
    if (!(await noteRef.get()).exists) return res.status(404).json({ error: 'Không tìm thấy ghi chú' });
    await noteRef.update({ archived: true });
    res.json({ message: 'Đã lưu trữ' });
  } catch (err) {
    console.error('[Notes] archive error:', err);
    res.status(500).json({ error: 'Không thể lưu trữ' });
  }
});
router.post('/:id/unarchive', async (req, res) => {
  try {
    const db = getFirestore();
    const noteRef = notesCol(db, req.user.uid).doc(req.params.id);
    if (!(await noteRef.get()).exists) return res.status(404).json({ error: 'Không tìm thấy ghi chú' });
    await noteRef.update({ archived: false });
    res.json({ message: 'Đã bỏ lưu trữ' });
  } catch (err) {
    console.error('[Notes] unarchive error:', err);
    res.status(500).json({ error: 'Không thể bỏ lưu trữ' });
  }
});

// ─── POST /api/notes/:id/duplicate ──────────────────────────
router.post('/:id/duplicate', async (req, res) => {
  try {
    const db = getFirestore();
    const uid = req.user.uid;
    const doc = await notesCol(db, uid).doc(req.params.id).get();
    if (!doc.exists) return res.status(404).json({ error: 'Không tìm thấy ghi chú' });
    const src = doc.data();
    const now = new Date().toISOString();
    const copy = {
      ...src,
      title: `${src.title || 'Ghi chú'} (bản sao)`,
      createdAt: now,
      editedAt: now,
      pinned: false,
      isPublished: false,
      deleted: false,
      archived: false,
      likesCount: 0,
      commentsCount: 0,
      publicShareToken: null,
      localId: null,
    };
    const ref = await notesCol(db, uid).add(copy);
    res.status(201).json({ id: ref.id, ...copy });
  } catch (err) {
    console.error('[Notes] duplicate error:', err);
    res.status(500).json({ error: 'Không thể nhân bản ghi chú' });
  }
});

// ─── Version history ────────────────────────────────────────
router.get('/:id/versions', async (req, res) => {
  try {
    const db = getFirestore();
    const uid = req.user.uid;
    const snap = await notesCol(db, uid).doc(req.params.id)
      .collection('versions').orderBy('createdAt', 'desc').get();
    res.json({ versions: snap.docs.map((d) => ({ id: d.id, ...d.data() })) });
  } catch (err) {
    console.error('[Notes] versions error:', err);
    res.status(500).json({ error: 'Không thể lấy lịch sử' });
  }
});

router.post('/:id/restore-version/:vid', async (req, res) => {
  try {
    const db = getFirestore();
    const uid = req.user.uid;
    const noteRef = notesCol(db, uid).doc(req.params.id);
    const noteDoc = await noteRef.get();
    if (!noteDoc.exists) return res.status(404).json({ error: 'Không tìm thấy ghi chú' });
    const vDoc = await noteRef.collection('versions').doc(req.params.vid).get();
    if (!vDoc.exists) return res.status(404).json({ error: 'Không tìm thấy phiên bản' });
    // Snapshot current state before reverting, then revert.
    await saveVersion(db, uid, req.params.id, noteDoc.data());
    const v = vDoc.data();
    await noteRef.update({ title: v.title, content: v.content, editedAt: new Date().toISOString() });
    res.json({ message: 'Đã khôi phục phiên bản', title: v.title, content: v.content });
  } catch (err) {
    console.error('[Notes] restore version error:', err);
    res.status(500).json({ error: 'Không thể khôi phục phiên bản' });
  }
});

// ════════════════════════════════════════════════════════════
//  PUBLISH  (note → public post)
// ════════════════════════════════════════════════════════════
router.post('/:id/publish', rateLimit({ key: 'publish', max: 60 }), async (req, res) => {
  try {
    const db = getFirestore();
    const uid = req.user.uid;
    await ensureUserProfile(req.user);
    const noteRef = notesCol(db, uid).doc(req.params.id);
    const doc = await noteRef.get();
    if (!doc.exists) return res.status(404).json({ error: 'Không tìm thấy ghi chú' });
    const data = doc.data();
    if (data.deleted) return res.status(400).json({ error: 'Không thể đăng ghi chú đã xóa' });

    const publishedAt = data.publishedAt || new Date().toISOString();
    await noteRef.update({ isPublished: true, publishedAt });
    if (!data.isPublished) {
      await db.collection('users').doc(uid).set(
        { publishedCount: getFieldValue().increment(1) }, { merge: true }
      );
    }
    const author = await getProfileMeta(uid);
    await upsertFeedDoc({ id: req.params.id, ...data, publishedAt }, author);

    res.json({ message: 'Đã đăng ghi chú', isPublished: true, publishedAt });
  } catch (err) {
    console.error('[Notes] publish error:', err);
    res.status(500).json({ error: 'Không thể đăng ghi chú' });
  }
});

router.post('/:id/unpublish', async (req, res) => {
  try {
    const db = getFirestore();
    const uid = req.user.uid;
    const noteRef = notesCol(db, uid).doc(req.params.id);
    const doc = await noteRef.get();
    if (!doc.exists) return res.status(404).json({ error: 'Không tìm thấy ghi chú' });
    if (doc.data().isPublished) {
      await db.collection('users').doc(uid).set(
        { publishedCount: getFieldValue().increment(-1) }, { merge: true }
      );
    }
    await noteRef.update({ isPublished: false });
    await removeFeedDoc(req.params.id);
    res.json({ message: 'Đã gỡ ghi chú', isPublished: false });
  } catch (err) {
    console.error('[Notes] unpublish error:', err);
    res.status(500).json({ error: 'Không thể gỡ ghi chú' });
  }
});

// ════════════════════════════════════════════════════════════
//  LIKES  (on a published post, keyed in the feed collection)
// ════════════════════════════════════════════════════════════
router.post('/:id/like', rateLimit({ key: 'like', max: 120 }), async (req, res) => {
  try {
    const db = getFirestore();
    const me = req.user.uid;
    const feedRef = db.collection('feed').doc(req.params.id);
    const feedDoc = await feedRef.get();
    if (!feedDoc.exists) return res.status(404).json({ error: 'Bài viết không tồn tại' });

    const likeRef = feedRef.collection('likes').doc(me);
    if ((await likeRef.get()).exists) {
      const fresh = await feedRef.get();
      return res.json({ liked: true, likesCount: fresh.data().likesCount || 0 });
    }
    await likeRef.set({
      uid: me,
      type: req.body.type || 'like',
      createdAt: new Date().toISOString(),
    });
    await bumpFeedCounter(req.params.id, 'likesCount', 1);

    const fd = feedDoc.data();
    // Mirror onto the author's own note counter.
    try {
      await notesCol(db, fd.authorUid).doc(req.params.id)
        .set({ likesCount: getFieldValue().increment(1) }, { merge: true });
    } catch (_) {}
    await createNotification({
      recipientUid: fd.authorUid, type: 'like', actor: req.user,
      noteId: req.params.id, noteTitle: fd.title,
    });

    const fresh = await feedRef.get();
    res.json({ liked: true, likesCount: fresh.data().likesCount || 0 });
  } catch (err) {
    console.error('[Notes] like error:', err);
    res.status(500).json({ error: 'Không thể thích bài viết' });
  }
});

router.delete('/:id/like', async (req, res) => {
  try {
    const db = getFirestore();
    const me = req.user.uid;
    const feedRef = db.collection('feed').doc(req.params.id);
    const feedDoc = await feedRef.get();
    if (!feedDoc.exists) return res.status(404).json({ error: 'Bài viết không tồn tại' });
    const likeRef = feedRef.collection('likes').doc(me);
    if (!(await likeRef.get()).exists) {
      const fresh = await feedRef.get();
      return res.json({ liked: false, likesCount: fresh.data().likesCount || 0 });
    }
    await likeRef.delete();
    await bumpFeedCounter(req.params.id, 'likesCount', -1);
    const fd = feedDoc.data();
    try {
      await notesCol(db, fd.authorUid).doc(req.params.id)
        .set({ likesCount: getFieldValue().increment(-1) }, { merge: true });
    } catch (_) {}
    const fresh = await feedRef.get();
    res.json({ liked: false, likesCount: fresh.data().likesCount || 0 });
  } catch (err) {
    console.error('[Notes] unlike error:', err);
    res.status(500).json({ error: 'Không thể bỏ thích' });
  }
});

router.get('/:id/likes', async (req, res) => {
  try {
    const db = getFirestore();
    const snap = await db.collection('feed').doc(req.params.id)
      .collection('likes').orderBy('createdAt', 'desc').get();
    const likers = [];
    for (const d of snap.docs) {
      const meta = await getProfileMeta(d.id);
      likers.push({ ...meta, type: d.data().type || 'like' });
    }
    res.json({ likers });
  } catch (err) {
    console.error('[Notes] likes list error:', err);
    res.status(500).json({ error: 'Không thể lấy danh sách thích' });
  }
});

// ════════════════════════════════════════════════════════════
//  BOOKMARKS
// ════════════════════════════════════════════════════════════
router.post('/:id/bookmark', async (req, res) => {
  try {
    const db = getFirestore();
    const me = req.user.uid;
    const feedDoc = await db.collection('feed').doc(req.params.id).get();
    if (!feedDoc.exists) return res.status(404).json({ error: 'Bài viết không tồn tại' });
    await db.collection('users').doc(me).collection('bookmarks').doc(req.params.id).set({
      ...feedDoc.data(),
      bookmarkedAt: new Date().toISOString(),
    });
    res.json({ bookmarked: true });
  } catch (err) {
    console.error('[Notes] bookmark error:', err);
    res.status(500).json({ error: 'Không thể lưu bài viết' });
  }
});

router.delete('/:id/bookmark', async (req, res) => {
  try {
    const db = getFirestore();
    const me = req.user.uid;
    await db.collection('users').doc(me).collection('bookmarks').doc(req.params.id).delete();
    res.json({ bookmarked: false });
  } catch (err) {
    console.error('[Notes] remove bookmark error:', err);
    res.status(500).json({ error: 'Không thể bỏ lưu bài viết' });
  }
});

// ════════════════════════════════════════════════════════════
//  SHARING  (private user / public link)
// ════════════════════════════════════════════════════════════
router.post('/:id/share', async (req, res) => {
  try {
    const db = getFirestore();
    const uid = req.user.uid;
    const { email, permission, isPublic } = req.body;
    const noteRef = notesCol(db, uid).doc(req.params.id);
    const noteDoc = await noteRef.get();
    if (!noteDoc.exists) return res.status(404).json({ error: 'Không tìm thấy ghi chú' });

    if (isPublic) {
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

    if (!email) return res.status(400).json({ error: 'Cần email hoặc chọn chia sẻ công khai' });

    // Resolve the recipient. Prefer the app's own user index (emailLower → the
    // REAL uid of someone who has logged into this app) so the share is stored
    // under the same uid the recipient authenticates with. Fall back to Firebase
    // Auth lookup for real-Firebase deployments.
    let targetUser;
    const idx = await db
      .collection('users')
      .where('emailLower', '==', email.toLowerCase())
      .limit(1)
      .get();
    if (!idx.empty) {
      const d = idx.docs[0];
      targetUser = { uid: d.id, email, displayName: d.data().displayName };
    } else {
      try {
        targetUser = await getAuth().getUserByEmail(email);
      } catch {
        return res.status(404).json({
          error: 'Không tìm thấy người dùng với email này. Người nhận cần đăng nhập ứng dụng ít nhất một lần.',
        });
      }
    }
    if (targetUser.uid === uid) return res.status(400).json({ error: 'Không thể chia sẻ với chính mình' });

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

    await createNotification({
      recipientUid: targetUser.uid, type: 'share', actor: req.user,
      noteId: req.params.id, noteTitle: noteDoc.data().title,
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

router.get('/:id/shares', async (req, res) => {
  try {
    const db = getFirestore();
    const snap = await notesCol(db, req.user.uid).doc(req.params.id).collection('shares').get();
    res.json({ shares: snap.docs.map((d) => ({ id: d.id, ...d.data() })) });
  } catch (err) {
    console.error('[Notes] GET shares error:', err);
    res.status(500).json({ error: 'Không thể lấy danh sách chia sẻ' });
  }
});

router.delete('/:id/share/:targetUid', async (req, res) => {
  try {
    const db = getFirestore();
    await notesCol(db, req.user.uid).doc(req.params.id)
      .collection('shares').doc(req.params.targetUid).delete();
    res.json({ message: 'Đã hủy chia sẻ' });
  } catch (err) {
    console.error('[Notes] Delete share error:', err);
    res.status(500).json({ error: 'Không thể hủy chia sẻ' });
  }
});

// ════════════════════════════════════════════════════════════
//  COMMENTS  (threaded, likeable, editable)
// ════════════════════════════════════════════════════════════
router.get('/:id/comments', async (req, res) => {
  try {
    const db = getFirestore();
    const ownerUid = req.query.ownerUid || req.user.uid;
    const me = req.user.uid;
    const noteRef = notesCol(db, ownerUid).doc(req.params.id);
    const snap = await noteRef.collection('comments').orderBy('createdAt', 'asc').get();
    const comments = [];
    for (const d of snap.docs) {
      const data = d.data();
      const liked = (await noteRef.collection('comments').doc(d.id)
        .collection('likes').doc(me).get()).exists;
      comments.push({ id: d.id, ...data, liked });
    }
    res.json({ comments });
  } catch (err) {
    console.error('[Notes] GET comments error:', err);
    res.status(500).json({ error: 'Không thể lấy bình luận' });
  }
});

router.post('/:id/comments', rateLimit({ key: 'comment', max: 60 }), async (req, res) => {
  try {
    const db = getFirestore();
    const uid = req.user.uid;
    const { text, noteOwnerUid, parentId } = req.body;
    if (!text || !text.trim()) return res.status(400).json({ error: 'Nội dung bình luận không được trống' });

    const ownerUid = noteOwnerUid || uid;
    const noteRef = notesCol(db, ownerUid).doc(req.params.id);
    const noteDoc = await noteRef.get();
    if (!noteDoc.exists) return res.status(404).json({ error: 'Không tìm thấy ghi chú' });

    const comment = {
      userId: uid,
      userName: req.user.name,
      userPhoto: req.user.picture || '',
      text: text.trim(),
      parentId: parentId || null,
      likesCount: 0,
      createdAt: new Date().toISOString(),
    };
    const ref = await noteRef.collection('comments').add(comment);

    await noteRef.set({ commentsCount: getFieldValue().increment(1) }, { merge: true });
    if (noteDoc.data().isPublished) await bumpFeedCounter(req.params.id, 'commentsCount', 1);

    // Notify the note owner (comment) and the parent author (reply).
    const noteTitle = noteDoc.data().title;
    await createNotification({
      recipientUid: ownerUid, type: parentId ? 'reply' : 'comment', actor: req.user,
      noteId: req.params.id, noteTitle, commentId: ref.id, text: comment.text,
    });
    if (parentId) {
      const parent = await noteRef.collection('comments').doc(parentId).get();
      if (parent.exists) {
        await createNotification({
          recipientUid: parent.data().userId, type: 'reply', actor: req.user,
          noteId: req.params.id, noteTitle, commentId: ref.id, text: comment.text,
        });
      }
    }
    // @mention notifications.
    for (const handle of extractMentions(comment.text)) {
      const idx = await db.collection('users').where('displayNameLower', '==', handle).limit(1).get();
      if (!idx.empty) {
        await createNotification({
          recipientUid: idx.docs[0].id, type: 'mention', actor: req.user,
          noteId: req.params.id, noteTitle, commentId: ref.id, text: comment.text,
        });
      }
    }

    res.status(201).json({ id: ref.id, ...comment, liked: false });
  } catch (err) {
    console.error('[Notes] Comment error:', err);
    res.status(500).json({ error: 'Không thể thêm bình luận' });
  }
});

router.put('/:id/comments/:cid', async (req, res) => {
  try {
    const db = getFirestore();
    const ownerUid = req.query.ownerUid || req.user.uid;
    const { text } = req.body;
    if (!text || !text.trim()) return res.status(400).json({ error: 'Nội dung không được trống' });
    const cRef = notesCol(db, ownerUid).doc(req.params.id).collection('comments').doc(req.params.cid);
    const cDoc = await cRef.get();
    if (!cDoc.exists) return res.status(404).json({ error: 'Không tìm thấy bình luận' });
    if (cDoc.data().userId !== req.user.uid) return res.status(403).json({ error: 'Không có quyền sửa' });
    await cRef.update({ text: text.trim(), editedAt: new Date().toISOString() });
    res.json({ id: req.params.cid, ...cDoc.data(), text: text.trim() });
  } catch (err) {
    console.error('[Notes] edit comment error:', err);
    res.status(500).json({ error: 'Không thể sửa bình luận' });
  }
});

router.delete('/:id/comments/:cid', async (req, res) => {
  try {
    const db = getFirestore();
    const ownerUid = req.query.ownerUid || req.user.uid;
    const noteRef = notesCol(db, ownerUid).doc(req.params.id);
    const cRef = noteRef.collection('comments').doc(req.params.cid);
    const cDoc = await cRef.get();
    if (!cDoc.exists) return res.status(404).json({ error: 'Không tìm thấy bình luận' });
    const isAuthor = cDoc.data().userId === req.user.uid;
    const isOwner = ownerUid === req.user.uid;
    if (!isAuthor && !isOwner) return res.status(403).json({ error: 'Không có quyền xóa' });
    await cRef.delete();
    await noteRef.set({ commentsCount: getFieldValue().increment(-1) }, { merge: true });
    const noteDoc = await noteRef.get();
    if (noteDoc.exists && noteDoc.data().isPublished) await bumpFeedCounter(req.params.id, 'commentsCount', -1);
    res.json({ message: 'Đã xóa bình luận' });
  } catch (err) {
    console.error('[Notes] delete comment error:', err);
    res.status(500).json({ error: 'Không thể xóa bình luận' });
  }
});

router.post('/:id/comments/:cid/like', async (req, res) => {
  try {
    const db = getFirestore();
    const me = req.user.uid;
    const ownerUid = req.query.ownerUid || req.user.uid;
    const cRef = notesCol(db, ownerUid).doc(req.params.id).collection('comments').doc(req.params.cid);
    if (!(await cRef.get()).exists) return res.status(404).json({ error: 'Không tìm thấy bình luận' });
    const likeRef = cRef.collection('likes').doc(me);
    const liked = (await likeRef.get()).exists;
    if (liked) {
      await likeRef.delete();
      await cRef.set({ likesCount: getFieldValue().increment(-1) }, { merge: true });
    } else {
      await likeRef.set({ uid: me, createdAt: new Date().toISOString() });
      await cRef.set({ likesCount: getFieldValue().increment(1) }, { merge: true });
    }
    const fresh = await cRef.get();
    res.json({ liked: !liked, likesCount: fresh.data().likesCount || 0 });
  } catch (err) {
    console.error('[Notes] comment like error:', err);
    res.status(500).json({ error: 'Không thể thích bình luận' });
  }
});

// ════════════════════════════════════════════════════════════
//  HELPERS
// ════════════════════════════════════════════════════════════
async function saveVersion(db, uid, noteId, before) {
  const noteRef = notesCol(db, uid).doc(noteId);
  await noteRef.collection('versions').add({
    title: before.title || '',
    content: before.content || '',
    createdAt: new Date().toISOString(),
  });
  // Trim to the most recent MAX_VERSIONS.
  const all = await noteRef.collection('versions').orderBy('createdAt', 'asc').get();
  if (all.size > MAX_VERSIONS) {
    const excess = all.docs.slice(0, all.size - MAX_VERSIONS);
    for (const d of excess) await d.ref.delete();
  }
}

async function purgeNote(db, uid, noteId, data) {
  const noteRef = notesCol(db, uid).doc(noteId);
  for (const sub of ['shares', 'comments', 'versions']) {
    const s = await noteRef.collection(sub).get();
    for (const d of s.docs) await d.ref.delete();
  }
  if (data && data.isPublished) await removeFeedDoc(noteId);
  await noteRef.delete();
}

module.exports = router;
