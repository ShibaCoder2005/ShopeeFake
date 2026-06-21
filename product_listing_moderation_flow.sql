-- =============================================================================
-- Luồng Đăng bán & Kiểm duyệt Sản phẩm
-- Swimlanes: Người bán | Hệ thống | Admin
-- Chạy sau: create_table.sql (+ insert_random_data.sql)
--
-- Logic:
--   [Người bán] Nhập thông tin SP (Tên, Danh mục, Giá, Ảnh, Mô tả)
--   [Hệ thống] Validate → lưu SP trạng thái "pending" (Chờ duyệt) hoặc "approved" (Hiển thị)
--   [Admin] Theo dõi SP mới → Phê duyệt hoặc Ẩn/Gỡ (ghi lý do, thông báo Seller)
--   [Hệ thống] Cập nhật hiển thị trang Khách hàng
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Trigger: validate approval_status + moderation_reason
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION func_validate_product_moderation_fields()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.approval_status NOT IN ('pending', 'approved', 'hidden') THEN
        RAISE EXCEPTION 'Trạng thái duyệt sản phẩm không hợp lệ: %', NEW.approval_status;
    END IF;

    IF NEW.moderation_reason IS NOT NULL
       AND NEW.moderation_reason NOT IN (
           'COUNTERFEIT',
           'WRONG_CATEGORY',
           'PROHIBITED_CONTENT',
           'MISLEADING_INFO',
           'OTHER'
       ) THEN
        RAISE EXCEPTION 'Lý do kiểm duyệt không hợp lệ: %', NEW.moderation_reason;
    END IF;

    IF NEW.price <= 0 THEN
        RAISE EXCEPTION 'Giá sản phẩm phải lớn hơn 0!';
    END IF;

    IF NEW.stock < 0 THEN
        RAISE EXCEPTION 'Tồn kho không được âm!';
    END IF;

    IF NEW.name IS NULL OR TRIM(NEW.name) = '' THEN
        RAISE EXCEPTION 'Tên sản phẩm không được để trống!';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER trg_products_validate_moderation_fields
BEFORE INSERT OR UPDATE OF approval_status, moderation_reason, price, stock, name ON Products
FOR EACH ROW
EXECUTE FUNCTION func_validate_product_moderation_fields();

-- -----------------------------------------------------------------------------
-- 2. Người bán đăng sản phẩm mới
-- Validate dữ liệu → pending (có từ khóa rủi ro) hoặc approved (hiển thị ngay)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION func_seller_list_product(
    p_seller_user_id INT,
    p_name VARCHAR(255),
    p_category_id INT,
    p_price DECIMAL(12, 2),
    p_description TEXT DEFAULT NULL,
    p_stock INT DEFAULT 0,
    p_img_path VARCHAR(255) DEFAULT NULL
)
RETURNS TABLE (
    out_product_id INT,
    out_approval_status VARCHAR(20),
    out_notification_message TEXT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_seller_id INT;
    v_user_role VARCHAR(20);
    v_product_id INT;
    v_status VARCHAR(20);
    v_text TEXT;
    v_msg TEXT;
BEGIN
    SELECT u.role INTO v_user_role
    FROM Users u
    WHERE u.user_id = p_seller_user_id;

    IF v_user_role IS NULL THEN
        RAISE EXCEPTION 'User ID % không tồn tại!', p_seller_user_id;
    END IF;

    IF v_user_role <> 'seller' THEN
        RAISE EXCEPTION 'Chỉ Người bán mới được đăng sản phẩm!';
    END IF;

    SELECT s.seller_id INTO v_seller_id
    FROM Sellers s
    WHERE s.user_id = p_seller_user_id;

    IF v_seller_id IS NULL THEN
        RAISE EXCEPTION 'User chưa có cửa hàng Seller!';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM Categories c WHERE c.category_id = p_category_id) THEN
        RAISE EXCEPTION 'Danh mục ID % không tồn tại!', p_category_id;
    END IF;

    IF p_price IS NULL OR p_price <= 0 THEN
        RAISE EXCEPTION 'Giá sản phẩm phải lớn hơn 0!';
    END IF;

    IF p_stock IS NULL OR p_stock < 0 THEN
        RAISE EXCEPTION 'Tồn kho không được âm!';
    END IF;

    IF p_name IS NULL OR TRIM(p_name) = '' THEN
        RAISE EXCEPTION 'Tên sản phẩm không được để trống!';
    END IF;

    IF p_img_path IS NULL OR TRIM(p_img_path) = '' THEN
        RAISE EXCEPTION 'Ảnh sản phẩm không được để trống!';
    END IF;

    v_text := LOWER(CONCAT(p_name, ' ', COALESCE(p_description, '')));
    IF v_text ~ '(hàng giả|hang gia|fake|replica|nhái|nhai|super fake)' THEN
        v_status := 'pending';
        v_msg := 'Sản phẩm đã lưu với trạng thái Chờ duyệt. Hệ thống phát hiện nội dung cần Admin xem xét.';
    ELSE
        v_status := 'approved';
        v_msg := 'Sản phẩm đã được đăng và hiển thị trên trang Khách hàng.';
    END IF;

    INSERT INTO Products (
        name, price, description, stock, img_path,
        seller_id, approval_status, submitted_at
    )
    VALUES (
        TRIM(p_name),
        p_price,
        p_description,
        p_stock,
        p_img_path,
        v_seller_id,
        v_status,
        CURRENT_TIMESTAMP
    )
    RETURNING Products.product_id INTO v_product_id;

    INSERT INTO Product_categories (product_id, category_id)
    VALUES (v_product_id, p_category_id);

    RETURN QUERY
    SELECT
        v_product_id,
        v_status,
        v_msg;

EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'Đăng sản phẩm thất bại: %', SQLERRM;
END;
$$;

-- -----------------------------------------------------------------------------
-- 3. Admin xem danh sách sản phẩm chờ duyệt
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION func_admin_list_pending_products(
    p_admin_user_id INT
)
RETURNS TABLE (
    out_product_id INT,
    out_name VARCHAR(255),
    out_price DECIMAL(12, 2),
    out_seller_id INT,
    out_store_name VARCHAR(100),
    out_category_name VARCHAR(100),
    out_submitted_at TIMESTAMP
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_admin_role VARCHAR(20);
BEGIN
    SELECT u.role INTO v_admin_role
    FROM Users u
    WHERE u.user_id = p_admin_user_id;

    IF v_admin_role IS NULL THEN
        RAISE EXCEPTION 'Admin user_id % không tồn tại!', p_admin_user_id;
    END IF;

    IF v_admin_role <> 'admin' THEN
        RAISE EXCEPTION 'Chỉ Admin mới được xem danh sách chờ duyệt!';
    END IF;

    RETURN QUERY
    SELECT
        p.product_id,
        p.name,
        p.price,
        p.seller_id,
        s.store_name,
        c.name,
        p.submitted_at
    FROM Products p
    JOIN Sellers s ON s.seller_id = p.seller_id
    LEFT JOIN Product_categories pc ON pc.product_id = p.product_id
    LEFT JOIN Categories c ON c.category_id = pc.category_id
    WHERE p.approval_status = 'pending'
    ORDER BY p.submitted_at ASC, p.product_id ASC;
END;
$$;

-- -----------------------------------------------------------------------------
-- 4. Admin quyết định duyệt / ẩn sản phẩm
-- p_decision: approve | reject
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION func_admin_moderate_product(
    p_product_id INT,
    p_admin_user_id INT,
    p_decision VARCHAR(20),
    p_reason VARCHAR(50) DEFAULT NULL,
    p_note TEXT DEFAULT NULL
)
RETURNS TABLE (
    out_product_id INT,
    out_approval_status VARCHAR(20),
    out_notification_message TEXT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_admin_role VARCHAR(20);
    v_current_status VARCHAR(20);
    v_seller_user_id INT;
    v_store_name VARCHAR(100);
    v_product_name VARCHAR(255);
    v_new_status VARCHAR(20);
    v_msg TEXT;
BEGIN
    SELECT u.role INTO v_admin_role
    FROM Users u
    WHERE u.user_id = p_admin_user_id;

    IF v_admin_role IS NULL THEN
        RAISE EXCEPTION 'Admin user_id % không tồn tại!', p_admin_user_id;
    END IF;

    IF v_admin_role <> 'admin' THEN
        RAISE EXCEPTION 'Chỉ Admin mới được kiểm duyệt sản phẩm!';
    END IF;

    IF p_decision NOT IN ('approve', 'reject') THEN
        RAISE EXCEPTION 'Quyết định không hợp lệ: %. Chỉ chấp nhận approve hoặc reject.', p_decision;
    END IF;

    SELECT p.approval_status, p.name, s.user_id, s.store_name
    INTO v_current_status, v_product_name, v_seller_user_id, v_store_name
    FROM Products p
    JOIN Sellers s ON s.seller_id = p.seller_id
    WHERE p.product_id = p_product_id;

    IF v_current_status IS NULL THEN
        RAISE EXCEPTION 'Sản phẩm ID % không tồn tại!', p_product_id;
    END IF;

    IF p_decision = 'approve' THEN
        IF v_current_status = 'approved' THEN
            RAISE EXCEPTION 'Sản phẩm đã được phê duyệt (approved)!';
        END IF;

        v_new_status := 'approved';

        UPDATE Products
        SET approval_status = v_new_status,
            moderation_reason = NULL,
            moderation_note = COALESCE(p_note, 'Admin đã phê duyệt sản phẩm.'),
            moderated_at = CURRENT_TIMESTAMP,
            moderated_by = p_admin_user_id
        WHERE product_id = p_product_id;

        v_msg := FORMAT(
            'Sản phẩm "%s" của cửa hàng %s đã được phê duyệt và hiển thị.',
            v_product_name,
            v_store_name
        );

    ELSE
        IF p_reason IS NULL THEN
            RAISE EXCEPTION 'Phải cung cấp lý do khi từ chối/ẩn sản phẩm!';
        END IF;

        v_new_status := 'hidden';

        UPDATE Products
        SET approval_status = v_new_status,
            moderation_reason = p_reason,
            moderation_note = p_note,
            moderated_at = CURRENT_TIMESTAMP,
            moderated_by = p_admin_user_id
        WHERE product_id = p_product_id;

        v_msg := FORMAT(
            'CẢNH BÁO: Sản phẩm "%s" đã bị ẩn/gỡ bỏ. Lý do: %s. %s',
            v_product_name,
            p_reason,
            COALESCE(p_note, '')
        );
    END IF;

    RETURN QUERY
    SELECT
        p_product_id,
        v_new_status,
        v_msg;

EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'Kiểm duyệt sản phẩm thất bại: %', SQLERRM;
END;
$$;

-- -----------------------------------------------------------------------------
-- 5. Trang Khách hàng — chỉ SP đã phê duyệt (approval_status = 'approved')
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION func_get_customer_approved_products()
RETURNS TABLE (
    out_product_id INT,
    out_name VARCHAR(255),
    out_price DECIMAL(12, 2),
    out_stock INT,
    out_img_path VARCHAR(255),
    out_store_name VARCHAR(100)
)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT
        p.product_id,
        p.name,
        p.price,
        p.stock,
        p.img_path,
        s.store_name
    FROM Products p
    JOIN Sellers s ON s.seller_id = p.seller_id
    WHERE p.approval_status = 'approved'
    ORDER BY p.product_id ASC;
END;
$$;

-- -----------------------------------------------------------------------------
-- 6. Tra cứu hồ sơ kiểm duyệt một sản phẩm
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION func_get_product_moderation_case(
    p_product_id INT
)
RETURNS TABLE (
    out_product_id INT,
    out_name VARCHAR(255),
    out_approval_status VARCHAR(20),
    out_moderation_reason VARCHAR(50),
    out_moderation_note TEXT,
    out_moderated_at TIMESTAMP,
    out_moderator_username VARCHAR(50)
)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT
        p.product_id,
        p.name,
        p.approval_status,
        p.moderation_reason,
        p.moderation_note,
        p.moderated_at,
        u.username
    FROM Products p
    LEFT JOIN Users u ON u.user_id = p.moderated_by
    WHERE p.product_id = p_product_id;
END;
$$;

-- Kịch bản kiểm thử: product_listing_moderation_flow_test.sql
