/**
 * End-to-end smoke test for the TodoApp social/professional API.
 * Run the server first (npm start), then: node scripts/smoke-test.js
 * Works against the offline mock DB — no Firebase needed.
 */
const BASE = process.env.BASE || 'http://localhost:3000/api';

// Build a fake (unsigned) Firebase-style token the mock auth understands.
function token({ uid, email, name }) {
  const header = Buffer.from(JSON.stringify({ alg: 'none', typ: 'JWT' })).toString('base64');
  const payload = Buffer.from(JSON.stringify({ sub: uid, email, name })).toString('base64');
  return `${header}.${payload}.sig`;
}

const ALICE = token({ uid: 'alice', email: 'alice@example.com', name: 'Alice' });
const BOB = token({ uid: 'bob', email: 'bob@example.com', name: 'Bob' });

let pass = 0, fail = 0;
function ok(cond, label, extra) {
  if (cond) { pass++; console.log(`  ✅ ${label}`); }
  else { fail++; console.log(`  ❌ ${label}`, extra ? JSON.stringify(extra) : ''); }
}

async function api(tok, method, path, body) {
  const res = await fetch(BASE + path, {
    method,
    headers: { 'Content-Type': 'application/json', ...(tok ? { Authorization: `Bearer ${tok}` } : {}) },
    body: body ? JSON.stringify(body) : undefined,
  });
  let data = null;
  try { data = await res.json(); } catch (_) {}
  return { status: res.status, data };
}

