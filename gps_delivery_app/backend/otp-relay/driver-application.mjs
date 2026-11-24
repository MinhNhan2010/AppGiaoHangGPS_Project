import { IntegrationError } from './provider-http.mjs';
import { normalizeDocumentImage, signPrivateObject } from './market-media.mjs';

// Driver partner application gateway: strict request shapes here, authoritative checks in
// public.delivery_driver_application (SQL). Every call runs with the caller's own JWT.
export const DRIVER_APPLICATION_ACTIONS = new Set(['get', 'upload_document', 'submit', 'admin_list', 'admin_get']);
export const DRIVER_DOCUMENT_KINDS = ['citizen_front', 'citizen_back', 'license', 'vehicle_registration', 'portrait'];
export const VEHICLE_TYPES = ['motorbike', 'ev_scooter', 'tricycle', 'van', 'truck'];
const LICENSE_CLASSES = {
  motorbike: ['A1', 'A', 'A2'],
  ev_scooter: ['A1', 'A', 'A2'],
  tricycle: ['A1', 'A', 'B', 'B1', 'B2'],
  van: ['B', 'B1', 'B2', 'C1'],
  truck: ['C1', 'C'],
};
const CONTENT_TYPES = { 'image/jpeg': 'jpeg', 'image/png': 'png', 'image/webp': 'webp' };
const SUBMIT_KEYS = ['vehicle_type', 'license_plate', 'vehicle_brand', 'vehicle_color', 'license_number', 'license_class', 'operating_area', 'documents'];
const UUID = '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}';
const uuidPattern = new RegExp(`^${UUID}$`, 'i');
const documentPathPattern = new RegExp(`^driver-applications/(${UUID})/(${DRIVER_DOCUMENT_KINDS.join('|')})-${UUID}\\.(webp|jpg|jpeg|png)$`);
const MIN_DOCUMENT_BYTES = 1024;
const MAX_DOCUMENT_BYTES = 5_000_000;
const SIGNED_URL_SECONDS = 600;

const invalid = message => new IntegrationError(400, message);
const plainObject = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const exactKeys = (value, keys) => {
  const actual = Object.keys(value);
  return actual.length === keys.length && keys.every(key => Object.hasOwn(value, key));
};
const textLength = value => [...value].length;

export function hasImageSignature(bytes, contentType) {
  if (!Buffer.isBuffer(bytes)) return false;
  if (contentType === 'image/jpeg') return bytes.length >= 3 && bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff;
  if (contentType === 'image/png') return bytes.length >= 8 && bytes.subarray(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]));
  if (contentType === 'image/webp') return bytes.length >= 12 && bytes.toString('latin1', 0, 4) === 'RIFF' && bytes.toString('latin1', 8, 12) === 'WEBP';
  return false;
}

export function decodeDocumentImage(body) {
  if (!plainObject(body) || !exactKeys(body, ['kind', 'content_base64', 'content_type'])) {
    throw invalid('Yêu cầu tải giấy tờ không hợp lệ.');
  }
  if (!DRIVER_DOCUMENT_KINDS.includes(body.kind)) throw invalid('Loại giấy tờ không hợp lệ.');
  if (!Object.hasOwn(CONTENT_TYPES, body.content_type)) throw invalid('Chỉ hỗ trợ ảnh JPEG, PNG hoặc WebP.');
  const raw = body.content_base64;
  if (typeof raw !== 'string' || !raw.length || raw.length > 6_666_668 || raw.length % 4 !== 0 ||
    !/^[A-Za-z0-9+/]+={0,2}$/.test(raw)) throw invalid('Ảnh giấy tờ cần mã hóa base64 hợp lệ, tối đa 5 MB.');
  const bytes = Buffer.from(raw, 'base64');
  if (bytes.toString('base64') !== raw) throw invalid('Ảnh giấy tờ cần mã hóa base64 hợp lệ, tối đa 5 MB.');
  if (bytes.length < MIN_DOCUMENT_BYTES || bytes.length > MAX_DOCUMENT_BYTES) throw invalid('Ảnh giấy tờ cần dung lượng từ 1 KB đến 5 MB.');
  if (!hasImageSignature(bytes, body.content_type)) throw invalid('Nội dung ảnh không đúng định dạng JPEG, PNG hoặc WebP đã khai báo.');
  return { kind: body.kind, bytes, format: CONTENT_TYPES[body.content_type] };
}

export function normalizePlate(value) {
  return String(value).replace(/\s+/g, '').toUpperCase();
}

