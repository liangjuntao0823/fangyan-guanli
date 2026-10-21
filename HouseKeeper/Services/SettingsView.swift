import SwiftUI
import PhotosUI

/// 设置页（v1.22 重构：归拢成两个入口——远程配置 / 名片信息）
/// 远程配置：腾讯云 COS 存储桶、密钥、自定义域名（用于分享房源卡片链接）
/// 名片信息：分享 H5 页面与微信卡片上显示的姓名/电话（默认：梁涛 / 13288251132）
struct SettingsView: View {
    @State private var refreshedTip: String?

    var body: some View {
        Form {
            Section {
                NavigationLink {
                    CosConfigView()
                } label: {
                    Label("远程配置", systemImage: "server.rack")
                }
                NavigationLink {
                    ShareProfileView()
                } label: {
                    Label("名片信息", systemImage: "person.crop.circle")
                }
            } footer: {
                Text("远程配置：腾讯云 COS 存储桶、密钥与自定义域名，用于把房源的图片/视频上传并生成分享卡片链接。名片信息：分享 H5 页面和微信卡片上显示的姓名与电话。")
            }

            // v1.23：分享时压缩开关——视频压到 720p、图片轻压缩（参照微信非原图质量），
            // 大幅降低上传流量与 COS 流量费用；关掉则按原文件原样上传
            Section {
                Toggle("分享时压缩视频和图片", isOn: Binding(
                    get: { UserDefaults.standard.bool(forKey: "compressOnShare") },
                    set: { UserDefaults.standard.set($0, forKey: "compressOnShare") }
                ))
            } footer: {
                Text("开启后：视频压缩到 720p 再上传，图片做轻压缩（不牺牲观感，参照微信「不加载原图」的画质），分享更快、更省流量。")
            }

            // v1.25：分享缓存管理——改了分享页面样式后想立刻重新生成链接时手动刷新；
            // 平时不需要：App 每次更新页面模板后旧缓存会自动失效，下次分享自动重新生成
            Section {
                Button {
                    ShareCacheStore.clearAll()
                    refreshedTip = "分享缓存已清空 ✅\n下次分享会重新上传并生成新链接（所有房源）"
                } label: {
                    Label("刷新分享缓存", systemImage: "arrow.clockwise.circle")
                }
            } footer: {
                Text("平时无需操作：App 更新页面设计后，旧缓存会自动失效、分享自动生成新页面。仅当您想立刻重置全部缓存（例如改了页面样式想马上生效）时才需要点这里。")
            }

            Section("开通步骤（简述）") {
                Text("1. 打开 cloud.tencent.com 注册并实名认证；2. 开通「对象存储 COS」；3. 创建存储桶：名称建议 fangyuan88、地域选香港、访问权限选「私有读写」；4. 在「访问管理 CAM → API 密钥管理」新建密钥，得到 SecretId 和 SecretKey；5. 在「存储桶 → 域名与传输管理 → 自定义源站域名」绑定自己的域名（需先在腾讯云购买域名），并把域名填入远程配置的「自定义域名」栏——微信只认自定义域名，才能把链接抓成网页卡片。")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                Text("密钥与名片只存在本机钥匙串，不会上传到任何地方。")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
        .alert("刷新分享缓存", isPresented: Binding(
            get: { refreshedTip != nil },
            set: { if !$0 { refreshedTip = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(refreshedTip ?? "")
        }
    }
}

// MARK: - 远程配置（腾讯云 COS）

/// v1.19：新增「自定义域名（可选）」——腾讯云 2024 年后新建桶默认域名会被微信识别成文件，
/// 绑定自定义域名后微信才会把分享链接抓成网页卡片；域名留空则回退默认域名（仅兜底）
/// v1.20：保存改为「保存并验证连接」——写入钥匙串成功后立即用当前配置向 COS 上传一个测试文件
/// 并回读，真实连通才算保存成功；任何环节失败都会给出具体错误码（桶不存在/签名错误/域名未生效），
/// 不再静默提示「已保存」；同时密钥写入失败也会明确报出。
struct CosConfigView: View {
    @State private var bucket = ""
    @State private var region = "ap-hongkong"
    @State private var secretId = ""
    @State private var secretKey = ""
    @State private var customDomain = ""
    @State private var savedTip: String?
    @State private var isVerifying = false

    init() {
        let b = KeychainStore.load(KeychainKey.bucket) ?? ""
        let r = KeychainStore.load(KeychainKey.region) ?? "ap-hongkong"
        let i = KeychainStore.load(KeychainKey.secretId) ?? ""
        let k = KeychainStore.load(KeychainKey.secretKey) ?? ""
        let d = KeychainStore.load(KeychainKey.customDomain) ?? ""
        _bucket = State(initialValue: b)
        _region = State(initialValue: r)
        _secretId = State(initialValue: i)
        _secretKey = State(initialValue: k)
        _customDomain = State(initialValue: d)
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("用途", value: "分享房源卡片链接")
                LabeledContent("有效期", value: "长期有效（不自动过期）")
            } footer: {
                Text("分享时 App 会把该房源的图片和视频上传到腾讯云 COS，生成一个链接卡片发给微信好友；好友点开卡片即可查看，链接长期有效。")
            }

            Section("腾讯云 COS 配置") {
                TextField("存储桶名称", text: $bucket)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("地域（如 ap-hongkong）", text: $region)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("自定义域名（必填，如 share.fangyuan88.site）", text: $customDomain)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                TextField("SecretId", text: $secretId)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("SecretKey", text: $secretKey)
            }

            Section {
                Button {
                    saveAndVerify()
                } label: {
                    if isVerifying {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("保存并验证连接")
                            .frame(maxWidth: .infinity)
                    }
                }
                .disabled(bucket.isEmpty || region.isEmpty || secretId.isEmpty || secretKey.isEmpty || isVerifying)
            } footer: {
                Text("点击后 App 会用当前配置向云存储上传一个测试文件并回读，成功才提示「配置正确」；失败会直接告诉您具体原因。")
            }
        }
        .navigationTitle("远程配置")
        .navigationBarTitleDisplayMode(.inline)
        .alert("配置结果", isPresented: Binding(
            get: { savedTip != nil },
            set: { if !$0 { savedTip = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(savedTip ?? "")
        }
    }

    private func saveAndVerify() {
        // 1. 写入钥匙串：任一项写失败都要明确提示（v1.20 之前写入失败被静默吞掉）
        var allSaved = true
        let items: [(String, String)] = [
            (KeychainKey.bucket, bucket),
            (KeychainKey.region, region),
            (KeychainKey.secretId, secretId),
            (KeychainKey.secretKey, secretKey),
            (KeychainKey.customDomain, customDomain)
        ]
        for (key, value) in items {
            if !KeychainStore.save(value, for: key) {
                allSaved = false
            }
        }
        if !allSaved {
            savedTip = "写入本机钥匙串失败，请重新保存一次；若仍失败请重启 App 后再试"
            return
        }

        // 2. 后台真实验证：上传测试文件 + 回读（失败会带具体错误码）
        isVerifying = true
        let config = CosConfig(bucket: bucket, region: region, secretId: secretId, secretKey: secretKey, customDomain: customDomain)
        Task {
            do {
                let hostUsed = try await CosUploader.verifyConnection(config: config)
                savedTip = "配置正确：云存储连接成功 ✅\n实际使用域名：\(hostUsed)\n现在可以去详情页「分享」生成卡片链接"
            } catch {
                savedTip = "验证失败：\(error.localizedDescription)"
            }
            isVerifying = false
        }
    }
}

// MARK: - 名片信息

/// v1.21：分享名片信息（姓名/电话）——显示在分享 H5 页面的名片区、微信卡片的描述和
/// 「拨打电话/复制电话」按钮上。v1.22：修改后再次分享自动按新名片重新生成链接
/// （分享缓存里存了名片，名片一变缓存自动失效，无需手动清缓存）。
/// v1.26：①新增实时名片预览；②说明应用范围覆盖所有出现姓名/电话的位置
/// （H5 名片区、微信卡片描述、页面底栏电话、拨打电话/复制电话）。
/// v1.27：新增「微信二维码」入口——从相册选择二维码图片保存（Documents/qrcode.png），
/// 分享时自动上传 COS 并显示在所有 H5 名片板块左侧，访客长按可直接被微信识别。
struct ShareProfileView: View {
    @State private var shareName = ""
    @State private var sharePhone = ""
    @State private var savedTip: String?
    @State private var qrImage: UIImage?
    @State private var qrPickerItem: PhotosPickerItem?

    init() {
        let n = KeychainStore.load(KeychainKey.shareName) ?? "梁涛"
        let p = KeychainStore.load(KeychainKey.sharePhone) ?? "13288251132"
        _shareName = State(initialValue: n)
        _sharePhone = State(initialValue: p)
        if let data = QrcodeStore.loadData() {
            _qrImage = State(initialValue: UIImage(data: data))
        }
    }

    /// 预览用的姓名/电话：输入为空时显示默认值（与分享时行为一致）
    private var previewName: String {
        let n = shareName.trimmingCharacters(in: .whitespacesAndNewlines)
        return n.isEmpty ? "梁涛" : n
    }
    private var previewPhone: String {
        let p = sharePhone.trimmingCharacters(in: .whitespacesAndNewlines)
        return p.isEmpty ? "13288251132" : p
    }

    var body: some View {
        Form {
            // v1.26：实时名片预览——输入即变，所见即所得
            Section(header: Text("名片预览")) {
                VStack(spacing: 10) {
                    Text("米兰租赁管家 · 专业省心租好房")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    HStack(spacing: 8) {
                        Text(previewName)
                            .font(.headline)
                        Text(previewPhone)
                            .font(.headline)
                            .foregroundColor(.orange)
                    }
                    Text("微信同号 · 24小时可约看房")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    HStack(spacing: 10) {
                        Text("拨打电话")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 26)
                            .padding(.vertical, 9)
                            .background(Color(red: 31/255, green: 58/255, blue: 95/255))
                            .clipShape(Capsule())
                        Text("复制电话")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 26)
                            .padding(.vertical, 9)
                            .background(Color(.systemGray6))
                            .clipShape(Capsule())
                    }
                    // v1.27：二维码预览（有则显示缩略图，无则提示）
                    if let qrImage {
                        Image(uiImage: qrImage)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 104, height: 104)
                            .background(Color.white)
                            .cornerRadius(10)
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(.systemGray4), lineWidth: 1))
                            .padding(.top, 6)
                    } else {
                        Text("未设置微信二维码")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .padding(.top, 6)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity)
                .background(Color(.systemBackground))
                .cornerRadius(14)
                .padding(.top, 4)
            }

            Section(header: Text("名片信息"), footer: Text("姓名和电话会应用到所有出现它们的地方：分享 H5 页面的名片区（含合集列表与详情页）、微信卡片的描述、页面底栏的联系电话、以及「拨打电话/复制电话」按钮。修改并保存后，下次分享会自动按新名片重新生成链接；之前已发出的链接保持原样。")) {
                TextField("姓名（默认：梁涛）", text: $shareName)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("电话（默认：13288251132）", text: $sharePhone)
                    .keyboardType(.phonePad)
                Button {
                    saveShareProfile()
                } label: {
                    Text("保存名片信息")
                        .frame(maxWidth: .infinity)
                }
                .disabled(shareName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            // v1.27：微信二维码——相册选择保存；分享时自动上传，显示在所有 H5 名片板块左侧
            Section(header: Text("微信二维码"), footer: Text("二维码会显示在所有分享 H5 页面的名片板块左侧（拨打电话/复制电话上方），访客长按二维码即可弹出微信「识别图中二维码」菜单。更换后无需重新分享——已发出的链接也会自动显示新二维码。")) {
                PhotosPicker(selection: $qrPickerItem, matching: .images) {
                    Label(qrImage == nil ? "选择二维码图片" : "更换二维码图片", systemImage: "qrcode")
                }
                .onChange(of: qrPickerItem) { _, newItem in
                    guard let newItem else { return }
                    Task {
                        if let data = try? await newItem.loadTransferable(type: Data.self),
                           let image = UIImage(data: data),
                           let jpeg = image.jpegData(compressionQuality: 0.9) {
                            let ok = QrcodeStore.save(jpeg)
                            qrImage = UIImage(data: jpeg)
                            savedTip = ok ? "微信二维码已更新 ✅\n下次分享起所有 H5 名片板块都会显示新二维码" : "保存二维码失败，请重试"
                        } else {
                            savedTip = "无法读取所选图片，请换一张清晰的二维码图片"
                        }
                        qrPickerItem = nil
                    }
                }
                if qrImage != nil {
                    Button("清除二维码", role: .destructive) {
                        QrcodeStore.clear()
                        qrImage = nil
                        savedTip = "二维码已清除，下次分享的页面将不再显示二维码"
                    }
                }
            }
        }
        .navigationTitle("名片信息")
        .navigationBarTitleDisplayMode(.inline)
        .alert("保存结果", isPresented: Binding(
            get: { savedTip != nil },
            set: { if !$0 { savedTip = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(savedTip ?? "")
        }
    }

    /// 保存分享名片信息（姓名/电话）到钥匙串
    private func saveShareProfile() {
        let name = shareName.trimmingCharacters(in: .whitespacesAndNewlines)
        let phone = sharePhone.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            savedTip = "姓名不能为空"
            return
        }
        var ok = KeychainStore.save(name, for: KeychainKey.shareName)
        ok = KeychainStore.save(phone, for: KeychainKey.sharePhone) && ok
        savedTip = ok ? "名片信息已保存 ✅\n姓名：\(name)\n电话：\(phone.isEmpty ? "（未填，分享时用默认号）" : phone)" : "写入本机钥匙串失败，请重新保存一次"
    }
}
