import assert from 'node:assert/strict';
import test from 'node:test';
import { readFile } from 'node:fs/promises';
import { randomBytes, randomUUID } from 'node:crypto';
import express from 'express';
import sharp from 'sharp';
import { PGlite } from '@electric-sql/pglite';
import { createCloudOrders } from './cloud-orders.mjs';
import { DEPLOYMENT_SCHEMA_SQL } from './deployment-readiness.mjs';
import { hasImageSignature, validateSubmission } from './driver-application.mjs';

const KINDS = ['citizen_front', 'citizen_back', 'license', 'vehicle_registration', 'portrait'];
const docPath = (uid, kind) => `driver-applications/${uid}/${kind}-${randomUUID()}.webp`;
const documentsFor = uid => Object.fromEntries(KINDS.map(kind => [kind, docPath(uid, kind)]));
const submission = (uid, patch = {}) => ({
  vehicle_type: 'van', license_plate: '51C-123.45', vehicle_brand: 'Suzuki Carry', vehicle_color: 'Trắng',
  license_number: '012345678901', license_class: 'B', operating_area: 'TP.HCM - Quận 1, 3, 10',
  documents: documentsFor(uid), ...patch,
});

test('Driver application gateway validates actions, documents and admin signing before any cloud call', async t => {
  const user = '10000000-0000-4000-8000-000000000001';
  const other = '10000000-0000-4000-8000-000000000002';
  const calls = [];
  let reservationOwner = user, storageStatus = 200, rpcError = null, application = null;
  const app = express();
  // Mirrors server.mjs: a small global JSON limit except for the document upload route.
  app.use((req, res, next) => req.path === '/cloud/driver-application/upload_document' ? next() : express.json({ limit: '32kb' })(req, res, next));
  app.use('/cloud', createCloudOrders({
    env: { SUPABASE_URL: 'https://project.supabase.co', SUPABASE_ANON_KEY: 'public-key' },
    authenticate(req, _res, next) { req.deliveryIdentity = { id: user, token: 'driver-jwt', local: false }; next(); },
    fetcher: async (url, options = {}) => {
      const href = String(url);
      calls.push({ url: href, options });
      if (href.endsWith('/rest/v1/rpc/delivery_driver_application')) {
        if (rpcError) return Response.json(rpcError, { status: 400 });
        const body = JSON.parse(options.body);
        if (body.p_action === 'upload_document') {
          return Response.json({ bucket: 'delivery-private-evidence', kind: body.p_details.kind, path: docPath(reservationOwner, body.p_details.kind) });
        }
        if (body.p_action === 'admin_get') return Response.json({ application });
        return Response.json({ ok: true, echo: body });
      }
      if (href.includes('/storage/v1/object/sign/')) {
        if (href.includes('/portrait-')) return new Response('{}', { status: 404 });
        const path = href.split('/storage/v1/object/sign/delivery-private-evidence/')[1];
        return Response.json({ signedURL: `/object/sign/delivery-private-evidence/${path}?token=signed`, expires: JSON.parse(options.body).expiresIn });
      }
      if (href.includes('/storage/v1/object/delivery-private-evidence/')) return Response.json({}, { status: storageStatus });
      throw new Error(`unexpected ${href}`);
    },
  }));
  app.use((error, _req, res, _next) => res.status(error.status || (error.type === 'entity.too.large' ? 413 : 500)).json({ error: error.message }));
  const server = app.listen(0, '127.0.0.1'); t.after(() => server.close());
  await new Promise(resolve => server.once('listening', resolve));
  const base = `http://127.0.0.1:${server.address().port}/cloud/driver-application`;
  const post = (action, body) => fetch(`${base}/${action}`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
  const status = async (action, body) => (await post(action, body)).status;

  const png = await sharp(randomBytes(48 * 48 * 3), { raw: { width: 48, height: 48, channels: 3 } }).png().toBuffer();
  assert.ok(png.length > 1024);
  const jpeg = await sharp(randomBytes(48 * 48 * 3), { raw: { width: 48, height: 48, channels: 3 } }).jpeg().toBuffer();
  const upload = (patch = {}) => ({ kind: 'license', content_base64: png.toString('base64'), content_type: 'image/png', ...patch });

  // Unknown actions, non-object bodies and extra keys never reach Supabase.
  assert.equal(await status('approve_myself', {}), 400);
  assert.equal(await status('get', []), 400);
  assert.equal(await status('get', { user_id: other }), 400);
  // Upload validation: keys, kind, content type, base64, size bounds and magic bytes.
  assert.equal(await status('upload_document', { ...upload(), path: '../../other' }), 400);
  assert.equal(await status('upload_document', { kind: 'license', content_base64: png.toString('base64') }), 400);
  assert.equal(await status('upload_document', upload({ kind: 'selfie_video' })), 400);
  assert.equal(await status('upload_document', upload({ content_type: 'image/gif' })), 400);
  assert.equal(await status('upload_document', upload({ content_base64: '@@not-base64@@' })), 400);
  assert.equal(await status('upload_document', upload({ content_base64: png.toString('base64').slice(0, -3) })), 400);
  assert.equal(await status('upload_document', upload({ content_base64: Buffer.alloc(512, 1).toString('base64') })), 400);
  assert.equal(await status('upload_document', upload({ content_base64: 'A'.repeat(6_666_672) })), 400);
  assert.equal(await status('upload_document', upload({ content_type: 'image/jpeg' })), 400); // PNG bytes declared as JPEG
  const html = Buffer.concat([Buffer.from('<html><script>alert(1)</script>'), Buffer.alloc(2048, 32)]);
  assert.equal(await status('upload_document', upload({ content_base64: html.toString('base64') })), 400);
  const fakePng = Buffer.concat([png.subarray(0, 8), Buffer.alloc(2048, 7)]);
  assert.equal(hasImageSignature(fakePng, 'image/png'), true);
  // Submission validation mirrors SQL: exact keys, owner-scoped document paths, plate, licence and class.
  assert.equal(await status('submit', { ...submission(user), referral: 'x' }), 400);
  assert.equal(await status('submit', submission(user, { documents: documentsFor(other) })), 400);
  assert.equal(await status('submit', submission(user, { documents: { ...documentsFor(user), portrait: 'https://evil.example/a.png' } })), 400);
  assert.equal(await status('submit', submission(user, { license_plate: 'ABC-123' })), 400);
  assert.equal(await status('submit', submission(user, { license_number: '12345' })), 400);
  assert.equal(await status('submit', submission(user, { license_class: 'A1' })), 400); // A1 cannot drive a van
  assert.equal(await status('submit', submission(user, { vehicle_type: 'bicycle' })), 400);
  assert.equal(await status('submit', submission(user, { vehicle_brand: 'x' })), 400);
  assert.equal(await status('admin_list', { state: 'everything' }), 400);
  assert.equal(await status('admin_list', { state: 'pending', limit: 5000 }), 400);
  assert.equal(await status('admin_get', { user_id: 'not-a-uuid' }), 400);
  assert.equal(calls.length, 0);
  assert.throws(() => validateSubmission(submission(user, { documents: { ...documentsFor(user), license: docPath(user, 'portrait') } }), user), e => e.status === 400);
  assert.equal(validateSubmission(submission(user, { license_plate: '59x1 123.45', vehicle_type: 'motorbike', license_class: 'a1' }), user).vehicle_type, 'motorbike');

  // A corrupt image that passes magic bytes is rejected after reservation, before storage.
  assert.equal(await status('upload_document', upload({ content_base64: fakePng.toString('base64') })), 400);
  assert.equal(calls.filter(c => c.url.includes('/storage/')).length, 0);
  calls.length = 0;

  // Valid upload: fixed RPC reservation, re-encoded WebP stored privately with the caller JWT.
  const ok = await post('upload_document', upload());
  assert.equal(ok.status, 200);
  const uploaded = await ok.json();
  assert.equal(uploaded.kind, 'license');
  assert.match(uploaded.path, new RegExp(`^driver-applications/${user}/license-[0-9a-f-]{36}\\.webp$`));
  assert.deepEqual(JSON.parse(calls[0].options.body), { p_action: 'upload_document', p_details: { kind: 'license' } });
  assert.equal(calls[0].options.headers.Authorization, 'Bearer driver-jwt');
  assert.equal(calls[1].url, `https://project.supabase.co/storage/v1/object/delivery-private-evidence/${uploaded.path}`);
  assert.equal(calls[1].options.headers['Content-Type'], 'image/webp');
  assert.equal(calls[1].options.headers['x-upsert'], 'false');
  assert.equal(calls[1].options.headers.Authorization, 'Bearer driver-jwt');
  assert.ok(hasImageSignature(Buffer.from(calls[1].options.body), 'image/webp'));
  assert.equal((await post('upload_document', upload({ kind: 'portrait', content_base64: jpeg.toString('base64'), content_type: 'image/jpeg' }))).status, 200);

  // Untrusted reservation path or storage denial never yields a success.
  calls.length = 0; reservationOwner = other;
  assert.equal(await status('upload_document', upload()), 502);
  assert.equal(calls.length, 1);
  reservationOwner = user; storageStatus = 403;
  assert.equal(await status('upload_document', upload()), 403);
  storageStatus = 200;

  // Valid submit / get / admin_list forward exact payloads to the fixed RPC.
  calls.length = 0;
  const body = submission(user, { license_plate: '51c 123.45' });
  assert.equal(await status('submit', body), 200);
  assert.deepEqual(JSON.parse(calls[0].options.body), { p_action: 'submit', p_details: body });
  assert.equal(await status('get', {}), 200);
  assert.deepEqual(JSON.parse(calls[1].options.body), { p_action: 'get', p_details: {} });
  assert.equal(await status('admin_list', { state: 'pending' }), 200);
  assert.deepEqual(JSON.parse(calls[2].options.body), { p_action: 'admin_list', p_details: { state: 'pending' } });
  assert.ok(calls.every(c => c.url === 'https://project.supabase.co/rest/v1/rpc/delivery_driver_application'));

  // Operator-only actions: SQL PT403 surfaces as 403 and nothing is signed.
  calls.length = 0; rpcError = { code: 'PT403', message: 'Cần quyền quản trị.' };
  const denied = await post('admin_get', { user_id: other });
  assert.equal(denied.status, 403);
  assert.equal((await denied.json()).error, 'Cần quyền quản trị.');
  assert.equal(await status('admin_list', {}), 403);
  assert.equal(calls.length, 2);
  rpcError = null;

  // admin_get signs each document for 10 minutes; unreadable documents become null.
  const documents = documentsFor(other);
  application = { user_id: other, full_name: 'Tài xế', documents: { ...documents, license: '../../etc/passwd' } };
  calls.length = 0;
  const detail = await post('admin_get', { user_id: other });
  assert.equal(detail.status, 200);
  const payload = await detail.json();
  assert.equal(payload.application.user_id, other);
  assert.deepEqual(Object.keys(payload.document_urls).sort(), ['citizen_back', 'citizen_front', 'portrait', 'vehicle_registration']);
  assert.equal(payload.document_urls.portrait, null);
  assert.equal(payload.document_urls.citizen_front,
    `https://project.supabase.co/storage/v1/object/sign/delivery-private-evidence/${documents.citizen_front}?token=signed`);
  const signs = calls.filter(c => c.url.includes('/object/sign/'));
  assert.equal(signs.length, 4);
  assert.ok(signs.every(c => JSON.parse(c.options.body).expiresIn === 600 && c.options.headers.Authorization === 'Bearer driver-jwt'));
});

test('Vehicle classes drive quotes, orders and dispatch; driver applications sync with membership review', async t => {
  const db = new PGlite();
  t.after(() => db.close());
  await db.exec(`create role authenticated; create role anon;
    create schema auth; create table auth.users(id uuid primary key);
    create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
    grant usage on schema auth to authenticated; grant execute on function auth.uid() to authenticated;
    create schema storage; create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);
    create table storage.objects(id uuid default gen_random_uuid(),bucket_id text,name text); alter table storage.objects enable row level security;
    create function storage.foldername(text) returns text[] language sql immutable as $$select (string_to_array($1,'/'))[1:array_length(string_to_array($1,'/'),1)-1]$$;
    grant usage on schema storage to authenticated; grant select,insert on storage.objects to authenticated;
    create publication supabase_realtime;`);
  for (const file of ['20261027_delivery_integrations', '20261028_cloud_orders', '20261029_payments_ghn', '20261029_cloud_addresses',
    '20261030_marketplace', '20261031_market_operations', '20261101_partner_memberships', '20261102_local_address_import',
    '20261103_catalog_stock_versions', '20261104_market_media', '20261105_market_browse', '20261106_catalog_configuration',
    '20261107_cloud_commercial_suite', '20261108_cloud_logistics', '20261109_admin_account_management', '20261110_cloud_promo_events',
    '20261111_profile_push_shipping_coins', '20261112_shipping_cash_settlement', '20261113_cloud_sync_and_journey',
    '20261114_merchant_cloud_suite', '20261115_driver_wallet_and_showcase_catalog', '20261116_realtime_dispatch_pricing_and_pod_signature',
    '20261117_vehicle_classes_and_driver_applications', '20261117_vehicle_classes_and_driver_applications']) {
    await db.exec(await readFile(new URL(`../../database/migrations/${file}.sql`, import.meta.url), 'utf8'));
  }
  const schema = (await db.query(DEPLOYMENT_SCHEMA_SQL)).rows[0];
  assert.equal(schema.vehicle_partner_schema, true);
  assert.equal(schema.realtime_dispatch_pricing_pod_schema, true);

  const ids = Object.fromEntries(['customer', 'driver', 'operator', 'outsider'].map(name => [name, randomUUID()]));
  for (const [name, id] of Object.entries(ids)) {
    await db.query('insert into auth.users values($1)', [id]);
    await db.query('insert into delivery_cloud_accounts(user_id,full_name,phone,role,blocked) values($1,$2,$3,$4,false)',
      [id, name, '0901234567', 'customer']);
  }
  await db.query("insert into delivery_api_profiles(user_id,role) values($1,'operator')", [ids.operator]);

  const as = async (actor, sql, args = []) => {
    await db.exec('begin');
    try {
      await db.exec('set local role authenticated');
      await db.query("select set_config('request.jwt.claim.sub',$1,true)", [actor]);
      const result = await db.query(sql, args);
      await db.exec('commit');
      return result.rows[0]?.data;
    } catch (error) {
      await db.exec('rollback').catch(() => {});
      throw error;
    }
  };
  const quote = details => as(ids.customer, 'select public.delivery_cloud_quote($1) as data', [details]);
  const application = (actor, action, details = {}) => as(actor, 'select public.delivery_driver_application($1,$2) as data', [action, details]);
  const membership = (decision, version, reason = '') => as(ids.operator,
    "select public.delivery_cloud_membership('driver',$1,$2,$3,$4) as data", [decision, ids.driver, version, reason]);
  const pt = code => error => error.code === code;
  const base = { pickup_lat: 10.77, pickup_lng: 106.7, dropoff_lat: 10.8, dropoff_lng: 106.75, weight_kg: 2, service_type: 'standard' };

  await t.test('quotes resolve, validate and price vehicle classes', async () => {
    const legacy = await quote(base);
    assert.equal(legacy.vehicle_type, 'motorbike');
    assert.equal(legacy.max_weight_kg, 30);
    assert.equal(legacy.breakdown.vehicle_fee, undefined);
    assert.equal((await quote({ ...base, prefer_ev: true })).vehicle_type, 'ev_scooter');
    const ev = await quote({ ...base, vehicle_type: 'ev_scooter' });
    assert.ok(ev.estimated_co2_saved_grams > 0);
    const truckService = { ...base, service_type: 'truck', weight_kg: 100 };
    const legacyTruck = await quote(truckService);
    assert.equal(legacyTruck.vehicle_type, 'van');
    assert.equal(legacyTruck.max_weight_kg, 500);
    const km = Math.max(0, Math.ceil(legacyTruck.distance_meters / 1000 - 2));
    assert.equal(legacyTruck.breakdown.vehicle_fee, 60000 + 3000 * km);
    const tricycle = await quote({ ...truckService, vehicle_type: 'tricycle' });
    assert.equal(tricycle.breakdown.vehicle_fee, undefined);
    assert.equal(legacyTruck.shipping_fee - tricycle.shipping_fee, legacyTruck.breakdown.vehicle_fee);
    const heavy = await quote({ ...truckService, vehicle_type: 'truck', weight_kg: 1200 });
    assert.equal(heavy.max_weight_kg, 1500);
    assert.equal(heavy.breakdown.vehicle_fee, 150000 + 8000 * km);
    await assert.rejects(quote({ ...truckService, vehicle_type: 'tricycle', weight_kg: 350 }), e => e.code === 'PT400' && /300 kg/.test(e.message));
    await assert.rejects(quote({ ...truckService, vehicle_type: 'van', weight_kg: 100, length_cm: 300, width_cm: 300, height_cm: 300 }), pt('PT400'));
    await assert.rejects(quote({ ...base, weight_kg: 31 }), pt('PT400'));
    await assert.rejects(quote({ ...base, vehicle_type: 'van' }), e => e.code === 'PT400' && /không hỗ trợ dịch vụ/.test(e.message));
    await assert.rejects(quote({ ...truckService, vehicle_type: 'motorbike' }), pt('PT400'));
    await assert.rejects(quote({ ...base, vehicle_type: 'bicycle' }), pt('PT400'));
    await assert.rejects(quote({ ...base, vehicle_type: 5 }), pt('PT400'));
  });

  const order = async extra => {
    const details = { ...base, pickup_address: '12 Nguyen Hue, TP HCM', dropoff_address: '20 Le Loi, TP HCM', recipient_name: 'Receiver',
      recipient_phone: '0912345678', package_description: 'Hàng hóa', cod_amount: 0, payment_method: 'sender_cash', ...extra };
    const q = await quote(details);
    return as(ids.customer, 'select public.delivery_cloud_create($1,$2,$3,$4) as data',
      [details, randomUUID(), q.pricing_version, q.payable_fee ?? q.shipping_fee]);
  };

  await t.test('orders persist the resolved vehicle class', async () => {
    assert.equal((await order({})).details.vehicle_type, 'motorbike');
    const ev = await order({ vehicle_type: 'ev_scooter' });
    assert.equal(ev.details.vehicle_type, 'ev_scooter');
    assert.equal(ev.details.prefer_ev, true);
    const truck = await order({ service_type: 'truck', vehicle_type: 'truck', weight_kg: 900 });
    assert.equal(truck.details.vehicle_type, 'truck');
    const list = await as(ids.customer, 'select public.delivery_cloud_list(false,null,null) as data');
    assert.ok(list.orders.some(o => o.id === truck.id && o.details.vehicle_type === 'truck'));
    await db.query("update delivery_cloud_orders set status='cancelled' where owner_id=$1 and status='searching'", [ids.customer]);
  });

  await t.test('capacity rule', async () => {
    const serve = async (driver, required) => (await db.query('select public.delivery_vehicle_can_serve($1,$2) as ok', [driver, required])).rows[0].ok;
    assert.equal(await serve('ev_scooter', 'motorbike'), true);
    assert.equal(await serve('motorbike', 'ev_scooter'), false);
    assert.equal(await serve('truck', 'tricycle'), true);
    assert.equal(await serve('tricycle', 'van'), false);
    assert.equal(await serve('van', 'truck'), false);
    assert.equal(await serve('truck', 'motorbike'), false);
    assert.equal((await db.query("select public.delivery_order_vehicle_type('{\"service_type\":\"truck\"}') as v")).rows[0].v, 'van');
    await assert.rejects(db.query("insert into delivery_driver_presence(user_id,vehicle_type) values($1,'bicycle')", [ids.outsider]), /check/);
  });

  await t.test('application submit, review sync, approved vehicle pinning and dispatch matching', async () => {
    assert.deepEqual(await application(ids.driver, 'get'), { application: null });
    const reserved = await application(ids.driver, 'upload_document', { kind: 'license' });
    assert.equal(reserved.bucket, 'delivery-private-evidence');
    assert.match(reserved.path, new RegExp(`^driver-applications/${ids.driver}/license-[0-9a-f-]{36}\\.webp$`));
    assert.equal(await as(ids.driver, 'select public.delivery_driver_application_can_upload($1) as data', [reserved.path]), true);
    assert.equal(await as(ids.outsider, 'select public.delivery_driver_application_can_upload($1) as data', [reserved.path]), false);
    assert.equal(await as(ids.outsider, 'select public.delivery_driver_application_can_read($1) as data', [reserved.path]), false);
    assert.equal(await as(ids.operator, 'select public.delivery_driver_application_can_read($1) as data', [reserved.path]), true);
    await assert.rejects(application(ids.driver, 'upload_document', { kind: 'selfie' }), pt('PT400'));
    await assert.rejects(application(ids.driver, 'submit', submission(ids.driver, { documents: documentsFor(ids.outsider) })), pt('PT400'));
    await assert.rejects(application(ids.driver, 'submit', submission(ids.driver, { license_class: 'C' })), pt('PT400'));
    await assert.rejects(application(ids.driver, 'submit', { ...submission(ids.driver), extra: true }), pt('PT400'));
    await assert.rejects(application(ids.driver, 'submit', submission(ids.driver, { license_plate: 'XX-1' })), pt('PT400'));

    const first = await application(ids.driver, 'submit', submission(ids.driver, { license_plate: '51c 123.45' }));
    assert.equal(first.application.state, 'pending');
    assert.equal(first.application.version, 1);
    assert.equal(first.application.license_plate, '51C123.45');
    let m = (await db.query("select state,version from delivery_cloud_memberships where user_id=$1 and role='driver'", [ids.driver])).rows[0];
    assert.equal(m.state, 'pending');
    await assert.rejects(application(ids.driver, 'submit', submission(ids.driver)), pt('PT409'));
    await assert.rejects(application(ids.driver, 'upload_document', { kind: 'license' }), pt('PT409'));
    assert.equal(await as(ids.driver, 'select public.delivery_driver_application_can_upload($1) as data', [reserved.path]), false);

    await assert.rejects(application(ids.customer, 'admin_list'), pt('PT403'));
    await assert.rejects(application(ids.customer, 'admin_get', { user_id: ids.driver }), pt('PT403'));
    const listed = await application(ids.operator, 'admin_list', { state: 'pending' });
    const row = listed.applications.find(a => a.user_id === ids.driver);
    assert.equal(row.full_name, 'driver');
    assert.equal(row.membership_version, m.version);
    assert.equal(row.vehicle_type, 'van');
    assert.equal((await application(ids.operator, 'admin_list', { state: 'approved' })).applications.length, 0);
    assert.equal((await application(ids.operator, 'admin_get', { user_id: ids.driver })).application.documents.license.startsWith(`driver-applications/${ids.driver}/`), true);
    await assert.rejects(application(ids.operator, 'admin_get', { user_id: ids.outsider }), pt('PT404'));

    await membership('reject', m.version, 'Ảnh giấy tờ bị mờ');
    let current = (await application(ids.driver, 'get')).application;
    assert.equal(current.state, 'rejected');
    assert.equal(current.reason, 'Ảnh giấy tờ bị mờ');

    const second = await application(ids.driver, 'submit', submission(ids.driver, { vehicle_type: 'truck', license_class: 'C' }));
    assert.equal(second.application.state, 'pending');
    assert.equal(second.application.version, 2);
    m = (await db.query("select state,version from delivery_cloud_memberships where user_id=$1 and role='driver'", [ids.driver])).rows[0];
    assert.equal(m.state, 'pending');
    await membership('approve', m.version);
    current = (await application(ids.driver, 'get')).application;
    assert.equal(current.state, 'approved');
    assert.ok(current.reviewed_at);
    assert.equal((await db.query('select vehicle_type from delivery_driver_presence where user_id=$1', [ids.driver])).rows[0].vehicle_type, 'truck');

    const dispatch = (action, payload = {}) => as(ids.driver, 'select public.delivery_driver_dispatch($1,$2) as data', [action, payload]);
    const online = await dispatch('set_presence', { is_online: true, latitude: 10.77, longitude: 106.7, vehicle_type: 'motorbike' });
    assert.equal(online.presence.vehicle_type, 'truck');
    assert.equal(online.presence.approved_vehicle_type, 'truck');
    assert.equal((await dispatch('get_presence')).presence.approved_vehicle_type, 'truck');

    const offersFor = async orderId => (await db.query('select driver_id from delivery_driver_offers where order_id=$1', [orderId])).rows;
    const small = await order({ vehicle_type: 'motorbike' });
    assert.equal((await offersFor(small.id)).length, 0);
    const big = await order({ service_type: 'truck', vehicle_type: 'tricycle', weight_kg: 200 });
    assert.deepEqual((await offersFor(big.id)).map(r => r.driver_id), [ids.driver]);
    const polled = await dispatch('poll_offer');
    assert.equal(polled.active_offer.vehicle_type, 'tricycle');
    await db.query("update delivery_driver_offers set state='cancelled' where driver_id=$1", [ids.driver]);
    await db.query("update delivery_cloud_orders set status='cancelled' where owner_id=$1 and status='searching'", [ids.customer]);

    m = (await db.query("select version from delivery_cloud_memberships where user_id=$1 and role='driver'", [ids.driver])).rows[0];
    await membership('revoke', m.version, 'Vi phạm quy định');
    current = (await application(ids.driver, 'get')).application;
    assert.equal(current.state, 'rejected');
    assert.equal(current.reason, 'Vi phạm quy định');
  });

  await t.test('an already-granted driver can still have a new application approved', async () => {
    await as(ids.operator, "select public.delivery_cloud_membership('driver','grant',$1,0,'Cấp trực tiếp') as data", [ids.outsider]);
    const submitted = await application(ids.outsider, 'submit', submission(ids.outsider, { vehicle_type: 'motorbike', license_class: 'A1', license_plate: '59X1-123.45' }));
    assert.equal(submitted.application.state, 'pending');
    const m = (await db.query("select state,version from delivery_cloud_memberships where user_id=$1 and role='driver'", [ids.outsider])).rows[0];
    assert.equal(m.state, 'active');
    await assert.rejects(as(ids.operator, "select public.delivery_cloud_membership('driver','reject',$1,$2,'Không hợp lệ') as data", [ids.outsider, m.version]), pt('PT409'));
    await as(ids.operator, "select public.delivery_cloud_membership('driver','approve',$1,$2,'') as data", [ids.outsider, m.version]);
    assert.equal((await application(ids.outsider, 'get')).application.state, 'approved');
    assert.equal((await db.query("select state from delivery_cloud_memberships where user_id=$1 and role='driver'", [ids.outsider])).rows[0].state, 'active');
    assert.equal((await db.query('select vehicle_type from delivery_driver_presence where user_id=$1', [ids.outsider])).rows[0].vehicle_type, 'motorbike');
    await assert.rejects(as(ids.operator, "select public.delivery_cloud_membership('driver','approve',$1,$2,'') as data", [ids.outsider, m.version + 1]), pt('PT409'));
  });

  await t.test('applications stay private to Supabase public roles', async () => {
    for (const role of ['anon', 'authenticated']) {
      await db.exec(`set role ${role}`);
      await assert.rejects(db.query('select * from public.delivery_driver_applications'), /permission denied/);
      await db.exec('reset role');
    }
    await db.exec('set role anon');
    await assert.rejects(db.query("select public.delivery_driver_application('get','{}')"), /permission denied/);
    await db.exec('reset role');
  });
});
