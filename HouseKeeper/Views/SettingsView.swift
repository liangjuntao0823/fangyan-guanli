import SwiftUI

/// 设置页：腾讯云 COS 配置（用于分享房源卡片链接）
struct SettingsView: View {
    @State private var bucket = \u{22}\u{22}
    @State private var region = \u{22}ap-guangzhou\u{22}
    @State private var secretId = \u{22}\u{22}
    @State private var secretKey = \u{22}\u{22}
    @State private var savedTip: String?

    init() {
        let b = KeychainStore.load(KeychainKey.bucket) ?? \u{22}\u{22}
        let r = KeychainStore.load(KeychainKey.region) ?? \u{22}ap-guangzhou\u{22}
        let i = KeychainStore.load(KeychainKey.secretId) ?? \u{22}\u{22}
        let k = KeychainStore.load(KeychainKey.secretKey) ?? \u{22}\u{22}
        _bucket = State(initialValue: b)
        _region = State(initialValue: r)
        _secretId = State(initialValue: i)
        _secretKey = State(initialValue: k)
    }

    var body: some View {
        Form {
            Section {
                LabeledContent(\u{22}用途\u{22}, value: \u{22}分享房源卡片链接\u{22})
                LabeledContent(\u{22}有效期\u{22}, value: \u{22}30 天（到期自动失效）\u{22})
            } footer: {
                Text(\u{22}分享时 App 会把该房源的图片和视频上传到腾讯云 COS，生成一个链接卡片发给微信好友；好友点开卡片即可查看。\u{22})
            }

            Section(\u{22}腾讯云 COS 配置\u{22}) {
                TextField(\u{22}存储桶名称\u{22}, text: $bucket)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField(\u{22}地域（如 ap-guangzhou）\u{22}, text: $region)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField(\u{22}SecretId\u{22}, text: $secretId)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField(\u{22}SecretKey\u{22}, text: $secretKey)
            }

            Section {
                Button {
                    save()
                } label: {
                    Text(\u{22}保存配置\u{22})
                        .frame(maxWidth: .infinity)
                }
                .disabled(bucket.isEmpty || region.isEmpty || secretId.isEmpty || secretKey.isEmpty)
            }

            Section(\u{22}开通步骤（简述）\u{22}) {
                Text(\u{22}1. 打开 cloud.tencent.com 注册并实名认证；2. 开通「对象存储 COS」；3. 创建存储桶：名称建议 fangyuan-media、地域选广州、访问权限选「私有读写」；4. 在「访问管理 CAM → API 密钥管理」新建密钥，得到 SecretId 和 SecretKey；5. 填到上方并保存。密钥只存在本机钥匙串，不会上传。\u{22})
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle(\u{22}设置\u{22})
        .navigationBarTitleDisplayMode(.inline)
        .alert(\u{22}已保存\u{22}, isPresented: Binding(
            get: { savedTip != nil },
            set: { if !$0 { savedTip = nil } }
        )) {
            Button(\u{22}好\u{22}, role: .cancel) {}
        } message: {
            Text(savedTip ?? \u{22}\u{22})
        }
    }

    private func save() {
        KeychainStore.save(bucket, for: KeychainKey.bucket)
        KeychainStore.save(region, for: KeychainKey.region)
        KeychainStore.save(secretId, for: KeychainKey.secretId)
        KeychainStore.save(secretKey, for: KeychainKey.secretKey)
        savedTip = \u{22}配置已保存到手机钥匙串，现在可以去详情页「分享」生成卡片链接\u{22}
    }
}
