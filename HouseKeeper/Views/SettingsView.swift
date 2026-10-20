import SwiftUI

/// 设置页：腾讯云 COS 配置（用于分享房源卡片链接）
struct SettingsView: View {
    @State private var bucket = ""
    @State private var region = "ap-guangzhou"
    @State private var secretId = ""
    @State private var secretKey = ""
    @State private var savedTip: String?

    init() {
        let b = KeychainStore.load(KeychainKey.bucket) ?? ""
        let r = KeychainStore.load(KeychainKey.region) ?? "ap-guangzhou"
        let i = KeychainStore.load(KeychainKey.secretId) ?? ""
        let k = KeychainStore.load(KeychainKey.secretKey) ?? ""
        _bucket = State(initialValue: b)
        _region = State(initialValue: r)
        _secretId = State(initialValue: i)
        _secretKey = State(initialValue: k)
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
                TextField("地域（如 ap-guangzhou）", text: $region)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("SecretId", text: $secretId)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("SecretKey", text: $secretKey)
            }

            Section {
                Button {
                    save()
                } label: {
                    Text("保存配置")
                        .frame(maxWidth: .infinity)
                }
                .disabled(bucket.isEmpty || region.isEmpty || secretId.isEmpty || secretKey.isEmpty)
            }

            Section("开通步骤（简述）") {
                Text("1. 打开 cloud.tencent.com 注册并实名认证；2. 开通「对象存储 COS」；3. 创建存储桶：名称建议 fangyuan-media、地域选广州、访问权限选「私有读写」；4. 在「访问管理 CAM → API 密钥管理」新建密钥，得到 SecretId 和 SecretKey；5. 填到上方并保存。密钥只存在本机钥匙串，不会上传。")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
        .alert("已保存", isPresented: Binding(
            get: { savedTip != nil },
            set: { if !$0 { savedTip = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(savedTip ?? "")
        }
    }

    private func save() {
        KeychainStore.save(bucket, for: KeychainKey.bucket)
        KeychainStore.save(region, for: KeychainKey.region)
        KeychainStore.save(secretId, for: KeychainKey.secretId)
        KeychainStore.save(secretKey, for: KeychainKey.secretKey)
        savedTip = "配置已保存到手机钥匙串，现在可以去详情页「分享」生成卡片链接"
    }
}
