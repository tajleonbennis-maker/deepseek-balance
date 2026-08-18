import Foundation

enum BalanceFetcher {

    static let endpoint = URL(string: "https://api.deepseek.com/user/balance")!

    /// 查询单个 key 的余额，回调在主线程执行
    static func fetch(_ key: KeyConfig, completion: @escaping (BalanceResult) -> Void) {
        var req = URLRequest(url: endpoint)
        req.httpMethod = "GET"
        req.setValue("Bearer \(key.apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 15

        URLSession.shared.dataTask(with: req) { data, resp, err in
            var result = BalanceResult(keyId: key.id, status: .networkError)

            defer { DispatchQueue.main.async { completion(result) } }

            if let err = err {
                let nsErr = err as NSError
                if nsErr.code == NSURLErrorNotConnectedToInternet || nsErr.code == NSURLErrorNetworkConnectionLost {
                    result.status = .networkError
                } else if nsErr.code == NSURLErrorTimedOut {
                    result.status = .networkError
                } else {
                    result.status = .networkError
                }
                return
            }

            guard let http = resp as? HTTPURLResponse else {
                result.status = .serverError
                return
            }

            switch http.statusCode {
            case 200:
                guard let data = data,
                      let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                      let infos = json["balance_infos"] as? [[String: Any]]
                else {
                    result.status = .serverError
                    return
                }
                // 多币种时优先 CNY（用户主力币种），否则取第一个
                let info = infos.first(where: { ($0["currency"] as? String)?.uppercased() == "CNY" }) ?? infos.first
                guard let info = info else {
                    result.status = .serverError
                    return
                }
                result.status = .ok
                result.isAvailable = (json["is_available"] as? Bool) ?? false
                result.currency = (info["currency"] as? String) ?? "CNY"
                result.total = Double(info["total_balance"] as? String ?? "") ?? 0
                result.granted = Double(info["granted_balance"] as? String ?? "") ?? 0
                result.toppedUp = Double(info["topped_up_balance"] as? String ?? "") ?? 0
            case 401:
                result.status = .invalidKey
            case 429:
                result.status = .rateLimited
            default:
                result.status = .serverError
            }
        }.resume()
    }
}
