import Foundation

/// DeepSeek 对话客户端（多轮对话用）
struct ChatMessage: Codable {
    var role: String   // system / user / assistant
    var content: String
}

final class DeepSeekChatClient {

    static let shared = DeepSeekChatClient()

    private init() {}

    /// 发起一轮对话，回调在主线程
    func chat(apiKey: String, messages: [ChatMessage], completion: @escaping (String?, String?) -> Void) {
        guard let url = URL(string: "https://api.deepseek.com/chat/completions") else {
            completion(nil, "URL 错误")
            return
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 180

        let body: [String: Any] = [
            "model": "deepseek-chat",
            "messages": messages.map { ["role": $0.role, "content": $0.content] },
            "stream": false,
            "max_tokens": 2000,
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: req) { data, _, err in
            DispatchQueue.main.async {
                guard let data = data,
                      let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                      let choices = json["choices"] as? [[String: Any]],
                      let msg = choices.first?["message"] as? [String: Any],
                      let content = msg["content"] as? String
                else {
                    completion(nil, err?.localizedDescription ?? "DeepSeek 无响应")
                    return
                }
                completion(content, nil)
            }
        }.resume()
    }
}
