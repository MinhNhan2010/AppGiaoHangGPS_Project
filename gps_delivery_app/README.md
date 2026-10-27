# GO-MAU Delivery

Ứng dụng giao hàng Flutter gồm bốn phân hệ: khách hàng, tài xế, cửa hàng và quản trị viên. Dữ liệu lưu trên thiết bị bằng SQLite; bản web dùng localStorage. Kết nối Supabase là tùy chọn.

## Chạy dự án

~~~sh
flutter pub get
flutter run -d chrome
~~~

Ứng dụng mở vào **Đăng nhập / Đăng ký tài khoản**, dành cho khách hàng, tài xế và cửa hàng. Đăng ký thông thường tạo tài khoản khách hàng. Quản trị viên đăng nhập ở trang web riêng **/#/admin**, có giao diện độc lập và không dùng các luồng đăng nhập của app. Khi chưa có quản trị viên, trang này hiển thị **Thiết lập quản trị viên đầu tiên**. Không có tài khoản hoặc mật khẩu dùng chung. Địa chỉ **/admin** cũng được hỗ trợ nếu máy chủ cấu hình trả về `index.html` cho đường dẫn này.

Supabase nhận cấu hình qua --dart-define=SUPABASE_URL=... và --dart-define=SUPABASE_ANON_KEY=..., hoặc phần cấu hình quản trị. Google OAuth và gửi OTP cần cấu hình nhà cung cấp tương ứng; đăng nhập bằng mật khẩu hoạt động với tài khoản đã tạo trên thiết bị. Bản Web gửi Email OTP qua HTTP relay bằng `--dart-define=OTP_EMAIL_WEBHOOK_URL=https://...` và tùy chọn `--dart-define=OTP_EMAIL_WEBHOOK_TOKEN=...`; endpoint này phải tự gửi email bằng SMTP ở phía máy chủ và cho phép CORS. SMTP 465/587 chỉ được dùng trực tiếp trên Desktop/Mobile.

Backend relay mẫu nằm tại `backend/otp-relay`. Xem `backend/otp-relay/README.md` để chạy relay Gmail và kết nối bản Web.

## Luồng sử dụng

- Khách hàng: tạo đơn, xem cước và chọn ưu đãi, quản lý đơn. Theo dõi GPS, chat, hủy và đánh giá mở từ từng đơn.
- Tài xế: gửi hồ sơ, nhận đơn, theo dõi hành trình và cập nhật tiến độ trong cùng luồng; quản lý thu nhập và yêu cầu rút tiền.
- Cửa hàng: tạo đơn lẻ hoặc nhập CSV, theo dõi đơn. In vận đơn và sửa/hủy mở trực tiếp từ danh sách.
- Quản trị viên: quản lý người dùng, hồ sơ, đơn hàng, bảng giá, tài chính và phân quyền.

Giao diện đặt đơn hiện hỗ trợ tiền mặt/COD. Thanh toán trực tuyến và nạp ví chưa có xác minh từ nhà cung cấp nên không có nút tự xác nhận hoặc tự cộng tiền. Yêu cầu rút tiền là bản ghi chờ xử lý, không phải bằng chứng ngân hàng đã chuyển tiền.

## Dữ liệu sạch

Bản cài mới bắt đầu không có đơn, tài xế, voucher, số dư hay tài liệu KYC mẫu. Bản đồ chỉ đặt dấu tài xế khi đã ghi nhận tọa độ thiết bị; không suy diễn vị trí từ tiến độ đơn. Tài xế chưa được đánh giá không hiển thị điểm mẫu. SLA không lấy thời gian dự kiến thay cho thời gian giao thực tế.

Khi nâng cấp từ bản có demo, migration remove_demo_v1 nhận diện các mẫu cũ bằng nhiều trường, chuyển chúng cùng dữ liệu phụ thuộc sang local_relational_entities với table_name = archived_demo_v1, rồi loại khỏi dữ liệu vận hành. Bản lưu chứa tên bảng và toàn bộ dòng gốc. Dữ liệu khác được giữ lại; các bản ghi đã chỉnh sửa không còn khớp mẫu có thể cần rà soát thủ công.

Dữ liệu mẫu kiểm thử nằm riêng tại test/fixtures/app_state_test_fixtures.dart, không được nạp khi chạy ứng dụng. Không xóa toàn bộ CSDL để làm sạch demo.

## Kiểm tra

~~~sh
flutter analyze
flutter test
flutter build web
~~~

Test clean_start_test.dart kiểm tra khởi tạo sạch, màn hình thiết lập quản trị viên, hồ sơ mới không có dữ liệu giả, GPS và migration giữ dữ liệu thật kể cả khi trùng mã với mẫu cũ. Test widget_test.dart kiểm tra nghiệp vụ và giao diện nhiều kích thước bằng fixtures riêng.
