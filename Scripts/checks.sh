#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
check_dir="$(mktemp -d "${TMPDIR:-/tmp}/current-checks.XXXXXX")"
trap 'rm -rf "$check_dir"' EXIT
for check in SyncRetryChecks ContextCategoryChecks CategoryBatchChecks CashBalanceChecks SpendingChecks NotificationParserChecks GoogleIdentityChecks; do
  xcrun swiftc -module-cache-path "$check_dir/cache" Sources/iOS/Domain/Models.swift Sources/iOS/Domain/SpendingCategory.swift "Tests/$check.swift" -o "$check_dir/$check"
  "$check_dir/$check"
done
