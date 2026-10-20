import Foundation
import CryptoKit
import Security
import UIKit

// MARK: - 钥匙串存取（COS 密钥等敏感配置）

enum KeychainKey {
    static let bucket = "cos.bucket"
    static let region = "cos.region"
    static let secretId = "cos.secretId"
    static let secretKey = "cos.secretKey"
    static let customDomain = "cos.customDomain"   // v1.19：自定义域名（可空），空 = 用 COS 默认域名
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
    let customDomain: String   // v1.19：自定义域名（如 share.fangyuan88.top），空 = 用默认域名

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
        let customDomain = (KeychainStore.load(KeychainKey.customDomain) ?? "").trimmingCharacters(in: trimSet)
        let config = CosConfig(bucket: bucket, region: region, secretId: secretId, secretKey: secretKey, customDomain: customDomain)
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

    /// 为房源生成 H5 分享卡片：
    /// - v1.17：og 标签 / 媒体 src 全部用绝对签名 URL（10 年有效），微信能抓到封面渲染成卡片
    /// - v1.18：分享页路径改为【无扩展名】h/<roomKey>/share（微信不再按 index.html 文件识别）；
    ///   同一房源媒体与信息未变化时【零上传】直接复用上次链接；只新增媒体/只改信息时仅上传增量
    /// - v1.19（方案 A 准备）：①支持【自定义域名】——腾讯云 2024 年后新建桶默认域名强制下载，
    ///   微信会把链接识别成文件；绑定自定义域名后微信才按网页抓取生成卡片（换域名自动重生成链接）；
    ///   ②og:image 改用【压缩封面】cover（最长边 400px），微信秒抓不卡顿；
    ///   ③分享链接追加【版本参数 v】，内容更新后微信按新链接重新抓取，避免旧卡片缓存
    /// 入参全部为值类型（ShareMediaFile / ShareHouseInfo），Task 内不触碰 SwiftData 模型，避免跨线程访问闪退
    static func shareCard(mediaFiles: [ShareMediaFile], roomKey: String, info: ShareHouseInfo, config: CosConfig) async throws -> URL {
        guard !mediaFiles.isEmpty else { throw CosError.missingMedia }

        // 0. 缓存命中：媒体清单、房源信息、COS 配置（含自定义域名）都没变化 → 直接复用上次链接，零上传
        if let cached = ShareCacheStore.load(roomKey: roomKey),
           cached.bucket == config.bucket,
           cached.region == config.region,
           (cached.customDomain ?? "") == config.customDomain,
           Set(cached.mediaFiles) == Set(mediaFiles),
           cached.info == info,
           let cachedURL = URL(string: cached.shareURL) {
            return cachedURL
        }

        // 1. 确定需上传的媒体：信息未变时只上传新增媒体（COS 上已存在的直接复用）；
        //    换自定义域名【不重传媒体】——对象仍在同一桶，只是访问入口变化，重新生成 URL 即可
        var toUpload = mediaFiles
        if let cached = ShareCacheStore.load(roomKey: roomKey), cached.bucket == config.bucket, cached.region == config.region, cached.info == info {
            let cachedSet = Set(cached.mediaFiles)
            toUpload = mediaFiles.filter { !cachedSet.contains($0) }
        }

        // 2. 上传需要上传的媒体，并生成每个媒体的绝对 GET 签名 URL（供 HTML 内 src / og:image 使用）
        var mediaTags: [String] = []
        var imageAbsURLs: [String] = []   // 图片的绝对 URL 列表，第一张作为 og:image 兜底封面
        for item in mediaFiles {
            let remotePath = "h/\(roomKey)/\(item.name)"
            if toUpload.contains(item) {
                let url = MediaStore.url(for: item.name, roomKey: roomKey)
                guard FileManager.default.fileExists(atPath: url.path) else { continue }
                let data = try Data(contentsOf: url)
                try await upload(data: data, to: remotePath, contentType: mimeType(for: item.kind), config: config)
            }
            let absURL = try presignedGetURL(for: remotePath, expires: shareLinkExpires, config: config).absoluteString
            if item.kind == "video" {
                mediaTags.append("<video class=\"v\" controls playsinline preload=\"metadata\" poster=\"\(absURL)\" src=\"\(absURL)\"></video>")
            } else {
                mediaTags.append("<img class=\"p\" src=\"\(absURL)\">")
                imageAbsURLs.append(absURL)
            }
        }
        guard !mediaTags.isEmpty else { throw CosError.missingMedia }

        // 2.5 压缩封面（v1.19）：把第一张照片压缩成最长边 400px 的 JPEG 上传为 h/<roomKey>/cover，
        //    微信 og:image 抓小图秒开；封面生成/上传失败不阻塞分享，回退用第一张原图
        var coverSrc = imageAbsURLs.first ?? ""
        if let firstImage = mediaFiles.first(where: { $0.kind == "image" }),
           let coverData = makeCoverJPEG(from: MediaStore.url(for: firstImage.name, roomKey: roomKey)) {
            let coverPath = "h/\(roomKey)/cover"
            do {
                try await upload(data: coverData, to: coverPath, contentType: "image/jpeg", config: config)
                coverSrc = try presignedGetURL(for: coverPath, expires: shareLinkExpires, config: config).absoluteString
            } catch {
                // 封面失败不阻塞：沿用第一张原图
            }
        }

        // 3. 生成并上传分享页（路径无扩展名，微信识别为网页链接而非文件；Content-Type 保持 text/html）
        //    链接追加版本参数 v（不参与签名，COS 忽略未声明参数）：内容变化 → v 变化 → 微信按新链接重新抓卡片
        let title = "\(info.displayRoomNo) · \(info.layout.isEmpty ? "房源" : info.layout)"
        let desc = "\(info.priceText) · \(info.landlord.isEmpty ? "房东信息见页内" : info.landlord)"
        let pagePath = "h/\(roomKey)/share"
        let shareURL = try presignedGetURL(for: pagePath, expires: shareLinkExpires, config: config)
        let versionedURL = appendVersionParameter(shareURL, version: "\(Int(Date().timeIntervalSince1970))")
        let html = buildHTML(
            title: title,
            desc: desc,
            roomNo: info.displayRoomNo,
            towerLabel: info.towerLabel,
            layout: info.layout,
            statusLabel: info.statusLabel,
            priceText: info.priceText,
            landlord: info.landlord,
            password: info.password,
            remark: info.remark,
            mediaTags: mediaTags,
            coverSrc: coverSrc,
            shareLink: versionedURL.absoluteString
        )
        try await upload(data: Data(html.utf8), to: pagePath, contentType: "text/html; charset=utf-8", config: config)

        // 4. 更新缓存（含自定义域名字段，换域名后旧缓存自动失效）
        ShareCacheStore.save(roomKey: roomKey, record: ShareCacheRecord(
            mediaFiles: mediaFiles,
            info: info,
            shareURL: versionedURL.absoluteString,
            bucket: config.bucket,
            region: config.region,
            customDomain: config.customDomain
        ))

        return versionedURL
    }

