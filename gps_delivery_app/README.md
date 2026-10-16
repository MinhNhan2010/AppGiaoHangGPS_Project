# Hệ Thống Ứng Dụng Giao Hàng Định Vị GPS Đa Nền Tảng (`gps_delivery_app`)

Dự án phát triển ứng dụng giao hàng định vị GPS thời gian thực đa nền tảng (Flutter + Supabase PostgreSQL/PostGIS + SQLite Offline Queue), bám sát **100%** tài liệu thiết kế hệ thống [`Design_Document.docx`](../Design_Document.docx) và lược đồ cơ sở dữ liệu [`database_schema.sql`](../database_schema.sql).

---

## 1. Tổng Quan Tiến Trình Hoàn Thiện (`100%`)

| Hạng mục theo `Design_Document.docx` | Số lượng đặc tả | Đã hoàn thiện | Tỷ lệ | Tệp mã nguồn chính |
| :--- | :---: | :---: | :---: | :--- |
| **CSDL PostgreSQL/PostGIS & SQLite Offline** | 16 bảng (3NF + GIST) | **16 / 16 bảng** | **100%** | `../database_schema.sql`, `lib/data/datasources/` |
| **Phân hệ Khách hàng (`UC01`–`UC12`, `UC41`, `UC42`)** | 14 màn hình (`Hình 8.1`–`8.14`) | **14 / 14 màn hình** | **100%** | `lib/presentation/customer/customer_subsystem_views.dart` |
| **Phân hệ Tài xế (`UC13`–`UC21`)** | 9 màn hình (`Hình 8.15`–`8.23`) | **9 / 9 màn hình** | **100%** | `lib/presentation/driver/driver_subsystem_views.dart` |
| **Phân hệ Cửa hàng / B2B Merchant (`UC30`–`UC40`)** | 11 màn hình (`Hình 8.36`–`8.46`) | **11 / 11 màn hình** | **100%** | `lib/presentation/merchant/merchant_subsystem_views.dart` |
| **Phân hệ Quản trị viên / Admin (`UC22`–`UC29`, `UC43`–`UC46`)** | 12 màn hình (`Hình 8.24`–`8.35`) | **12 / 12 màn hình** | **100%** | `lib/presentation/admin/admin_subsystem_views.dart` |
| **Trạng thái Hệ thống & Bản đồ 3D (`Hình 8.47`–`8.51`)** | 5 màn hình | **5 / 5 màn hình** | **100%** | `lib/presentation/widgets/system_state_screens.dart` |
| **Thuật toán GPS, Điều phối & Bảo mật chuyên sâu** | 6 nhóm tính năng | **6 / 6 nhóm** | **100%** | `lib/core/gps/`, `lib/core/utils/` |
| **Kiểm thử Tự động (`TC-01`–`TC-09`) & `flutter analyze`** | 9 kịch bản | **9 / 9 Passed (0 lỗi)** | **100%** | `test/widget_test.dart` |

---

## 2. Danh Mục Tiến Trình Chi Tiết

- [x] **Giai đoạn 0: Khởi tạo Dự án, CSDL PostgreSQL/PostGIS & Hạ tầng Cốt lõi (100%)**
  - [x] Lược đồ `database_schema.sql` gồm 16 bảng chuẩn 3NF, kiểu không gian `GEOGRAPHY(POINT, 4326)`, `GEOGRAPHY(POLYGON, 4326)` và chỉ mục không gian `GIST`.
  - [x] Hệ thống màu sắc & Typography chuẩn thiết kế (`AppColors`, `AppTheme`), `GeoMath` (Haversine, Bearing, Ray-Casting Point-in-Polygon), `KalmanGpsFilter`, `GpsIntegrityValidator`, máy trạng thái đơn hàng `OrderStatus`.
