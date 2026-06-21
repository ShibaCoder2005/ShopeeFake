-- Dữ liệu mẫu cho ShopeeFake (chỉ dùng INSERT ... VALUES)
-- Chạy sau create_table.sql
-- Thứ tự: Categories -> Users -> Admin/Sellers/Shipping_units -> Carts -> Products
--         -> Product_categories -> Orders -> Cart_items -> Order_Items

BEGIN;

-- ============================================================
-- 1. Categories (không phụ thuộc bảng khác)
-- ============================================================
INSERT INTO Categories (category_id, name) VALUES
(1, 'Thời trang nam'),
(2, 'Thời trang nữ'),
(3, 'Điện thoại & Phụ kiện'),
(4, 'Máy tính & Laptop'),
(5, 'Đồ gia dụng'),
(6, 'Mẹ & Bé'),
(7, 'Sắc đẹp'),
(8, 'Thể thao & Du lịch'),
(9, 'Sách & Văn phòng phẩm'),
(10, 'Thực phẩm & Đồ uống');

-- ============================================================
-- 2. Users (không phụ thuộc bảng khác)
--    user_id 1-2: admin | 3-7: seller | 8-10: shipping | 11-20: buyer
-- ============================================================
INSERT INTO Users (user_id, username, password, email, address, phone, full_name, role, locked) VALUES
(1,  'admin_minh',    'e10adc3949ba59abbe56e057f20f883e', 'admin.minh@shopeefake.vn',    '123 Nguyễn Huệ, Q.1, TP.HCM',           '0901000001', 'Nguyễn Văn Minh',  'admin',    FALSE),
(2,  'admin_lan',     'e10adc3949ba59abbe56e057f20f883e', 'admin.lan@shopeefake.vn',     '56 Hai Bà Trưng, Q. Hoàn Kiếm, Hà Nội',  '0901000002', 'Trần Thị Lan',     'admin',    FALSE),
(3,  'seller_hoa',    'e10adc3949ba59abbe56e057f20f883e', 'seller.hoa@shopeefake.vn',    '45 Lê Lợi, Q.3, TP.HCM',                 '0902000003', 'Lê Thị Hoa',       'seller',   FALSE),
(4,  'seller_tuan',   'e10adc3949ba59abbe56e057f20f883e', 'seller.tuan@shopeefake.vn',   '78 Trần Hưng Đạo, Q.5, TP.HCM',          '0902000004', 'Phạm Văn Tuấn',    'seller',   FALSE),
(5,  'seller_mai',    'e10adc3949ba59abbe56e057f20f883e', 'seller.mai@shopeefake.vn',    '89 Lê Duẩn, Q. Hải Châu, Đà Nẵng',       '0902000005', 'Hoàng Thị Mai',    'seller',   FALSE),
(6,  'seller_khoa',   'e10adc3949ba59abbe56e057f20f883e', 'seller.khoa@shopeefake.vn',   '12 Phan Chu Trinh, Q. Hoàn Kiếm, Hà Nội','0902000006', 'Vũ Văn Khoa',      'seller',   FALSE),
(7,  'seller_ngoc',   'e10adc3949ba59abbe56e057f20f883e', 'seller.ngoc@shopeefake.vn',   '34 Nguyễn Văn Cừ, Q. Ninh Kiều, Cần Thơ','0902000007', 'Đặng Thị Ngọc',    'seller',   FALSE),
(8,  'ship_ghn',      'e10adc3949ba59abbe56e057f20f883e', 'ship.ghn@shopeefake.vn',      '100 Võ Văn Tần, Q.3, TP.HCM',            '0903000008', 'Ngô Văn Hùng',     'shipping', FALSE),
(9,  'ship_ghtk',     'e10adc3949ba59abbe56e057f20f883e', 'ship.ghtk@shopeefake.vn',     '200 Cầu Giấy, Q. Cầu Giấy, Hà Nội',      '0903000009', 'Bùi Văn Nam',      'shipping', FALSE),
(10, 'ship_jnt',      'e10adc3949ba59abbe56e057f20f883e', 'ship.jnt@shopeefake.vn',      '300 Nguyễn Văn Linh, Q.7, TP.HCM',       '0903000010', 'Dương Văn Phúc',   'shipping', FALSE),
(11, 'buyer_an',      'e10adc3949ba59abbe56e057f20f883e', 'buyer.an@shopeefake.vn',      '15 Pasteur, Q.1, TP.HCM',                '0904000011', 'Nguyễn Văn An',    'buyer',    FALSE),
(12, 'buyer_binh',    'e10adc3949ba59abbe56e057f20f883e', 'buyer.binh@shopeefake.vn',    '22 Lý Tự Trọng, Q.1, TP.HCM',            '0904000012', 'Trần Thị Bình',    'buyer',    FALSE),
(13, 'buyer_cuong',   'e10adc3949ba59abbe56e057f20f883e', 'buyer.cuong@shopeefake.vn',   '8 Hàng Bài, Q. Hoàn Kiếm, Hà Nội',       '0904000013', 'Lê Văn Cường',     'buyer',    FALSE),
(14, 'buyer_dung',    'e10adc3949ba59abbe56e057f20f883e', 'buyer.dung@shopeefake.vn',    '55 Trần Phú, Q. Hải Châu, Đà Nẵng',      '0904000014', 'Phạm Thị Dung',    'buyer',    FALSE),
(15, 'buyer_em',      'e10adc3949ba59abbe56e057f20f883e', 'buyer.em@shopeefake.vn',      '90 Mậu Thân, Q. Ninh Kiều, Cần Thơ',     '0904000015', 'Hoàng Văn Em',     'buyer',    FALSE),
(16, 'buyer_phuong',  'e10adc3949ba59abbe56e057f20f883e', 'buyer.phuong@shopeefake.vn',  '17 Nguyễn Trãi, Q. Thanh Xuân, Hà Nội',  '0904000016', 'Vũ Thị Phương',    'buyer',    FALSE),
(17, 'buyer_giang',   'e10adc3949ba59abbe56e057f20f883e', 'buyer.giang@shopeefake.vn',   '63 Võ Thị Sáu, Q.3, TP.HCM',             '0904000017', 'Đặng Văn Giang',   'buyer',    FALSE),
(18, 'buyer_hoa',     'e10adc3949ba59abbe56e057f20f883e', 'buyer.hoa@shopeefake.vn',     '41 Lê Lai, Q.1, TP.HCM',                 '0904000018', 'Bùi Thị Hoa',      'buyer',    FALSE),
(19, 'buyer_ich',     'e10adc3949ba59abbe56e057f20f883e', 'buyer.ich@shopeefake.vn',     '28 Bạch Đằng, Q. Hải Châu, Đà Nẵng',     '0904000019', 'Ngô Văn Ích',      'buyer',    TRUE),
(20, 'buyer_kim',     'e10adc3949ba59abbe56e057f20f883e', 'buyer.kim@shopeefake.vn',     '5 Nguyễn Đình Chiểu, Q.3, TP.HCM',       '0904000020', 'Dương Thị Kim',    'buyer',    FALSE);

