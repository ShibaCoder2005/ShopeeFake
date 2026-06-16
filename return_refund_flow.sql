-- =============================================================================
-- Luồng Yêu cầu Trả hàng & Hoàn tiền
-- Swimlanes: Khách hàng | Hệ thống | Người bán | Admin
-- Chạy sau: create_table.sql (+ order_payment_flow.sql nếu đã có cột phụ trợ)
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 0. Bổ sung cột phục vụ luồng trả hàng
-- -----------------------------------------------------------------------------
ALTER TABLE Orders ADD COLUMN IF NOT EXISTS return_status       VARCHAR(50) DEFAULT 'none';
ALTER TABLE Orders ADD COLUMN IF NOT EXISTS return_reason       VARCHAR(50);
ALTER TABLE Orders ADD COLUMN IF NOT EXISTS return_requested_at TIMESTAMP;
ALTER TABLE Orders ADD COLUMN IF NOT EXISTS return_received_at  TIMESTAMP;
ALTER TABLE Orders ADD COLUMN IF NOT EXISTS refund_processed_at TIMESTAMP;
ALTER TABLE Orders ADD COLUMN IF NOT EXISTS refund_note         TEXT;

-- -----------------------------------------------------------------------------
-- 1. Trigger: validate giá trị return_status + return_reason
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION func_validate_return_fields()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.return_status NOT IN (
        'none',
        'requested',
        'in_transit',
        'seller_received',
        'refund_completed',
        'rejected'
    ) THEN
        RAISE EXCEPTION 'Trạng thái trả hàng không hợp lệ: %', NEW.return_status;
    END IF;

    IF NEW.return_reason IS NOT NULL
       AND NEW.return_reason NOT IN ('PRODUCT_DEFECT', 'COUNTERFEIT', 'CHANGE_OF_MIND') THEN
        RAISE EXCEPTION 'Lý do trả hàng không hợp lệ: %', NEW.return_reason;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER trg_orders_validate_return_fields
BEFORE INSERT OR UPDATE OF return_status, return_reason ON Orders
FOR EACH ROW
EXECUTE FUNCTION func_validate_return_fields();

-- -----------------------------------------------------------------------------
-- 2. Trigger: hoàn lại tồn kho khi hoàn tiền trả hàng hoàn tất
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION func_restore_stock_on_refund_completed()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.return_status = 'refund_completed'
       AND OLD.return_status IS DISTINCT FROM 'refund_completed' THEN
        UPDATE Products p
        SET stock = p.stock + oi.quantity
        FROM Order_Items oi
        WHERE oi.order_id = NEW.order_id
          AND oi.product_id = p.product_id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER trg_orders_restore_stock_on_refund
AFTER UPDATE OF return_status ON Orders
FOR EACH ROW
EXECUTE FUNCTION func_restore_stock_on_refund_completed();

-- -----------------------------------------------------------------------------
-- 3. Khách hàng tạo yêu cầu trả hàng
-- Logic:
-- - Chỉ cho phép trong vòng 3 ngày kể từ delivered_at
-- - Chỉ cho đơn đã giao/đã nhận và đã thanh toán
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION func_request_return(
    p_order_id INT,
    p_user_id INT,
    p_reason VARCHAR(50) -- PRODUCT_DEFECT | COUNTERFEIT | CHANGE_OF_MIND
)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
DECLARE
    v_order_user_id INT;
    v_order_status VARCHAR(50);
    v_payment_status VARCHAR(50);
    v_return_status VARCHAR(50);
    v_delivered_at TIMESTAMP;
