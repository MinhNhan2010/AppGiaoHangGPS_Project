# GO-MAU OTP relay

Backend này nhận yêu cầu gửi Email OTP từ Flutter Web rồi gửi email bằng Gmail SMTP. App Password chỉ nằm trong backend, không nằm trong JavaScript của trình duyệt.

## Cài đặt

```powershell
cd gps_delivery_app/backend/otp-relay
npm install
Copy-Item .env.example .env
```

Mở `.env` và điền:

- `SMTP_USER`: Gmail dùng để gửi thư.
- `SMTP_PASS`: Gmail App Password 16 ký tự.
- `RELAY_TOKEN`: chuỗi ngẫu nhiên riêng cho relay.
- `WEB_ORIGINS`: domain chạy Flutter Web, phân tách bằng dấu phẩy.

Không dùng mật khẩu Gmail thông thường và không commit `.env`.

## Chạy

```powershell
npm start
```

Kiểm tra:

```powershell
Invoke-RestMethod http://127.0.0.1:8787/health
```

## Chạy Flutter Web

Từ thư mục `gps_delivery_app`:

```powershell
flutter run -d chrome `
  --dart-define=OTP_EMAIL_WEBHOOK_URL=http://127.0.0.1:8787/otp-email `
  --dart-define=OTP_EMAIL_WEBHOOK_TOKEN=gia-tri-RELAY_TOKEN
```

Khi deploy, dùng URL HTTPS của backend và thêm domain production vào `WEB_ORIGINS`.
