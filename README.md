# 📝 My Note — Ứng dụng Ghi Chú Flutter

<div align="center">

![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter)
![Dart](https://img.shields.io/badge/Dart-3.x-0175C2?logo=dart)
![Firebase](https://img.shields.io/badge/Firebase-FFCA28?logo=firebase&logoColor=black)
![Node.js](https://img.shields.io/badge/Node.js-Express-339933?logo=node.js)
![SQLite](https://img.shields.io/badge/SQLite-sqflite-003B57?logo=sqlite)

**Đồ án môn học Mobile App Development**

</div>

---

## 👥 Thông tin nhóm

|             | Thông tin              |
| ----------- | ---------------------- |
| **Nhóm**    | Nhóm 13                |
| **Môn học** | Lập trình Mobile (N02) |

### Thành viên

| STT | Họ và tên         |   MSSV   |
| :-: | ----------------- | :------: |
|  1  | Nguyễn Tuấn Thiền | 23010571 |
|  2  | Đặng Việt Anh     | 23010689 |
|  3  | Đỗ Trung Kiên     | 23010516 |

---

## 📖 Giới thiệu

**My Note** là ứng dụng ghi chú đa năng được xây dựng bằng Flutter, hỗ trợ đồng bộ dữ liệu thời gian thực qua Firebase Firestore. Ứng dụng cho phép người dùng tạo, quản lý và chia sẻ ghi chú với nhiều định dạng phong phú.

---

## ✨ Tính năng chính

### 📋 Quản lý ghi chú

- ✅ **Ghi chú văn bản** — soạn thảo rich text với Flutter Quill (in đậm, in nghiêng, gạch chân, gạch ngang)
- ✅ **Checklist** — ghi chú dạng danh sách việc cần làm
- ✅ **Sticky note** — ghi chú màu sắc kiểu giấy nhớ
- ✅ **Ghi chú mua sắm** — danh sách shopping chuyên biệt
- ✅ **Ghi chú nhắc nhở** — tích hợp lịch nhắc
- ✅ **Ghim ghi chú** — đưa ghi chú quan trọng lên đầu
- ✅ **Yêu thích** — đánh dấu ghi chú yêu thích
- ✅ **Thùng rác** — khôi phục ghi chú đã xóa

### 🗂️ Tổ chức

- ✅ **Tag / nhãn** — gắn nhãn và lọc theo tag
- ✅ **Thư mục** — phân loại ghi chú theo folder
- ✅ **Tìm kiếm** — tìm kiếm nhanh theo nội dung
- ✅ **Lọc & sắp xếp** — theo thời gian, loại ghi chú

### 🔊 Media

- ✅ **Ghi âm** — nhúng file âm thanh vào ghi chú rich text
- ✅ **Hình ảnh** — chèn ảnh từ gallery hoặc camera
- ✅ **Upload ảnh** — lưu trữ ảnh qua backend Node.js

### 🔄 Đồng bộ & chia sẻ

- ✅ **Realtime sync** — đồng bộ ghi chú giữa các thiết bị qua Firebase Firestore
- ✅ **Offline first** — hoạt động không cần mạng nhờ SQLite local
- ✅ **Chia sẻ ghi chú** — chia sẻ với người dùng khác
- ✅ **Bình luận** — nhận xét trên ghi chú được chia sẻ
- ✅ **Social explore** — xem ghi chú công khai từ người dùng khác

### 👤 Tài khoản

- ✅ **Đăng nhập Google** — nhanh và tiện lợi
- ✅ **Đăng nhập Email Link** — không cần mật khẩu (Passwordless)
- ✅ **Thống kê** — xem số liệu ghi chú của bản thân
- ✅ **Dark mode / Light mode** — tùy chỉnh giao diện

---

## 🏗️ Kiến trúc dự án

```
todoapp/
├── lib/
│   ├── main.dart                  # Entry point, routing
│   ├── firebase_options.dart      # Firebase configuration
│   ├── class/                     # Data models (Note, Tag, Folder...)
│   ├── database/                  # SQLite DAO (NoteDatabase, TagDatabase...)
│   ├── helper/                    # DatabaseHelper, sample data
│   ├── provider/                  # State management (Provider)
│   │   ├── note_provider.dart
│   │   ├── tag_provider.dart
│   │   ├── folder_provider.dart
│   │   ├── theme_provider.dart
│   │   └── social_provider.dart
│   ├── screen/                    # UI Screens (28 màn hình)
│   ├── services/                  # API services, notifications
│   ├── sync/                      # Firebase sync logic
│   ├── theme/                     # Theme configuration
│   └── widget/                    # Reusable widgets
│
└── backend/                       # Node.js Express backend
    ├── server.js                  # Entry point
    ├── routes/                    # API routes
    ├── middleware/                 # Auth middleware
    ├── config/                    # Firebase Admin config
    └── utils/                     # Helpers
```

---

## 🛠️ Công nghệ sử dụng

### Frontend (Flutter)

| Thư viện                       | Chức năng                    |
| ------------------------------ | ---------------------------- |
| `flutter`                      | Framework chính              |
| `firebase_auth`                | Xác thực người dùng          |
| `cloud_firestore`              | Đồng bộ realtime             |
| `sqflite`                      | Database offline (SQLite)    |
| `provider`                     | State management             |
| `flutter_quill`                | Rich text editor             |
| `audioplayers` + `record`      | Ghi âm & phát nhạc           |
| `image_picker` + `file_picker` | Chọn ảnh/file                |
| `flutter_local_notifications`  | Thông báo local              |
| `google_sign_in`               | Đăng nhập Google             |
| `google_fonts`                 | Typography (Roboto, Lobster) |
| `share_plus`                   | Chia sẻ nội dung             |
| `connectivity_plus`            | Kiểm tra kết nối mạng        |

### Backend (Node.js)

| Công nghệ            | Chức năng                        |
| -------------------- | -------------------------------- |
| `Express.js`         | REST API framework               |
| `Firebase Admin SDK` | Xác thực & Firestore server-side |
| `Multer`             | Upload file ảnh                  |
| `Render.com`         | Hosting backend                  |

### Cơ sở dữ liệu

| Database               | Vai trò                                   |
| ---------------------- | ----------------------------------------- |
| **SQLite** (local)     | Lưu trữ offline, hoạt động không cần mạng |
| **Firebase Firestore** | Đồng bộ realtime giữa các thiết bị        |

---

## ⚙️ Cài đặt & Chạy dự án

### Yêu cầu hệ thống

- Flutter SDK `>=3.9.2`
- Dart SDK `>=3.9.2`
- Android Studio / VS Code
- Node.js `>=18.x` (cho backend)
- Tài khoản Firebase

### 1. Clone dự án

```bash
git clone https://github.com/<your-repo>/todoapp.git
cd todoapp
```

### 2. Cài đặt Flutter dependencies

```bash
flutter pub get
```

### 3. Cấu hình Firebase

- Đảm bảo file `android/app/google-services.json` đã có (project `mobile-final-3`)
- File `lib/firebase_options.dart` đã được cấu hình sẵn

#### Hướng dẫn lấy Base64 Service Account cho Backend:
1. Truy cập **Firebase Console** -> Cài đặt dự án (Project Settings) -> Tài khoản dịch vụ (Service Accounts).
2. Nhấp vào **Tạo khóa riêng mới (Generate new private key)** để tải file JSON chứa thông tin tài khoản dịch vụ.
3. Mã hóa nội dung file JSON đó sang chuỗi Base64:
   - Trên Windows (PowerShell):
     ```powershell
     [Convert]::ToBase64String([System.IO.File]::ReadAllBytes("duong/dan/den/file-key.json"))
     ```
   - Trên Linux/macOS:
     ```bash
     base64 -i file-key.json
     ```
4. Copy chuỗi kết quả thu được dán vào giá trị `FIREBASE_SERVICE_ACCOUNT` trong file `.env`.

### 4. Chạy ứng dụng Flutter

```bash
# Kiểm tra các thiết bị đang kết nối (Emulator, thiết bị thật, Chrome...)
flutter devices

# Chạy debug trên thiết bị cụ thể
flutter run -d <ID_thiet_bi>

# Clean build nếu có lỗi
flutter clean && flutter pub get && flutter run
```

### 5. Chạy Backend (tuỳ chọn)

```bash
cd backend
npm install

# Tạo file .env từ mẫu
cp .env.example .env
# Điền các biến môi trường vào .env

# Chạy chế độ phát triển (watch mode tự động reload khi sửa code)
npm run dev

# Hoặc khởi chạy thông thường
npm start
```

#### Biến môi trường backend (`.env`)

```env
PORT=3000
FIREBASE_PROJECT_ID=mobile-final-3
FIREBASE_SERVICE_ACCOUNT=<base64 service account JSON>
CORS_ORIGIN=*
```

### 6. Cấu hình kết nối giữa App và Backend

Để ứng dụng di động giao tiếp được với Backend cục bộ (localhost), bạn cần cấu hình lại URL máy chủ trong ứng dụng:

1. **Khởi chạy Backend** trên máy tính của bạn (mặc định chạy tại cổng `3000`).
2. Mở ứng dụng trên thiết bị/trình giả lập, truy cập màn hình **Cài đặt (Settings)** từ menu.
3. Ở mục **Máy chủ & Kết nối**, nhập địa chỉ API tương ứng:
   - Nếu dùng **Android Emulator**: Nhập `http://10.0.2.2:3000/api` (Địa chỉ IP loopback của máy chủ chạy máy ảo).
   - Nếu dùng **iOS Simulator** hoặc chạy **Web**: Nhập `http://localhost:3000/api`.
   - Nếu dùng **thiết bị thật (Physical Device)**: Nhập địa chỉ IP mạng nội bộ của máy tính của bạn (Ví dụ: `http://192.168.1.5:3000/api`). Đảm bảo điện thoại và máy tính kết nối chung mạng Wi-Fi.
4. Nhấn **Lưu máy chủ** và khởi động lại ứng dụng để áp dụng.

---

## 📱 Màn hình ứng dụng

| Màn hình          | Mô tả                              |
| ----------------- | ---------------------------------- |
| **Onboarding**    | Giới thiệu app lần đầu             |
| **Login**         | Đăng nhập Google / Email           |
| **Home**          | Danh sách ghi chú chính            |
| **Detail**        | Xem/sửa ghi chú văn bản            |
| **Rich Detail**   | Soạn thảo rich text + ghi âm + ảnh |
| **Todo List**     | Checklist tương tác                |
| **Sticky Editor** | Tạo sticky note màu sắc            |
| **Favorites**     | Ghi chú yêu thích                  |
| **Explore**       | Khám phá ghi chú cộng đồng         |
| **Folders**       | Quản lý thư mục                    |
| **Tags**          | Quản lý nhãn                       |
| **Search**        | Tìm kiếm toàn văn                  |
| **Shared Notes**  | Ghi chú được chia sẻ               |
| **Notifications** | Thông báo hệ thống                 |
| **Statistics**    | Thống kê ghi chú                   |
| **Trash**         | Thùng rác                          |
| **Profile**       | Thông tin tài khoản                |
| **Settings**      | Cài đặt ứng dụng                   |

---

## 🔒 Bảo mật

- Xác thực người dùng qua Firebase Authentication
- Mỗi người dùng chỉ truy cập được dữ liệu của mình (Firestore Security Rules)
- Backend API yêu cầu Firebase ID Token hợp lệ
- Không lưu mật khẩu (sử dụng Google OAuth + Passwordless Email)

<div align="center">

**© 2026 Nhóm 13 — Mobile N02 **
Nguyễn Tuấn Thiền · Đặng Việt Anh · Đỗ Trung Kiên

</div>
