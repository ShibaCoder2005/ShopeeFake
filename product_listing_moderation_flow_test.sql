-- =============================================================================
-- KỊCH BẢN KIỂM THỬ — Luồng Đăng bán & Kiểm duyệt Sản phẩm
-- Thứ tự chạy file:
--   1) create_table.sql
--   2) insert_random_data.sql
--   3) product_listing_moderation_flow.sql
--   4) product_listing_moderation_flow_test.sql
-- =============================================================================

-- -----------------------------------------------------------------------------
-- RESET DỮ LIỆU TEST
-- -----------------------------------------------------------------------------
DELETE FROM Product_categories WHERE product_id > 15;
DELETE FROM Products WHERE product_id > 15;

UPDATE Products
SET approval_status = CASE product_id WHEN 9 THEN 'hidden' ELSE 'approved' END,
    moderation_reason = NULL,
    moderation_note = NULL,
    moderated_at = NULL,
    moderated_by = NULL
WHERE product_id <= 15;

SELECT setval(
    pg_get_serial_sequence('products', 'product_id'),
    COALESCE((SELECT MAX(product_id) FROM Products), 0) + 1,
    false
) AS next_product_id;

-- -----------------------------------------------------------------------------
-- A. THÀNH CÔNG — Seller đăng SP hợp lệ → Hiển thị ngay (approved)
-- seller_hoa (user_id=3), danh mục Thời trang nam (1)
-- Kỳ vọng: product_id=16, approval_status=approved
-- -----------------------------------------------------------------------------
SELECT * FROM func_seller_list_product(
    3,                                      -- p_seller_user_id
    'Áo khoác gió nam chống nước',          -- p_name
    1,                                      -- p_category_id
    299000.00,                              -- p_price
    'Vải polyester chống nước, có mũ trùm.',-- p_description
    50,                                     -- p_stock
    '/images/products/p16.jpg'              -- p_img_path
);

SELECT * FROM func_get_product_moderation_case(16);
-- Kỳ vọng: approved

-- -----------------------------------------------------------------------------
-- B. CHỜ DUYỆT — Seller đăng SP có từ khóa rủi ro → pending
-- Kỳ vọng: product_id=17, approval_status=pending
-- -----------------------------------------------------------------------------
SELECT * FROM func_seller_list_product(
    3,
    'Đồng hồ hàng giả Rolex',
    3,                                      -- Điện thoại & Phụ kiện
    1500000.00,
    'Replica cao cấp, giống hàng thật 99%.',
    10,
    '/images/products/p17.jpg'
);

SELECT * FROM func_get_product_moderation_case(17);
-- Kỳ vọng: pending

-- -----------------------------------------------------------------------------
-- C. ADMIN — Danh sách sản phẩm chờ duyệt
-- admin_minh (user_id=1)
-- Kỳ vọng: có product_id=17
-- -----------------------------------------------------------------------------
SELECT * FROM func_admin_list_pending_products(1);

-- -----------------------------------------------------------------------------
-- D. ADMIN — Từ chối SP vi phạm (hàng giả)
-- Kỳ vọng: hidden, có moderation_reason + thông báo cảnh báo
-- -----------------------------------------------------------------------------
SELECT * FROM func_admin_moderate_product(
    17,                                     -- p_product_id
    1,                                      -- p_admin_user_id
    'reject',                               -- p_decision
    'COUNTERFEIT',                          -- p_reason
    'Phát hiện mô tả hàng nhái, vi phạm chính sách.' -- p_note
);

SELECT * FROM func_get_product_moderation_case(17);
-- Kỳ vọng: hidden, moderation_reason=COUNTERFEIT

-- -----------------------------------------------------------------------------
-- E. ADMIN — Phê duyệt SP hợp lệ (đã hiển thị từ kịch bản A, chạy riêng nếu cần)
-- Kỳ vọng ERROR: "Sản phẩm đã được phê duyệt (approved)!"
-- -----------------------------------------------------------------------------
-- SELECT * FROM func_admin_moderate_product(16, 1, 'approve');

-- -----------------------------------------------------------------------------
-- F. TRANG KHÁCH HÀNG — Chỉ thấy SP approved
-- Kỳ vọng: có product 16, KHÔNG có product 17
-- -----------------------------------------------------------------------------
SELECT product_id, name, approval_status
FROM Products
WHERE product_id IN (16, 17)
ORDER BY product_id;
-- Kỳ vọng: 16 approved, 17 hidden

SELECT COUNT(*) AS approved_new_products
FROM func_get_customer_approved_products()
WHERE out_product_id IN (16, 17);
-- Kỳ vọng: 1 (chỉ product 16)

-- -----------------------------------------------------------------------------
-- G. LỖI — Không phải Seller đăng SP (chạy riêng, đã comment)
-- Kỳ vọng ERROR: "Chỉ Người bán mới được đăng sản phẩm!"
-- -----------------------------------------------------------------------------
-- SELECT * FROM func_seller_list_product(11, 'SP lậu', 1, 100000, 'Test', 1, '/x.jpg');

-- -----------------------------------------------------------------------------
-- H. LỖI — Admin từ chối không có lý do (chạy riêng, đã comment)
-- Kỳ vọng ERROR: "Phải cung cấp lý do khi từ chối/ẩn sản phẩm!"
-- -----------------------------------------------------------------------------
-- SELECT * FROM func_admin_moderate_product(16, 1, 'reject');

-- -----------------------------------------------------------------------------
-- I. TỔNG HỢP SAU KỊCH BẢN
-- -----------------------------------------------------------------------------
SELECT
    p.product_id,
    p.name,
    p.approval_status,
    p.moderation_reason,
    s.store_name
FROM Products p
JOIN Sellers s ON s.seller_id = p.seller_id
WHERE p.product_id > 15
ORDER BY p.product_id;

-- Kỳ vọng:
--   16 | Áo khoác gió...     | approved | NULL         | Shop Thời Trang Hoa
--   17 | Đồng hồ hàng giả... | hidden   | COUNTERFEIT  | Shop Thời Trang Hoa
