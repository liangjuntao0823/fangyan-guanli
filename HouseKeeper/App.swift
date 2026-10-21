import SwiftUI
import SwiftData

@main
struct HouseKeeperApp: App {
    let container: ModelContainer?
    let storageErrorMessage: String?

    init() {
        // v1.29：数据容器显式放在 Documents 目录（housekeeper.store），与 Media/ 同处一个文件夹。
        // 「文件」App 里整个「房源管家」文件夹 = 完整数据 → 复制整个文件夹即备份，放回即恢复（微信式文件夹备份）。
        // 旧版默认放 Library/Application Support，用户看不到也复制不出来，重装后房源记录必丢——已修复。
        var created: ModelContainer?
        var errorMessage: String?
        do {
            let schema = Schema([House.self, MediaItem.self])
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let storeURL = docs.appendingPathComponent("housekeeper.store")
            created = try ModelContainer(for: schema, configurations: [ModelConfiguration(url: storeURL)])
        } catch {
            errorMessage = error.localizedDescription
        }
        container = created
        storageErrorMessage = errorMessage

        // v1.29：Documents 里生成「备份说明.txt」（只写一次），引导用户复制整个文件夹做备份
        BackupGuide.ensureExists()

        // 首次启动写入示例房源（已有数据则跳过，放回备份后不会覆盖）
        if let created {
            SampleData.seedIfNeeded(created)
        }
    }

    var body: some Scene {
        WindowGroup {
            if let container {
                HouseListView()
                    .modelContainer(container)
            } else {
                StorageErrorView(message: storageErrorMessage)
            }
        }
    }
}

/// v1.29：数据存储打不开时（例如备份文件夹只复制了一部分、数据库半损坏）不再 fatalError 闪退，
/// 而是显示恢复引导：优先从完整备份放回文件，兜底可清除损坏数据重新开始。
struct StorageErrorView: View {
    let message: String?

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 44))
                .foregroundColor(.orange)
            Text("数据存储打开失败")
                .font(.headline)
            Text("原因：\(message ?? "未知错误")\n\n请优先通过「文件」App → 我的 iPhone → 房源管家，把完整备份（housekeeper.store 及 Media 文件夹）放回原位后重新打开 App。\n\n注意：下方「重新开始」会清空本机全部房源记录，仅在没有备份可用时才点。")
                .font(.footnote)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
            Button("删除损坏数据，重新开始") {
                let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                for name in ["housekeeper.store", "housekeeper.store-shm", "housekeeper.store-wal"] {
                    try? FileManager.default.removeItem(at: docs.appendingPathComponent(name))
                }
                exit(0)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(UIColor.systemGroupedBackground))
    }
}
