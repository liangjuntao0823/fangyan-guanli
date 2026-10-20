import SwiftUI

/// 设置页：腾讯云 COS 配置（用于分享房源卡片链接）
/// v1.19：新增「自定义域名（可选）」——腾讯云 2024 年后新建桶默认域名会被微信识别成文件，
/// 绑定自定义域名后微信才会把分享链接抓成网页卡片；域名留空则回退默认域名（仅兜底）
/// v1.20：保存改为「保存并验证连接」——写入钥匙串成功后立即用当前配置向 COS 上传一个测试文件
/// 并回读，真实连通才算保存成功；任何环节失败都会给出具体错误码（桶不存在/签名错误/域名未生效），
/// 不再静默提示「已保存」；同时密钥写入失败也会明确报出。
struct SettingsView: View {
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

            Section("开通步骤（简述）") {
                Text("1. 打开 cloud.tencent.com 注册并实名认证；2. 开通「对象存储 COS」；3. 创建存储桶：名称建议 fangyuan88、地域选香港、访问权限选「私有读写」；4. 在「访问管理 CAM → API 密钥管理」新建密钥，得到 SecretId 和 SecretKey；5. 填到上方并保存。密钥只存在本机钥匙串，不会上传。")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                Text("6. （必做）在「存储桶 → 域名与传输管理 → 自定义源站域名」绑定自己的域名（需先在腾讯云购买域名），并把域名填到上方的「自定义域名」栏——微信只认自定义域名，才能把链接抓成网页卡片；不填的话分享会被识别成文件。")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle("设置")
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
