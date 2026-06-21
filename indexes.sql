-- =============================================================================
-- Index tối ưu — mức "nên có"
-- Chạy sau: create_table.sql (trước hoặc sau insert_random_data.sql đều được)
-- Chạy lại an toàn: DROP IF EXISTS trước khi CREATE
-- =============================================================================

DROP INDEX IF EXISTS idx_products_pending_queue;
DROP INDEX IF EXISTS idx_products_approved;
DROP INDEX IF EXISTS idx_products_seller_id;
DROP INDEX IF EXISTS idx_order_items_product_id;

-- Products: hàng chờ admin duyệt (func_admin_list_pending_products)
CREATE INDEX idx_products_pending_queue
    ON Products (submitted_at, product_id)
    WHERE approval_status = 'pending';

-- Products: catalog khách hàng (func_get_customer_approved_products)
CREATE INDEX idx_products_approved
    ON Products (product_id)
    WHERE approval_status = 'approved';

-- Products: lọc/join theo shop (func_place_order, danh sách SP seller)
CREATE INDEX idx_products_seller_id
    ON Products (seller_id);

-- Order_Items: join ngược theo product khi hoàn kho (hủy đơn, trả hàng)
CREATE INDEX idx_order_items_product_id
    ON Order_Items (product_id);
