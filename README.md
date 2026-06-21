# ShopeeFake

Mô phỏng luồng nghiệp vụ Shopee bằng PostgreSQL (schema, trigger, stored function).

## Yêu cầu

- PostgreSQL 14+ (`psql`, `createdb`)
- Bash (script chạy kịch bản)

## Chạy nhanh (đầy đủ)

```bash
chmod +x scripts/run_scenario.sh
./scripts/run_scenario.sh all shopeefake
```

Kịch bản `all`: reset schema → tạo bảng → index → seed → 4 luồng nghiệp vụ → 4 file test.

## Các kịch bản

| Kịch bản | Mô tả |
|----------|--------|
| `reset` | Xóa schema `public` (giữ database) |
| `base` | `create_table` + `indexes` + `insert_random_data` |
| `seller` | base + đăng ký người bán |
| `moderation` | base + đăng bán & kiểm duyệt SP |
| `order` | base + đặt hàng & thanh toán |
| `return` | base + order + trả hàng & hoàn tiền |
| `all-flows` | base + cả 4 luồng (không chạy test) |
| `test-seller` | seller + test |
| `test-moderation` | moderation + test |
| `test-order` | order + test |
| `test-return` | return + test |
| `all` | reset + base + flows + toàn bộ test |

```bash
./scripts/run_scenario.sh help
```

## Thứ tự file SQL (thủ công)

```
1. create_table.sql
2. indexes.sql
3. insert_random_data.sql
4. seller_registration_flow.sql      } thứ tự 4–7 có thể hoán đổi
5. product_listing_moderation_flow.sql } (trừ return cần order)
6. order_payment_flow.sql
7. return_refund_flow.sql            ← phụ thuộc order_payment_flow
```

File test (chạy sau flow tương ứng):

- `seller_registration_flow_test.sql`
- `product_listing_moderation_flow_test.sql`
- `order_payment_flow_test.sql`
- `return_refund_flow_test.sql`

## Chạy thủ công bằng psql

```bash
createdb shopeefake
psql -d shopeefake -v ON_ERROR_STOP=1 -f create_table.sql -f indexes.sql -f insert_random_data.sql
psql -d shopeefake -v ON_ERROR_STOP=1 -f product_listing_moderation_flow.sql -f product_listing_moderation_flow_test.sql
```

## Cấu trúc luồng nghiệp vụ

| File | Swimlanes |
|------|-----------|
| `seller_registration_flow.sql` | Admin / Hệ thống / User |
| `product_listing_moderation_flow.sql` | Người bán / Hệ thống / Admin |
| `order_payment_flow.sql` | Khách hàng / Hệ thống / Người bán / ĐVVC |
| `return_refund_flow.sql` | Khách hàng / Hệ thống / Người bán / Admin |

Sơ đồ PlantUML: `diagrams/order_payment_flow/`
