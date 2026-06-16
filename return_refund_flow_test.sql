-- =============================================================================
-- KỊCH BẢN KIỂM THỬ — Luồng Trả hàng & Hoàn tiền
-- Thứ tự chạy file:
--   1) create_table.sql
--   2) insert_random_data.sql
--   3) order_payment_flow.sql          (cột phụ: shipping_fee, service_fee, delivered_at...)
--   4) return_refund_flow.sql
--   5) return_refund_flow_test.sql
-- =============================================================================

-- -----------------------------------------------------------------------------
-- RESET DỮ LIỆU TEST
-- -----------------------------------------------------------------------------
DELETE FROM Order_Items WHERE order_id > 10;
DELETE FROM Orders WHERE order_id > 10;

UPDATE Products p
SET stock = v.stock
FROM (
    VALUES
        (1, 120), (2, 85), (3, 45), (4, 200), (5, 310),
        (6, 500), (7, 60), (8, 150), (9, 75), (10, 90),
        (11, 220), (12, 55), (13, 40), (14, 30), (15, 100)
) AS v(product_id, stock)
WHERE p.product_id = v.product_id;

-- Reset cột trả hàng & hoàn tiền
UPDATE Orders
SET return_status = 'none',
    return_reason = NULL,
    return_requested_at = NULL,
    return_received_at = NULL,
    refund_processed_at = NULL,
    refund_note = NULL,
    refund_amount = 0,
    order_note = NULL,
    shipping_fee = NULL,
    service_fee = NULL,
    delivered_at = NULL,
    received_at = NULL,
    seller_revenue = NULL,
    shipping_revenue = NULL,
    settlement_status = NULL,
    can_rate = FALSE,
    can_return = TRUE,
    auto_completed = FALSE;

ALTER TABLE Orders DISABLE TRIGGER trg_orders_validate_status;

UPDATE Orders
SET status = CASE order_id
    WHEN 1 THEN 'delivered'
    WHEN 2 THEN 'delivered'
    WHEN 6 THEN 'delivered'
END,
payment_status = 'paid'
WHERE order_id IN (1, 2, 6);

ALTER TABLE Orders ENABLE TRIGGER trg_orders_validate_status;

-- Chuẩn bị phí & thời gian giao cho 3 đơn dùng trong kịch bản
UPDATE Orders
SET shipping_fee = 30000.00,
    service_fee  = 5000.00,
    delivered_at = CASE order_id
        WHEN 1 THEN CURRENT_TIMESTAMP - INTERVAL '2 days'   -- kịch bản C
        WHEN 2 THEN CURRENT_TIMESTAMP - INTERVAL '1 day'  -- kịch bản B
        WHEN 6 THEN CURRENT_TIMESTAMP - INTERVAL '4 days' -- kịch bản A (quá hạn)
    END
WHERE order_id IN (1, 2, 6);

-- -----------------------------------------------------------------------------
-- A. TỪ CHỐI — Quá 3 ngày kể từ delivered_at
-- Đơn 6: buyer_phuong (16), seller 1
-- Kỳ vọng: ERROR (transaction rollback → return_status vẫn 'none')
-- -----------------------------------------------------------------------------
-- SELECT func_request_return(6, 16, 'CHANGE_OF_MIND');
-- Kỳ vọng ERROR: "Đơn đã quá 3 ngày kể từ lúc giao hàng, không thể trả hàng!"

SELECT * FROM func_get_return_case(6);
-- Kỳ vọng: return_status='none', return_reason=NULL

-- -----------------------------------------------------------------------------
-- B. LUỒNG ĐẦY ĐỦ — CHANGE_OF_MIND (hoàn = amount - ship - phụ phí)
-- Đơn 2: buyer_binh (12), seller 2, amount=890000
-- Hoàn kỳ vọng: 890000 - 30000 - 5000 = 855000
-- -----------------------------------------------------------------------------
SELECT func_request_return(2, 12, 'CHANGE_OF_MIND') AS requested;

SELECT func_mark_return_in_transit(2) AS in_transit;

SELECT func_seller_confirm_return_received(2, 2) AS seller_received;

SELECT * FROM func_admin_process_return_refund(2, 1);

-- Kiểm tra đơn 2
SELECT order_id, status, payment_status, return_status, return_reason,
       amount, shipping_fee, service_fee, refund_amount
FROM Orders WHERE order_id = 2;
-- Kỳ vọng: status=returned, payment_status=refunded,
--          return_status=refund_completed, refund_amount=855000.00

SELECT * FROM func_get_return_case(2);

-- Kiểm tra tồn kho product 4 (đơn 2 có 1 tai nghe)
SELECT product_id, stock FROM Products WHERE product_id = 4;
-- Kỳ vọng: stock = 201 (200 + 1)

-- -----------------------------------------------------------------------------
-- C. LUỒNG ĐẦY ĐỦ — PRODUCT_DEFECT (hoàn 100%)
-- Đơn 1: buyer_an (11), seller 1, amount=538000
-- Hoàn kỳ vọng: 538000
-- -----------------------------------------------------------------------------
SELECT func_request_return(1, 11, 'PRODUCT_DEFECT') AS requested;

SELECT func_mark_return_in_transit(1) AS in_transit;

SELECT func_seller_confirm_return_received(1, 1) AS seller_received;

SELECT * FROM func_admin_process_return_refund(1, 1);

-- Kiểm tra đơn 1
SELECT order_id, status, payment_status, return_status, return_reason,
       amount, refund_amount
FROM Orders WHERE order_id = 1;
-- Kỳ vọng: status=returned, payment_status=refunded,
--          return_status=refund_completed, refund_amount=538000.00

SELECT * FROM func_get_return_case(1);

-- Kiểm tra tồn kho (product 1 ×2, product 3 ×1)
SELECT product_id, stock FROM Products WHERE product_id IN (1, 3) ORDER BY product_id;
-- Kỳ vọng: product 1 = 122, product 3 = 46

-- -----------------------------------------------------------------------------
-- D. TỔNG HỢP HỒ SƠ TRẢ HÀNG SAU KỊCH BẢN
-- -----------------------------------------------------------------------------
SELECT order_id, user_id, status, payment_status,
       return_status, return_reason, refund_amount,
       delivered_at, return_requested_at, return_received_at, refund_processed_at
FROM Orders
WHERE order_id IN (1, 2, 6)
ORDER BY order_id;
