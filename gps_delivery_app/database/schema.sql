-- =============================================================================
-- HỆ THỐNG GIAO HÀNG TÍCH HỢP ĐỊNH VỊ GPS ĐA NỀN TẢNG (FLUTTER & WEB PORTAL)
-- Database Engine : PostgreSQL 16+ & PostGIS Spatial Extension
-- Cloud Compatible: Supabase (PostgreSQL + PostGIS + Realtime) & Docker PostGIS
-- Chuẩn hóa       : 3NF | 16 Bảng Cốt lõi | GIST Spatial Indexes
-- =============================================================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "postgis";

-- -----------------------------------------------------------------------------
-- 1. BẢNG PHÂN QUYỀN QUẢN TRỊ VIÊN RBAC (admin_roles_permissions - UC46)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS admin_roles_permissions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    role_name VARCHAR(50) UNIQUE NOT NULL,
    order_permissions JSONB NOT NULL DEFAULT '{"view": true, "create": false, "edit": false, "delete": false}'::jsonb,
    driver_permissions JSONB NOT NULL DEFAULT '{"view": true, "approve": false, "edit": false, "suspend": false}'::jsonb,
    finance_permissions JSONB NOT NULL DEFAULT '{"view_report": false, "transactions": false, "payout": false}'::jsonb,
    system_permissions JSONB NOT NULL DEFAULT '{"general": false, "security": false, "audit_log": false}'::jsonb,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- -----------------------------------------------------------------------------
-- 2. BẢNG NGƯỜI DÙNG / KHÁCH HÀNG (users - UC01, UC23, UC41)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    phone VARCHAR(15) UNIQUE NOT NULL,
    email VARCHAR(100) UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    full_name VARCHAR(100) NOT NULL,
    avatar_url TEXT,
    default_address TEXT,
    default_lat_lng GEOMETRY(Point, 4326),
    role VARCHAR(20) NOT NULL DEFAULT 'CUSTOMER' CHECK (role IN ('CUSTOMER', 'DRIVER', 'MERCHANT', 'ADMIN')),
    role_id UUID REFERENCES admin_roles_permissions(id) ON DELETE SET NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'SUSPENDED', 'LOCKED')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- -----------------------------------------------------------------------------
