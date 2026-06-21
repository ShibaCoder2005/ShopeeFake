#!/usr/bin/env bash
# =============================================================================
# Kịch bản chạy mã nguồn ShopeeFake (PostgreSQL)
#
# Cách dùng:
#   ./scripts/run_scenario.sh <tên_kịch_bản> [tên_database]
#
# Biến môi trường (tùy chọn):
#   PGHOST PGPORT PGUSER PGPASSWORD
#
# Ví dụ:
#   ./scripts/run_scenario.sh base shopeefake
#   ./scripts/run_scenario.sh all shopeefake
#   DB_NAME=shopeefake ./scripts/run_scenario.sh test-order
# =============================================================================

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DB_NAME="${2:-${DB_NAME:-shopeefake}}"
PSQL_OPTS=(-v ON_ERROR_STOP=1 --dbname "$DB_NAME")

run_sql() {
  local file="$1"
  echo ">> $(basename "$file")"
  psql "${PSQL_OPTS[@]}" -f "$file"
}

ensure_db() {
  if ! psql -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname = '$DB_NAME'" | grep -q 1; then
    echo ">> Tạo database: $DB_NAME"
    createdb "$DB_NAME"
  fi
}

reset_schema() {
  echo ">> RESET schema public trong database: $DB_NAME"
  psql "${PSQL_OPTS[@]}" <<'SQL'
DROP SCHEMA IF EXISTS public CASCADE;
CREATE SCHEMA public;
GRANT ALL ON SCHEMA public TO public;
SQL
}

run_base() {
  run_sql "$ROOT_DIR/create_table.sql"
  run_sql "$ROOT_DIR/indexes.sql"
  run_sql "$ROOT_DIR/insert_random_data.sql"
}

run_flow_seller() {
  run_sql "$ROOT_DIR/seller_registration_flow.sql"
}

run_flow_moderation() {
  run_sql "$ROOT_DIR/product_listing_moderation_flow.sql"
}

run_flow_order() {
  run_sql "$ROOT_DIR/order_payment_flow.sql"
}

run_flow_return() {
  run_sql "$ROOT_DIR/return_refund_flow.sql"
}

run_all_flows() {
  run_flow_seller
  run_flow_moderation
  run_flow_order
  run_flow_return
}

usage() {
  cat <<'EOF'
Kịch bản khả dụng:

  reset            Xóa toàn bộ schema public (DROP CASCADE) — chạy trên DB đã tồn tại
  base             create_table + indexes + insert_random_data
  seller           base + seller_registration_flow
  moderation       base + product_listing_moderation_flow
  order            base + order_payment_flow
  return           base + order_payment_flow + return_refund_flow
  all-flows        base + tất cả file flow (seller, moderation, order, return)

  test-seller      seller + seller_registration_flow_test
  test-moderation  moderation + product_listing_moderation_flow_test
  test-order       order + order_payment_flow_test
  test-return      return + return_refund_flow_test

  all              reset + base + all-flows + tất cả file test (cài đặt & kiểm thử đầy đủ)
  help             Hiển thị trợ giúp

Thứ tự phụ thuộc:
  create_table → indexes → insert_random_data
  return_refund_flow cần order_payment_flow (trigger/hàm dùng chung Orders, Order_Items)

Ví dụ:
  ./scripts/run_scenario.sh reset shopeefake
  ./scripts/run_scenario.sh base shopeefake
  ./scripts/run_scenario.sh test-moderation shopeefake
  ./scripts/run_scenario.sh all shopeefake
EOF
}

main() {
  local scenario="${1:-help}"

  if [[ "$scenario" == "help" || "$scenario" == "-h" || "$scenario" == "--help" ]]; then
    usage
    exit 0
  fi

  if ! command -v psql >/dev/null 2>&1; then
    echo "Lỗi: cần cài PostgreSQL client (psql)." >&2
    exit 1
  fi

  ensure_db

  case "$scenario" in
    reset)
      reset_schema
      ;;
    base)
      run_base
      ;;
    seller)
      run_base
      run_flow_seller
      ;;
    moderation)
      run_base
      run_flow_moderation
      ;;
    order)
      run_base
      run_flow_order
      ;;
    return)
      run_base
      run_flow_order
      run_flow_return
      ;;
    all-flows)
      run_base
      run_all_flows
      ;;
    test-seller)
      run_base
      run_flow_seller
      run_sql "$ROOT_DIR/seller_registration_flow_test.sql"
      ;;
    test-moderation)
      run_base
      run_flow_moderation
      run_sql "$ROOT_DIR/product_listing_moderation_flow_test.sql"
      ;;
    test-order)
      run_base
      run_flow_order
      run_sql "$ROOT_DIR/order_payment_flow_test.sql"
      ;;
    test-return)
      run_base
      run_flow_order
      run_flow_return
      run_sql "$ROOT_DIR/return_refund_flow_test.sql"
      ;;
    all)
      reset_schema
      run_base
      run_all_flows
      run_sql "$ROOT_DIR/seller_registration_flow_test.sql"
      run_sql "$ROOT_DIR/product_listing_moderation_flow_test.sql"
      run_sql "$ROOT_DIR/order_payment_flow_test.sql"
      run_sql "$ROOT_DIR/return_refund_flow_test.sql"
      echo ""
      echo "Hoàn tất: base + flows + toàn bộ test."
      ;;
    *)
      echo "Kịch bản không hợp lệ: $scenario" >&2
      echo "" >&2
      usage >&2
      exit 1
      ;;
  esac

  echo ""
  echo "Xong kịch bản: $scenario (database: $DB_NAME)"
}

main "$@"