BEGIN
    SELECT o.user_id, o.status, o.payment_status, o.return_status, o.delivered_at
    INTO v_order_user_id, v_order_status, v_payment_status, v_return_status, v_delivered_at
    FROM Orders o
    WHERE o.order_id = p_order_id;

    IF v_order_user_id IS NULL THEN
        RAISE EXCEPTION 'Đơn hàng ID % không tồn tại!', p_order_id;
    END IF;

    IF v_order_user_id <> p_user_id THEN
        RAISE EXCEPTION 'Bạn không có quyền yêu cầu trả đơn hàng này!';
    END IF;

    IF v_order_status NOT IN ('delivered', 'received') THEN
        RAISE EXCEPTION 'Đơn chưa ở trạng thái đã giao/đã nhận. Hiện tại: %', v_order_status;
    END IF;

    IF v_payment_status NOT IN ('paid', 'partial_refund') THEN
        RAISE EXCEPTION 'Đơn chưa thanh toán nên không thể yêu cầu hoàn tiền. Trạng thái: %', v_payment_status;
    END IF;

    IF v_delivered_at IS NULL THEN
        RAISE EXCEPTION 'Đơn hàng chưa có thời điểm giao hàng (delivered_at).';
    END IF;

    IF CURRENT_TIMESTAMP > v_delivered_at + INTERVAL '3 days' THEN
        UPDATE Orders
        SET return_status = 'rejected',
            refund_note = 'Từ chối: quá 3 ngày kể từ lúc giao hàng.'
        WHERE order_id = p_order_id;

        RAISE EXCEPTION 'Đơn đã quá 3 ngày kể từ lúc giao hàng, không thể trả hàng!';
    END IF;

    IF COALESCE(v_return_status, 'none') NOT IN ('none', 'rejected') THEN
        RAISE EXCEPTION 'Đơn đã có yêu cầu trả hàng trước đó. Trạng thái hiện tại: %', v_return_status;
    END IF;

    UPDATE Orders
    SET return_status = 'requested',
        return_reason = p_reason,
        return_requested_at = CURRENT_TIMESTAMP,
        refund_note = 'Đã tạo yêu cầu trả hàng, chờ người bán xử lý.'
    WHERE order_id = p_order_id;

    RETURN TRUE;
END;
$$;