- [x] **Giai đoạn 1: Hệ thống Trạng thái, Điều hướng & Engine Bản đồ 3D (`Hình 8.47` – `Hình 8.51`) (100%)**
  - [x] Onboarding (`Hình 8.47`), Empty State (`Hình 8.48`), Offline Sync Banner & Modal (`Hình 8.49`), Shimmer Skeleton (`Hình 8.50`), Bản đồ 3D Perspective (`Hình 8.51` – góc nghiêng `55°`, khối nhà 3D Extrusion, dải lộ trình `#00B4D8`).
- [x] **Giai đoạn 2: Phân hệ Khách hàng – 14 Màn hình (`Hình 8.1` – `Hình 8.14`) (100%)**
  - [x] `UC01` Đăng nhập OTP, `UC02` Sổ địa chỉ GPS, `UC03`–`UC05` Tạo đơn & Ước tính chi phí (`138.250 VNĐ`), `UC06` Theo dõi GPS trực tuyến, `UC07` Thanh toán đa kênh, `UC08` Lịch sử đơn, `UC09` Đánh giá sao, `UC10` Chat & Gọi ẩn SĐT, `UC11` Kho Voucher, `UC12` Hủy đơn, `UC41` Hồ sơ cá nhân, `UC42` Thông báo đẩy.
- [x] **Giai đoạn 3: Phân hệ Tài xế – 9 Màn hình (`Hình 8.15` – `Hình 8.23`) (100%)**
  - [x] `UC13` Đăng ký eKYC 3 bước, `UC14` Trang chủ Online/Offline, `UC15` Popup nhận đơn đếm ngược `28s`, `UC16` Điều hướng 3D GPS, `UC17` Cập nhật trạng thái + Chụp ảnh POD có Watermark GPS + Khóa Geofence `<= 100m`, `UC18` Ví thu nhập & Rút tiền, `UC19` Lịch sử giao hàng, `UC20` Báo cáo sự cố GPS, `UC21` Thống kê hoạt động Dark Mode.
- [x] **Giai đoạn 4: Phân hệ Cửa hàng / B2B Merchant – 11 Màn hình (`Hình 8.36` – `Hình 8.46`) (100%)**
  - [x] `UC30` Đăng ký đối tác B2B, `UC31` Cấu hình kho GPS & Webhook, `UC32` Tạo đơn lẻ B2B, `UC33` Nhập đơn hàng loạt CSV/Excel, `UC34` In tem vận đơn khổ A6 (`Code-128` Barcode & `21x21` QR Matrix), `UC35`–`UC36` Theo dõi & Xử lý giao lại/hoàn hàng, `UC37`–`UC38` Đối soát & Rút tiền COD, `UC39` Thống kê B2B, `UC40` Khiếu nại đính kèm bằng chứng.
- [x] **Giai đoạn 5: Phân hệ Quản trị viên / Admin Web Portal – 12 Màn hình (`Hình 8.24` – `Hình 8.35`) (100%)**
  - [x] `UC22` Dashboard tổng quan, `UC23` Quản lý người dùng, `UC24` Duyệt hồ sơ tài xế, `UC25` Bản đồ giám sát GPS toàn đội xe, `UC26` Cấu hình bảng giá & Phụ phí, `UC27` Báo cáo doanh thu, `UC28` Trọng tài xử lý khiếu nại, `UC29` Đối soát tài chính & Duyệt rút tiền, `UC43` Quản lý toàn bộ đơn hàng, `UC44` Vẽ đa giác Geofence trực tiếp trên bản đồ, `UC45` Phát thông báo Broadcast, `UC46` Ma trận phân quyền RBAC.

---

## 3. Hướng Dẫn Kiểm Tra & Chạy Ứng Dụng

```bash
# Kiểm tra phân tích tĩnh (0 errors, 0 warnings)
flutter analyze

# Chạy bộ kiểm thử tự động (TC-01 -> TC-09)
flutter test

# Chạy ứng dụng trên Windows / Web / Android / iOS
flutter run
```
