import SwiftUI
import SwiftData

@main
struct HouseKeeperApp: App {
    let container: ModelContainer

    init() {
        let schema = Schema([House.self, MediaItem.self])
        do {
            container = try ModelContainer(for: schema)
        } catch {
            fatalError("无法创建数据存储：\(error)")
        }
        // 首次启动写入示例房源，方便直接看效果（可在应用内删除）
        SampleData.seedIfNeeded(container)
    }

    var body: some Scene {
        WindowGroup {
            HouseListView()
        }
        .modelContainer(container)
    }
}
