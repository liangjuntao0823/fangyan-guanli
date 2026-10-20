import SwiftUI

/// 设置页（v1.22 重构：归拢成两个入口——远程配置 / 名片信息）
/// 远程配置：腾讯云 COS 存储桶、密钥、自定义域名（用于分享房源卡片链接）
/// 名片信息：分享 H5 页面与微信卡片上显示的姓名/电话（默认：梁涛 / 13288251132）
struct SettingsView: View {
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
struct ShareProfileView: View {
    @State private var shareName = ""
    @State private var sharePhone = ""
    @State private var savedTip: String?

    init() {
        let n = KeychainStore.load(KeychainKey.shareName) ?? "梁涛"
        let p = KeychainStore.load(KeychainKey.sharePhone) ?? "13288251132"
        _shareName = State(initialValue: n)
        _sharePhone = State(initialValue: p)
    }

    var body: some View {
        Form {
            Section(header: Text("名片信息"), footer: Text("姓名和电话会显示在分享 H5 页面的名片区、微信卡片的描述和「拨打电话/复制电话」按钮上。修改并保存后，下次分享会自动按新名片重新生成链接；之前已发出的链接保持原样。")) {
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