(async () => {
  console.log('\n=== HEALTH ===');
  ok((await api(null, 'GET', '/health')).status === 200, 'health check');

  console.log('\n=== PROFILES / DISCOVERY ===');
  await api(ALICE, 'GET', '/users/profile');
  await api(BOB, 'GET', '/users/profile');
  let r = await api(BOB, 'GET', '/social/users/search?q=alice');
  ok(r.data.users.some((u) => u.uid === 'alice'), 'Bob can find Alice by search');

  console.log('\n=== NOTES CRUD ===');
  r = await api(ALICE, 'POST', '/notes', { title: 'Cách học Flutter', content: 'Bắt đầu với widget cơ bản' });
  const note1 = r.data.id;
  ok(r.status === 201 && note1, 'Alice creates a note');
  r = await api(ALICE, 'POST', '/notes', { title: 'Ghi chú phụ', content: 'nội dung khác' });
  const note2 = r.data.id;
  r = await api(ALICE, 'GET', '/notes');
  ok(r.data.notes.length === 2, 'Alice lists 2 active notes', r.data.notes.length);
  r = await api(ALICE, 'GET', '/notes/search?q=flutter');
  ok(r.data.notes.length === 1, 'Full-text search finds 1', r.data.notes.length);

  console.log('\n=== VERSION HISTORY ===');
  await api(ALICE, 'PUT', `/notes/${note1}`, { content: 'Phiên bản 2' });
  await api(ALICE, 'PUT', `/notes/${note1}`, { content: 'Phiên bản 3' });
  r = await api(ALICE, 'GET', `/notes/${note1}/versions`);
  ok(r.data.versions.length === 2, 'Two versions snapshotted', r.data.versions.length);
  const oldVid = r.data.versions[r.data.versions.length - 1].id;
  r = await api(ALICE, 'POST', `/notes/${note1}/restore-version/${oldVid}`);
  ok(r.data.content === 'Bắt đầu với widget cơ bản', 'Restored original content', r.data.content);

  console.log('\n=== DUPLICATE ===');
  r = await api(ALICE, 'POST', `/notes/${note1}/duplicate`);
  ok(r.status === 201 && r.data.title.includes('bản sao'), 'Duplicate created');

  console.log('\n=== PUBLISH → FEED ===');
  r = await api(ALICE, 'POST', `/notes/${note1}/publish`);
  ok(r.data.isPublished === true, 'Alice publishes note1');
  r = await api(BOB, 'GET', '/social/explore');
  ok(r.data.posts.some((p) => p.id === note1), 'note1 appears in explore', r.data.posts.map((p) => p.id));

  console.log('\n=== FOLLOW ===');
  r = await api(BOB, 'POST', '/social/follow/alice');
  ok(r.data.following === true, 'Bob follows Alice');
  r = await api(BOB, 'GET', '/social/feed');
  ok(r.data.posts.some((p) => p.id === note1), 'note1 in Bob\'s following-feed');
  r = await api(ALICE, 'GET', '/social/followers');
  ok(r.data.users.some((u) => u.uid === 'bob'), 'Alice sees Bob as follower');

  console.log('\n=== LIKES ===');
  r = await api(BOB, 'POST', `/notes/${note1}/like`);
  ok(r.data.liked === true && r.data.likesCount === 1, 'Bob likes note1 → count 1', r.data);
  r = await api(BOB, 'POST', `/notes/${note1}/like`);
  ok(r.data.likesCount === 1, 'Double-like is idempotent', r.data);
  r = await api(BOB, 'GET', `/notes/${note1}/likes`);
  ok(r.data.likers.some((l) => l.uid === 'bob'), 'Likers list includes Bob');

  console.log('\n=== COMMENTS (threaded) ===');
  r = await api(BOB, 'POST', `/notes/${note1}/comments`, { text: 'Bài viết hay! @alice', noteOwnerUid: 'alice' });
  const c1 = r.data.id;
  ok(r.status === 201, 'Bob comments on Alice\'s post');
  r = await api(ALICE, 'POST', `/notes/${note1}/comments`, { text: 'Cảm ơn bạn!', noteOwnerUid: 'alice', parentId: c1 });
  ok(r.status === 201 && r.data.parentId === c1, 'Alice replies to Bob');
  r = await api(BOB, 'POST', `/notes/${note1}/comments/${c1}/like?ownerUid=alice`);
  ok(r.data.liked === true, 'Comment can be liked');
  r = await api(ALICE, 'GET', `/notes/${note1}/comments?ownerUid=alice`);
  ok(r.data.comments.length === 2, '2 comments total', r.data.comments.length);

  console.log('\n=== BOOKMARKS ===');
  r = await api(BOB, 'POST', `/notes/${note1}/bookmark`);
  ok(r.data.bookmarked === true, 'Bob bookmarks note1');
  r = await api(BOB, 'GET', '/notes/bookmarks');
  ok(r.data.posts.some((p) => p.id === note1), 'Bookmark appears in list');

  console.log('\n=== NOTIFICATIONS ===');
  r = await api(ALICE, 'GET', '/notifications/unread-count');
  ok(r.data.count >= 3, `Alice has unread notifications (${r.data.count}): follow+like+comment+mention`, r.data);
  r = await api(ALICE, 'GET', '/notifications');
  const types = r.data.notifications.map((n) => n.type);
  ok(types.includes('follow') && types.includes('like') && types.includes('comment'),
    'Notification types present', types);
  await api(ALICE, 'POST', '/notifications/read-all');
  r = await api(ALICE, 'GET', '/notifications/unread-count');
  ok(r.data.count === 0, 'read-all clears unread', r.data);

  console.log('\n=== TRENDING ===');
  r = await api(BOB, 'GET', '/social/trending');
  ok(r.data.posts[0] && r.data.posts[0].id === note1, 'note1 is trending (most liked)');

  console.log('\n=== PUBLIC PROFILE ===');
  r = await api(BOB, 'GET', '/social/profile/alice');
  ok(r.data.profile.isFollowing === true && r.data.posts.length >= 1, 'Alice profile shows isFollowing + posts');

  console.log('\n=== ARCHIVE ===');
  await api(ALICE, 'POST', `/notes/${note2}/archive`);
  r = await api(ALICE, 'GET', '/notes');
  ok(!r.data.notes.some((n) => n.id === note2), 'Archived note hidden from active');
  r = await api(ALICE, 'GET', '/notes/archived');
  ok(r.data.notes.some((n) => n.id === note2), 'Archived note in archived list');
  await api(ALICE, 'POST', `/notes/${note2}/unarchive`);

  console.log('\n=== TRASH (soft delete / restore / purge) ===');
  await api(ALICE, 'DELETE', `/notes/${note2}`);
  r = await api(ALICE, 'GET', '/notes');
  ok(!r.data.notes.some((n) => n.id === note2), 'Deleted note hidden from active');
  r = await api(ALICE, 'GET', '/notes/trash');
  ok(r.data.notes.some((n) => n.id === note2), 'Deleted note in trash');
  await api(ALICE, 'POST', `/notes/${note2}/restore`);
  r = await api(ALICE, 'GET', '/notes');
  ok(r.data.notes.some((n) => n.id === note2), 'Restored note back in active');
  await api(ALICE, 'DELETE', `/notes/${note2}?permanent=true`);
  r = await api(ALICE, 'GET', `/notes/${note2}`);
  ok(r.status === 404, 'Permanent delete removes note');

  console.log('\n=== UNFOLLOW + UNLIKE counters ===');
  r = await api(BOB, 'DELETE', `/notes/${note1}/like`);
  ok(r.data.likesCount === 0, 'Unlike → count 0', r.data);
  r = await api(BOB, 'DELETE', '/social/follow/alice');
  ok(r.data.following === false, 'Bob unfollows Alice');

  console.log('\n=== STATS ===');
  r = await api(ALICE, 'GET', '/users/stats');
  ok(typeof r.data.totalNotes === 'number' && typeof r.data.wordCount === 'number', 'Stats returns numbers', r.data);

  console.log(`\n──────────────────────────────`);
  console.log(`  RESULT: ${pass} passed, ${fail} failed`);
  console.log(`──────────────────────────────\n`);
  process.exit(fail === 0 ? 0 : 1);
})().catch((e) => { console.error('TEST CRASHED:', e); process.exit(2); });