export function validateSubmission(body, userId) {
  if (!plainObject(body) || !exactKeys(body, SUBMIT_KEYS) ||
    SUBMIT_KEYS.filter(key => key !== 'documents').some(key => typeof body[key] !== 'string') || !plainObject(body.documents)) {
    throw invalid('Hồ sơ đối tác tài xế không hợp lệ.');
  }
  if (!VEHICLE_TYPES.includes(body.vehicle_type)) throw invalid('Loại phương tiện không hợp lệ.');
  const plate = normalizePlate(body.license_plate);
  if (!/^[0-9]{2}[A-Z]{1,2}[0-9]?-?[0-9]{3}\.?[0-9]{2}$/.test(plate) && !/^[0-9]{2}[A-Z]{1,2}[0-9]?-?[0-9]{4}$/.test(plate)) {
    throw invalid('Biển số xe không hợp lệ (ví dụ 59X1-123.45 hoặc 51C-123.45).');
  }
  if (!/^[0-9]{12}$/.test(body.license_number.trim())) throw invalid('Số giấy phép lái xe phải gồm đúng 12 chữ số.');
  const brand = textLength(body.vehicle_brand.trim());
  if (brand < 2 || brand > 60) throw invalid('Hãng và dòng xe cần từ 2 đến 60 ký tự.');
  const color = textLength(body.vehicle_color.trim());
  if (color < 2 || color > 30) throw invalid('Màu xe cần từ 2 đến 30 ký tự.');
  const area = textLength(body.operating_area.trim());
  if (area < 2 || area > 120) throw invalid('Khu vực hoạt động cần từ 2 đến 120 ký tự.');
  if (!LICENSE_CLASSES[body.vehicle_type].includes(body.license_class.trim().toUpperCase())) {
    throw invalid('Hạng giấy phép lái xe không phù hợp với loại phương tiện đã chọn.');
  }
  if (!exactKeys(body.documents, DRIVER_DOCUMENT_KINDS)) {
    throw invalid('Cần đủ 5 ảnh: CCCD mặt trước, CCCD mặt sau, giấy phép lái xe, đăng ký xe và ảnh chân dung.');
  }
  const owner = String(userId || '').toLowerCase();
  for (const kind of DRIVER_DOCUMENT_KINDS) {
    const path = body.documents[kind];
    const match = typeof path === 'string' ? documentPathPattern.exec(path) : null;
    if (!match || match[1] !== owner || match[2] !== kind) throw invalid('Đường dẫn ảnh giấy tờ không hợp lệ.');
  }
  return body;
}

function validateAdminList(body) {
  if (!plainObject(body) || Object.keys(body).some(key => key !== 'state') ||
    (Object.hasOwn(body, 'state') && !['pending', 'approved', 'rejected'].includes(body.state))) {
    throw invalid('Bộ lọc hồ sơ tài xế không hợp lệ.');
  }
  return body;
}

function validateAdminGet(body) {
  if (!plainObject(body) || !exactKeys(body, ['user_id']) || typeof body.user_id !== 'string' || !uuidPattern.test(body.user_id)) {
    throw invalid('Mã tài khoản không hợp lệ.');
  }
  return body;
}

export function createDriverApplicationHandler({ env, fetcher, rpc }) {
  const call = (req, action, details) => rpc(req, 'delivery_driver_application', { p_action: action, p_details: details });

  async function uploadDocument(req) {
    const { kind, bytes, format } = decodeDocumentImage(req.body);
    const owner = String(req.deliveryIdentity.id || '').toLowerCase();
    const reserved = await call(req, 'upload_document', { kind });
    const match = typeof reserved?.path === 'string' ? documentPathPattern.exec(reserved.path) : null;
    if (reserved?.bucket !== 'delivery-private-evidence' || !match || match[1] !== owner || match[2] !== kind || match[3] !== 'webp') {
      throw new IntegrationError(502, 'Phản hồi đặt chỗ lưu giấy tờ không hợp lệ.');
    }
    const image = await normalizeDocumentImage(bytes, format);
    let response;
    try {
      response = await fetcher(new URL(`/storage/v1/object/delivery-private-evidence/${reserved.path}`, env.SUPABASE_URL), {
        method: 'POST', redirect: 'error', signal: AbortSignal.timeout(15000),
        headers: {
          apikey: env.SUPABASE_ANON_KEY,
          Authorization: `Bearer ${req.deliveryIdentity.token}`,
          'Content-Type': 'image/webp',
          'x-upsert': 'false',
        },
        body: image,
      });
    } catch { throw new IntegrationError(502, 'Chưa lưu được ảnh giấy tờ. Vui lòng thử lại.'); }
    await response.body?.cancel?.();
    if (response.status === 401 || response.status === 403) {
      throw new IntegrationError(403, 'Không có quyền tải giấy tờ lúc này. Hồ sơ có thể đang chờ duyệt hoặc tài khoản bị khóa.');
    }
    if (!response.ok) throw new IntegrationError(502, 'Chưa lưu được ảnh giấy tờ. Vui lòng thử lại.');
    return { kind, path: reserved.path };
  }

  async function adminGet(req) {
    const result = await call(req, 'admin_get', validateAdminGet(req.body));
    const documents = plainObject(result?.application?.documents) ? result.application.documents : {};
    const documentUrls = {};
    for (const kind of DRIVER_DOCUMENT_KINDS) {
      const path = documents[kind];
      const match = typeof path === 'string' ? documentPathPattern.exec(path) : null;
      if (!match || match[2] !== kind) continue;
      try {
        documentUrls[kind] = (await signPrivateObject({
          env, fetcher, req, bucket: 'delivery-private-evidence', objectPath: path, expiresIn: SIGNED_URL_SECONDS,
        })).url;
      } catch (error) {
        if (!(error instanceof IntegrationError)) throw error;
        documentUrls[kind] = null; // Missing/unreadable object: keep the review screen usable.
      }
    }
    return { ...result, document_urls: documentUrls };
  }

  return async req => {
    const action = req.params.action;
    if (!DRIVER_APPLICATION_ACTIONS.has(action) || !plainObject(req.body)) throw invalid('Yêu cầu hồ sơ tài xế không hợp lệ.');
    if (action !== 'upload_document' && Buffer.byteLength(JSON.stringify(req.body)) > 8000) throw invalid('Yêu cầu hồ sơ tài xế không hợp lệ.');
    switch (action) {
      case 'get':
        if (Object.keys(req.body).length) throw invalid('Yêu cầu hồ sơ tài xế không hợp lệ.');
        return call(req, 'get', {});
      case 'upload_document':
        return uploadDocument(req);
      case 'submit':
        return call(req, 'submit', validateSubmission(req.body, req.deliveryIdentity.id));
      case 'admin_list':
        return call(req, 'admin_list', validateAdminList(req.body));
      default:
        return adminGet(req);
    }
  };
}
