/**
 * Seed dữ liệu mẫu cho TodoApp.
 *
 * Cách dùng:
 *   1) Mở terminal 1:  cd backend && npm start
 *   2) Mở terminal 2:  cd backend && node scripts/seed-data.js
 *
 * Script gọi thẳng vào API thật (đã được kiểm thử) nên dữ liệu sinh ra
 * giống y hệt dữ liệu app đọc. Chạy ở chế độ mock => lưu vào backend/mock_db/.
 *
 * Sau khi seed, mở app (backend chạy mock mode) là thấy ngay nội dung ở
 * tab "Khám phá" / "Xu hướng" và tìm kiếm người dùng.
 */
const BASE = process.env.BASE || 'http://localhost:3000/api';

// ─── Token giả mà mock-auth hiểu được (header.payload.sig) ──
function token({ uid, email, name }) {
  const header = Buffer.from(JSON.stringify({ alg: 'none', typ: 'JWT' })).toString('base64');
  const payload = Buffer.from(JSON.stringify({ sub: uid, email, name })).toString('base64');
  return `${header}.${payload}.sig`;
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

// ─── Bộ dựng nội dung Quill Delta (để hiển thị đẹp trong editor) ──
const h1 = (t) => [{ insert: t }, { insert: '\n', attributes: { header: 1 } }];
const h2 = (t) => [{ insert: t }, { insert: '\n', attributes: { header: 2 } }];
const p = (t) => [{ insert: t + '\n' }];
const bold = (t) => [{ insert: t, attributes: { bold: true } }];
const bullet = (t) => [{ insert: t }, { insert: '\n', attributes: { list: 'bullet' } }];
const check = (t, done) => [{ insert: t }, { insert: '\n', attributes: { list: done ? 'checked' : 'unchecked' } }];
const delta = (...parts) => JSON.stringify(parts.flat());

// ─── Người dùng mẫu ─────────────────────────────────────────
const USERS = {
  an:   token({ uid: 'demo_an',   email: 'an@demo.vn',   name: 'An Nguyễn' }),
  binh: token({ uid: 'demo_binh', email: 'binh@demo.vn', name: 'Bình Trần' }),
  chi:  token({ uid: 'demo_chi',  email: 'chi@demo.vn',  name: 'Chi Lê' }),
  dung: token({ uid: 'demo_dung', email: 'dung@demo.vn', name: 'Dũng Phạm' }),
  ha:   token({ uid: 'demo_ha',   email: 'ha@demo.vn',   name: 'Hà Võ' }),
  minh: token({ uid: 'demo_minh', email: 'minh@demo.vn', name: 'Minh Hoàng' }),
};
const UID = {
  an: 'demo_an', binh: 'demo_binh', chi: 'demo_chi',
  dung: 'demo_dung', ha: 'demo_ha', minh: 'demo_minh',
};

// title, content (delta), tags, published?
const NOTES = {
  an: [
    { title: 'Lộ trình học Flutter trong 30 ngày',
      content: delta(h1('Lộ trình học Flutter trong 30 ngày'),
        p('Mình tổng hợp lại lộ trình tự học Flutter từ con số 0.'),
        h2('Tuần 1: Nền tảng Dart'), bullet('Biến, hàm, class'), bullet('Async/await & Future'),
        h2('Tuần 2: Widget cơ bản'), bullet('Stateless vs Stateful'), bullet('Layout: Row, Column, Stack'),
        p('Kiên trì mỗi ngày 1 giờ là được nhé!')),
      tags: ['flutter', 'lập trình', 'dart'], pub: true },
    { title: 'State management nên chọn cái nào?',
      content: delta(h1('State management nên chọn gì?'),
        p('So sánh nhanh Provider, Riverpod và Bloc cho người mới.'),
        bullet('Provider: đơn giản, dễ bắt đầu'),
        bullet('Riverpod: an toàn hơn, testable'),
        bullet('Bloc: phù hợp dự án lớn')),
      tags: ['flutter', 'kiến trúc'], pub: true },
    { title: 'Mẹo tối ưu hiệu năng ListView',
      content: delta(h1('Tối ưu ListView'),
        p('Dùng ListView.builder thay vì ListView thường khi danh sách dài.'),
        ...bold('Luôn dùng key ổn định cho item.'), p('')),
      tags: ['flutter', 'hiệu năng'], pub: true },
    { title: 'Ghi chú riêng: ý tưởng app cá nhân',
      content: delta(p('Một vài ý tưởng app mình muốn làm năm nay...')),
      tags: ['ý tưởng'], pub: false },
  ],
  binh: [
    { title: 'Lịch trình 3 ngày 2 đêm ở Đà Lạt',
      content: delta(h1('Đà Lạt 3N2Đ'),
        h2('Ngày 1'), bullet('Sáng: Hồ Xuân Hương'), bullet('Chiều: Đồi chè Cầu Đất'),
        h2('Ngày 2'), bullet('Vườn hoa thành phố'), bullet('Chợ đêm Đà Lạt'),
        p('Nhớ mang theo áo ấm vì tối khá lạnh!')),
      tags: ['du lịch', 'đà lạt'], pub: true },
    { title: 'Kinh nghiệm săn vé máy bay giá rẻ',
      content: delta(h1('Săn vé giá rẻ'),
        bullet('Đặt trước 1-2 tháng'),
        bullet('Bay giữa tuần thường rẻ hơn'),
        bullet('Theo dõi các đợt flash sale')),
      tags: ['du lịch', 'tiết kiệm'], pub: true },
    { title: 'Checklist đồ cần mang khi đi phượt',
      content: delta(h1('Checklist đi phượt'),
        check('Giấy tờ tùy thân', true), check('Sạc dự phòng', true),
        check('Áo mưa', false), check('Thuốc cá nhân', false)),
      tags: ['du lịch', 'checklist'], pub: true },
  ],
  chi: [
    { title: 'Công thức phở bò chuẩn vị Hà Nội',
      content: delta(h1('Phở bò Hà Nội'),
        h2('Nguyên liệu'), bullet('Xương bò: 1kg'), bullet('Bánh phở: 500g'), bullet('Gừng, hành, quế, hồi'),
        h2('Cách làm'), p('Ninh xương 6-8 tiếng để nước dùng trong và ngọt.')),
      tags: ['nấu ăn', 'món việt'], pub: true },
    { title: 'Mẹo bảo quản rau củ tươi lâu',
      content: delta(h1('Bảo quản rau củ'),
        bullet('Rau lá: bọc giấy ăn rồi cho vào hộp'),
        bullet('Cà chua: để ngoài, tránh tủ lạnh'),
        bullet('Hành tỏi: nơi khô thoáng')),
      tags: ['nấu ăn', 'mẹo vặt'], pub: true },
    { title: 'Thực đơn ăn healthy 7 ngày',
      content: delta(h1('Thực đơn healthy'),
        p('Cân bằng đạm, tinh bột tốt và rau xanh mỗi bữa.'),
        bullet('Sáng: yến mạch + trứng'),
        bullet('Trưa: ức gà + cơm gạo lứt'),
        bullet('Tối: cá hấp + rau luộc')),
      tags: ['nấu ăn', 'healthy'], pub: true },
  ],
  dung: [
    { title: 'Quy tắc 50/30/20 quản lý chi tiêu',
      content: delta(h1('Quy tắc 50/30/20'),
        bullet('50% nhu cầu thiết yếu'),
        bullet('30% mong muốn cá nhân'),
        bullet('20% tiết kiệm & đầu tư'),
        p('Áp dụng ngay từ tháng lương đầu tiên nhé.')),
      tags: ['tài chính', 'tiết kiệm'], pub: true },
    { title: 'Quỹ dự phòng nên có bao nhiêu?',
      content: delta(h1('Quỹ dự phòng'),
        p('Tối thiểu 3-6 tháng chi phí sinh hoạt.'),
        ...bold('Để riêng, không đụng vào trừ khi khẩn cấp.'), p('')),
      tags: ['tài chính'], pub: true },
    { title: 'Ghi chú riêng: theo dõi đầu tư',
      content: delta(p('Bảng theo dõi danh mục cá nhân...')),
      tags: ['đầu tư'], pub: false },
  ],
  ha: [
    { title: '5 cuốn sách thay đổi tư duy của tôi',
      content: delta(h1('5 cuốn sách hay'),
        bullet('Đắc Nhân Tâm'),
        bullet('Tư Duy Nhanh và Chậm'),
        bullet('Atomic Habits'),
        bullet('Sapiens'),
        bullet('Nhà Giả Kim')),
      tags: ['sách', 'phát triển bản thân'], pub: true },
    { title: 'Cách đọc sách hiệu quả hơn',
      content: delta(h1('Đọc sách hiệu quả'),
        bullet('Ghi chú khi đọc'),
        bullet('Tóm tắt lại sau mỗi chương'),
        bullet('Áp dụng vào thực tế')),
      tags: ['sách', 'kỹ năng'], pub: true },
  ],
  minh: [
    { title: 'Phương pháp Pomodoro tăng năng suất',
      content: delta(h1('Pomodoro'),
        p('Làm việc tập trung 25 phút, nghỉ 5 phút.'),
        bullet('Cứ 4 pomodoro nghỉ dài 15-30 phút'),
        bullet('Tắt thông báo khi làm việc')),
      tags: ['năng suất', 'pomodoro'], pub: true },
    { title: 'Cách lập kế hoạch tuần',
      content: delta(h1('Lập kế hoạch tuần'),
        check('Xác định 3 mục tiêu lớn', true),
        check('Chia nhỏ thành công việc ngày', false),
        check('Đánh giá lại vào cuối tuần', false)),
      tags: ['năng suất', 'kế hoạch'], pub: true },
    { title: 'Dọn dẹp điện thoại để bớt xao nhãng',
      content: delta(h1('Bớt xao nhãng'),
        bullet('Xóa app không cần thiết'),
        bullet('Bật chế độ không làm phiền'),
        bullet('Để màn hình chính tối giản')),
      tags: ['năng suất', 'tối giản'], pub: true },
  ],
};

const created = {}; // user -> [{id, title, pub}]

async function run() {
  console.log('\n🌱 Bắt đầu tạo dữ liệu mẫu...\n');

  // 1) Tạo ghi chú + đăng bài
  for (const [u, notes] of Object.entries(NOTES)) {
    created[u] = [];
    for (const n of notes) {
      const r = await api(USERS[u], 'POST', '/notes', {
        title: n.title, content: n.content, tags: n.tags,
      });
      const id = r.data?.id;
      if (id && n.pub) await api(USERS[u], 'POST', `/notes/${id}/publish`);
      created[u].push({ id, title: n.title, pub: n.pub });
    }
    console.log(`  ✅ ${u}: ${notes.length} ghi chú (${notes.filter((x) => x.pub).length} đã đăng)`);
  }

  // 2) Mạng lưới theo dõi
  const follows = [
    ['binh', 'an'], ['chi', 'an'], ['dung', 'an'], ['ha', 'an'], ['minh', 'an'],
    ['an', 'binh'], ['chi', 'binh'], ['minh', 'binh'],
    ['an', 'chi'], ['binh', 'chi'], ['ha', 'chi'], ['dung', 'chi'],
    ['an', 'dung'], ['minh', 'dung'],
    ['an', 'ha'], ['chi', 'ha'], ['minh', 'ha'],
    ['an', 'minh'], ['binh', 'minh'], ['chi', 'minh'], ['dung', 'minh'], ['ha', 'minh'],
  ];
  for (const [a, b] of follows) await api(USERS[a], 'POST', `/social/follow/${UID[b]}`);
  console.log(`  ✅ ${follows.length} lượt theo dõi`);

  // Tập hợp các bài đã đăng
  const published = [];
  for (const [u, notes] of Object.entries(created)) {
    for (const n of notes) if (n.pub && n.id) published.push({ owner: u, id: n.id, title: n.title });
  }

  // 3) Lượt thích (nhiều người thích các bài khác nhau)
  let likeCount = 0;
  const likers = ['an', 'binh', 'chi', 'dung', 'ha', 'minh'];
  for (const post of published) {
    // mỗi bài được 2-5 người thích (trừ chính chủ)
    const n = 2 + (post.id.charCodeAt(post.id.length - 1) % 4);
    let added = 0;
    for (const liker of likers) {
      if (liker === post.owner) continue;
      if (added >= n) break;
      await api(USERS[liker], 'POST', `/notes/${post.id}/like`);
      added++; likeCount++;
    }
  }
  console.log(`  ✅ ${likeCount} lượt thích`);

  // 4) Bình luận + trả lời (phân luồng)
  const COMMENTS = [
    { by: 'binh', text: 'Bài viết rất hữu ích, cảm ơn bạn @An Nguyễn!' },
    { by: 'chi', text: 'Mình đã áp dụng và thấy hiệu quả ngay.' },
    { by: 'minh', text: 'Cho mình hỏi thêm phần nâng cao với?' },
    { by: 'dung', text: 'Lưu lại để đọc dần, quá chất lượng.' },
    { by: 'ha', text: 'Đúng thứ mình đang tìm, tuyệt vời!' },
  ];
  let commentCount = 0;
  for (const post of published.slice(0, 12)) {
    const c = COMMENTS[commentCount % COMMENTS.length];
    if (c.by === post.owner) continue;
    const r = await api(USERS[c.by], 'POST', `/notes/${post.id}/comments`, {
      text: c.text, noteOwnerUid: UID[post.owner],
    });
    commentCount++;
    // chủ bài trả lời
    const cid = r.data?.id;
    if (cid) {
      await api(USERS[post.owner], 'POST', `/notes/${post.id}/comments`, {
        text: 'Cảm ơn bạn đã ghé đọc nhé!', noteOwnerUid: UID[post.owner], parentId: cid,
      });
      commentCount++;
      // thích bình luận
      await api(USERS[post.owner], 'POST', `/notes/${post.id}/comments/${cid}/like?ownerUid=${UID[post.owner]}`);
    }
  }
  console.log(`  ✅ ${commentCount} bình luận & trả lời`);

  // 5) Bookmark
  let bm = 0;
  for (const post of published.slice(0, 8)) {
    const saver = post.owner === 'an' ? 'minh' : 'an';
    await api(USERS[saver], 'POST', `/notes/${post.id}/bookmark`);
    bm++;
  }
  console.log(`  ✅ ${bm} bài viết được lưu`);

  // 6) Kiểm tra nhanh
  const explore = await api(USERS.an, 'GET', '/social/explore');
  const trending = await api(USERS.binh, 'GET', '/social/trending');
  const notif = await api(USERS.an, 'GET', '/notifications/unread-count');

  console.log('\n──────────────────────────────');
  console.log(`  Bài viết công khai: ${explore.data?.posts?.length ?? 0}`);
  console.log(`  Xu hướng (top):     ${trending.data?.posts?.[0]?.title ?? '-'}`);
  console.log(`  Thông báo của An:   ${notif.data?.count ?? 0} chưa đọc`);
  console.log('──────────────────────────────');
  console.log('\n✅ Hoàn tất! Mở app (backend chạy mock) để xem dữ liệu mẫu.');
  console.log('   Tài khoản mẫu: an@demo.vn, binh@demo.vn, chi@demo.vn,');
  console.log('                  dung@demo.vn, ha@demo.vn, minh@demo.vn\n');
}

run().catch((e) => { console.error('❌ Seed lỗi:', e); process.exit(1); });
