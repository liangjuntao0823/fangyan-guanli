import Foundation

/// 房源照片 / 视频文件管理：按房号子目录存到 App 的 Documents/Media/<房号>/ 目录
/// 数据库里只保存文件名，文件本体在磁盘，避免 SwiftData 存储膨胀
/// Documents 已开启文件共享（UIFileSharingEnabled），可在 iOS「文件」App 中查看
enum MediaStore {
    static let mediaDirectoryName = "Media"

    static func mediaDirectory() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent(mediaDirectoryName, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// 某套房源对应的媒体目录（Documents/Media/<房号>/）
    static func houseDirectory(roomKey: String) -> URL {
        let dir = mediaDirectory().appendingPathComponent(roomKey, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// 保存二进制数据（照片转 JPEG 后调用），返回文件名
    static func save(data: Data, ext: String, roomKey: String) -> String {
        let fileName = "\(UUID().uuidString).\(ext)"
        let url = houseDirectory(roomKey: roomKey).appendingPathComponent(fileName)
        try? data.write(to: url)
        return fileName
    }

    /// 保存临时文件（相册选中的视频等），拷贝到 App 目录，返回文件名
    static func saveFile(from source: URL, roomKey: String) -> String {
        let ext = source.pathExtension.isEmpty ? "mov" : source.pathExtension
        let fileName = "\(UUID().uuidString).\(ext)"
        let target = houseDirectory(roomKey: roomKey).appendingPathComponent(fileName)
        try? FileManager.default.copyItem(at: source, to: target)
        return fileName
    }

    /// 获取文件完整路径；优先按房号目录读取，兼容旧版平铺目录（Documents/Media/<文件名>）
    static func url(for fileName: String, roomKey: String) -> URL {
        let newURL = houseDirectory(roomKey: roomKey).appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: newURL.path) {
            return newURL
        }
        return mediaDirectory().appendingPathComponent(fileName)
    }

    /// 删除文件（删除房源 / 删除单条媒体时调用），新旧两处路径都清理
    /// 防御：fileName 为空时绝不执行——否则 appendingPathComponent("") 会指向目录本身，removeItem 会误删整个房号目录
    static func delete(fileName: String, roomKey: String) {
        guard !fileName.isEmpty else { return }
        let newURL = houseDirectory(roomKey: roomKey).appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: newURL)
        let legacyURL = mediaDirectory().appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: legacyURL)
    }

    /// 删除房源关联的全部媒体文件
    static func deleteAll(files: [String], roomKey: String) {
        for fileName in files {
            delete(fileName: fileName, roomKey: roomKey)
        }
    }

    /// 房号变更时，把旧房号目录整体迁移到新房号目录（编辑房号后媒体不丢失）
    static func migrateHouseDirectory(from oldKey: String, to newKey: String) {
        guard oldKey != newKey, !oldKey.isEmpty, !newKey.isEmpty else { return }
        let oldDir = mediaDirectory().appendingPathComponent(oldKey, isDirectory: true)
        let newDir = mediaDirectory().appendingPathComponent(newKey, isDirectory: true)
        guard FileManager.default.fileExists(atPath: oldDir.path) else { return }
        try? FileManager.default.createDirectory(at: newDir, withIntermediateDirectories: true)
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: oldDir.path)) ?? []
        for name in contents {
            try? FileManager.default.moveItem(
                at: oldDir.appendingPathComponent(name),
                to: newDir.appendingPathComponent(name)
            )
        }
        try? FileManager.default.removeItem(at: oldDir)
    }
}
