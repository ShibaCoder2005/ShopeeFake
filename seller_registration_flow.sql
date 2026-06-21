-- =============================================================================
-- Luồng Nâng cấp lên Người bán (rút gọn)
-- Swimlanes: Admin | Hệ thống
-- Chạy sau: create_table.sql
--
-- Logic:
--   [Admin] Tạo bản ghi Sellers liên kết user_id hiện tại → mở tính năng cửa hàng
--   [Hệ thống] Trả thông báo thành công
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Trigger: validate role Users
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION func_validate_user_fields()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.role NOT IN ('admin', 'buyer', 'seller', 'shipping') THEN
        RAISE EXCEPTION 'Role không hợp lệ: %', NEW.role;
    END IF;

    IF TG_OP = 'UPDATE' AND OLD.role = 'seller' AND NEW.role <> 'seller' THEN
        IF EXISTS (SELECT 1 FROM Sellers s WHERE s.user_id = NEW.user_id) THEN
            RAISE EXCEPTION 'Không thể đổi role khi user vẫn còn bản ghi Sellers!';
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER trg_users_validate_fields
BEFORE INSERT OR UPDATE OF role ON Users
FOR EACH ROW
EXECUTE FUNCTION func_validate_user_fields();

-- -----------------------------------------------------------------------------
-- 2. Trigger: đồng bộ role seller khi Admin tạo bản ghi Sellers
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION func_sellers_sync_user_role()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE Users
    SET role = 'seller'
    WHERE user_id = NEW.user_id
      AND role <> 'seller';

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER trg_sellers_sync_user_role
AFTER INSERT ON Sellers
FOR EACH ROW
EXECUTE FUNCTION func_sellers_sync_user_role();

-- -----------------------------------------------------------------------------
-- 3. Admin tạo cửa hàng Seller cho user hiện tại
-- Phân vai: hàm = phân quyền + điều kiện nghiệp vụ trước INSERT
--           trigger trg_sellers_sync_user_role = đồng bộ role sau INSERT
-- DROP trước khi CREATE khi đổi tên cột RETURNS TABLE (PostgreSQL không REPLACE được)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION func_admin_create_seller(
    p_user_id INT,
    p_admin_user_id INT,
    p_store_name VARCHAR(100),
    p_description TEXT DEFAULT NULL,
    p_qr_img_path VARCHAR(255) DEFAULT NULL
)
RETURNS TABLE (
    out_seller_id INT,
    out_user_id INT,
    out_store_name VARCHAR(100),
    out_notification_message TEXT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_admin_role VARCHAR(20);
    v_user_role VARCHAR(20);
    v_seller_id INT;
BEGIN
    SELECT role INTO v_admin_role
    FROM Users
    WHERE user_id = p_admin_user_id;

    IF v_admin_role IS NULL THEN
        RAISE EXCEPTION 'Admin user_id % không tồn tại!', p_admin_user_id;
    END IF;

    IF v_admin_role <> 'admin' THEN
        RAISE EXCEPTION 'Chỉ Admin mới được tạo cửa hàng Seller!';
    END IF;

    SELECT role INTO v_user_role
    FROM Users
    WHERE user_id = p_user_id;

    IF v_user_role IS NULL THEN
        RAISE EXCEPTION 'User ID % không tồn tại!', p_user_id;
    END IF;

    IF v_user_role NOT IN ('buyer', 'shipping') THEN
        RAISE EXCEPTION 'Chỉ có thể nâng cấp user buyer/shipping lên Seller. Role hiện tại: %', v_user_role;
    END IF;

    IF EXISTS (SELECT 1 FROM Sellers s WHERE s.user_id = p_user_id) THEN
        RAISE EXCEPTION 'User đã có cửa hàng Seller!';
    END IF;

    IF p_store_name IS NULL OR TRIM(p_store_name) = '' THEN
        RAISE EXCEPTION 'Tên cửa hàng không được để trống!';
    END IF;

    INSERT INTO Sellers (user_id, store_name, description, qr_img_path)
    VALUES (
        p_user_id,
        p_store_name,
        p_description,
        COALESCE(p_qr_img_path, '/images/qr/seller_default.png')
    )
    RETURNING Sellers.seller_id INTO v_seller_id;

    -- role = 'seller' do trigger trg_sellers_sync_user_role xử lý

    RETURN QUERY
    SELECT
        v_seller_id,
        p_user_id,
        p_store_name,
        'Chúc mừng! Tài khoản đã được nâng cấp lên Người bán thành công.'::TEXT;

EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'Tạo cửa hàng Seller thất bại: %', SQLERRM;
END;
$$;

-- -----------------------------------------------------------------------------
-- 4. Tra cứu thông tin cửa hàng theo user
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION func_get_seller_by_user(
    p_user_id INT
)
RETURNS TABLE (
    out_seller_id INT,
    out_user_id INT,
    out_store_name VARCHAR(100),
    out_description TEXT,
    out_qr_img_path VARCHAR(255),
    out_user_role VARCHAR(20)
)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT
        s.seller_id,
        s.user_id,
        s.store_name,
        s.description,
        s.qr_img_path,
        u.role
    FROM Sellers s
    JOIN Users u ON u.user_id = s.user_id
    WHERE s.user_id = p_user_id;
END;
$$;

-- Dọn dữ liệu test: seller_registration_flow_cleanup.sql
-- Kịch bản kiểm thử: seller_registration_flow_test.sql
