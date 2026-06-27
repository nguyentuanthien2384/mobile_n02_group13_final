# TodoApp → Nền tảng ghi chú chuyên nghiệp & mạng xã hội

Tài liệu này mô tả toàn bộ nâng cấp biến ứng dụng ghi chú cơ bản thành một nền tảng ghi chú **chuyên nghiệp + mạng xã hội**, với backend đầy đủ.

## Giao diện mới kiểu "My Notes" (3 chế độ)

Màn hình chính đã được thiết kế lại theo phong cách thẻ ghi chú nhiều màu, gồm **3 chế độ**
chuyển nhanh bằng thanh dưới:

- **MY NOTES** — lưới masonry các thẻ màu, có thể đính kèm ảnh bìa, tiêu đề + nội dung + ngày
- **REMINDER** — thẻ màu có ghim 📌, tiêu đề canh giữa
- **SHOPPING LIST** — thẻ giấy nhớ cam, có tên món + giá tiền

Kèm theo: tiêu đề serif lớn (font Cinzel) đổi theo chế độ, ô tìm kiếm + nút hồ sơ,
nút **+** để thêm, và **trình soạn nền tối** với bảng chọn màu + nút "Add image" —
bám sát thiết kế mẫu bạn cung cấp.

**Dữ liệu mẫu tự nạp:** lần đầu mở app (khi máy chưa có ghi chú nào), app tự thêm sẵn
~14 mục mẫu (6 ghi chú, 4 nhắc nhở, 4 món mua sắm) để bạn thấy giao diện đầy đủ ngay.

Các file giao diện mới:
- `lib/screen/notes_home_screen.dart` — màn hình chính 3 chế độ
- `lib/screen/sticky_editor_screen.dart` — trình soạn nền tối + chọn màu + thêm ảnh
- `lib/widget/sticky_note_card.dart` — thẻ ghi chú (3 kiểu)
- `lib/widget/masonry_grid.dart` — lưới masonry 2 cột
- `lib/theme/note_palette.dart` — bảng màu + định dạng ngày tiếng Việt
- `lib/helper/sample_data.dart` — nạp dữ liệu mẫu cục bộ lần đầu

Model `Note` được bổ sung 3 trường: `noteType` (note/reminder/shopping), `price`, `imagePath`
(đã thêm cột tương ứng vào SQLite, tự migrate an toàn).

---

## Tổng quan những gì đã thêm

**Tính năng chuyên nghiệp (professional)**
- Tìm kiếm toàn văn (full-text search) trên ghi chú
- Thùng rác (soft-delete) — xóa tạm, khôi phục, xóa vĩnh viễn, dọn sạch
- Lưu trữ (archive / unarchive)
- Lịch sử phiên bản (version history) — tự động lưu mỗi lần sửa nội dung, tối đa 20 bản, khôi phục bản cũ
- Nhân bản ghi chú (duplicate)
- Thống kê người dùng (số ghi chú, từ, lượt thích, người theo dõi…)
- Nhắc nhở (reminderAt) và ảnh bìa (coverImage)

**Tính năng mạng xã hội (social)**
- Đăng ghi chú công khai (publish) → xuất hiện trong feed
- Theo dõi / bỏ theo dõi người dùng (follow graph)
- 3 luồng bài viết: **Đang theo dõi** (following feed), **Khám phá** (explore), **Xu hướng** (trending)
- Thích bài viết (like) — idempotent, có bộ đếm
- Lưu bài viết (bookmark)
- Bình luận phân luồng (threaded), có thể thích / sửa / xóa bình luận
- Nhắc tên @mention
- Thông báo (notifications): like, comment, reply, follow, share, mention — kèm bộ đếm chưa đọc
- Hồ sơ công khai (public profile) với nút theo dõi
- Tìm kiếm người dùng

---

## Backend

### Cách chạy

```bash
cd backend
npm install
npm start          # chạy trên cổng 3000
```

Backend tự động chạy ở **chế độ mock offline** khi không có thông tin Firebase
(dữ liệu lưu trong thư mục `backend/mock_db/`). Để dùng Firebase thật, đặt biến
môi trường thông tin xác thực hoặc file `serviceAccountKey.json`.

### Kiểm thử

Một bộ kiểm thử end-to-end đầy đủ đã được viết và **chạy thành công 36/36**:

