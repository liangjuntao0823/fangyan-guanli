import Foundation
import CryptoKit
import Security

// MARK: - 钥匙串存取（COS 密钥等敏感配置）

enum KeychainKey {
    static let bucket = "cos.bucket"
    static let region = "cos.region"
    static let secretId = "cos.secretId"
    static let secretKey = "cos.secretKey"
}

enum KeychainStore {
    private static let service = "com.zfgj.housekeeper"

    static func save(_ value: String, for key: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    static func load(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

// MARK: - COS 配置

struct CosConfig {
    let bucket: String
    let region: String
    let secretId: String
    let secretKey: String

    var isValid: Bool {
        !bucket.isEmpty && !region.isEmpty && !secretId.isEmpty && !secretKey.isEmpty
    }

    /// 从钥匙串读取配置（自动去掉首尾空格，避免复制粘贴带入空白导致签名失败）
    static func load() -> CosConfig? {
        let trimSet = CharacterSet.whitespacesAndNewlines
        let bucket = (KeychainStore.load(KeychainKey.bucket) ?? "").trimmingCharacters(in: trimSet)
        let region = (KeychainStore.load(KeychainKey.region) ?? "").trimmingCharacters(in: trimSet)
        let secretId = (KeychainStore.load(KeychainKey.secretId) ?? "").trimmingCharacters(in: trimSet)
        let secretKey = (KeychainStore.load(KeychainKey.secretKey) ?? "").trimmingCharacters(in: trimSet)
        let config = CosConfig(bucket: bucket, region: region, secretId: secretId, secretKey: secretKey)
        return config.isValid ? config : nil
    }
}

// MARK: - 腾讯云 COS V5 预签名上传（HMAC-SHA1，零第三方依赖）

enum CosUploader {

    /// 分享链接有效期：永久（10 年，COS 预签名 URL 上限内足够长，视为长期有效）
    static let shareLinkExpires: Int = 3650 * 86400

    enum CosError: LocalizedError {
        case invalidConfig
        case missingMedia
        case uploadFailed(String)
        case responseInvalid

        var errorDescription: String? {
            switch self {
            case .invalidConfig:
                return "云存储配置不完整，请先在设置页填写"
            case .missingMedia:
                return "这套房源还没有照片或视频，先编辑添加素材再分享"
            case .uploadFailed(let msg):
                return "上传失败：" + msg
            case .responseInvalid:
                return "上传服务返回异常，请稍后重试"
            }
        }
    }

    /// 为房源生成 H5 分享卡片：上传所有媒体 → 生成 index.html → 上传 → 返回长期有效的链接（URL 对象，系统分享面板可直接作为链接分享）
    static func shareCard(for house: House, config: CosConfig) async throws -> URL {
        let media = house.mediaItems
        guard !media.isEmpty else { throw CosError.missingMedia }

        let roomKey = house.mediaRoomKey  // 房号目录名（安全文件名）

        // 1. 逐个上传媒体
        var mediaTags: [String] = []
        for item in media {
            let url = MediaStore.url(for: item.fileName, roomKey: roomKey)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            let data = try Data(contentsOf: url)
            let remotePath = "h/\(roomKey)/\(item.fileName)"
            try await upload(data: data, to: remotePath, contentType: mimeType(for: item.kind), config: config)
            if item.kind == "video" {
                mediaTags.append("<video class=\"v\" controls playsinline preload=\"metadata\" poster=\"\(remotePath)\" src=\"\(remotePath)\"></video>")
            } else {
                mediaTags.append("<img class=\"p\" src=\"\(remotePath)\">")
            }
        }
        guard !mediaTags.isEmpty else { throw CosError.missingMedia }

        // 2. 生成 index.html（带 og 标签，微信抓取卡片）
        let title = "\(house.displayRoomNo) · \(house.layout.isEmpty ? "房源" : house.layout)"
        let desc = "\(house.priceText) · \(house.landlord.isEmpty ? "房东信息见页内" : house.landlord)"
        // 封面用第一张图（og:image 用与页面相同的长期有效 URL，微信能持续抓取到封面）
        let cover = mediaTags.first { $0.contains("img") } ?? ""
        let coverSrc = cover.isEmpty ? "" : extractSrc(from: cover)

        let html = buildHTML(
            title: title,
            desc: desc,
            roomNo: house.displayRoomNo,
            towerLabel: house.towerLabel,
            layout: house.layout,
            statusLabel: house.status.label,
            priceText: house.priceText,
            landlord: house.landlord,
            password: house.password,
            remark: house.remark,
            mediaTags: mediaTags,
            coverSrc: coverSrc
        )
        let htmlData = Data(html.utf8)
        let htmlPath = "h/\(roomKey)/index.html"
        try await upload(data: htmlData, to: htmlPath, contentType: "text/html; charset=utf-8", config: config)

        // 3. 返回 index.html 的长期有效 GET 预签名 URL
        return try presignedGetURL(for: htmlPath, expires: shareLinkExpires, config: config)
    }

    private static func extractSrc(from tag: String) -> String {
        guard let start = tag.range(of: "src=\"")?.upperBound else { return "" }
        guard let end = tag[start...].range(of: "\"")?.lowerBound else { return "" }
        return String(tag[start..<end])
    }

    // MARK: - HTML 模板

    private static func buildHTML(title: String, desc: String, roomNo: String, towerLabel: String, layout: String, statusLabel: String, priceText: String, landlord: String, password: String, remark: String, mediaTags: [String], coverSrc: String) -> String {
        let hero = """
        <div class="hero">
          <div class="badge">\(escapeHTML(statusLabel))</div>
          <h1>\(escapeHTML(roomNo))</h1>
          <p class="sub">\(escapeHTML(towerLabel)) · \(escapeHTML(layout))</p>
          <p class="price">\(escapeHTML(priceText))</p>
        </div>
        """
        let info = """
        <div class="info">
          <div class="row"><span>房东</span><b>\(escapeHTML(landlord))</b></div>
          <div class="row"><span>密码</span><b>\(escapeHTML(password))</b></div>
          <div class="row"><span>备注</span><b>\(escapeHTML(remark))</b></div>
        </div>
        """
        let grid = "<div class=\"grid\">" + mediaTags.joined(separator: "") + "</div>"
        let coverMeta = coverSrc.isEmpty ? "" : "<meta property=\"og:image\" content=\"\(coverSrc)\">"
        return """
        <!DOCTYPE html>
        <html lang="zh-CN">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta property="og:title" content="\(escapeHTML(title))">
        <meta property="og:description" content="\(escapeHTML(desc))">
        \(coverMeta)
        <title>\(escapeHTML(title))</title>
        <style>
        body{font-family:-apple-system,BlinkMacSystemFont,"PingFang SC","Helvetica Neue",sans-serif;margin:0;background:#f4f5f7;color:#1c1c1e;}
        .wrap{max-width:640px;margin:0 auto;padding:16px;}
        .hero{background:linear-gradient(135deg,#1f3a5f,#2d5f8a);color:#fff;border-radius:16px;padding:24px 20px;}
        .badge{display:inline-block;background:rgba(255,255,255,.2);border-radius:999px;padding:4px 12px;font-size:13px;}
        h1{margin:12px 0 4px;font-size:28px;}
        .sub{color:rgba(255,255,255,.85);margin:0 0 10px;font-size:14px;}
        .price{font-size:22px;font-weight:700;margin:0;}
        .info{background:#fff;border-radius:16px;padding:6px 16px;margin:12px 0;}
        .row{display:flex;justify-content:space-between;padding:10px 0;border-bottom:1px solid #f0f0f0;font-size:15px;}
        .row:last-child{border-bottom:none;}
        .row span{color:#8e8e93;}
        .grid{background:#fff;border-radius:16px;padding:12px;margin:12px 0;}
        .grid img{width:100%;border-radius:10px;margin-bottom:8px;display:block;}
        .grid video{width:100%;border-radius:10px;margin-bottom:8px;display:block;}
        .foot{text-align:center;color:#8e8e93;font-size:12px;padding:16px 0 28px;}
        </style>
        </head>
        <body>
        <div class="wrap">
        \(hero)
        \(info)
        \(grid)
        <div class="foot">房源管家 · 分享链接长期有效</div>
        </div>
        </body>
        </html>
        """
    }

    private static func escapeHTML(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    // MARK: - 上传 / 预签名

    private static func mimeType(for kind: String) -> String {
        kind == "video" ? "video/quicktime" : "image/jpeg"
    }

    private static func upload(data: Data, to remotePath: String, contentType: String, config: CosConfig) async throws {
        let url = try presignedPutURL(for: remotePath, config: config)
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw CosError.uploadFailed("HTTP \(String(describing: (response as? HTTPURLResponse)?.statusCode))")
        }
    }

    private static func host(for config: CosConfig) -> String {
        "\(config.bucket).cos.\(config.region).myqcloud.com"
    }

    private static func presignedPutURL(for path: String, config: CosConfig) throws -> URL {
        try presignedURL(for: path, method: "PUT", expires: 3600, config: config)
    }

    private static func presignedGetURL(for path: String, expires: Int, config: CosConfig) throws -> URL {
        try presignedURL(for: path, method: "GET", expires: expires, config: config)
    }

    /// COS V5 签名：q-sign-algorithm=sha1;q-ak=...;q-sign-time=...;q-key-time=...;q-header-list=...;q-url-param-list=...;q-signature=...
    private static func presignedURL(for path: String, method: String, expires: Int, config: CosConfig) throws -> URL {
        let now = Int(Date().timeIntervalSince1970)
        let signTime = "\(now);\(now + expires)"
        let keyTime = signTime

        let hostValue = host(for: config)
        let pathWithSlash = "/" + path
        let headerList = "host"
        let headerValue = "host=\(hostValue.lowercased())"

        let signKey = HMAC_SHA1(key: config.secretKey, message: keyTime)
        let httpString = "\(method.lowercased())\n\(pathWithSlash)\n\n\n\(headerValue)\n"
        let sha1Http = SHA1(hexString: httpString)
        let stringToSign = "sha1\n\(signTime)\n\(sha1Http)\n"
        let signature = HMAC_SHA1(key: signKey, message: stringToSign)

        var comps = URLComponents()
        comps.scheme = "https"
        comps.host = hostValue
        comps.percentEncodedPath = pathWithSlash
        comps.percentEncodedQuery = "q-sign-algorithm=sha1&q-ak=\(config.secretId)&q-sign-time=\(signTime)&q-key-time=\(keyTime)&q-header-list=\(headerList)&q-url-param-list=&q-signature=\(signature)"
        guard let url = comps.url else { throw CosError.invalidConfig }
        return url
    }

    // MARK: - 加密原语（HMAC-SHA1 / SHA1 hex）

    private static func HMAC_SHA1(key: String, message: String) -> String {
        let keyData = Data(key.utf8)
        let msgData = Data(message.utf8)
        let mac = HMAC<Insecure.SHA1>.authenticationCode(for: msgData, using: SymmetricKey(data: keyData))
        return mac.map { String(format: "%02x", $0) }.joined()
    }

    private static func SHA1(hexString: String) -> String {
        let data = Data(hexString.utf8)
        return Insecure.SHA1.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
