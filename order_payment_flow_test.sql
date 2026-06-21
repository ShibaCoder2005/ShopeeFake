-- =============================================================================
-- KỊCH BẢN SỬ DỤNG CÁC HÀM
-- Thứ tự chạy file:
--   1) create_table.sql
--   2) insert_random_data.sql
--   3) order_payment_flow.sql
--   4) order_payment_flow_test.sql
-- =============================================================================

-- -----------------------------------------------------------------------------
-- RESET DỮ LIỆU TEST (để chạy lại nhiều lần cho cùng kết quả kỳ vọng)
-- -----------------------------------------------------------------------------
-- Xóa các đơn phát sinh từ các lần test trước (seed chỉ có order_id 1..10)
DELETE FROM Order_Items WHERE order_id > 10;
DELETE FROM Orders WHERE order_id > 10;

-- Reset tồn kho về đúng dữ liệu seed
UPDATE Products p
SET stock = v.stock,
    approval_status = CASE p.product_id WHEN 9 THEN 'hidden' ELSE 'approved' END
FROM (
    VALUES
        (1, 120), (2, 85), (3, 45), (4, 200), (5, 310),
        (6, 500), (7, 60), (8, 150), (9, 75), (10, 90),
        (11, 220), (12, 55), (13, 40), (14, 30), (15, 100)
) AS v(product_id, stock)
WHERE p.product_id = v.product_id;

-- Reset dữ liệu trả hàng trên chi tiết đơn
UPDATE Order_Items
SET return_quantity = 0,
    return_reason = NULL;

-- Reset các cột mở rộng của Orders về trạng thái ban đầu cho bộ test
UPDATE Orders
SET order_note = NULL,
    shipping_fee = NULL,
    service_fee = NULL,
    delivered_at = NULL,
    received_at = NULL,
    refund_amount = 0,
    seller_revenue = NULL,
    shipping_revenue = NULL,
    settlement_status = NULL,
    can_rate = FALSE,
    can_return = TRUE,
    auto_completed = FALSE;

-- Khôi phục trạng thái/payment_status seed cho các order dùng trong kịch bản
-- Tạm tắt trigger validate để cho phép reset từ trạng thái đã mutate (vd: returned -> delivered)
ALTER TABLE Orders DISABLE TRIGGER trg_orders_validate_status;

UPDATE Orders
SET status = CASE order_id
    WHEN 1 THEN 'delivered'
    WHEN 2 THEN 'delivered'
    WHEN 3 THEN 'shipping'
    WHEN 4 THEN 'confirmed'
    WHEN 5 THEN 'pending'
    WHEN 6 THEN 'delivered'
    WHEN 7 THEN 'cancelled'
    WHEN 8 THEN 'delivered'
    WHEN 9 THEN 'shipping'
    WHEN 10 THEN 'confirmed'
END,
payment_status = CASE order_id
    WHEN 1 THEN 'paid'
    WHEN 2 THEN 'paid'
    WHEN 3 THEN 'paid'
    WHEN 4 THEN 'paid'
    WHEN 5 THEN 'unpaid'
    WHEN 6 THEN 'paid'
    WHEN 7 THEN 'refunded'
    WHEN 8 THEN 'paid'
    WHEN 9 THEN 'paid'
    WHEN 10 THEN 'paid'
END
WHERE order_id BETWEEN 1 AND 10;

ALTER TABLE Orders ENABLE TRIGGER trg_orders_validate_status;

-- Khôi phục giỏ hàng về seed cho các kịch bản đặt hàng
DELETE FROM Cart_items;
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

-- -----------------------------------------------------------------------------
-- 0. CHUẨN BỊ MÔI TRƯỜNG (chạy một lần sau insert_random_data.sql)
-- -----------------------------------------------------------------------------

-- 0.1 Đồng bộ sequence order_id (tránh lỗi duplicate key khi đặt hàng mới)
SELECT setval(
    pg_get_serial_sequence('orders', 'order_id'),
    COALESCE((SELECT MAX(order_id) FROM Orders), 0) + 1,
    false
) AS next_order_id;

-- 0.2 Bổ sung dữ liệu phụ cho đơn delivered (seed chưa có delivered_at / shipping_fee)
UPDATE Orders
SET delivered_at = COALESCE(delivered_at, order_date + INTERVAL '3 days'),
    shipping_fee = COALESCE(shipping_fee, 30000.00),
    service_fee  = COALESCE(service_fee, 5000.00)
WHERE status = 'delivered';

-- -----------------------------------------------------------------------------
-- 1. ĐẶT HÀNG — func_place_order
-- Kịch bản: buyer_binh (12) thanh toán đơn từ TechZone Tuấn (seller 2) qua GHTK
-- Giỏ hàng cart_id=2: product 4 (×1), product 5 (×2)
-- -----------------------------------------------------------------------------
SELECT func_place_order(
    12,                          -- p_user_id
    2,                           -- p_seller_id
    2,                           -- p_shipping_units_id (GHTK)
    'vnpay',                     -- p_payment_method
    'Giao giờ hành chính',       -- p_order_note
    25000.00                     -- p_shipping_fee
) AS new_order_id;

