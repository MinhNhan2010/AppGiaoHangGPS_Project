import 'dotenv/config';
import crypto from 'node:crypto';
import cors from 'cors';
import express from 'express';
import rateLimit from 'express-rate-limit';
import nodemailer from 'nodemailer';

const port = Number(process.env.PORT || 8787);
const relayToken = process.env.RELAY_TOKEN?.trim() || '';
const smtpUser = process.env.SMTP_USER?.trim() || '';
const smtpPass = process.env.SMTP_PASS?.trim() || '';
const allowedOrigins = (process.env.WEB_ORIGINS || '')
  .split(',')
  .map((origin) => origin.trim())
  .filter(Boolean);

if (!relayToken || !smtpUser || !smtpPass) {
  throw new Error(
    'Thiếu RELAY_TOKEN, SMTP_USER hoặc SMTP_PASS trong file .env',
  );
}

const app = express();
app.disable('x-powered-by');
app.use(express.json({ limit: '10kb' }));
app.use(
  cors({
    origin(origin, callback) {
      // Cho phép curl/health check không có Origin; trình duyệt phải nằm trong allowlist.
      if (!origin || allowedOrigins.includes(origin)) {
        callback(null, true);
        return;
      }
      callback(new Error('Origin không được phép'));
    },
  }),
);

const otpLimiter = rateLimit({
  windowMs: 60 * 1000,
  limit: 10,
  standardHeaders: 'draft-7',
  legacyHeaders: false,
  message: { error: 'Bạn đã gửi quá nhiều yêu cầu OTP. Hãy thử lại sau.' },
});

const mailer = nodemailer.createTransport({
  host: process.env.SMTP_HOST || 'smtp.gmail.com',
  port: Number(process.env.SMTP_PORT || 465),
  secure: Number(process.env.SMTP_PORT || 465) === 465,
  auth: { user: smtpUser, pass: smtpPass },
});

function tokenMatches(value) {
  const received = Buffer.from(value || '');
  const expected = Buffer.from(relayToken);
  return (
    received.length === expected.length &&
    crypto.timingSafeEqual(received, expected)
  );
}

function isEmail(value) {
  return typeof value === 'string' &&
    value.length <= 254 &&
    /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value);
}

app.get('/health', (_req, res) => {
  res.json({ ok: true, service: 'go-mau-otp-relay' });
});

app.post('/otp-email', otpLimiter, async (req, res) => {
  const authorization = req.get('authorization') || '';
  const token = authorization.startsWith('Bearer ')
    ? authorization.slice('Bearer '.length).trim()
    : '';
  if (!tokenMatches(token)) {
    res.status(401).json({ error: 'Unauthorized' });
    return;
  }

  const recipient = typeof req.body?.to === 'string'
    ? req.body.to.trim()
    : '';
  const otp = typeof req.body?.otp === 'string'
    ? req.body.otp.trim()
    : '';
  if (!isEmail(recipient) || !/^\d{6}$/.test(otp)) {
    res.status(400).json({ error: 'Email hoặc OTP không hợp lệ' });
    return;
  }

  try {
    await mailer.sendMail({
      from: `GO-MAU <${smtpUser}>`,
      to: recipient,
      subject: '[GO-MAU] Mã xác thực OTP',
      text: `Mã OTP của bạn là ${otp}. Mã có hiệu lực trong 120 giây.`,
      html: [
        '<div style="font-family:Arial,sans-serif;max-width:460px">',
        '<h2>GO-MAU - Mã xác thực OTP</h2>',
        `<p>Mã xác thực của bạn là: <strong style="font-size:28px;letter-spacing:6px">${otp}</strong></p>`,
        '<p>Mã có hiệu lực trong 120 giây.</p>',
        '</div>',
      ].join(''),
    });
    res.json({ success: true });
  } catch (error) {
    console.error('SMTP delivery failed:', error instanceof Error ? error.message : error);
    res.status(502).json({ error: 'Không gửi được email OTP' });
  }
});

app.use((error, _req, res, _next) => {
  if (error?.message === 'Origin không được phép') {
    res.status(403).json({ error: error.message });
    return;
  }
  console.error('Unhandled relay error:', error);
  res.status(500).json({ error: 'Lỗi máy chủ relay OTP' });
});

app.listen(port, '0.0.0.0', () => {
  console.log(`GO-MAU OTP relay đang chạy tại http://127.0.0.1:${port}`);
});
