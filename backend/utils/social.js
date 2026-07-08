/**
 * Shared helpers for the social layer: creating notifications, keeping a
 * searchable user index, fetching denormalized author metadata, and counters.
 */
const { getFirestore, getFieldValue } = require('../config/firebase');

/**
 * Make sure a user profile document exists and is indexed for search.
 * Called on most authenticated requests so anyone who has logged in becomes
 * discoverable / followable. Cheap (single merge write only when needed).
 */
async function ensureUserProfile(user) {
  const db = getFirestore();
  const ref = db.collection('users').doc(user.uid);
  const snap = await ref.get();
  const base = {
    uid: user.uid,
    email: user.email || '',
    emailLower: (user.email || '').toLowerCase(),
    displayName: user.name || (user.email || '').split('@')[0] || 'User',
    displayNameLower: (user.name || (user.email || '').split('@')[0] || 'user').toLowerCase(),
    photoURL: user.picture || '',
  };
  if (!snap.exists) {
    await ref.set(
      {
        ...base,
        bio: '',
        followersCount: 0,
        followingCount: 0,
        publishedCount: 0,
        createdAt: new Date().toISOString(),
        settings: {
          language: 'vi',
          defaultView: 'list',
          fontSize: 'medium',
          sortMode: 'editedDesc',
          notificationsEnabled: true,
        },
      },
      { merge: true }
    );
    return base;
  }
  // Keep the search index fields fresh without clobbering user-edited fields.
  const data = snap.data();
  const patch = {};
  if (data.emailLower !== base.emailLower) patch.emailLower = base.emailLower;
  if (!data.displayNameLower) patch.displayNameLower = base.displayNameLower;
  if (data.photoURL !== base.photoURL && base.photoURL) patch.photoURL = base.photoURL;
  if (Object.keys(patch).length) await ref.set(patch, { merge: true });
  return { ...base, ...data };
}

/** Lightweight author metadata for denormalizing onto posts/comments. */
async function getProfileMeta(uid) {
  const db = getFirestore();
  const snap = await db.collection('users').doc(uid).get();
  if (!snap.exists) return { uid, displayName: 'User', photoURL: '' };
  const d = snap.data();
  return { uid, displayName: d.displayName || 'User', photoURL: d.photoURL || '' };
}

/**
 * Create a notification for `recipientUid`. No-op when the actor is the
 * recipient (don't notify yourself). Returns the created notification or null.
 */
async function createNotification({
  recipientUid,
  type, // 'like' | 'comment' | 'reply' | 'follow' | 'share' | 'folder_share' | 'mention'
  actor, // { uid, name, picture }
  noteId = null,
  noteTitle = null,
  commentId = null,
  text = null,
}) {
  if (!recipientUid || recipientUid === actor.uid) return null;
  const db = getFirestore();
  const payload = {
    type,
    actorUid: actor.uid,
    actorName: actor.name || 'Người dùng',
    actorPhoto: actor.picture || '',
    noteId,
    noteTitle: noteTitle || '',
    commentId,
    text: text || '',
    read: false,
    createdAt: new Date().toISOString(),
  };
  const ref = await db
    .collection('users')
    .doc(recipientUid)
    .collection('notifications')
    .add(payload);
  // Maintain an unread counter on the profile for fast badge rendering.
  try {
    await db.collection('users').doc(recipientUid).set(
      { unreadNotifications: getFieldValue().increment(1) },
      { merge: true }
    );
  } catch (_) {}
  return { id: ref.id, ...payload };
}

/** Extract @mentions from free text → list of lowercase handles. */
function extractMentions(text) {
  if (!text) return [];
  const matches = text.match(/@([a-zA-Z0-9_.-]{2,40})/g) || [];
  return [...new Set(matches.map((m) => m.slice(1).toLowerCase()))];
}

/** Build a short plain-text excerpt from (possibly Quill-JSON) note content. */
function buildExcerpt(content, max = 180) {
  if (!content) return '';
  let text = content;
  // flutter_quill stores a JSON delta; pull the "insert" strings out if so.
  try {
    const parsed = JSON.parse(content);
    if (Array.isArray(parsed)) {
      text = parsed.map((op) => (typeof op.insert === 'string' ? op.insert : '')).join('');
    }
  } catch (_) {
    /* plain text */
  }
  text = text.replace(/\s+/g, ' ').trim();
  return text.length > max ? text.slice(0, max) + '…' : text;
}

/** Create / update the denormalized public feed document for a published note. */
async function upsertFeedDoc(note, author) {
  const db = getFirestore();
  await db.collection('feed').doc(note.id).set(
    {
      noteId: note.id,
      authorUid: author.uid,
      authorName: author.displayName || author.name || 'User',
      authorPhoto: author.photoURL || author.picture || '',
      title: note.title || '',
      excerpt: buildExcerpt(note.content),
      color: note.color || 0,
      tags: note.tags || [],
      coverImage: note.coverImage || '',
      likesCount: note.likesCount || 0,
      commentsCount: note.commentsCount || 0,
      publishedAt: note.publishedAt || new Date().toISOString(),
      editedAt: note.editedAt || new Date().toISOString(),
    },
    { merge: true }
  );
}

async function removeFeedDoc(noteId) {
  const db = getFirestore();
  await db.collection('feed').doc(noteId).delete();
}

async function bumpFeedCounter(noteId, field, delta) {
  const db = getFirestore();
  try {
    await db.collection('feed').doc(noteId).set(
      { [field]: getFieldValue().increment(delta) },
      { merge: true }
    );
  } catch (_) {}
}

module.exports = {
  ensureUserProfile,
  getProfileMeta,
  createNotification,
  extractMentions,
  buildExcerpt,
  upsertFeedDoc,
  removeFeedDoc,
  bumpFeedCounter,
};