-- -----------------------------------------------------------------------------
-- 4. Hệ thống/ĐVVC cập nhật trạng thái đang lấy hàng trả
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION func_mark_return_in_transit(
    p_order_id INT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
DECLARE
    v_return_status VARCHAR(50);
BEGIN
    SELECT return_status INTO v_return_status
    FROM Orders
    WHERE order_id = p_order_id;

    IF v_return_status IS NULL THEN
        RAISE EXCEPTION 'Đơn hàng ID % không tồn tại!', p_order_id;
    END IF;

    IF v_return_status <> 'requested' THEN
        RAISE EXCEPTION 'Chỉ chuyển sang in_transit khi trạng thái đang là requested. Hiện tại: %', v_return_status;
    END IF;

    UPDATE Orders
    SET return_status = 'in_transit',
        refund_note = 'ĐVVC đang lấy hàng trả về cho người bán.'
    WHERE order_id = p_order_id;

    RETURN TRUE;
END;
$$;

-- -----------------------------------------------------------------------------
-- 5. Người bán xác nhận đã nhận hàng trả lại
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION func_seller_confirm_return_received(
    p_order_id INT,
    p_seller_id INT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
DECLARE
    v_order_seller_id INT;
    v_return_status VARCHAR(50);
BEGIN
    SELECT seller_id, return_status
    INTO v_order_seller_id, v_return_status
    FROM Orders
    WHERE order_id = p_order_id;

    IF v_order_seller_id IS NULL THEN
        RAISE EXCEPTION 'Đơn hàng ID % không tồn tại!', p_order_id;
    END IF;

    IF v_order_seller_id <> p_seller_id THEN
        RAISE EXCEPTION 'Bạn không có quyền xác nhận hàng trả cho đơn này!';
    END IF;

    IF v_return_status NOT IN ('requested', 'in_transit') THEN
        RAISE EXCEPTION 'Không thể xác nhận nhận hàng trả ở trạng thái: %', v_return_status;
    END IF;

    UPDATE Orders
    SET return_status = 'seller_received',
        return_received_at = CURRENT_TIMESTAMP,
        refund_note = 'Người bán đã nhận hàng trả lại.'
    WHERE order_id = p_order_id;

    RETURN TRUE;
END;
$$;

-- -----------------------------------------------------------------------------
-- 6. Admin xử lý hoàn tiền theo lý do trả hàng
-- Logic:
-- - CHANGE_OF_MIND  : Hoàn = Tổng đơn - ship - phụ phí
-- - PRODUCT_DEFECT/COUNTERFEIT: Hoàn 100% tổng đơn
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION func_admin_process_return_refund(
    p_order_id INT,
    p_admin_user_id INT
)
RETURNS TABLE (
    refund_amount DECIMAL(12, 2),
    refund_policy VARCHAR(100)
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_admin_role VARCHAR(20);
    v_return_status VARCHAR(50);
    v_return_reason VARCHAR(50);
    v_amount DECIMAL(12, 2);
    v_shipping_fee DECIMAL(12, 2);
    v_service_fee DECIMAL(12, 2);
    v_refund DECIMAL(12, 2);
    v_policy VARCHAR(100);
BEGIN
    SELECT role INTO v_admin_role
    FROM Users
    WHERE user_id = p_admin_user_id;

    IF v_admin_role IS NULL THEN
        RAISE EXCEPTION 'Admin user_id % không tồn tại!', p_admin_user_id;
    END IF;

    IF v_admin_role <> 'admin' THEN
        RAISE EXCEPTION 'Chỉ Admin mới được xử lý hoàn tiền!';
    END IF;

    SELECT return_status, return_reason, amount, COALESCE(shipping_fee, 0), COALESCE(service_fee, 0)
    INTO v_return_status, v_return_reason, v_amount, v_shipping_fee, v_service_fee
    FROM Orders
    WHERE order_id = p_order_id;

    IF v_return_status IS NULL THEN
        RAISE EXCEPTION 'Đơn hàng ID % không tồn tại!', p_order_id;
    END IF;

    IF v_return_status <> 'seller_received' THEN
        RAISE EXCEPTION 'Chỉ hoàn tiền khi người bán đã nhận hàng trả. Trạng thái hiện tại: %', v_return_status;
    END IF;

    IF v_return_reason = 'CHANGE_OF_MIND' THEN
        v_refund := GREATEST(v_amount - v_shipping_fee - v_service_fee, 0);
        v_policy := 'Hoan tong don tru phi ship va phu phi';
    ELSIF v_return_reason IN ('PRODUCT_DEFECT', 'COUNTERFEIT') THEN
        v_refund := v_amount;
        v_policy := 'Hoan 100 phan tram tong don';
    ELSE
        RAISE EXCEPTION 'Lý do trả hàng chưa hợp lệ để tính hoàn tiền: %', v_return_reason;
    END IF;

    UPDATE Orders
    SET refund_amount = v_refund,
        payment_status = 'refunded',
        return_status = 'refund_completed',
        status = 'returned',
        refund_processed_at = CURRENT_TIMESTAMP,
        refund_note = CONCAT(
            'Admin da xu ly hoan tien theo chinh sach: ',
            v_policy
        )
    WHERE order_id = p_order_id;

    RETURN QUERY
    SELECT v_refund, v_policy;
END;
$$;

-- -----------------------------------------------------------------------------
-- 7. Hàm xem nhanh trạng thái hồ sơ trả hàng
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION func_get_return_case(
    p_order_id INT
)
RETURNS TABLE (
    order_id INT,
    order_status VARCHAR(50),
    return_status VARCHAR(50),
    return_reason VARCHAR(50),
    return_requested_at TIMESTAMP,
    return_received_at TIMESTAMP,
    refund_amount DECIMAL(12, 2),
    refund_processed_at TIMESTAMP,
    refund_note TEXT
)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT
        o.order_id,
        o.status,
        o.return_status,
        o.return_reason,
        o.return_requested_at,
        o.return_received_at,
        o.refund_amount,
        o.refund_processed_at,
        o.refund_note
    FROM Orders o
    WHERE o.order_id = p_order_id;
END;
$$;

-- Kịch bản kiểm thử: return_refund_flow_test.sql

