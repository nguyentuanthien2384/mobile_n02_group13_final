const express = require('express');
const multer = require('multer');
const { getStorage } = require('../config/firebase');
const { v4: uuidv4 } = require('uuid');
const router = express.Router();

// Multer config - store in memory for upload to Firebase Storage
const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 10 * 1024 * 1024 }, // 10MB limit
  fileFilter: (req, file, cb) => {
    const allowed = ['image/jpeg', 'image/png', 'image/gif', 'image/webp'];
    if (allowed.includes(file.mimetype)) {
      cb(null, true);
    } else {
      cb(new Error('Chỉ hỗ trợ file ảnh (JPEG, PNG, GIF, WebP)'));
    }
  },
});

// ─── POST /api/upload/image ─────────────────────────────────
router.post('/image', upload.single('image'), async (req, res) => {
  try {
    if (!req.file) {
      return res.status(400).json({ error: 'Không có file ảnh' });
    }

    const uid = req.user.uid;
    const bucket = getStorage().bucket();
    const ext = req.file.originalname.split('.').pop() || 'jpg';
    const fileName = `users/${uid}/images/${uuidv4()}.${ext}`;
    const file = bucket.file(fileName);

    await file.save(req.file.buffer, {
      metadata: {
        contentType: req.file.mimetype,
        metadata: {
          uploadedBy: uid,
          originalName: req.file.originalname,
        },
      },
    });

    // Make public
    await file.makePublic();
    const publicUrl = getStorage().isMock
      ? `${req.protocol}://${req.get('host')}/uploads/${fileName.replace(/\//g, '_')}`
      : `https://storage.googleapis.com/${bucket.name}/${fileName}`;

    res.json({
      url: publicUrl,
      fileName,
      size: req.file.size,
    });
  } catch (err) {
    console.error('[Upload] Image error:', err);
    res.status(500).json({ error: 'Không thể tải ảnh lên' });
  }
});

// ─── POST /api/upload/avatar ────────────────────────────────
router.post('/avatar', upload.single('avatar'), async (req, res) => {
  try {
    if (!req.file) {
      return res.status(400).json({ error: 'Không có file ảnh' });
    }

    const uid = req.user.uid;
    const bucket = getStorage().bucket();
    const ext = req.file.originalname.split('.').pop() || 'jpg';
    const fileName = `users/${uid}/avatar.${ext}`;
    const file = bucket.file(fileName);

    await file.save(req.file.buffer, {
      metadata: {
        contentType: req.file.mimetype,
      },
    });

    await file.makePublic();
    const publicUrl = getStorage().isMock
      ? `${req.protocol}://${req.get('host')}/uploads/${fileName.replace(/\//g, '_')}`
      : `https://storage.googleapis.com/${bucket.name}/${fileName}`;

    // Update user profile photo
    const { getAuth, getFirestore } = require('../config/firebase');
    try {
      await getAuth().updateUser(uid, { photoURL: publicUrl });
    } catch (e) {
      console.warn('[Upload] Could not update Auth photoURL:', e.message);
    }

    // Update Firestore profile
    const db = getFirestore();
    await db.collection('users').doc(uid).set({ photoURL: publicUrl }, { merge: true });

    res.json({ url: publicUrl });
  } catch (err) {
    console.error('[Upload] Avatar error:', err);
    res.status(500).json({ error: 'Không thể tải ảnh đại diện' });
  }
});

module.exports = router;
