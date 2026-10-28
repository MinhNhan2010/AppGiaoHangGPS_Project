# GO-MAU Delivery (`gps_delivery_app`)

Gói mã nguồn ứng dụng đa nền tảng **Flutter & Dart** của hệ thống **GO-MAU Delivery / Giao Hàng Siêu Tốc (GHST)** — bao gồm 4 phân hệ độc lập (**Khách hàng**, **Tài xế**, **Cửa hàng B2B**, **Quản trị viên CMS**) vận hành theo kiến trúc **Offline-First SQLite v8** và đồng bộ đám mây **Supabase PostgreSQL 16 + PostGIS**.

> 📖 **Tài liệu đầy đủ về kiến trúc, sơ đồ hệ thống, thuật toán và toàn bộ tính năng**: Xem tại [`../README.md`](../README.md) ở thư mục gốc của kho lưu trữ.

---

## 1. Khởi chạy nhanh

```powershell
flutter pub get
flutter run -d chrome --web-port=8080
```

- **Cổng Người dùng (Khách hàng / Tài xế / Cửa hàng B2B)**: `http://localhost:8080/`
- **Cổng Quản trị viên độc lập (Admin CMS)**: `http://localhost:8080/admin` (hoặc `http://localhost:8080/#/admin`)
  - Khi hệ thống chưa có quản trị viên nào, cổng `/admin` sẽ hiển thị màn hình **Thiết lập quản trị viên đầu tiên**. Không sử dụng tài khoản hay mật khẩu dùng chung mặc định.

---

## 2. Điểm nhấn tính năng trong phiên bản hiện tại

- **Giao nhận định vị GPS thời gian thực**: Bản đồ 3D nghiêng `55°`, lọc nhiễu Kalman 2D, chống Fake GPS 3 lớp, khóa xác nhận giao hàng POD `<= 100m` kèm mã OTP 4 chữ số và chia sẻ hành trình trực tiếp (*Live Share Tracking*).
- **Đa gói cước, Ghép đơn 2H & Lộ trình đa điểm (`2-Opt TSP`)**: Tối ưu thứ tự nhiều điểm giao hàng, hỗ trợ chuyến khứ hồi 2 chiều và tùy chọn ưu tiên **Xe máy điện không khói (EV)** + đóng góp **Quỹ Xanh**.
- **Gợi ý Ăn uống thông minh (`GrabFood`)**: Đề xuất quán ăn theo bữa & khoảng cách GPS, tự động tính phụ phí túi giữ lạnh món đá/kem và đồng bộ thực đơn trực tiếp từ phân hệ Cửa hàng B2B.
- **Sự kiện Khuyến mãi `Shopee × Grab`**: Điểm danh 7 ngày tích `GHST Xu`, săn mã Khung Giờ Vàng Flash Sale, Nhiệm vụ `GrabChallenges`, **Vòng Xoay May Mắn 8 ô** và **Bàn Gacha 6 Hộp Mù Bí Ẩn** (`R / SR / SSR`) cấp Voucher thật vào SQLite.

---

## 3. Cấu hình Tùy chọn (Cloud PostGIS & OTP Relay)

- **Supabase PostGIS**: Truyền qua `--dart-define=SUPABASE_URL=...` và `--dart-define=SUPABASE_ANON_KEY=...` (hoặc cấu hình nóng ngay trong cổng Quản trị viên).
- **Email OTP cho bản Web**: Chạy dịch vụ phụ trợ tại [`backend/otp-relay`](backend/otp-relay/README.md) để bảo vệ `SMTP_PASS` ở phía máy chủ, sau đó truyền `--dart-define=OTP_EMAIL_WEBHOOK_URL=http://127.0.0.1:8787/otp-email` và `--dart-define=OTP_EMAIL_WEBHOOK_TOKEN=...`.

---

## 4. Kiểm tra chất lượng mã nguồn

```powershell
flutter analyze
flutter test --reporter compact
flutter build web
```

- Dữ liệu khởi tạo khi chạy ứng dụng hoàn toàn sạch (*Clean Start*); dữ liệu giả lập chỉ phục vụ kiểm thử tự động nằm tách biệt tại `test/fixtures/app_state_test_fixtures.dart`.