-- ============================================================
-- 3. Admin (phụ thuộc Users)
-- ============================================================
INSERT INTO Admin (admin_id, user_id, bank_account_number, bank_account_name, qr_img_path) VALUES
(1, 1, '012345678901', 'Nguyễn Văn Minh', '/images/qr/admin_1.png'),
(2, 2, '987654321098', 'Trần Thị Lan',    '/images/qr/admin_2.png');

-- ============================================================
-- 4. Sellers (phụ thuộc Users)
-- ============================================================
INSERT INTO Sellers (seller_id, user_id, store_name, description, qr_img_path) VALUES
(1, 3, 'Shop Thời Trang Hoa',   'Thời trang nam nữ giá tốt, freeship nội thành.',     '/images/qr/seller_1.png'),
(2, 4, 'TechZone Tuấn',         'Điện thoại, phụ kiện công nghệ chính hãng.',         '/images/qr/seller_2.png'),
(3, 5, 'Nhà Cửa Xinh Mai',      'Đồ gia dụng thông minh cho mọi gia đình.',           '/images/qr/seller_3.png'),
(4, 6, 'Beauty House Khoa',     'Mỹ phẩm Hàn - Nhật, cam kết hàng thật.',             '/images/qr/seller_4.png'),
(5, 7, 'Sport Pro Ngọc',        'Dụng cụ thể thao, balo du lịch giá sỉ.',             '/images/qr/seller_5.png');