```bash
cd backend
npm start                       # cửa sổ 1
node scripts/smoke-test.js      # cửa sổ 2
```

### Dữ liệu mẫu (sample data)

Dự án đã kèm sẵn **dữ liệu mẫu phong phú** trong `backend/mock_db/` để bạn mở app
lên là thấy ngay nội dung ở tab **Khám phá**, **Xu hướng** và khi tìm kiếm người dùng:

- 6 người dùng mẫu (An, Bình, Chi, Dũng, Hà, Minh) với chủ đề khác nhau
  (lập trình, du lịch, nấu ăn, tài chính, sách, năng suất)
- 18 ghi chú (16 bài đã đăng công khai) — nội dung định dạng đẹp (tiêu đề, gạch đầu dòng, checklist)
- 22 lượt theo dõi, 55 lượt thích, 20 bình luận & trả lời phân luồng, 8 bài được lưu
- Nhiều thông báo (like / comment / follow / mention)

> Dữ liệu mẫu chỉ hiển thị khi backend chạy ở **chế độ mock** (mặc định khi không có
> Firebase). Nội dung công khai của các tài khoản mẫu sẽ xuất hiện trong **Khám phá /
> Xu hướng / tìm người dùng**, và bạn có thể theo dõi, thích, bình luận với họ.

**Tạo lại dữ liệu mẫu** bất cứ lúc nào:

```bash
cd backend
npm start                       # cửa sổ 1
node scripts/seed-data.js       # cửa sổ 2 — ghi vào mock_db
```

Tài khoản mẫu: `an@demo.vn`, `binh@demo.vn`, `chi@demo.vn`, `dung@demo.vn`,
`ha@demo.vn`, `minh@demo.vn`.


### Các endpoint mới

Tất cả endpoint nằm dưới `/api` và yêu cầu header `Authorization: Bearer <token>`.

#### Ghi chú — `/api/notes`
| Method | Path | Mô tả |
|---|---|---|
| GET | `/notes?filter=active\|trash\|archived\|all` | Danh sách ghi chú (mặc định `active`) |
| GET | `/notes/search?q=` | Tìm kiếm toàn văn |
| GET | `/notes/trash` | Ghi chú trong thùng rác |
| DELETE | `/notes/trash/empty` | Dọn sạch thùng rác |
| GET | `/notes/archived` | Ghi chú đã lưu trữ |
| GET | `/notes/bookmarks` | Bài viết đã lưu |
| DELETE | `/notes/:id` | Xóa mềm (vào thùng rác) |
| DELETE | `/notes/:id?permanent=true` | Xóa vĩnh viễn |
| POST | `/notes/:id/restore` | Khôi phục từ thùng rác |
| POST | `/notes/:id/archive` · `/unarchive` | Lưu trữ / bỏ lưu trữ |
| POST | `/notes/:id/duplicate` | Nhân bản |
| GET | `/notes/:id/versions` | Lịch sử phiên bản |
| POST | `/notes/:id/restore-version/:vid` | Khôi phục phiên bản |
| POST | `/notes/:id/publish` · `/unpublish` | Đăng / gỡ bài công khai |
| POST/DELETE | `/notes/:id/like` | Thích / bỏ thích |
| GET | `/notes/:id/likes` | Danh sách người thích |
| POST/DELETE | `/notes/:id/bookmark` | Lưu / bỏ lưu |
| GET/POST | `/notes/:id/comments` | Xem / thêm bình luận (hỗ trợ `parentId` để trả lời) |
| PUT/DELETE | `/notes/:id/comments/:cid` | Sửa / xóa bình luận |
| POST | `/notes/:id/comments/:cid/like` | Thích bình luận |

*(Các endpoint cũ — tạo, sửa, chia sẻ riêng tư, chia sẻ link công khai — vẫn giữ nguyên.)*

#### Mạng xã hội — `/api/social`
| Method | Path | Mô tả |
|---|---|---|
| POST/DELETE | `/social/follow/:uid` | Theo dõi / bỏ theo dõi |
| GET | `/social/following` · `/followers` | Danh sách đang theo dõi / người theo dõi |
| GET | `/social/users/search?q=` | Tìm người dùng |
| GET | `/social/suggestions` | Gợi ý người dùng |
| GET | `/social/profile/:uid` | Hồ sơ công khai + bài viết |
| GET | `/social/feed` | Feed từ người đang theo dõi |
| GET | `/social/explore?after=` | Bài viết công khai mới nhất (phân trang) |
| GET | `/social/trending` | Bài viết nhiều lượt thích nhất |

