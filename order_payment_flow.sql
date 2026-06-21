-- =============================================================================
-- Luồng Đặt hàng & Thanh toán (Activity Diagram)
-- Swimlanes: Khách hàng | Hệ thống | Người bán | Đơn vị vận chuyển (ĐVVC)
-- Sơ đồ PlantUML: diagrams/order_payment_flow/*.puml
-- Chạy sau create_table.sql
-- =============================================================================

-- =============================================================================
-- TRIGGERS — Ràng buộc toàn vẹn & đồng bộ tồn kho (CREATE OR REPLACE)
-- =============================================================================

-- 1. Trừ tồn kho khi thêm chi tiết đơn hàng
CREATE OR REPLACE FUNCTION func_check_and_update_stock()
RETURNS TRIGGER AS $$
DECLARE
    v_stock INT;
    v_approval_status VARCHAR(20);
BEGIN
    SELECT stock, approval_status INTO v_stock, v_approval_status
    FROM Products
    WHERE product_id = NEW.product_id;

    IF v_stock IS NULL THEN
        RAISE EXCEPTION 'Sản phẩm không tồn tại!';
    END IF;

    IF v_approval_status IS DISTINCT FROM 'approved' THEN
        RAISE EXCEPTION 'Sản phẩm chưa được phê duyệt hoặc không khả dụng!';
    END IF;

    IF v_stock < NEW.quantity THEN
        RAISE EXCEPTION 'Sản phẩm không đủ số lượng tồn kho!';
    END IF;

    UPDATE Products
    SET stock = v_stock - NEW.quantity
    WHERE product_id = NEW.product_id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER trg_order_item_insert
BEFORE INSERT ON Order_Items
FOR EACH ROW
EXECUTE FUNCTION func_check_and_update_stock();

-- 2. Kiểm tra chuyển trạng thái hợp lệ + tự ghi received_at
CREATE OR REPLACE FUNCTION func_validate_order_status()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.status IS DISTINCT FROM OLD.status THEN
        IF NOT (
            (OLD.status = 'pending'   AND NEW.status IN ('confirmed', 'cancelled', 'shipping')) OR
            (OLD.status = 'confirmed' AND NEW.status IN ('shipping', 'cancelled')) OR
            (OLD.status = 'shipping'  AND NEW.status IN ('delivered', 'cancelled')) OR
            (OLD.status = 'delivered' AND NEW.status IN ('received', 'returned')) OR
            (OLD.status = 'received'  AND NEW.status = 'returned')
        ) THEN
            RAISE EXCEPTION 'Chuyển trạng thái không hợp lệ: % → %', OLD.status, NEW.status;
        END IF;
    END IF;

    IF NEW.status = 'received' AND NEW.received_at IS NULL THEN
        NEW.received_at := CURRENT_TIMESTAMP;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER trg_orders_validate_status
BEFORE UPDATE ON Orders
FOR EACH ROW
EXECUTE FUNCTION func_validate_order_status();

-- 3. Hoàn tồn kho khi hủy đơn (pending → cancelled)
CREATE OR REPLACE FUNCTION func_restore_stock_on_cancel()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.status = 'cancelled' AND OLD.status IS DISTINCT FROM 'cancelled' THEN
        UPDATE Products p
        SET stock = p.stock + oi.quantity
        FROM Order_Items oi
        WHERE oi.order_id = NEW.order_id
          AND oi.product_id = p.product_id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER trg_orders_restore_stock
AFTER UPDATE OF status ON Orders
FOR EACH ROW
EXECUTE FUNCTION func_restore_stock_on_cancel();

-- 4. Chặn trả hàng khi đơn đã khóa + kiểm tra số lượng trả
CREATE OR REPLACE FUNCTION func_order_items_validate_return()
RETURNS TRIGGER AS $$
DECLARE
    v_can_return BOOLEAN;
BEGIN
    IF NEW.return_quantity IS DISTINCT FROM OLD.return_quantity THEN
        IF NEW.return_quantity > NEW.quantity THEN
            RAISE EXCEPTION 'Số lượng trả (%) vượt quá số lượng đặt (%)!',
                NEW.return_quantity, NEW.quantity;
        END IF;

        IF NEW.return_quantity > OLD.return_quantity THEN
            SELECT o.can_return INTO v_can_return
            FROM Orders o
            WHERE o.order_id = NEW.order_id;

            IF v_can_return = FALSE THEN
                RAISE EXCEPTION 'Đơn hàng đã khóa quyền trả hàng và hoàn tiền!';
            END IF;
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER trg_order_items_validate_return
BEFORE UPDATE OF return_quantity ON Order_Items
FOR EACH ROW
EXECUTE FUNCTION func_order_items_validate_return();

-- 5. Hoàn tồn kho khi tăng return_quantity (trả hàng)
CREATE OR REPLACE FUNCTION func_order_items_restore_stock_on_return()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.return_quantity > OLD.return_quantity THEN
        UPDATE Products
        SET stock = stock + (NEW.return_quantity - OLD.return_quantity)
        WHERE product_id = NEW.product_id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER trg_order_items_restore_stock
AFTER UPDATE OF return_quantity ON Order_Items
FOR EACH ROW
EXECUTE FUNCTION func_order_items_restore_stock_on_return();

-- =============================================================================
-- HÀM NGHIỆP VỤ (gọi từ ứng dụng / kịch bản kiểm thử)
-- =============================================================================

CREATE OR REPLACE FUNCTION func_place_order(
    p_user_id INT,
    p_seller_id INT,
    p_shipping_units_id INT,
    p_payment_method VARCHAR(50),
    p_order_note TEXT,
    p_shipping_fee DECIMAL(12, 2)
)
RETURNS INT
LANGUAGE plpgsql
AS $$
DECLARE
    v_order_id INT;
    v_cart_id INT;
    v_service_fee DECIMAL(12, 2) := 5000;
    v_total_amount DECIMAL(12, 2) := 0;
    v_item RECORD;
BEGIN
    -- Lấy ID giỏ hàng của khách hàng hiện tại
    SELECT cart_id INTO v_cart_id FROM Carts WHERE user_id = p_user_id;

    IF v_cart_id IS NULL THEN
        RAISE EXCEPTION 'Khách hàng chưa có giỏ hàng!';
    END IF;

    -- Kiểm tra giỏ hàng có sản phẩm thuộc người bán này không
    IF NOT EXISTS (
        SELECT 1
        FROM Cart_items ci
        JOIN Products p ON p.product_id = ci.product_id
        WHERE ci.cart_id = v_cart_id
          AND p.seller_id = p_seller_id
    ) THEN
        RAISE EXCEPTION 'Giỏ hàng không có sản phẩm của người bán này!';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM Cart_items ci
        JOIN Products p ON p.product_id = ci.product_id
        WHERE ci.cart_id = v_cart_id
          AND p.seller_id = p_seller_id
          AND p.approval_status IS DISTINCT FROM 'approved'
    ) THEN
        RAISE EXCEPTION 'Giỏ hàng có sản phẩm chưa được phê duyệt hoặc không khả dụng!';
    END IF;

    -- Bước 1: Tạo bản ghi Đơn hàng mới và lấy lại order_id
    INSERT INTO Orders (
        user_id, seller_id, shipping_units_id,
        status, shipping_status, payment_method,
        order_note, shipping_fee, service_fee, amount, payment_status
    ) VALUES (
        p_user_id, p_seller_id, p_shipping_units_id,
        'pending', 'waiting', p_payment_method,
        p_order_note, p_shipping_fee, v_service_fee, 0, 'unpaid'
    ) RETURNING order_id INTO v_order_id;

    -- Bước 2: Lấy sản phẩm từ Cart_items (lọc theo seller_id)
    FOR v_item IN
        SELECT ci.product_id, ci.quantity, p.price
        FROM Cart_items ci
        JOIN Products p ON p.product_id = ci.product_id
        WHERE ci.cart_id = v_cart_id
          AND p.seller_id = p_seller_id
    LOOP
        INSERT INTO Order_Items (order_id, product_id, quantity)
        VALUES (v_order_id, v_item.product_id, v_item.quantity);

        v_total_amount := v_total_amount + (v_item.price * v_item.quantity);
    END LOOP;

    -- Bước 3: Tính tổng tiền cuối cùng và cập nhật lại đơn hàng
    v_total_amount := v_total_amount + p_shipping_fee + v_service_fee;

    UPDATE Orders
    SET amount = v_total_amount
    WHERE order_id = v_order_id;

    -- Bước 4: Xóa sản phẩm đã đặt khỏi giỏ hàng
    DELETE FROM Cart_items ci
    USING Products p
    WHERE ci.cart_id = v_cart_id
      AND ci.product_id = p.product_id
      AND p.seller_id = p_seller_id;

    RETURN v_order_id;

EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'Đặt hàng thất bại, đã hoàn tác dữ liệu: %', SQLERRM;
END;
$$;

-- -----------------------------------------------------------------------------
-- Hàm xử lý Trả hàng & Tính tiền hoàn (trả từng sản phẩm)
-- Chỉ áp dụng đơn đã giao (delivered) và đã thanh toán (paid / partial_refund)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION func_process_return(
    p_order_id INT,
    p_product_id INT,
    p_return_quantity INT,
    p_return_reason TEXT DEFAULT NULL
)
RETURNS DECIMAL(12, 2)
LANGUAGE plpgsql
AS $$
DECLARE
    v_status VARCHAR(50);
    v_payment_status VARCHAR(50);
    v_shipping_fee DECIMAL(12, 2);
    v_refund_amount DECIMAL(12, 2);
    v_amount DECIMAL(12, 2);
    v_ordered_qty INT;
    v_returned_qty INT;
    v_product_price DECIMAL(12, 2);
    v_item_refund DECIMAL(12, 2) := 0;
    v_shipping_refund DECIMAL(12, 2) := 0;
    v_all_returned BOOLEAN;
    v_can_return BOOLEAN;
BEGIN
    IF p_return_quantity IS NULL OR p_return_quantity <= 0 THEN
        RAISE EXCEPTION 'Số lượng trả hàng phải lớn hơn 0!';
    END IF;

    SELECT o.status, o.payment_status, o.shipping_fee, o.refund_amount, o.amount, o.can_return
    INTO v_status, v_payment_status, v_shipping_fee, v_refund_amount, v_amount, v_can_return
    FROM Orders o
    WHERE o.order_id = p_order_id;

    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Đơn hàng ID % không tồn tại!', p_order_id;
    END IF;

    IF v_can_return = FALSE THEN
        RAISE EXCEPTION 'Đơn hàng đã khóa quyền trả hàng và hoàn tiền!';
    END IF;

    IF v_status NOT IN ('delivered', 'received') THEN
        RAISE EXCEPTION 'Chỉ trả hàng khi đơn đã giao hoặc đã nhận. Hiện tại: %', v_status;
    END IF;

    IF v_payment_status NOT IN ('paid', 'partial_refund') THEN
        RAISE EXCEPTION 'Đơn hàng không thể hoàn tiền. Trạng thái thanh toán: %', v_payment_status;
    END IF;

    SELECT oi.quantity, oi.return_quantity, p.price
    INTO v_ordered_qty, v_returned_qty, v_product_price
    FROM Order_Items oi
    JOIN Products p ON p.product_id = oi.product_id
    WHERE oi.order_id = p_order_id
      AND oi.product_id = p_product_id;

    IF v_ordered_qty IS NULL THEN
        RAISE EXCEPTION 'Sản phẩm ID % không thuộc đơn hàng %!', p_product_id, p_order_id;
    END IF;

    IF v_returned_qty + p_return_quantity > v_ordered_qty THEN
        RAISE EXCEPTION 'Số lượng trả (%) vượt quá số lượng còn lại (%)!',
            p_return_quantity, v_ordered_qty - v_returned_qty;
    END IF;

    -- Tiền hoàn = giá sản phẩm × số lượng trả
    v_item_refund := v_product_price * p_return_quantity;

    UPDATE Order_Items
    SET return_quantity = return_quantity + p_return_quantity,
        return_reason = COALESCE(p_return_reason, return_reason)
    WHERE order_id = p_order_id
      AND product_id = p_product_id;

    -- Hoàn kho: trigger trg_order_items_restore_stock xử lý khi return_quantity tăng

    -- Kiểm tra đã trả hết toàn bộ sản phẩm trong đơn chưa
    SELECT NOT EXISTS (
        SELECT 1
        FROM Order_Items oi
        WHERE oi.order_id = p_order_id
          AND oi.return_quantity < oi.quantity
    ) INTO v_all_returned;

    -- Trả hết: hoàn thêm phí ship (phí dịch vụ không hoàn)
    IF v_all_returned THEN
        v_shipping_refund := COALESCE(v_shipping_fee, 0);
        v_item_refund := v_item_refund + v_shipping_refund;

        UPDATE Orders
        SET refund_amount = refund_amount + v_item_refund,
            status = 'returned',
            payment_status = 'refunded'
        WHERE order_id = p_order_id;
    ELSE
        UPDATE Orders
        SET refund_amount = refund_amount + v_item_refund,
            payment_status = 'partial_refund'
        WHERE order_id = p_order_id;

        -- Nếu tổng hoàn đã bằng tổng đơn thì chuyển sang refunded
        SELECT refund_amount INTO v_refund_amount
        FROM Orders
        WHERE order_id = p_order_id;

        IF v_refund_amount >= v_amount THEN
            UPDATE Orders
            SET payment_status = 'refunded',
                status = 'returned'
            WHERE order_id = p_order_id;
        END IF;
    END IF;

    RETURN v_item_refund;

EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'Trả hàng thất bại, đã hoàn tác dữ liệu: %', SQLERRM;
END;
$$;

-- -----------------------------------------------------------------------------
-- Hàm xác nhận "Đã nhận hàng" & chốt doanh thu
-- Khách bấm xác nhận sau khi ĐVVC giao (delivered) → mở đánh giá, chốt tiền trả seller/ship
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION func_confirm_received(
    p_order_id INT,
    p_user_id INT
)
RETURNS TABLE (
    received_at TIMESTAMP,
    seller_revenue DECIMAL(12, 2),
    shipping_revenue DECIMAL(12, 2),
    can_rate BOOLEAN
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_status VARCHAR(50);
    v_payment_status VARCHAR(50);
    v_order_user_id INT;
    v_shipping_fee DECIMAL(12, 2);
    v_seller_revenue DECIMAL(12, 2);
    v_received_at TIMESTAMP;
BEGIN
    SELECT o.status, o.payment_status, o.user_id,
           COALESCE(o.shipping_fee, 0)
    INTO v_status, v_payment_status, v_order_user_id, v_shipping_fee
    FROM Orders o
    WHERE o.order_id = p_order_id;

    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Đơn hàng ID % không tồn tại!', p_order_id;
    END IF;

    IF v_order_user_id != p_user_id THEN
        RAISE EXCEPTION 'Khách hàng không có quyền xác nhận đơn hàng này!';
    END IF;

    IF v_status = 'received' THEN
        RAISE EXCEPTION 'Đơn hàng đã được xác nhận nhận hàng trước đó!';
    END IF;

    IF v_status != 'delivered' THEN
        RAISE EXCEPTION 'Chỉ xác nhận khi đơn đã giao (delivered). Hiện tại: %', v_status;
    END IF;

    IF v_payment_status != 'paid' THEN
        RAISE EXCEPTION 'Đơn hàng chưa thanh toán, không thể xác nhận nhận hàng!';
    END IF;

    -- Tiền hàng cho người bán = tổng giá sản phẩm trong đơn
    SELECT COALESCE(SUM(p.price * oi.quantity), 0)
    INTO v_seller_revenue
    FROM Order_Items oi
    JOIN Products p ON p.product_id = oi.product_id
    WHERE oi.order_id = p_order_id;

    v_received_at := CURRENT_TIMESTAMP;

    UPDATE Orders
    SET status = 'received',
        received_at = v_received_at,
        seller_revenue = v_seller_revenue,
        shipping_revenue = v_shipping_fee,
        settlement_status = 'pending',
        can_rate = TRUE,
        can_return = TRUE
    WHERE order_id = p_order_id;

    RETURN QUERY
    SELECT v_received_at, v_seller_revenue, v_shipping_fee, TRUE;

EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'Xác nhận nhận hàng thất bại, đã hoàn tác dữ liệu: %', SQLERRM;
END;
$$;

-- -----------------------------------------------------------------------------
-- Hàm tự động chốt đơn sau 3 ngày (Auto-Complete)
-- Đơn delivered quá 3 ngày không xác nhận → received, chốt doanh thu, khóa trả hàng
-- Gọi định kỳ bởi cron/scheduler
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION func_auto_complete_orders()
RETURNS TABLE (
    order_id INT,
    received_at TIMESTAMP,
    seller_revenue DECIMAL(12, 2),
    shipping_revenue DECIMAL(12, 2)
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_order RECORD;
    v_seller_revenue DECIMAL(12, 2);
    v_received_at TIMESTAMP;
BEGIN
    FOR v_order IN
        SELECT o.order_id, COALESCE(o.shipping_fee, 0) AS shipping_fee
        FROM Orders o
        WHERE o.status = 'delivered'
          AND o.payment_status = 'paid'
          AND o.delivered_at IS NOT NULL
          AND o.delivered_at + INTERVAL '3 days' < CURRENT_TIMESTAMP
          AND o.received_at IS NULL
    LOOP
        SELECT COALESCE(SUM(p.price * oi.quantity), 0)
        INTO v_seller_revenue
        FROM Order_Items oi
        JOIN Products p ON p.product_id = oi.product_id
        WHERE oi.order_id = v_order.order_id;

        v_received_at := CURRENT_TIMESTAMP;

        UPDATE Orders
        SET status = 'received',
            received_at = v_received_at,
            seller_revenue = v_seller_revenue,
            shipping_revenue = v_order.shipping_fee,
            settlement_status = 'pending',
            can_rate = TRUE,
            can_return = FALSE,
            auto_completed = TRUE
        WHERE Orders.order_id = v_order.order_id;

        order_id := v_order.order_id;
        received_at := v_received_at;
        seller_revenue := v_seller_revenue;
        shipping_revenue := v_order.shipping_fee;
        RETURN NEXT;
    END LOOP;

EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'Auto-complete thất bại, đã hoàn tác dữ liệu: %', SQLERRM;
END;
$$;

CREATE OR REPLACE FUNCTION func_cancel_order(
    p_order_id INT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
DECLARE
    v_current_status VARCHAR(50);
BEGIN
    SELECT status INTO v_current_status
    FROM Orders
    WHERE order_id = p_order_id;

    IF v_current_status IS NULL THEN
        RAISE EXCEPTION 'Đơn hàng ID % không tồn tại!', p_order_id;
    END IF;

    IF v_current_status != 'pending' THEN
        RAISE EXCEPTION 'Không thể hủy. Đơn hàng đang ở trạng thái: %', v_current_status;
    END IF;

    -- Hoàn kho: trigger trg_orders_restore_stock xử lý khi status → cancelled
    UPDATE Orders
    SET status = 'cancelled',
        payment_status = CASE WHEN payment_status = 'paid' THEN 'refunded' ELSE payment_status END
    WHERE order_id = p_order_id;

    RETURN TRUE;

EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'Lỗi quá trình hủy đơn: %', SQLERRM;
END;
$$;

-- Kịch bản kiểm thử đã được tách riêng:
--   order_payment_flow_test.sql