-- ============================================================
-- 5. Shipping_units (phụ thuộc Users)
-- ============================================================
INSERT INTO Shipping_units (shipping_units_id, user_id, company_name) VALUES
(1, 8,  'Giao Hàng Nhanh'),
(2, 9,  'Giao Hàng Tiết Kiệm'),
(3, 10, 'J&T Express');

-- ============================================================
-- 6. Carts (phụ thuộc Users — buyer)
-- ============================================================
INSERT INTO Carts (cart_id, user_id) VALUES
(1, 11),
(2, 12),
(3, 13),
(4, 14),
(5, 15);

-- ============================================================
-- 7. Products (phụ thuộc Sellers)
-- ============================================================
INSERT INTO Products (product_id, name, price, description, stock, img_path, approval_status, seller_id) VALUES
(1,  'Áo thun nam Premium - Trắng',       189000.00, 'Cotton 100%, form regular fit.',              120, '/images/products/p1.jpg',  'approved', 1),
(2,  'Quần jean nam Slim Fit',             349000.00, 'Jean co giãn, màu xanh đậm.',                 85,  '/images/products/p2.jpg',  'approved', 1),
(3,  'Giày sneaker unisex Lite',           520000.00, 'Đế cao su chống trượt, size 39-43.',          45,  '/images/products/p3.jpg',  'approved', 1),
(4,  'Tai nghe Bluetooth Pro Max',         890000.00, 'Chống ồn chủ động, pin 30 giờ.',              200, '/images/products/p4.jpg',  'approved', 2),
(5,  'Sạc nhanh 65W USB-C',                259000.00, 'Tương thích iPhone, Samsung, laptop.',          310, '/images/products/p5.jpg',  'approved', 2),
(6,  'Ốp lưng điện thoại trong suốt',      45000.00,  'Chống sốc 4 góc, dày 1.2mm.',                  500, '/images/products/p6.jpg',  'approved', 2),
(7,  'Nồi cơm điện 1.8L Smart',            1250000.00,'Nấu cơm, hấp, nấu cháo, hẹn giờ.',             60,  '/images/products/p7.jpg',  'approved', 3),
(8,  'Bình giữ nhiệt 500ml',               135000.00, 'Giữ nóng 12h, giữ lạnh 24h.',                 150, '/images/products/p8.jpg',  'approved', 3),
(9,  'Máy xay sinh tố cầm tay',             420000.00, 'Công suất 700W, 2 tốc độ.',                   75,  '/images/products/p9.jpg',  'hidden',   3),
(10, 'Kem dưỡng da ban đêm 50ml',          320000.00, 'Dưỡng ẩm sâu, phù hợp da khô.',               90,  '/images/products/p10.jpg', 'approved', 4),
(11, 'Son môi lì Ultra Red',               175000.00, 'Màu đỏ cam, giữ màu 8 giờ.',                  220, '/images/products/p11.jpg', 'approved', 4),
(12, 'Serum vitamin C 30ml',               450000.00, 'Làm sáng da, giảm thâm nám.',                 55,  '/images/products/p12.jpg', 'approved', 4),
(13, 'Balo du lịch 40L chống nước',         680000.00, 'Ngăn laptop 15.6 inch, chống nước IPX4.',     40,  '/images/products/p13.jpg', 'approved', 5),
(14, 'Giày chạy bộ Air Flex',              1150000.00,'Đế Phylon nhẹ, thoáng khí.',                  30,  '/images/products/p14.jpg', 'approved', 5),
(15, 'Thảm yoga cao su tự nhiên',          290000.00, 'Dày 6mm, chống trượt hai mặt.',               100, '/images/products/p15.jpg', 'approved', 5);

-- ============================================================
-- 8. Product_categories (phụ thuộc Products, Categories)
-- ============================================================
INSERT INTO Product_categories (product_id, category_id) VALUES
(1,  1), (1,  2),
(2,  1),
(3,  1), (3,  8),
(4,  3),
(5,  3), (5,  4),
(6,  3),
(7,  5),
(8,  5), (8,  10),
(9,  5),
(10, 7),
(11, 7),
(12, 7),
(13, 8),
(14, 8),
(15, 8);

