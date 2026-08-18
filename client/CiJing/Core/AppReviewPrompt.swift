import Foundation

/// 求评分的节流规则。
///
/// iOS 每个用户每 12 个月只给这个 App **3 次**弹窗配额，而且是否真的弹出由系统决定
/// ——请求了不一定看得见，看不见也照样扣配额。所以我们在系统之上再收一道，只把配额
/// 花在最值得的时刻：练习总结页刚跨级解锁徽章那一下。
///
/// `SKStoreReviewController` 只是「请求」，绝不能接在写着「点这里评分」的按钮上
/// （违反审核指南）。显式入口走设置页那条 `?action=write-review` 商品页链接，是另一
/// 回事，两者不冲突。
enum AppReviewPrompt {
    /// 自动弹窗总开关。关掉之后只剩设置页的手动入口。
    ///
    /// 留这个开关是因为时机比实现更要紧：把配额投给一个刚修完一批问题、还没在线上
    /// 跑稳的版本是净亏。如果决定等 1.0.1 上架稳定一两周再放开，把这里改成 false，
    /// 下一版再改回来即可。
    static let automaticPromptEnabled = true

    /// 连续完成不足这个天数不请求——刚上手的用户还没形成判断。
    private static let minimumStreakDays = 3
    /// 两次请求之间至少隔这么久，避免跨版本反复打扰。
    private static let minimumInterval: TimeInterval = 90 * 24 * 60 * 60

    private static let lastVersionKey = "review.prompt.lastVersion"
    private static let lastDateKey = "review.prompt.lastDate"

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    /// 同一版本只请求一次，且要同时满足连续天数和时间间隔。
    static func shouldRequest(streakDays: Int, defaults: UserDefaults = .standard) -> Bool {
        guard automaticPromptEnabled, streakDays >= minimumStreakDays else { return false }
        guard defaults.string(forKey: lastVersionKey) != currentVersion else { return false }
        if let last = defaults.object(forKey: lastDateKey) as? Date,
           Date().timeIntervalSince(last) < minimumInterval {
            return false
        }
        return true
    }

    /// 在发出请求时记账。记的是「请求过」而不是「弹出过」——系统不告诉我们弹没弹，
    /// 配额也是按请求扣的，按请求记才对得上。
    static func recordRequest(defaults: UserDefaults = .standard) {
        defaults.set(currentVersion, forKey: lastVersionKey)
        defaults.set(Date(), forKey: lastDateKey)
    }
}