-- Kiểm tra: đơn mới, chi tiết, giỏ hàng seller 2 đã được dọn
SELECT order_id, status, payment_status, amount, shipping_fee, service_fee
FROM Orders
WHERE order_id = (SELECT MAX(order_id) FROM Orders);

SELECT oi.product_id, oi.quantity, p.name, p.price
FROM Order_Items oi
JOIN Products p ON p.product_id = oi.product_id
WHERE oi.order_id = (SELECT MAX(order_id) FROM Orders);

SELECT ci.product_id, ci.quantity
FROM Cart_items ci
JOIN Carts c ON c.cart_id = ci.cart_id
JOIN Products p ON p.product_id = ci.product_id
WHERE c.user_id = 12 AND p.seller_id = 2;
-- Kỳ vọng: 0 dòng (đã xóa khỏi giỏ)

-- -----------------------------------------------------------------------------
-- 2. HỦY ĐƠN — func_cancel_order
-- Kịch bản: buyer_em (15) hủy đơn 5 đang pending, chưa thanh toán
-- -----------------------------------------------------------------------------
SELECT func_cancel_order(5) AS cancelled;

-- Kiểm tra: status cancelled, tồn kho product 13 được hoàn (+1)
SELECT order_id, status, payment_status FROM Orders WHERE order_id = 5;
SELECT product_id, stock FROM Products WHERE product_id = 13;

-- -----------------------------------------------------------------------------
-- 3. XÁC NHẬN ĐÃ NHẬN HÀNG — func_confirm_received
-- Kịch bản: buyer_binh (12) xác nhận đơn 2 (delivered, paid), chốt doanh thu
-- -----------------------------------------------------------------------------
SELECT * FROM func_confirm_received(2, 12);

-- Kiểm tra: received, chốt tiền seller/ship, mở đánh giá, vẫn được trả hàng
SELECT order_id, status, received_at, seller_revenue, shipping_revenue,
       settlement_status, can_rate, can_return, auto_completed
FROM Orders WHERE order_id = 2;

-- -----------------------------------------------------------------------------
-- 4. TRẢ HÀNG & HOÀN TIỀN — func_process_return
-- Kịch bản A: buyer_an (11) trả 1 áo thun trên đơn 1 (delivered, chưa xác nhận)
-- Hoàn: 189.000đ (1 × giá product 1)
-- -----------------------------------------------------------------------------
SELECT func_process_return(
    1,                       -- p_order_id
    1,                       -- p_product_id
    1,                       -- p_return_quantity
    'Áo bị lỗi đường may'    -- p_return_reason
) AS refund_amount;

-- Kiểm tra: hoàn một phần
SELECT order_id, status, payment_status, refund_amount, can_return
FROM Orders WHERE order_id = 1;

SELECT product_id, quantity, return_quantity, return_reason
FROM Order_Items WHERE order_id = 1;

-- Kịch bản B: trả nốt product 3 → trả hết đơn → hoàn thêm phí ship
SELECT func_process_return(1, 3, 1, 'Giày không vừa size') AS refund_amount;

SELECT order_id, status, payment_status, refund_amount, shipping_fee
FROM Orders WHERE order_id = 1;
-- Kỳ vọng: status=returned, payment_status=refunded

-- -----------------------------------------------------------------------------
-- 5. TỰ ĐỘNG CHỐT ĐƠN SAU 3 NGÀY — func_auto_complete_orders
-- Kịch bản: buyer_phuong (16) quên xác nhận đơn 6 → hệ thống auto-complete
-- -----------------------------------------------------------------------------
-- Chuẩn bị: giả lập giao hàng cách đây 4 ngày
UPDATE Orders
SET delivered_at = CURRENT_TIMESTAMP - INTERVAL '4 days',
    received_at    = NULL,
    status         = 'delivered',
    can_return     = TRUE,
    can_rate       = FALSE,
    auto_completed = FALSE
WHERE order_id = 6;

SELECT * FROM func_auto_complete_orders();

-- Kiểm tra: received tự động, khóa trả hàng, vẫn mở đánh giá
SELECT order_id, status, received_at, seller_revenue, shipping_revenue,
       can_rate, can_return, auto_completed
FROM Orders WHERE order_id = 6;

-- Thử trả hàng sau auto-complete → phải bị từ chối
-- SELECT func_process_return(6, 2, 1, 'Muốn trả quần jean');
-- Kỳ vọng: ERROR "Đơn hàng đã khóa quyền trả hàng và hoàn tiền!"

-- -----------------------------------------------------------------------------
-- 6. TỔNG HỢP TRẠNG THÁI CÁC ĐƠN SAU KỊCH BẢN
-- -----------------------------------------------------------------------------
SELECT order_id, user_id, status, payment_status,
       amount, refund_amount, seller_revenue, shipping_revenue,
       can_rate, can_return, auto_completed,
       delivered_at, received_at
FROM Orders
ORDER BY order_id;