    // MARK: - HTML 模板

    private static func buildHTML(title: String, desc: String, roomNo: String, towerLabel: String, layout: String, statusLabel: String, priceText: String, landlord: String, password: String, remark: String, mediaTags: [String], coverSrc: String, shareLink: String) -> String {
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
        // og:image / og:url 必须用绝对 URL，微信服务端才能抓取到封面并渲染成卡片
        let coverMeta = coverSrc.isEmpty ? "" : "<meta property=\"og:image\" content=\"\(coverSrc)\">"
        let urlMeta = shareLink.isEmpty ? "" : "<meta property=\"og:url\" content=\"\(shareLink)\">"
        return """
        <!DOCTYPE html>
        <html lang="zh-CN">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta property="og:title" content="\(escapeHTML(title))">
        <meta property="og:description" content="\(escapeHTML(desc))">
        \(coverMeta)
        \(urlMeta)
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
        let url = try presignedPutURL(for: remotePath, contentType: contentType, config: config)
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        let (respData, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            // 读取 COS 返回的 XML 错误码（SignatureDoesNotMatch / InvalidAccessKeyId / AccessDenied 等），精确定位 403 原因
            let detail = extractCosError(from: respData)
            let statusText: String
            if let http = response as? HTTPURLResponse {
                statusText = "HTTP \(http.statusCode)"
            } else {
                statusText = "网络响应无效"
            }
            throw CosError.uploadFailed(statusText + (detail.isEmpty ? "" : "（" + detail + "）"))
        }
    }

    /// 从 COS 错误响应 XML 中提取 Error Code 与 Message
    private static func extractCosError(from data: Data) -> String {
        guard let text = String(data: data, encoding: .utf8) else { return "" }
        func value(of tag: String) -> String? {
            guard let start = text.range(of: "<\(tag)>")?.upperBound,
                  let end = text[start...].range(of: "</\(tag)>")?.lowerBound else { return nil }
            return String(text[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let code = value(of: "Code") ?? ""
        let message = value(of: "Message") ?? ""
        if code.isEmpty { return "" }
        return message.isEmpty ? "错误码 \(code)" : "错误码 \(code)：\(message)"
    }

    /// v1.19：配置了自定义域名就用它（Host 与签名都指向自定义域名，微信按网页抓取）；
    /// 未配置时回退 COS 默认域名（2024 年后新建桶默认域名强制下载，微信会识别成文件——仅作兜底）
    private static func host(for config: CosConfig) -> String {
        let domain = config.customDomain.trimmingCharacters(in: .whitespacesAndNewlines)
        if !domain.isEmpty {
            return domain
        }
        return "\(config.bucket).cos.\(config.region).myqcloud.com"
    }

    /// PUT 预签名：Content-Type 参与签名（COS 要求请求携带的 header 必须在签名中，否则返回 403）
    private static func presignedPutURL(for path: String, contentType: String, config: CosConfig) throws -> URL {
        try presignedURL(for: path, method: "PUT", expires: 3600, headers: [("content-type", contentType)], config: config)
    }

    /// GET 预签名：只签 host（下载/访问链接不带自定义 header）
    private static func presignedGetURL(for path: String, expires: Int, config: CosConfig) throws -> URL {
        try presignedURL(for: path, method: "GET", expires: expires, headers: [], config: config)
    }

    /// COS V5 签名：q-sign-algorithm=sha1;q-ak=...;q-sign-time=...;q-key-time=...;q-header-list=...;q-url-param-list=...;q-signature=...
    /// 关键（严格按 COS 官方规范文档 436/7778 及官方 Python SDK cos_auth.py）：
    /// 1. HttpString = HttpMethod\nUriPathname\nHttpParameters\nHttpHeaders\n —— 恰好 3 个换行分隔 4 段，末尾再一个换行（参数为空时是两个连续换行）
    /// 2. 【根因修复】UriPathname 必须用【未编码】的原样路径参与签名（服务端会用解码后的请求路径重算校验）；
    ///    实际请求 URL 的 path 才做百分号编码。v1.12 曾误把编码路径用于签名 → SignatureDoesNotMatch（本次修复）
    /// 3. HttpHeaders 的 key 小写、value 按 RFC3986 编码、按字典序拼接
    /// 4. q-header-list 用分号分隔参与签名的 header key
    private static func presignedURL(for path: String, method: String, expires: Int, headers: [(String, String)], config: CosConfig) throws -> URL {
        let now = Int(Date().timeIntervalSince1970)
        let signTime = "\(now);\(now + expires)"
        let keyTime = signTime

        let hostValue = host(for: config)
        let rawPath = "/" + path
        // 请求 URL 的路径做百分号编码（保留 /），中文房号目录会被编码
        let encodedPath = rawPath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? rawPath

        // 组装签名 headers：key 小写、value RFC3986 编码，排序后拼接
        var pairs = headers.map { (key: $0.0.lowercased(), value: urlEncode($0.1)) }
        pairs.append(("host", hostValue.lowercased()))
        pairs.sort { $0.key < $1.key }
        let headerList = pairs.map(\.key).joined(separator: ";")
        let headerValue = pairs.map { "\($0.key)=\($0.value)" }.joined(separator: "&")

        let signKey = HMAC_SHA1(key: config.secretKey, message: keyTime)
        // HttpString 段结构：method\n路径\n参数\n请求头\n（参数为空时是两个连续换行）
        // 路径必须用未编码的 rawPath 参与签名（官方规范），请求 URL 才用 encodedPath
        let httpString = "\(method.lowercased())\n\(rawPath)\n\n\(headerValue)\n"
        let sha1Http = SHA1(hexString: httpString)
        let stringToSign = "sha1\n\(signTime)\n\(sha1Http)\n"
        let signature = HMAC_SHA1(key: signKey, message: stringToSign)

        var comps = URLComponents()
        comps.scheme = "https"
        comps.host = hostValue
        comps.percentEncodedPath = encodedPath
        comps.percentEncodedQuery = "q-sign-algorithm=sha1&q-ak=\(config.secretId)&q-sign-time=\(signTime)&q-key-time=\(keyTime)&q-header-list=\(headerList)&q-url-param-list=&q-signature=\(signature)"
        guard let url = comps.url else { throw CosError.invalidConfig }
        return url
    }

    /// RFC 3986 严格百分号编码（保留 A-Z a-z 0-9 - _ . ~）
    private static func urlEncode(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.~")) ?? s
    }

    // MARK: - v1.19 新增：压缩封面 / 版本参数

    /// 生成微信 og:image 压缩封面：最长边 400px、JPEG 质量 0.72（通常几十 KB），微信服务端秒抓
    private static func makeCoverJPEG(from url: URL) -> Data? {
        guard let image = UIImage(contentsOfFile: url.path) else { return nil }
        let maxSide: CGFloat = 400
        let w = image.size.width
        let h = image.size.height
        guard w > 0, h > 0 else { return nil }
        let scale = min(maxSide / max(w, h), 1)
        let target = CGSize(width: max(Int(w * scale), 1), height: max(Int(h * scale), 1))
        UIGraphicsBeginImageContextWithOptions(target, false, 1.0)
        image.draw(in: CGRect(origin: .zero, size: target))
        let scaled = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return scaled?.jpegData(compressionQuality: 0.72)
    }

    /// 在签名 URL 上追加版本参数 v。v 不参与签名（q-url-param-list 为空，COS 服务端忽略未声明参数，签名仍有效）；
    /// 内容更新后 v 变化 → 微信把链接当新链接重新抓取 og，避免命中旧卡片缓存
    private static func appendVersionParameter(_ url: URL, version: String) -> URL {
        let s = url.absoluteString + "&v=" + version
        return URL(string: s) ?? url
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