-- 3. BẢNG SỔ ĐỊA CHỈ GIAO NHẬN GPS CỦA KHÁCH HÀNG (user_addresses - UC02)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS user_addresses (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    label VARCHAR(30) NOT NULL DEFAULT 'Nhà',
    recipient_name VARCHAR(100) NOT NULL,
    recipient_phone VARCHAR(15) NOT NULL,
    full_address TEXT NOT NULL,
    location GEOMETRY(Point, 4326) NOT NULL,
    is_default BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- -----------------------------------------------------------------------------
-- 4. BẢNG TÀI XẾ & ĐỊNH VỊ PHƯƠNG TIỆN (drivers - UC13, UC14, UC21, UC24)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS drivers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID UNIQUE REFERENCES users(id) ON DELETE CASCADE,
    phone VARCHAR(15) UNIQUE NOT NULL,
    full_name VARCHAR(100) NOT NULL,
    citizen_id VARCHAR(20) UNIQUE NOT NULL,
    license_plate VARCHAR(20) NOT NULL,
    vehicle_type VARCHAR(20) NOT NULL CHECK (vehicle_type IN ('MOTORBIKE', 'EV_MOTORBIKE', 'VAN', 'TRUCK_500KG', 'TRUCK_1T')),
    vehicle_color VARCHAR(30),
    is_electric_vehicle BOOLEAN NOT NULL DEFAULT FALSE,
    battery_percent SMALLINT NOT NULL DEFAULT 95 CHECK (battery_percent BETWEEN 0 AND 100),
    portrait_image_url TEXT,
    license_image_url TEXT,
    vehicle_doc_image_url TEXT,
    attached_kyc_docs TEXT[],
    is_online BOOLEAN NOT NULL DEFAULT FALSE,
    current_location GEOMETRY(Point, 4326),
    current_bearing DOUBLE PRECISION NOT NULL DEFAULT 0.0,
    rating_avg DECIMAL(3, 2) NOT NULL DEFAULT 5.00,
    acceptance_rate DECIMAL(5, 2) NOT NULL DEFAULT 100.00,
    rejected_count INTEGER NOT NULL DEFAULT 0,
    bank_name VARCHAR(80),
    bank_account VARCHAR(40),
    approval_status VARCHAR(20) NOT NULL DEFAULT 'PENDING' CHECK (approval_status IN ('PENDING', 'APPROVED', 'REJECTED', 'SUSPENDED')),
    wallet_balance DECIMAL(12, 2) NOT NULL DEFAULT 0.00,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- -----------------------------------------------------------------------------
-- 5. BẢNG HỒ SƠ CỬA HÀNG / ĐỐI TÁC GỬI HÀNG (merchants - UC30)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS merchants (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    owner_user_id UUID UNIQUE NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    store_name VARCHAR(150) NOT NULL,
    business_type VARCHAR(50) NOT NULL,
    tax_code VARCHAR(30) UNIQUE,
    representative_name VARCHAR(100) NOT NULL,
    contact_phone VARCHAR(15) NOT NULL,
    contact_email VARCHAR(100),
    headquarters_address TEXT NOT NULL DEFAULT '',
    logo_url TEXT,
    license_image_url TEXT NOT NULL DEFAULT '',
    storefront_image_url TEXT NOT NULL DEFAULT '',
    attached_kyc_docs TEXT[],
    bank_name VARCHAR(80) NOT NULL DEFAULT '',
    bank_account_no VARCHAR(40) NOT NULL DEFAULT '',
    bank_account_holder VARCHAR(100) NOT NULL DEFAULT '',
    webhook_url TEXT NOT NULL DEFAULT '',
    cod_balance DECIMAL(12, 2) NOT NULL DEFAULT 0.00,
    approval_status VARCHAR(20) NOT NULL DEFAULT 'PENDING' CHECK (approval_status IN ('PENDING', 'APPROVED', 'REJECTED', 'SUSPENDED')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- -----------------------------------------------------------------------------
-- 6. BẢNG ĐIỂM LẤY HÀNG / KHO CỦA CỬA HÀNG (merchant_pickup_points - UC31)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS merchant_pickup_points (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    merchant_id UUID NOT NULL REFERENCES merchants(id) ON DELETE CASCADE,
    warehouse_name VARCHAR(100) NOT NULL,
    contact_phone VARCHAR(15) NOT NULL,
    full_address TEXT NOT NULL,
    location GEOMETRY(Point, 4326) NOT NULL,
    open_hours VARCHAR(50) NOT NULL DEFAULT '08:00 - 21:00 (Thứ 2 - Chủ Nhật)',
    is_primary BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- -----------------------------------------------------------------------------
-- 7. BẢNG CẤU HÌNH CÔNG THỨC GIÁ CƯỚC (pricing_configs - UC04, UC05, UC26)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS pricing_configs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    service_type VARCHAR(30) UNIQUE NOT NULL CHECK (service_type IN ('EXPRESS_30M', 'STANDARD', 'SAVING', 'SAME_DAY_2H', 'TRUCK')),
    service_name VARCHAR(100) NOT NULL,
    estimated_time_label VARCHAR(50) NOT NULL,
    base_fare DECIMAL(10, 2) NOT NULL,
    price_per_km DECIMAL(10, 2) NOT NULL,
    peak_hour_surcharge DECIMAL(10, 2) NOT NULL DEFAULT 10000.00,
    bad_weather_surcharge DECIMAL(10, 2) NOT NULL DEFAULT 15000.00,
    is_peak_enabled BOOLEAN NOT NULL DEFAULT FALSE,
    is_weather_enabled BOOLEAN NOT NULL DEFAULT FALSE,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- -----------------------------------------------------------------------------
-- 8. BẢNG MÃ GIẢM GIÁ & KHUYẾN MÃI (vouchers - UC11, UC26)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS vouchers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    code VARCHAR(30) UNIQUE NOT NULL,
    title VARCHAR(150) NOT NULL,
    discount_type VARCHAR(20) NOT NULL CHECK (discount_type IN ('PERCENTAGE', 'FIXED_AMOUNT', 'FREE_SHIPPING')),
    discount_value DECIMAL(10, 2) NOT NULL,
    min_order_value DECIMAL(10, 2) NOT NULL DEFAULT 0.00,
    max_discount_amount DECIMAL(10, 2),
    usage_limit INTEGER NOT NULL DEFAULT 1000,
    used_count INTEGER NOT NULL DEFAULT 0,
    expired_at TIMESTAMPTZ NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'PENDING', 'EXPIRED', 'DISABLED')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- -----------------------------------------------------------------------------
-- 9. BẢNG ĐƠN HÀNG TRUNG TÂM (orders - UC03, UC12, UC15, UC17, UC32, UC34, UC43)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS orders (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tracking_code VARCHAR(20) UNIQUE NOT NULL,
    customer_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    driver_id UUID REFERENCES drivers(id) ON DELETE SET NULL,
    merchant_id UUID REFERENCES merchants(id) ON DELETE SET NULL,
    pickup_point_id UUID REFERENCES merchant_pickup_points(id) ON DELETE SET NULL,
    voucher_id UUID REFERENCES vouchers(id) ON DELETE SET NULL,
    service_type VARCHAR(30) NOT NULL CHECK (service_type IN ('EXPRESS_30M', 'STANDARD', 'SAVING', 'SAME_DAY_2H', 'TRUCK')),
    package_category VARCHAR(50) NOT NULL DEFAULT 'Hàng thông thường',
    weight_kg DOUBLE PRECISION NOT NULL DEFAULT 1.0,
    dimensions_cm VARCHAR(30),
    driver_note TEXT,
    sender_name VARCHAR(100) NOT NULL DEFAULT '',
    sender_phone VARCHAR(15) NOT NULL DEFAULT '',
    pickup_address TEXT NOT NULL,
    pickup_location GEOMETRY(Point, 4326) NOT NULL,
    recipient_name VARCHAR(100) NOT NULL DEFAULT '',
    recipient_phone VARCHAR(15) NOT NULL DEFAULT '',
    dropoff_address TEXT NOT NULL,
    dropoff_location GEOMETRY(Point, 4326) NOT NULL,
    distance_meters INTEGER NOT NULL,
    duration_seconds INTEGER NOT NULL,
    route_polyline TEXT,
    fee_payer VARCHAR(15) NOT NULL DEFAULT 'SENDER' CHECK (fee_payer IN ('SENDER', 'RECIPIENT')),
    delivery_fee DECIMAL(10, 2) NOT NULL,
    surcharge_fee DECIMAL(10, 2) NOT NULL DEFAULT 0.00,
    discount_amount DECIMAL(10, 2) NOT NULL DEFAULT 0.00,
    cod_amount DECIMAL(10, 2) NOT NULL DEFAULT 0.00,
    total_amount DECIMAL(10, 2) NOT NULL,
    payment_method VARCHAR(20) NOT NULL CHECK (payment_method IN ('CASH', 'MOMO', 'ZALOPAY', 'VNPAY', 'BANK_CARD', 'BANK_TRANSFER')),
    payment_status VARCHAR(20) NOT NULL DEFAULT 'UNPAID' CHECK (payment_status IN ('UNPAID', 'PAID', 'REFUNDED', 'RETURNED')),
    status VARCHAR(30) NOT NULL DEFAULT 'DRAFT' CHECK (
        status IN ('DRAFT', 'SEARCHING', 'ACCEPTED', 'ARRIVING_PICKUP', 'IN_TRANSIT', 'DELIVERED', 'CANCELLED', 'FAILED', 'RETURNING')
    ),
    cancel_reason TEXT,
    pod_image_url TEXT,
    pod_otp_code VARCHAR(6),
    pod_signature_url TEXT,
    prefer_eco_ev BOOLEAN NOT NULL DEFAULT FALSE,
    declared_value_vnd DECIMAL(12, 2) NOT NULL DEFAULT 0.00,
    insurance_fee DECIMAL(10, 2) NOT NULL DEFAULT 0.00,
    is_round_trip BOOLEAN NOT NULL DEFAULT FALSE,
    extra_stop_count INTEGER NOT NULL DEFAULT 0,
    batch_group_id VARCHAR(40),
    co2_saved_grams DOUBLE PRECISION NOT NULL DEFAULT 0.0,
    green_fund_contributed BOOLEAN NOT NULL DEFAULT FALSE,
    public_tracking_token VARCHAR(64),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    delivered_at TIMESTAMPTZ
);

-- -----------------------------------------------------------------------------
-- 10. BẢNG VẾT TỌA ĐỘ LỘ TRÌNH GPS (order_tracking_logs - UC06, UC16, UC25, UC35)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS order_tracking_logs (
    id BIGSERIAL PRIMARY KEY,
    order_id UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    driver_id UUID NOT NULL REFERENCES drivers(id) ON DELETE CASCADE,
    location GEOMETRY(Point, 4326) NOT NULL,
    speed DOUBLE PRECISION,
    bearing DOUBLE PRECISION,
    camera_pitch_3d DOUBLE PRECISION DEFAULT 55.0,
    is_mock_location BOOLEAN NOT NULL DEFAULT FALSE,
    recorded_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- -----------------------------------------------------------------------------
-- 11. BẢNG HÀNG RÀO ĐỊA LÝ GEOFENCING (geofence_zones - UC44)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS geofence_zones (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    zone_name VARCHAR(100) NOT NULL,
    city_name VARCHAR(80) NOT NULL DEFAULT 'TP. Hồ Chí Minh',
    zone_type VARCHAR(30) NOT NULL CHECK (zone_type IN ('CENTER_ZONE', 'SURCHARGE_ZONE', 'RESTRICTED_ZONE')),
    polygon_boundary GEOMETRY(Polygon, 4326) NOT NULL,
    surcharge_rate DECIMAL(10, 2) NOT NULL DEFAULT 0.00,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- -----------------------------------------------------------------------------
-- 12. BẢNG VÍ ĐIỆN TỬ & GIAO DỊCH RÚT TIỀN (wallets_and_transactions - UC18, UC29, UC38)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS wallets_and_transactions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    owner_id UUID NOT NULL,
    owner_type VARCHAR(20) NOT NULL CHECK (owner_type IN ('DRIVER', 'MERCHANT')),
    balance_after DECIMAL(12, 2) NOT NULL,
    tx_type VARCHAR(30) NOT NULL CHECK (tx_type IN ('DELIVERY_EARNING', 'WITHDRAWAL', 'COD_PAYOUT', 'PLATFORM_COMMISSION', 'REFUND', 'RETURN_FEE', 'ESCROW_TOPUP', 'TIP')),
    reference_order_id UUID REFERENCES orders(id) ON DELETE SET NULL,
    amount DECIMAL(12, 2) NOT NULL,
    bank_info_snapshot JSONB,
    approval_status VARCHAR(20) NOT NULL DEFAULT 'PENDING' CHECK (approval_status IN ('PENDING', 'APPROVED', 'TRANSFERRED', 'REJECTED')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- -----------------------------------------------------------------------------
-- 13. BẢNG ĐỐI SOÁT CÔNG NỢ COD CỬA HÀNG (cod_reconciliations - UC37)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS cod_reconciliations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    merchant_id UUID NOT NULL REFERENCES merchants(id) ON DELETE CASCADE,
    period_start DATE NOT NULL,
    period_end DATE NOT NULL,
    total_cod_collected DECIMAL(12, 2) NOT NULL DEFAULT 0.00,
    total_service_fee DECIMAL(12, 2) NOT NULL DEFAULT 0.00,
    return_cancel_fee DECIMAL(12, 2) NOT NULL DEFAULT 0.00,
    net_payout_amount DECIMAL(12, 2) NOT NULL DEFAULT 0.00,
    reconciliation_status VARCHAR(20) NOT NULL DEFAULT 'VERIFIED' CHECK (reconciliation_status IN ('VERIFIED', 'DISPUTED', 'PAID')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- -----------------------------------------------------------------------------
-- 14. BẢNG ĐÁNH GIÁ CHẤT LƯỢNG TÀI XẾ (order_ratings - UC09, UC21)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS order_ratings (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_id UUID UNIQUE NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    customer_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    driver_id UUID NOT NULL REFERENCES drivers(id) ON DELETE CASCADE,
    stars SMALLINT NOT NULL CHECK (stars BETWEEN 1 AND 5),
    tip_amount DECIMAL(10, 2) NOT NULL DEFAULT 0.00,
    feedback_tags TEXT[],
    comment VARCHAR(500),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- -----------------------------------------------------------------------------
-- 15. BẢNG SỰ CỐ & KHIẾU NẠI (incidents_and_complaints - UC20, UC28, UC40)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS incidents_and_complaints (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    ticket_code VARCHAR(20) UNIQUE NOT NULL,
    order_id UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    reporter_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    reporter_role VARCHAR(20) NOT NULL CHECK (reporter_role IN ('CUSTOMER', 'DRIVER', 'MERCHANT')),
    issue_type VARCHAR(50) NOT NULL,
    description TEXT NOT NULL,
    evidence_images TEXT[],
    incident_location GEOMETRY(Point, 4326),
    admin_reply TEXT,
    resolution_status VARCHAR(20) NOT NULL DEFAULT 'NEW' CHECK (resolution_status IN ('NEW', 'PROCESSING', 'RESOLVED', 'CLOSED')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- -----------------------------------------------------------------------------
-- 16. BẢNG TIN NHẮN TRONG ĐƠN & THÔNG BÁO HỆ THỐNG (chat_messages_and_notifications - UC10, UC42, UC45)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS chat_messages_and_notifications (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_id UUID REFERENCES orders(id) ON DELETE CASCADE,
    sender_id UUID REFERENCES users(id) ON DELETE SET NULL,
    recipient_user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    target_group VARCHAR(20) NOT NULL DEFAULT 'INDIVIDUAL' CHECK (target_group IN ('INDIVIDUAL', 'ALL_USERS', 'ALL_CUSTOMERS', 'ALL_DRIVERS', 'ALL_MERCHANTS')),
    category VARCHAR(25) NOT NULL CHECK (category IN ('CHAT_MESSAGE', 'ORDER_UPDATE', 'PROMOTION', 'SYSTEM_BROADCAST')),
    title VARCHAR(150),
    content TEXT NOT NULL,
    attachment_url TEXT,
    is_read BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Commercial operations extensions: multi-stop, scheduling, ledger, webhooks and audit.
CREATE TABLE IF NOT EXISTS order_stops (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_id UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    sequence_no INTEGER NOT NULL CHECK (sequence_no >= 0),
    stop_type VARCHAR(20) NOT NULL CHECK (stop_type IN ('PICKUP', 'DROPOFF', 'RETURN')),
    address TEXT NOT NULL,
    location GEOMETRY(Point, 4326),
    recipient_name VARCHAR(100),
    recipient_phone VARCHAR(15),
    cod_amount DECIMAL(12, 2) NOT NULL DEFAULT 0.00,
    status VARCHAR(20) NOT NULL DEFAULT 'PENDING',
    note TEXT,
    otp_code VARCHAR(6),
    pod_note TEXT,
    completed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(order_id, sequence_no)
);

CREATE TABLE IF NOT EXISTS scheduled_orders (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_id UUID UNIQUE NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    scheduled_at TIMESTAMPTZ NOT NULL,
    timezone VARCHAR(64) NOT NULL DEFAULT 'Asia/Ho_Chi_Minh',
    status VARCHAR(20) NOT NULL DEFAULT 'PENDING',
    last_error TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS payment_ledger (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    owner_id UUID,
    owner_type VARCHAR(20) NOT NULL CHECK (owner_type IN ('CUSTOMER', 'DRIVER', 'MERCHANT', 'PLATFORM')),
    order_id UUID REFERENCES orders(id) ON DELETE SET NULL,
    direction VARCHAR(10) NOT NULL CHECK (direction IN ('DEBIT', 'CREDIT')),
    entry_type VARCHAR(40) NOT NULL,
    amount DECIMAL(14, 2) NOT NULL CHECK (amount >= 0),
    currency VARCHAR(3) NOT NULL DEFAULT 'VND',
    idempotency_key VARCHAR(160) UNIQUE NOT NULL,
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS webhook_deliveries (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    endpoint_url TEXT NOT NULL,
    event_type VARCHAR(80) NOT NULL,
    aggregate_id UUID,
    payload JSONB NOT NULL,
    signature TEXT,
    status VARCHAR(20) NOT NULL DEFAULT 'PENDING',
    attempt_count INTEGER NOT NULL DEFAULT 0,
    next_attempt_at TIMESTAMPTZ,
    last_http_status INTEGER,
    last_error TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    delivered_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS audit_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    actor_id UUID,
    actor_role VARCHAR(20),
    action VARCHAR(100) NOT NULL,
    entity_type VARCHAR(60) NOT NULL,
    entity_id UUID,
    before_data JSONB,
    after_data JSONB,
    ip_address INET,
    device_id TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Bảng thực đơn ăn uống Đối tác B2B (GrabFood Smart Dining Ecosystem)
CREATE TABLE IF NOT EXISTS merchant_menu_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    merchant_id UUID NOT NULL REFERENCES merchants(id) ON DELETE CASCADE,
    store_name VARCHAR(150) NOT NULL,
    store_address TEXT NOT NULL,
    store_location GEOMETRY(Point, 4326) NOT NULL,
    name VARCHAR(150) NOT NULL,
    description TEXT NOT NULL DEFAULT '',
    category VARCHAR(80) NOT NULL DEFAULT 'Cơm • Bún • Phở',
    price_vnd DECIMAL(12, 2) NOT NULL CHECK (price_vnd >= 0),
    prep_minutes INTEGER NOT NULL DEFAULT 15 CHECK (prep_minutes >= 1),
    meal_slots_json JSONB NOT NULL DEFAULT '["breakfast","lunch","afternoonTea","dinner"]'::jsonb,
    is_eco_packaging BOOLEAN NOT NULL DEFAULT FALSE,
    is_cold_item BOOLEAN NOT NULL DEFAULT FALSE,
    has_promo_badge BOOLEAN NOT NULL DEFAULT FALSE,
    is_available BOOLEAN NOT NULL DEFAULT TRUE,
    rating DECIMAL(3, 2) NOT NULL DEFAULT 4.80,
    sold_count INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- =============================================================================
-- CHỈ MỤC KHÔNG GIAN POSTGIS (SPATIAL GIST INDEXES) & CHỈ MỤC HIỆU NĂNG CAO
-- =============================================================================
CREATE INDEX IF NOT EXISTS idx_users_default_loc_gist ON users USING GIST (default_lat_lng);
CREATE INDEX IF NOT EXISTS idx_user_addresses_loc_gist ON user_addresses USING GIST (location);
CREATE INDEX IF NOT EXISTS idx_drivers_current_loc_gist ON drivers USING GIST (current_location);
CREATE INDEX IF NOT EXISTS idx_drivers_online_status ON drivers (is_online, approval_status);
CREATE INDEX IF NOT EXISTS idx_pickup_points_loc_gist ON merchant_pickup_points USING GIST (location);
CREATE INDEX IF NOT EXISTS idx_orders_pickup_loc_gist ON orders USING GIST (pickup_location);
CREATE INDEX IF NOT EXISTS idx_orders_dropoff_loc_gist ON orders USING GIST (dropoff_location);
CREATE INDEX IF NOT EXISTS idx_orders_status_created ON orders (status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_orders_public_tracking_token ON orders (public_tracking_token);
CREATE INDEX IF NOT EXISTS idx_orders_batch_group ON orders (batch_group_id);
CREATE INDEX IF NOT EXISTS idx_tracking_logs_loc_gist ON order_tracking_logs USING GIST (location);
CREATE INDEX IF NOT EXISTS idx_tracking_logs_order_time ON order_tracking_logs (order_id, recorded_at DESC);
CREATE INDEX IF NOT EXISTS idx_geofence_polygon_gist ON geofence_zones USING GIST (polygon_boundary);
CREATE INDEX IF NOT EXISTS idx_order_stops_order_sequence ON order_stops (order_id, sequence_no);
CREATE INDEX IF NOT EXISTS idx_scheduled_orders_due ON scheduled_orders (status, scheduled_at);
CREATE INDEX IF NOT EXISTS idx_payment_ledger_owner_time ON payment_ledger (owner_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_webhook_deliveries_retry ON webhook_deliveries (status, next_attempt_at);
CREATE INDEX IF NOT EXISTS idx_audit_logs_entity_time ON audit_logs (entity_type, entity_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_merchant_menu_items_loc_gist ON merchant_menu_items USING GIST (store_location);
CREATE INDEX IF NOT EXISTS idx_merchant_menu_items_merchant_avail ON merchant_menu_items (merchant_id, is_available);

-- =============================================================================
-- DỮ LIỆU CẤU HÌNH KHỞI TẠO CHUẨN THEO THIẾT KẾ UI (SEED DATA)
-- =============================================================================
INSERT INTO pricing_configs (service_type, service_name, estimated_time_label, base_fare, price_per_km, peak_hour_surcharge, bad_weather_surcharge, is_peak_enabled, is_weather_enabled)
VALUES
    ('EXPRESS_30M', 'Giao nhanh (Express)', '1-2 giờ', 15000.00, 8500.00, 20000.00, 15000.00, TRUE, FALSE),
    ('STANDARD', 'Giao tiêu chuẩn', '1-3 ngày', 25000.00, 5000.00, 10000.00, 15000.00, TRUE, TRUE),
    ('SAVING', 'Giao tiết kiệm', '3-5 ngày', 12000.00, 4000.00, 0.00, 10000.00, FALSE, FALSE),
    ('SAME_DAY_2H', 'Giao nhanh 2H (Ghép đơn)', 'Trong 2 giờ', 12000.00, 5500.00, 8000.00, 12000.00, TRUE, FALSE),
    ('TRUCK', 'Giao hàng lớn', '2-4 ngày', 80000.00, 15000.00, 30000.00, 25000.00, TRUE, FALSE)
ON CONFLICT (service_type) DO NOTHING;

INSERT INTO admin_roles_permissions (role_name, order_permissions, driver_permissions, finance_permissions, system_permissions)
VALUES
    ('Super Admin', '{"view": true, "create": true, "edit": true, "delete": true}'::jsonb, '{"view": true, "approve": true, "edit": true, "suspend": true}'::jsonb, '{"view_report": true, "transactions": true, "payout": true}'::jsonb, '{"general": true, "security": true, "audit_log": true}'::jsonb),
    ('Điều phối viên', '{"view": true, "create": true, "edit": true, "delete": true}'::jsonb, '{"view": true, "approve": true, "edit": true, "suspend": false}'::jsonb, '{"view_report": false, "transactions": false, "payout": false}'::jsonb, '{"general": false, "security": false, "audit_log": false}'::jsonb),
    ('Kế toán', '{"view": false, "create": false, "edit": false, "delete": false}'::jsonb, '{"view": false, "approve": false, "edit": false, "suspend": false}'::jsonb, '{"view_report": true, "transactions": true, "payout": true}'::jsonb, '{"general": false, "security": false, "audit_log": false}'::jsonb),
    ('Hỗ trợ CSKH', '{"view": true, "create": true, "edit": false, "delete": false}'::jsonb, '{"view": true, "approve": false, "edit": false, "suspend": false}'::jsonb, '{"view_report": true, "transactions": false, "payout": false}'::jsonb, '{"general": true, "security": false, "audit_log": false}'::jsonb)
ON CONFLICT (role_name) DO NOTHING;