#### Thông báo — `/api/notifications`
| Method | Path | Mô tả |
|---|---|---|
| GET | `/notifications` | Danh sách thông báo |
| GET | `/notifications/unread-count` | Số chưa đọc |
| POST | `/notifications/:id/read` · `/read-all` | Đánh dấu đã đọc |
| DELETE | `/notifications/:id` | Xóa thông báo |

#### Người dùng — `/api/users`
| Method | Path | Mô tả |
|---|---|---|
| GET | `/users/stats` | Thống kê (số ghi chú, từ, lượt thích, người theo dõi…) |

### Kiến trúc dữ liệu

- `users/{uid}/notes/{noteId}` — ghi chú, với subcollection `shares`, `comments`, `versions`
- `users/{uid}/{following, followers, notifications, bookmarks}`
- `feed/{noteId}` — bản sao denormalized của bài đã đăng (để feed/explore/trending nhanh), với subcollection `likes`
- `users/{uid}` — hồ sơ tìm kiếm được (emailLower, displayNameLower, các bộ đếm)

Lớp mock Firestore (`config/mockFirebase.js`) hỗ trợ đầy đủ `FieldValue` (increment,
arrayUnion…), truy vấn `.where().orderBy().limit()`, `collectionGroup`, `batch()` và
`runTransaction()` — nên backend chạy y hệt nhau ở chế độ mock và Firebase thật.

---

## Flutter (app)

> ⚠️ **Lưu ý quan trọng:** Phần Flutter được viết theo đúng quy ước sẵn có của dự án
> (Provider, `ApiService`, Material) nhưng **chưa được biên dịch** trong môi trường này
> vì không có Flutter SDK. Bạn cần chạy `flutter pub get` rồi `flutter run` trên máy của
> mình. Không cần thêm package mới — mọi thư viện cần thiết đã có trong `pubspec.yaml`.

### File mới
- `lib/class/social_user.dart`, `feed_post.dart`, `app_notification.dart` — model
- `lib/services/social_api_service.dart` — feed, follow, profile, search
- `lib/services/notification_api_service.dart` — thông báo
- `lib/provider/social_provider.dart` — đếm thông báo chưa đọc (badge)
- `lib/widget/post_card.dart` — thẻ bài viết (like/comment/bookmark)
- `lib/screen/explore_screen.dart` — hub mạng xã hội (3 tab + tìm kiếm + chuông thông báo)
- `lib/screen/post_detail_screen.dart` — bài viết + bình luận phân luồng
- `lib/screen/notifications_screen.dart` — danh sách thông báo
- `lib/screen/public_profile_screen.dart` — hồ sơ người khác + nút theo dõi

### File đã sửa
- `lib/class/note.dart` — thêm trường `isPublished, likesCount, commentsCount, archived, deleted`
- `lib/class/comment.dart` — thêm `parentId, likesCount, liked`
- `lib/services/note_api_service.dart` — thêm các phương thức publish, like, bookmark, trash, archive, version, duplicate, search, bình luận phân luồng
- `lib/screen/main_shell.dart` — thêm tab **Khám phá** + badge thông báo
- `lib/main.dart` — đăng ký `SocialProvider`

### Nút quay lại (back)
Mọi màn hình chi tiết đều được mở bằng `Navigator.push`/`pushNamed` nên **luôn có nút
quay lại** (mũi tên trắng ở góc trái AppBar) để trở về trang trước — bao gồm xem ghi
chú, danh sách việc, thống kê, thùng rác… Ba màn hình mạng xã hội mới (chi tiết bài
viết, hồ sơ người dùng, thông báo) đã được thêm nút quay lại hiển thị rõ ràng.

### Việc có thể làm thêm (tùy chọn)
Các màn hình sẵn có (`rich_detail_screen.dart`, `note_card.dart`, `trash_screen.dart`,
`statistics_screen.dart`) có thể được nối thêm các nút **Đăng bài / Lịch sử phiên bản /
Nhân bản / Lưu trữ** và dùng các endpoint thùng rác + thống kê mới. Toàn bộ phương thức
service đã sẵn sàng để gọi.
