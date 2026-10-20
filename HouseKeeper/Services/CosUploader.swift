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
    static let shareName = "share.name"            // v1.21：分享名片-姓名（可空，空 = 梁涛）
    static let sharePhone = "share.phone"          // v1.21：分享名片-电话（可空，空 = 13288251132）
}

enum KeychainStore {
    private static let service = "com.zfgj.housekeeper"

    /// v1.20：返回写入结果（true=成功）。此前写入失败被静默吞掉，用户以为保存成功实际没写入。
    /// kSecAttrAccessibleAfterFirstUnlock 提高开机解锁前访问的可靠性
    @discardableResult
    static func save(_ value: String, for key: String) -> Bool {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess || status == errSecDuplicateItem
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
    let customDomain: String   // v1.19：自定义域名（如 share.fangyuan88.site），空 = 用默认域名

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

// MARK: - 分享模式（v1.21：脱敏 / 完整 双模板、双缓存、双链接）

/// masked = 脱敏版（发给找房客户）：只显示户型 + 位置导航 + 实拍 + 名片，隐藏房号/价格/房东
/// full   = 完整版（发给同事）：显示房号/房东/价格/密码/户型/备注全部信息
enum ShareMode: String {
    case masked = "masked"
    case full = "full"

    /// 分享页固定路径后缀：两个模式独立页面互不覆盖
    var pageSuffix: String {
        switch self {
        case .masked: return "share"
        case .full: return "share-full"
        }
    }
}

// MARK: - 腾讯云 COS V5 预签名上传（HMAC-SHA1，零第三方依赖）

enum CosUploader {

    /// 分享链接有效期：永久（10 年，COS 预签名 URL 上限内足够长，视为长期有效）
    static let shareLinkExpires: Int = 3650 * 86400

    enum CosError: LocalizedError {
        case invalidConfig
        case missingMedia
        case customDomainMissing      // v1.20：未填自定义域名，微信无法渲染卡片
        case uploadFailed(String)
        case responseInvalid

        var errorDescription: String? {
            switch self {
            case .invalidConfig:
                return "云存储配置不完整，请先在设置页填写并保存验证"
            case .missingMedia:
                return "这套房源还没有照片或视频，先编辑添加素材再分享"
            case .customDomainMissing:
                return "未填写自定义域名，分享链接会被微信识别成文件而不是卡片。请到设置页把 share.fangyuan88.site 填入「自定义域名」栏并保存"
            case .uploadFailed(let msg):
                return "上传失败：" + msg
            case .responseInvalid:
                return "上传服务返回异常，请稍后重试"
            }
        }
    }

    /// 为房源生成 H5 分享卡片（v1.21：按 mode 生成脱敏版 / 完整版，各自独立页面、独立缓存、独立链接）
    /// - v1.17：og 标签 / 媒体 src 全部用绝对签名 URL（10 年有效），微信能抓到封面渲染成卡片
    /// - v1.18：分享页路径改为【无扩展名】h/<roomKey>/share（微信不再按 index.html 文件识别）；
    ///   同一房源媒体与信息未变化时【零上传】直接复用上次链接；只新增媒体/只改信息时仅上传增量
    /// - v1.19（方案 A 准备）：①支持【自定义域名】；②og:image 改用【压缩封面】cover（最长边 400px）；③链接追加版本参数 v
    /// - v1.20：①分享前强制校验自定义域名已填；②host 自动剥离用户误填的 https:// 前缀与尾部斜杠
    /// - v1.21：①分享模式双轨（脱敏/完整），模板按设计稿定稿（隐藏版/完整版）；
    ///   ②缓存按模式分文件（_masked / _full），互不影响、各自增量；升级后脱敏版兼容旧单文件缓存；
    ///   ③媒体排序视频置顶、图片单列（模板要求）；④名片姓名/电话来自设置页（可编辑）；
    ///   ⑤图片改 CSS 背景图渲染 + 全局禁右键/禁长按选择，视频 controlsList=nodownload（防保存下载）
    /// 入参全部为值类型（ShareMediaFile / ShareHouseInfo），Task 内不触碰 SwiftData 模型，避免跨线程访问闪退
    static func shareCard(mediaFiles: [ShareMediaFile], roomKey: String, info: ShareHouseInfo, mode: ShareMode, config: CosConfig) async throws -> URL {
        guard !mediaFiles.isEmpty else { throw CosError.missingMedia }
        // v1.20：微信渲染卡片必须走自定义域名；没填就不生成链接，直接告诉用户去哪填
        guard !config.customDomain.isEmpty else { throw CosError.customDomainMissing }

        // 0. 缓存命中（按模式）：媒体清单、房源信息、COS 配置（含自定义域名）都没变化 → 直接复用上次链接，零上传
        if let cached = ShareCacheStore.load(roomKey: roomKey, mode: mode.rawValue),
           cached.bucket == config.bucket,
           cached.region == config.region,
           (cached.customDomain ?? "") == config.customDomain,
           Set(cached.mediaFiles) == Set(mediaFiles),
           cached.info == info,
           let cachedURL = URL(string: cached.shareURL) {
            return cachedURL
        }

        // 1. 确定需上传的媒体：桶/地域未变时只上传新增媒体（媒体对象与信息无关，信息变化只重生成页面与链接）
        var toUpload = mediaFiles
        if let cached = ShareCacheStore.load(roomKey: roomKey, mode: mode.rawValue),
           cached.bucket == config.bucket,
           cached.region == config.region {
            let cachedSet = Set(cached.mediaFiles)
            toUpload = mediaFiles.filter { !cachedSet.contains($0) }
        }

        // 2. 媒体排序（v1.21 模板要求）：视频置顶第一位、图片在后
        let ordered = mediaFiles.sorted { lhs, rhs in
            let l = lhs.kind == "video" ? 0 : 1
            let r = rhs.kind == "video" ? 0 : 1
            return l < r
        }

        // 3. 上传新增媒体并生成绝对 GET 签名 URL；视频生成 video 标签，图片收集 URL 待模板渲染（背景图防保存）
        var videoTags: [String] = []
        var imageAbsURLs: [String] = []
        for item in ordered {
            let remotePath = "h/\(roomKey)/\(item.name)"
            if toUpload.contains(item) {
                let url = MediaStore.url(for: item.name, roomKey: roomKey)
                guard FileManager.default.fileExists(atPath: url.path) else { continue }
                let data = try Data(contentsOf: url)
                try await upload(data: data, to: remotePath, contentType: mimeType(for: item.kind), config: config)
            }
            let absURL = try presignedGetURL(for: remotePath, expires: shareLinkExpires, config: config).absoluteString
            if item.kind == "video" {
                videoTags.append("<video class=\"v\" controls controlsList=\"nodownload\" disablepictureinpicture playsinline preload=\"metadata\" poster=\"\(absURL)\" src=\"\(absURL)\"></video>")
            } else {
                imageAbsURLs.append(absURL)
            }
        }
        guard !videoTags.isEmpty || !imageAbsURLs.isEmpty else { throw CosError.missingMedia }

        // 4. 压缩封面（v1.19）：第一张照片压缩成最长边 400px JPEG 上传为 h/<roomKey>/cover（两模式共用）
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

        // 5. 生成并上传分享页（路径无扩展名；两模式独立页面）。链接追加版本参数 v（内容更新 → v 变 → 微信重新抓卡片）
        let pagePath = "h/\(roomKey)/\(mode.pageSuffix)"
        let shareURL = try presignedGetURL(for: pagePath, expires: shareLinkExpires, config: config)
        let versionedURL = appendVersionParameter(shareURL, version: "\(Int(Date().timeIntervalSince1970))")

        // 名片姓名/电话：优先取设置页保存值（调用方已填入 info），缺失/旧版缓存时回退默认值
        let name = (info.name ?? "").isEmpty ? "梁涛" : info.name!
        let phone = (info.phone ?? "").isEmpty ? "13288251132" : info.phone!

        let html: String
        switch mode {
        case .masked:
            // 微信卡片：标题=户型（突出），描述=姓名-电话；页面隐藏房号/价格/房东
            let title = layoutTitle(info.layout, roomNo: info.displayRoomNo)
            let desc = "\(name)-\(phone)"
            html = buildMaskedHTML(
                title: title, desc: desc,
                name: name, phone: phone,
                videoTags: videoTags, imageURLs: imageAbsURLs,
                coverSrc: coverSrc, shareLink: versionedURL.absoluteString
            )
        case .full:
            let title = "\(info.displayRoomNo) · \(info.layout.isEmpty ? "房源" : info.layout)"
            let desc = "\(info.priceText) · \(info.landlord.isEmpty ? "房东信息见页内" : info.landlord)"
            html = buildFullHTML(
                title: title, desc: desc,
                info: info, name: name, phone: phone,
                videoTags: videoTags, imageURLs: imageAbsURLs,
                coverSrc: coverSrc, shareLink: versionedURL.absoluteString
            )
        }
        try await upload(data: Data(html.utf8), to: pagePath, contentType: "text/html; charset=utf-8", config: config)

        // 6. 更新缓存（按模式分文件；含自定义域名，换域名后旧缓存自动失效）
        ShareCacheStore.save(roomKey: roomKey, mode: mode.rawValue, record: ShareCacheRecord(
            mediaFiles: mediaFiles,
            info: info,
            shareURL: versionedURL.absoluteString,
            bucket: config.bucket,
            region: config.region,
            customDomain: config.customDomain
        ))

        return versionedURL
    }

    /// v1.20：连接自检（设置页「保存并验证」调用）。
    /// ①用当前配置上传一个测试文件到桶 → 验证桶名/地域/密钥/签名；
    /// ②再用访问域名（自定义域名或默认域名）读取该文件 → 验证域名解析 + HTTPS 证书 + 私有桶签名访问。
    /// 全部通过返回实际使用的访问域名；任一环节失败抛出带具体错误码的详细信息。
    static func verifyConnection(config: CosConfig) async throws -> String {
        let testPath = "h/_verify/connect.txt"
        let testData = Data("connect-ok-\(Int(Date().timeIntervalSince1970))".utf8)

        // 1. 上传测试对象：失败 = 桶名/地域/密钥/签名有误（错误信息里带 COS 错误码）
        try await upload(data: testData, to: testPath, contentType: "text/plain", config: config)

        // 2. 用访问域名读取测试对象：失败 = 自定义域名未绑定/未生效/证书异常（HTTP 错误或证书错误）
        let getURL = try presignedGetURL(for: testPath, expires: 120, config: config)
        var request = URLRequest(url: getURL)
        request.httpMethod = "GET"
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CosError.uploadFailed("网络响应无效")
        }
        guard (200...299).contains(http.statusCode), String(data: data, encoding: .utf8)?.hasPrefix("connect-ok") == true else {
            let detail = extractCosError(from: data)
            throw CosError.uploadFailed("读取测试文件失败 HTTP \(http.statusCode)（" + (detail.isEmpty ? "请确认自定义域名已在存储桶「域名与传输管理」绑定并生效（状态为上线/已解析）" : detail) + "）")
        }
        return host(for: config)
    }

    /// 读设置页保存的分享名片信息（姓名/电话）；未设置时用默认值
    /// 默认：梁涛 / 13288251132（名片、微信卡片描述、拨打电话、复制按钮四处统一）
    static func loadShareProfile() -> (name: String, phone: String) {
        let trimSet = CharacterSet.whitespacesAndNewlines
        let name = (KeychainStore.load(KeychainKey.shareName) ?? "").trimmingCharacters(in: trimSet)
        let phone = (KeychainStore.load(KeychainKey.sharePhone) ?? "").trimmingCharacters(in: trimSet)
        return (name.isEmpty ? "梁涛" : name, phone.isEmpty ? "13288251132" : phone)
    }

    // MARK: - HTML 模板（v1.21 设计稿定稿：脱敏版）

    /// 脱敏版（隐藏版）：户型大字 → 位置+导航 → 实拍（视频置顶、图片单列）→ 名片 → 底栏
    /// 无房号/价格/房东/密码/备注；图片用 CSS 背景图渲染（微信长按背景图无「保存图片」），全局禁右键/禁长按选择
    private static func buildMaskedHTML(title: String, desc: String, name: String, phone: String, videoTags: [String], imageURLs: [String], coverSrc: String, shareLink: String) -> String {
        let mediaBlock = mediaBlockHTML(videoTags: videoTags, imageURLs: imageURLs)
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
        body{font-family:-apple-system,BlinkMacSystemFont,"PingFang SC","Helvetica Neue",sans-serif;margin:0;background:#f4f5f7;color:#1c1c1e;-webkit-touch-callout:none;-webkit-user-select:none;user-select:none;-webkit-tap-highlight-color:transparent;}
        .wrap{max-width:640px;margin:0 auto;padding:0 16px 16px;}
        .hero{background:linear-gradient(135deg,#1f3a5f,#2d5f8a);color:#fff;border-radius:16px;padding:20px 20px 16px;}
        .type{font-size:30px;font-weight:700;margin:0 0 14px;}
        .loc{display:flex;align-items:center;gap:8px;color:rgba(255,255,255,.92);text-decoration:none;}
        .loc-name{font-size:15px;}
        .nav-pill{display:inline-flex;align-items:center;gap:4px;background:rgba(255,255,255,.18);border-radius:999px;padding:6px 12px;font-size:13px;margin-left:auto;}
        .sec{font-size:15px;color:#3a3a3c;margin:18px 4px 10px;font-weight:600;}
        .media{background:#fff;border-radius:16px;padding:12px;}
        .media video{width:100%;border-radius:10px;display:block;margin-bottom:10px;background:#000;}
        .cell{width:100%;aspect-ratio:4/3;border-radius:10px;background-size:cover;background-position:center;background-color:#e8e8ec;margin-bottom:10px;}
        .card{background:#fff;border-radius:16px;padding:16px;margin-top:12px;text-align:center;}
        .tag{color:#8e8e93;font-size:12px;margin-bottom:10px;}
        .row{display:flex;align-items:center;justify-content:center;gap:8px;}
        .name{font-size:17px;font-weight:600;}
        .num{font-size:16px;font-weight:600;color:#b8860b;}
        .note{color:#8e8e93;font-size:12px;margin:10px 0 14px;}
        .btns{display:flex;gap:10px;justify-content:center;}
        .btn{flex:1;max-width:220px;padding:12px 0;border-radius:999px;font-size:15px;font-weight:600;text-align:center;text-decoration:none;}
        .btn.call{background:#1f3a5f;color:#fff;}
        .btn.copy{background:#f0f0f2;color:#1c1c1e;border:none;}
        .foot{text-align:center;color:#8e8e93;font-size:12px;padding:18px 0 26px;}
        #toast{position:fixed;left:50%;bottom:80px;transform:translateX(-50%);background:rgba(0,0,0,.8);color:#fff;padding:10px 18px;border-radius:8px;font-size:14px;z-index:999;display:none;}
        </style>
        </head>
        <body oncontextmenu="return false">
        <div class="wrap">
        <section class="hero">
          <h1 class="type">\(escapeHTML(title))</h1>
          <a class="loc" href="https://uri.amap.com/search?keyword=%E5%88%A9%E4%BF%9D%E7%B1%B3%E5%85%B0%E5%85%AC%E5%AF%93" target="_blank" rel="noopener">
            <span class="loc-name">利保米兰公馆</span>
            <span class="nav-pill"><svg width="12" height="12" viewBox="0 0 24 24" fill="currentColor"><path d="M12 2a7 7 0 0 0-4 12.7V17a1 1 0 0 0 2 0v-1h4v1a1 1 0 0 0 2 0v-2.3A7 7 0 0 0 12 2zm0 2a5 5 0 1 1 0 10 5 5 0 0 1 0-10zm0 3a2 2 0 1 0 0 4 2 2 0 0 0 0-4z"/></svg>导航</span>
          </a>
        </section>
        <h2 class="sec">实拍 · 点击放大</h2>
        \(mediaBlock)
        <section class="card">
          <div class="tag">米兰租赁管家 · 专业省心租好房</div>
          <div class="row"><span class="name">\(escapeHTML(name))</span><span class="num">\(escapeHTML(phone))</span></div>
          <div class="note">微信同号 · 24小时可约看房</div>
          <div class="btns">
            <a class="btn call" href="tel:\(escapeHTML(phone))">拨打电话</a>
            <button class="btn copy" type="button" onclick="copyPhone()">复制电话</button>
          </div>
        </section>
        <div class="foot">更多米兰优质房源请与我联系</div>
        </div>
        <div id="toast"></div>
        <script>
        function openImg(src){var d=document.createElement('div');d.style.cssText='position:fixed;inset:0;background:rgba(0,0,0,.95) url("'+src+'") no-repeat center/contain;z-index:999;';d.onclick=function(){d.remove()};document.body.appendChild(d);}
        function toast(msg){var t=document.getElementById('toast');t.textContent=msg;t.style.display='block';clearTimeout(t._h);t._h=setTimeout(function(){t.style.display='none'},1600);}
        function copyPhone(){var p='\(phone)';function done(){toast('已复制 '+p)}function fb(){var i=document.createElement('input');i.value=p;document.body.appendChild(i);i.select();i.setSelectionRange(0,999);document.execCommand('copy');i.remove();done()}if(navigator.clipboard&&window.isSecureContext){navigator.clipboard.writeText(p).then(done,fb)}else{fb()}}
        </script>
        </body>
        </html>
        """
    }

    // MARK: - HTML 模板（v1.21 设计稿定稿：完整版）

    /// 完整版（不隐藏版）：信息板块五行（房号+房东 / 价格+密码 / 户型 / 备注动态 / 无导航行）→ 实拍 → 名片 → 底栏
    /// 第一行：左边房号（30px 粗体）+ 最右边房东名（18px，直接显示房东姓名，无「房东」两字）
    /// 第二行：价格（22px 金色）+ 密码（18px）从左到右
    /// 第三行：户型；第四行：备注（有才显示，空则整行隐藏）
    private static func buildFullHTML(title: String, desc: String, info: ShareHouseInfo, name: String, phone: String, videoTags: [String], imageURLs: [String], coverSrc: String, shareLink: String) -> String {
        let mediaBlock = mediaBlockHTML(videoTags: videoTags, imageURLs: imageURLs)
        let coverMeta = coverSrc.isEmpty ? "" : "<meta property=\"og:image\" content=\"\(coverSrc)\">"
        let urlMeta = shareLink.isEmpty ? "" : "<meta property=\"og:url\" content=\"\(shareLink)\">"

        let host = info.landlord.isEmpty ? "" : "<span class=\"host\">\(escapeHTML(info.landlord))</span>"
        let pw = info.password.isEmpty ? "" : "<span class=\"pw\">\(escapeHTML(info.password))</span>"
        let remarkLine = info.remark.isEmpty ? "" : "<div class=\"remark\">\(escapeHTML(info.remark))</div>"
        let layoutLine = info.layout.isEmpty ? "" : "<div class=\"l3\">\(escapeHTML(info.layout))</div>"

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
        body{font-family:-apple-system,BlinkMacSystemFont,"PingFang SC","Helvetica Neue",sans-serif;margin:0;background:#f4f5f7;color:#1c1c1e;-webkit-touch-callout:none;-webkit-user-select:none;user-select:none;-webkit-tap-highlight-color:transparent;}
        .wrap{max-width:640px;margin:0 auto;padding:0 16px 16px;}
        .hero{background:linear-gradient(135deg,#1f3a5f,#2d5f8a);color:#fff;border-radius:16px;padding:20px 20px 16px;}
        .l1{display:flex;justify-content:space-between;align-items:baseline;}
        .room{font-size:30px;font-weight:700;}
        .host{font-size:18px;color:rgba(255,255,255,.9);}
        .l2{display:flex;align-items:baseline;gap:14px;margin-top:12px;}
        .price{font-size:22px;font-weight:700;color:#f5c46b;}
        .pw{font-size:18px;color:rgba(255,255,255,.9);}
        .l3{margin-top:10px;font-size:15px;color:rgba(255,255,255,.92);}
        .remark{margin-top:8px;font-size:13px;color:rgba(255,255,255,.7);}
        .sec{font-size:15px;color:#3a3a3c;margin:18px 4px 10px;font-weight:600;}
        .media{background:#fff;border-radius:16px;padding:12px;}
        .media video{width:100%;border-radius:10px;display:block;margin-bottom:10px;background:#000;}
        .cell{width:100%;aspect-ratio:4/3;border-radius:10px;background-size:cover;background-position:center;background-color:#e8e8ec;margin-bottom:10px;}
        .card{background:#fff;border-radius:16px;padding:16px;margin-top:12px;text-align:center;}
        .tag{color:#8e8e93;font-size:12px;margin-bottom:10px;}
        .row{display:flex;align-items:center;justify-content:center;gap:8px;}
        .name{font-size:17px;font-weight:600;}
        .num{font-size:16px;font-weight:600;color:#b8860b;}
        .note{color:#8e8e93;font-size:12px;margin:10px 0 14px;}
        .btns{display:flex;gap:10px;justify-content:center;}
        .btn{flex:1;max-width:220px;padding:12px 0;border-radius:999px;font-size:15px;font-weight:600;text-align:center;text-decoration:none;}
        .btn.call{background:#1f3a5f;color:#fff;}
        .btn.copy{background:#f0f0f2;color:#1c1c1e;border:none;}
        .foot{text-align:center;color:#8e8e93;font-size:12px;padding:18px 0 26px;}
        #toast{position:fixed;left:50%;bottom:80px;transform:translateX(-50%);background:rgba(0,0,0,.8);color:#fff;padding:10px 18px;border-radius:8px;font-size:14px;z-index:999;display:none;}
        </style>
        </head>
        <body oncontextmenu="return false">
        <div class="wrap">
        <section class="hero">
          <div class="l1"><span class="room">\(escapeHTML(info.displayRoomNo))</span>\(host)</div>
          <div class="l2"><span class="price">\(escapeHTML(info.priceText))</span>\(pw)</div>
          \(layoutLine)
          \(remarkLine)
        </section>
        <h2 class="sec">实拍 · 点击放大</h2>
        \(mediaBlock)
        <section class="card">
          <div class="tag">米兰租赁管家 · 专业省心租好房</div>
          <div class="row"><span class="name">\(escapeHTML(name))</span><span class="num">\(escapeHTML(phone))</span></div>
          <div class="note">微信同号 · 24小时可约看房</div>
          <div class="btns">
            <a class="btn call" href="tel:\(escapeHTML(phone))">拨打电话</a>
            <button class="btn copy" type="button" onclick="copyPhone()">复制电话</button>
          </div>
        </section>
        <div class="foot">更多米兰优质房源请与我联系</div>
        </div>
        <div id="toast"></div>
        <script>
        function openImg(src){var d=document.createElement('div');d.style.cssText='position:fixed;inset:0;background:rgba(0,0,0,.95) url("'+src+'") no-repeat center/contain;z-index:999;';d.onclick=function(){d.remove()};document.body.appendChild(d);}
        function toast(msg){var t=document.getElementById('toast');t.textContent=msg;t.style.display='block';clearTimeout(t._h);t._h=setTimeout(function(){t.style.display='none'},1600);}
        function copyPhone(){var p='\(phone)';function done(){toast('已复制 '+p)}function fb(){var i=document.createElement('input');i.value=p;document.body.appendChild(i);i.select();i.setSelectionRange(0,999);document.execCommand('copy');i.remove();done()}if(navigator.clipboard&&window.isSecureContext){navigator.clipboard.writeText(p).then(done,fb)}else{fb()}}
        </script>
        </body>
        </html>
        """
    }

    /// 媒体块：视频标签原样输出（置顶），图片渲染为背景图 div（单列、防长按保存、点击放大）
    private static func mediaBlockHTML(videoTags: [String], imageURLs: [String]) -> String {
        var parts: [String] = []
        for tag in videoTags { parts.append(tag) }
        for url in imageURLs {
            parts.append("<div class=\"cell\" style=\"background-image:url('\(url)')\" onclick=\"openImg('\(url)')\"></div>")
        }
        guard !parts.isEmpty else { return "" }
        return "<div class=\"media\">" + parts.joined(separator: "") + "</div>"
    }

    /// 户型标题：户型 + 房号中的上下层后缀（如「单间 · 上层」）；无后缀只显示户型
    private static func layoutTitle(_ layout: String, roomNo: String) -> String {
        let suffix = roomNo.filter { !$0.isNumber && $0 != "-" && $0 != " " && $0 != "." && $0 != "/" }
        var title = layout.isEmpty ? "房源" : layout
        if !suffix.isEmpty { title += " · " + suffix }
        return title
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
    /// v1.20：自动剥离用户误填的 https:// / http:// 前缀和尾部斜杠
    private static func host(for config: CosConfig) -> String {
        var domain = config.customDomain.trimmingCharacters(in: .whitespacesAndNewlines)
        if !domain.isEmpty {
            for prefix in ["https://", "http://"] {
                if domain.lowercased().hasPrefix(prefix) {
                    domain = String(domain.dropFirst(prefix.count))
                }
            }
            while domain.hasSuffix("/") {
                domain.removeLast()
            }
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
    ///    实际请求 URL 的 path 才做百分号编码
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