-- ============================================================
-- 9. Orders (phụ thuộc Users, Sellers, Shipping_units)
-- ============================================================
INSERT INTO Orders (
    order_id, order_date, status, tracking_number, shipping_status,
    estimated_delivery, payment_id, payment_date, payment_method,
    amount, payment_status, user_id, seller_id, shipping_units_id
) VALUES
(1,  '2025-03-01 09:15:00', 'delivered',  'VN000000000001', 'delivered',  '2025-03-04 18:00:00', 'PAY-001', '2025-03-01 09:20:00', 'momo',         538000.00, 'paid',    11, 1, 1),
(2,  '2025-03-05 14:30:00', 'delivered',  'VN000000000002', 'delivered',  '2025-03-08 12:00:00', 'PAY-002', '2025-03-05 14:35:00', 'vnpay',        890000.00, 'paid',    12, 2, 2),
(3,  '2025-03-10 08:00:00', 'shipping',   'VN000000000003', 'in_transit', '2025-03-13 17:00:00', 'PAY-003', '2025-03-10 08:05:00', 'cod',          1250000.00,'paid',    13, 3, 3),
(4,  '2025-03-12 16:45:00', 'confirmed',  'VN000000000004', 'picked_up',  '2025-03-15 10:00:00', 'PAY-004', '2025-03-12 16:50:00', 'bank_transfer',495000.00, 'paid',    14, 4, 1),
(5,  '2025-03-15 11:20:00', 'pending',    NULL,             'waiting',    '2025-03-18 15:00:00', NULL,      NULL,                  'cod',          680000.00, 'unpaid',  15, 5, 2),
(6,  '2025-02-20 10:10:00', 'delivered',  'VN000000000006', 'delivered',  '2025-02-23 14:00:00', 'PAY-006', '2025-02-20 10:15:00', 'credit_card',  349000.00, 'paid',    16, 1, 3),
(7,  '2025-02-25 19:00:00', 'cancelled',  NULL,             'waiting',    NULL,                  NULL,      NULL,                  'momo',         45000.00,  'refunded',17, 2, 1),
(8,  '2025-04-01 07:30:00', 'delivered',  'VN000000000008', 'delivered',  '2025-04-04 11:00:00', 'PAY-008', '2025-04-01 07:35:00', 'vnpay',        1360000.00,'paid',    18, 5, 2),
(9,  '2025-04-05 13:00:00', 'shipping',   'VN000000000009', 'in_transit', '2025-04-08 16:00:00', 'PAY-009', '2025-04-05 13:05:00', 'momo',         304000.00, 'paid',    19, 4, 3),
(10, '2025-04-08 20:15:00', 'confirmed',  'VN000000000010', 'picked_up',  '2025-04-11 09:00:00', 'PAY-010', '2025-04-08 20:20:00', 'bank_transfer',520000.00, 'paid',    20, 1, 1);

-- ============================================================
-- 10. Cart_items (phụ thuộc Carts, Products)
-- ============================================================
INSERT INTO Cart_items (cart_id, product_id, quantity) VALUES
(1, 1, 2),
(1, 3, 1),
(2, 4, 1),
(2, 5, 2),
(3, 7, 1),
(3, 8, 3),
(4, 10, 1),
(4, 11, 2),
(5, 13, 1),
(5, 15, 1);

-- ============================================================
-- 11. Order_Items (phụ thuộc Orders, Products)
--     product_id phải thuộc seller của đơn hàng tương ứng
-- ============================================================
INSERT INTO Order_Items (order_id, product_id, quantity, comment, rating) VALUES
(1,  1, 2, 'Áo đẹp, vải mát.',                    5),
(1,  3, 1, 'Giày êm chân, giao nhanh.',            4),
(2,  4, 1, 'Tai nghe ok, bass tốt.',               5),
(3,  7, 1, NULL,                                   NULL),
(4,  10, 1, 'Kem thấm nhanh, không bết dính.',     4),
(4,  11, 2, 'Màu son đúng như hình.',               5),
(5,  13, 1, NULL,                                   NULL),
(6,  2, 1, 'Quần vừa size, chất jean tốt.',        4),
(7,  6, 1, NULL,                                   NULL),
(8,  13, 1, 'Balo rộng, đi phượt rất ổn.',          5),
(8,  14, 1, 'Giày chạy nhẹ, thoáng chân.',          4),
(9,  12, 1, NULL,                                   NULL),
(10, 1, 1, NULL,                                   NULL),
(10, 3, 1, 'Giao hàng đúng hẹn.',                  5);

COMMIT;
