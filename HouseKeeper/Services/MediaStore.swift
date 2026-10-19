import Foundation

/// 房源照片 / 视频文件管理：统一存到 App 的 Documents/Media 目录
/// 数据库里只保存文件名，文件本体在磁盘，避免 SwiftData 存储膨胀
enum MediaStore {
    static let mediaDirectoryName = "Media"

    static func mediaDirectory() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent(mediaDirectoryName, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// 保存二进制数据（照片转 JPEG 后调用），返回文件名
    static func save(data: Data, ext: String) -> String {
        let fileName = "\(UUID().uuidString).\(ext)"
        let url = mediaDirectory().appendingPathComponent(fileName)
        try? data.write(to: url)
        return fileName
    }

    /// 保存临时文件（相册选中的视频等），拷贝到 App 目录，返回文件名
    static func saveFile(from source: URL) -> String {
        let ext = source.pathExtension.isEmpty ? "mov" : source.pathExtension
        let fileName = "\(UUID().uuidString).\(ext)"
        let target = mediaDirectory().appendingPathComponent(fileName)
        try? FileManager.default.copyItem(at: source, to: target)
        return fileName
    }

    /// 获取文件完整路径
    static func url(for fileName: String) -> URL {
        mediaDirectory().appendingPathComponent(fileName)
    }

    /// 删除文件（删除房源 / 删除单条媒体时调用）
    static func delete(fileName: String) {
        let url = url(for: fileName)
        try? FileManager.default.removeItem(at: url)
    }

    /// 删除房源关联的全部媒体文件
    static func deleteAll(files: [String]) {
        for fileName in files {
            delete(fileName: fileName)
        }
    }
}
