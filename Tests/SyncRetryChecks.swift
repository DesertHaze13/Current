import Foundation
@main struct SyncRetryChecks {
    static func main() {
        precondition(CloudRetryPolicy.isQuota(statusCode: 429, status: nil, message: "Too many requests"))
        precondition(CloudRetryPolicy.isQuota(statusCode: 403, status: "RESOURCE_EXHAUSTED", message: "Limit reached"))
        precondition(CloudRetryPolicy.isQuota(statusCode: 403, status: nil, message: "Quota exceeded."))
        precondition(!CloudRetryPolicy.isQuota(statusCode: 403, status: "PERMISSION_DENIED", message: "Missing permissions"))
        precondition(!CloudRetryPolicy.isQuota(statusCode: 500, status: nil, message: "Server unavailable"))
        precondition(CloudRetryPolicy.quotaDelay(attempt: 1) == 900)
        precondition(CloudRetryPolicy.quotaDelay(attempt: 2) == 1800)
        precondition(CloudRetryPolicy.quotaDelay(attempt: 30) == 3600)
        print("PASS: quota routing, permission/error distinction, bounded retry backoff.")
    }
}
