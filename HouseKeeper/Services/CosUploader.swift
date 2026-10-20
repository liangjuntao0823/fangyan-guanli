import Foundation
import CryptoKit
import Security

// MARK: - 云存储配置（腾讯云 COS，存于系统钥匙串）

struct CosConfig {
    let bucket: String
    let region: String
    let secretId: String
    let secretKey: String

    var isValid: Bool {
        !bucket.isEmpty && !region.isEmpty && !secretId.isEmpty && !secretKey.isEmpty
    }

    static func load() -> CosConfig? {
        let b = KeychainStore.load(KeychainKey.bucket) ?? \u{22}\u{22}
        let r = KeychainStore.load(KeychainKey.region) ?? \u{22}\u{22}
        let i = KeychainStore.load(KeychainKey.secretId) ?? \u{22}\u{22}
        let k = KeychainStore.load(KeychainKey.secretKey) ?? \u{22}\u{22}
        return CosConfig(bucket: b, region: r, secretId: i, secretKey: k)
    }
}

enum KeychainKey {
    static let bucket = \u{22}cosBucket\u{22}
    static let region = \u{22}cosRegion\u{22}
    static let secretId = \u{22}cosSecretId\u{22}
    static let secretKey = \u{22}cosSecretKey\u{22}
}

enum KeychainStore {
    private static func baseQuery(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: \u{22}com.zfgj.housekeeper\u{22},
         kSecAttrAccount as String: key]
    }

    static func save(_ value: String, for key: String) {
        var q = baseQuery(key)
        SecItemDelete(q as CFDictionary)
        q[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(q as CFDictionary, nil)
    }

    static func load(_ key: String) -> String? {
        var q = baseQuery(key)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

// MARK: - 腾讯云 COS 直传（V5 预签名 URL，零第三方依赖）

enum CosError: LocalizedError {
    case invalidConfig
    case uploadFailed

    var errorDescription: String? {
        switch self {
        case .invalidConfig:
            return \u{22}云存储配置无效，请在首页左上角「设置」里检查存储桶、地域和密钥\u{22}
        case .uploadFailed:
            return \u{22}上传失败，请检查存储桶名称、地域和密钥是否正确\u{22}
        }
    }
}

enum CosUploader {
    /// 分享链接有效期（30 天）
    static let shareExpiry: TimeInterval = 30 * 24 * 3600

    private static func host(bucket: String, region: String) -> String {
        bucket + \u{22}.cos.\u{22} + region + \u{22}.myqcloud.com\u{22}
    }

    private static func encodePath(_ p: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: \u{22}/-._~\u{22}))
        return p.addingPercentEncoding(withAllowedCharacters: allowed) ?? p
    }

    private static func sha1Hex(_ s: String) -> String {
        let h = Insecure.SHA1.hash(data: Data(s.utf8))
        return h.map { String(format: \u{22}%02x\u{22}, $0) }.joined()
    }

    /// 生成 COS V5 预签名 URL（GET / PUT）
    static func presignedURL(method: String, bucket: String, region: String, secretId: String, secretKey: String, path: String, expiry: TimeInterval) -> URL? {
        let now = Int(Date().timeIntervalSince1970)
        let end = now + Int(expiry)
        let keyTime = \u{22}\(now);\(end)\u{22}
        let signTime = keyTime
        let hst = host(bucket: bucket, region: region)
        let uri = encodePath(path)
        let headers = [\u{22}host\u{22}: hst]
        let headerKeys = headers.keys.sorted()
        let canonicalHeaders = headerKeys.map { $0.lowercased() + \u{22}=\u{22} + (headers[$0] ?? \u{22}\u{22}) + \u{22}\n\u{22} }.joined()
        let headerList = headerKeys.map { $0.lowercased() }.joined(separator: \u{22};\u{22})
        let canonicalRequest = method + \u{22}\n\u{22} + uri + \u{22}\n\n\u{22} + canonicalHeaders + \u{22}\n\u{22} + headerList
        let stringToSign = \u{22}sha1\n\u{22} + signTime + \u{22}\n\u{22} + sha1Hex(canonicalRequest) + \u{22}\n\u{22}
        let signKey = HMAC<Insecure.SHA1>.authenticationCode(for: Data(keyTime.utf8), using: SymmetricKey(data: Data(secretKey.utf8)))
        let signature = HMAC<Insecure.SHA1>.authenticationCode(for: Data(stringToSign.utf8), using: SymmetricKey(data: Data(signKey)))
        let sigHex = signature.map { String(format: \u{22}%02x\u{22}, $0) }.joined()
        let query = \u{22}q-sign-algorithm=sha1&q-ak=\u{22} + secretId + \u{22}&q-sign-time=\u{22} + signTime + \u{22}&q-key-time=\u{22} + keyTime + \u{22}&q-header-list=\u{22} + headerList + \u{22}&q-url-param-list=&q-signature=\u{22} + sigHex
        var comps = URLComponents()
        comps.scheme = \u{22}https\u{22}
        comps.host = hst
        comps.percentEncodedPath = uri
        comps.percentEncodedQuery = query
        return comps.url
    }

    static func upload(data: Data, contentType: String, to url: URL) async throws {
        var req = URLRequest(url: url)
        req.httpMethod = \u{22}PUT\u{22}
        req.setValue(contentType, forHTTPHeaderField: \u{22}Content-Type\u{22})
        req.httpBody = data
        let (_, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw CosError.uploadFailed
        }
    }

    static func mimeType(for fileName: String) -> String {
        let ext = (fileName as NSString).pathExtension.lowercased()
        switch ext {
        case \u{22}jpg\u{22}, \u{22}jpeg\u{22}: return \u{22}image/jpeg\u{22}
        case \u{22}png\u{22}: return \u{22}image/png\u{22}
        case \u{22}heic\u{22}: return \u{22}image/heic\u{22}
        case \u{22}mp4\u{22}: return \u{22}video/mp4\u{22}
        case \u{22}mov\u{22}: return \u{22}video/quicktime\u{22}
        case \u{22}html\u{22}: return \u{22}text/html; charset=utf-8\u{22}
        default: return \u{22}application/octet-stream\u{22}
        }
    }

    // MARK: - 生成并上传房源分享卡片

    static func shareCard(for house: House, config: CosConfig) async throws -> URL {
        let roomKey = house.mediaRoomKey
        let base = \u{22}h/\u{22} + roomKey

        // 1. 上传素材（图片 + 视频）
        for media in house.mediaItems {
            let local = MediaStore.url(for: media.fileName, roomKey: roomKey)
            guard FileManager.default.fileExists(atPath: local.path) else { continue }
            let data = try Data(contentsOf: local)
            let path = base + \u{22}/\u{22} + media.fileName
            guard let put = presignedURL(method: \u{22}PUT\u{22}, bucket: config.bucket, region: config.region, secretId: config.secretId, secretKey: config.secretKey, path: path, expiry: 3600) else {
                throw CosError.invalidConfig
            }
            try await upload(data: data, contentType: mimeType(for: media.fileName), to: put)
        }

        // 2. 素材 GET 预签名 URL（30 天）
        let imageURLs = house.photos.compactMap { m -> URL? in
            presignedURL(method: \u{22}GET\u{22}, bucket: config.bucket, region: config.region, secretId: config.secretId, secretKey: config.secretKey, path: base + \u{22}/\u{22} + m.fileName, expiry: shareExpiry)
        }
        let videoURLs = house.videos.compactMap { m -> URL? in
            presignedURL(method: \u{22}GET\u{22}, bucket: config.bucket, region: config.region, secretId: config.secretId, secretKey: config.secretKey, path: base + \u{22}/\u{22} + m.fileName, expiry: shareExpiry)
        }

        // 3. 生成 H5 页面
        let html = buildHTML(house: house, imageURLs: imageURLs.map(\.absoluteString), videoURLs: videoURLs.map(\.absoluteString))

        // 4. 上传 H5 页面
        let htmlPath = base + \u{22}/index.html\u{22}
        guard let putHtml = presignedURL(method: \u{22}PUT\u{22}, bucket: config.bucket, region: config.region, secretId: config.secretId, secretKey: config.secretKey, path: htmlPath, expiry: 3600) else {
            throw CosError.invalidConfig
        }
        try await upload(data: Data(html.utf8), contentType: mimeType(for: \u{22}index.html\u{22}), to: putHtml)

        // 5. 页面分享链接
        guard let share = presignedURL(method: \u{22}GET\u{22}, bucket: config.bucket, region: config.region, secretId: config.secretId, secretKey: config.secretKey, path: htmlPath, expiry: shareExpiry) else {
            throw CosError.invalidConfig
        }
        return share
    }

    // MARK: - H5 页面模板

    static func escapeHTML(_ s: String) -> String {
        s.replacingOccurrences(of: \u{22}&\u{22}, with: \u{22}&amp;\u{22})
         .replacingOccurrences(of: \u{22}<\u{22}, with: \u{22}&lt;\u{22})
         .replacingOccurrences(of: \u{22}>\u{22}, with: \u{22}&gt;\u{22})
         .replacingOccurrences(of: \u{22}'\u{22}, with: \u{22}&#39;\u{22})
    }

    static func buildHTML(house: House, imageURLs: [String], videoURLs: [String]) -> String {
        let title = house.displayRoomNo + \u{22} \u{22} + (house.layout.isEmpty ? \u{22}\u{22} : house.layout)
        let priceLine = house.price > 0 ? \u{22}\(house.price)元/月\u{22} : \u{22}价格面议\u{22}
        let landlordLine = house.landlord.isEmpty ? \u{22}—\u{22} : house.landlord
        let statusLine = house.status == .available ? \u{22}待租（可带看）\u{22} : \u{22}已租\u{22}
        let ogImage = imageURLs.first ?? \u{22}\u{22}
        let ogDesc = priceLine + \u{22} · 房东 \u{22} + landlordLine + \u{22} · \u{22} + statusLine

        var imgs = \u{22}\u{22}
        for u in imageURLs {
            imgs += \u{22}<img src='\u{22} + escapeHTML(u) + \u{22}' loading='lazy' />\n\u{22}
        }
        var vids = \u{22}\u{22}
        for u in videoURLs {
            vids += \u{22}<div class='vid'><video controls playsinline preload='metadata' src='\u{22} + escapeHTML(u) + \u{22}'></video></div>\n\u{22}
        }

        var passwordHTML = \u{22}\u{22}
        if !house.password.isEmpty {
            passwordHTML = \u{22}<div class='row'><span class='k'>密码</span><span class='v'>\u{22} + escapeHTML(house.password) + \u{22}</span></div>\n\u{22}
        }
        var remarkHTML = \u{22}\u{22}
        if !house.remark.isEmpty {
            remarkHTML = \u{22}<div class='row'><span class='k'>备注</span><span class='v'>\u{22} + escapeHTML(house.remark) + \u{22}</span></div>\n\u{22}
        }

        let css = \u{22}<style>body{margin:0;padding:0;font-family:-apple-system,'PingFang SC','Helvetica Neue',sans-serif;background:#f2f3f5;color:#1f2328}.wrap{max-width:640px;margin:0 auto;padding:16px}.hero{background:linear-gradient(135deg,#0f5a8a,#1e88c7);color:#fff;border-radius:14px;padding:18px 16px}.hero .no{font-size:24px;font-weight:700}.hero .sub{font-size:14px;opacity:.9;margin-top:6px}.hero .tag{display:inline-block;margin-top:10px;font-size:13px;background:rgba(255,255,255,.22);padding:4px 12px;border-radius:999px}.card{background:#fff;border-radius:14px;padding:14px;margin-top:12px}.row{display:flex;justify-content:space-between;align-items:center;padding:9px 0;border-bottom:1px solid #f0f0f0;font-size:15px}.row:last-child{border-bottom:none}.k{color:#8a9199}.v{font-weight:600;text-align:right;padding-left:12px}.grid{display:grid;grid-template-columns:repeat(3,1fr);gap:6px}.grid img{width:100%;aspect-ratio:1;object-fit:cover;border-radius:8px;display:block}.vid{margin-top:10px}.vid video{width:100%;border-radius:10px;background:#000}.foot{margin:18px 0 26px;text-align:center;font-size:12px;color:#a0a6ad}</style>\u{22}

        var lines: [String] = []
        lines.append(\u{22}<!DOCTYPE html><html><head><meta charset='utf-8'><meta name='viewport' content='width=device-width,initial-scale=1'>\u{22})
        lines.append(\u{22}<title>\u{22} + escapeHTML(title) + \u{22}</title>\u{22})
        lines.append(\u{22}<meta property='og:title' content='\u{22} + escapeHTML(title) + \u{22}' />\u{22})
        lines.append(\u{22}<meta property='og:description' content='\u{22} + escapeHTML(ogDesc) + \u{22}' />\u{22})
        if !ogImage.isEmpty {
            lines.append(\u{22}<meta property='og:image' content='\u{22} + escapeHTML(ogImage) + \u{22}' />\u{22})
        }
        lines.append(css)
        lines.append(\u{22}</head><body><div class='wrap'>\u{22})
        lines.append(\u{22}<div class='hero'><div class='no'>\u{22} + escapeHTML(house.displayRoomNo) + \u{22}</div><div class='sub'>\u{22} + escapeHTML(house.towerLabel) + \u{22} · \u{22} + escapeHTML(house.layout.isEmpty ? \u{22}户型未填\u{22} : house.layout) + \u{22}</div><span class='tag'>\u{22} + escapeHTML(statusLine) + \u{22}</span></div>\u{22})
        lines.append(\u{22}<div class='card'>\u{22})
        lines.append(\u{22}<div class='row'><span class='k'>价格</span><span class='v'>\u{22} + escapeHTML(priceLine) + \u{22}</span></div>\n\u{22})
        lines.append(\u{22}<div class='row'><span class='k'>房东</span><span class='v'>\u{22} + escapeHTML(landlordLine) + \u{22}</span></div>\n\u{22})
        lines.append(\u{22}<div class='row'><span class='k'>户型</span><span class='v'>\u{22} + escapeHTML(house.layout.isEmpty ? \u{22}—\u{22} : house.layout) + \u{22}</span></div>\n\u{22})
        lines.append(passwordHTML)
        lines.append(remarkHTML)
        lines.append(\u{22}</div>\u{22})
        if !imgs.isEmpty {
            lines.append(\u{22}<div class='card'><div class='grid'>\u{22})
            lines.append(imgs)
            lines.append(\u{22}</div></div>\u{22})
        }
        if !vids.isEmpty {
            lines.append(vids)
        }
        lines.append(\u{22}<div class='foot'>房源管家 · 分享链接 30 天内有效</div>\u{22})
        lines.append(\u{22}</div></body></html>\u{22})
        return lines.joined(separator: \u{22}\n\u{22})
    }
}
