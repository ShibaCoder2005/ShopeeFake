-- =============================================================================
-- KỊCH BẢN KIỂM THỬ — Luồng Nâng cấp lên Người bán
-- Thứ tự chạy file:
--   1) create_table.sql
--   2) insert_random_data.sql
--   3) seller_registration_flow.sql
--   4) seller_registration_flow_test.sql
-- =============================================================================

-- -----------------------------------------------------------------------------
-- RESET DỮ LIỆU TEST
-- -----------------------------------------------------------------------------
DELETE FROM Sellers WHERE seller_id > 5;

UPDATE Users
SET role = 'buyer'
WHERE user_id BETWEEN 11 AND 20
  AND role = 'seller'
  AND NOT EXISTS (SELECT 1 FROM Sellers s WHERE s.user_id = Users.user_id);

UPDATE Users
SET role = 'shipping'
WHERE user_id BETWEEN 8 AND 10;

SELECT setval(
    pg_get_serial_sequence('sellers', 'seller_id'),
    COALESCE((SELECT MAX(seller_id) FROM Sellers), 0) + 1,
    false
) AS next_seller_id;

-- -----------------------------------------------------------------------------
-- A. THÀNH CÔNG — Admin nâng cấp buyer lên Seller
-- buyer_an (user_id=11), admin_minh (user_id=1)
-- Kỳ vọng: seller_id=6, role='seller', thông báo thành công
-- -----------------------------------------------------------------------------
SELECT * FROM func_admin_create_seller(
    11,                              -- p_user_id (buyer)
    1,                               -- p_admin_user_id
    'Shop An Fashion',               -- p_store_name
    'Thời trang trẻ trung',          -- p_description
    '/images/qr/seller_an.png'       -- p_qr_img_path
);

SELECT * FROM func_get_seller_by_user(11);
-- Kỳ vọng: out_seller_id=6, out_store_name='Shop An Fashion', out_user_role='seller'

SELECT user_id, username, role FROM Users WHERE user_id = 11;
-- Kỳ vọng: role='seller' (trigger trg_sellers_sync_user_role)

-- -----------------------------------------------------------------------------
-- B. THÀNH CÔNG — Admin nâng cấp tài khoản shipping lên Seller
-- ship_ghn (user_id=8), admin_lan (user_id=2)
-- Kỳ vọng: seller_id=7, role='seller'
-- -----------------------------------------------------------------------------
SELECT * FROM func_admin_create_seller(
    8,                               -- p_user_id (shipping)
    2,                               -- p_admin_user_id
    'GHN Seller Hub',
    'Cửa hàng đối tác GHN'
);

SELECT * FROM func_get_seller_by_user(8);
-- Kỳ vọng: out_seller_id=7, out_user_role='seller'

-- -----------------------------------------------------------------------------
-- C. LỖI — Tạo trùng cửa hàng cho user đã là Seller (chạy riêng, đã comment)
-- Kỳ vọng ERROR: "User đã có cửa hàng Seller!"
-- -----------------------------------------------------------------------------
-- SELECT * FROM func_admin_create_seller(11, 1, 'Shop Trùng');

-- -----------------------------------------------------------------------------
-- D. LỖI — Không phải Admin gọi hàm (chạy riêng, đã comment)
-- Kỳ vọng ERROR: "Chỉ Admin mới được tạo cửa hàng Seller!"
-- -----------------------------------------------------------------------------
-- SELECT * FROM func_admin_create_seller(12, 12, 'Shop Bình');

-- -----------------------------------------------------------------------------
-- E. LỖI — User đã là seller từ seed (seller_hoa user_id=3) (chạy riêng, đã comment)
-- Kỳ vọng ERROR: "Chỉ có thể nâng cấp user buyer/shipping..."
-- -----------------------------------------------------------------------------
-- SELECT * FROM func_admin_create_seller(3, 1, 'Shop Hoa 2');

-- -----------------------------------------------------------------------------
-- F. TỔNG HỢP SAU KỊCH BẢN
-- -----------------------------------------------------------------------------
SELECT s.seller_id, s.user_id, u.username, u.role, s.store_name
FROM Sellers s
JOIN Users u ON u.user_id = s.user_id
WHERE s.seller_id > 5
ORDER BY s.seller_id;

-- Kỳ vọng 2 dòng:
--   seller_id=6, user_id=11, buyer_an,   seller, Shop An Fashion
--   seller_id=7, user_id=8,  ship_ghn,   seller, GHN Seller Hub
