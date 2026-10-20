import SwiftUI
import UIKit
import AVKit
import Photos

// MARK: - 主题色（沿用网页版配色方向：深墨蓝 + 暖白 + 琥珀）

enum AppTheme {
    /// 深墨蓝主色
    static let primary = Color(red: 0.20, green: 0.28, blue: 0.40)
    /// 暖白背景
    static let background = Color(red: 0.98, green: 0.96, blue: 0.93)
    /// 琥珀价格强调
    static let accent = Color(red: 0.87, green: 0.55, blue: 0.22)
}

// MARK: - 状态徽章

struct StatusBadge: View {
    let status: HouseStatus

    var body: some View {
        Text(status.label)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundColor(.white)
            .background(badgeColor)
            .clipShape(Capsule())
    }

    private var badgeColor: Color {
        switch status {
        case .available: return Color(red: 0.24, green: 0.58, blue: 0.34)
        case .rented: return Color(red: 0.47, green: 0.49, blue: 0.55)
        }
    }
}

// MARK: - 视频首帧缩略图（异步提取第一帧，避免灰色占位）

struct VideoThumbnailView: View {
    let url: URL
    @State private var thumbnail: UIImage?

    var body: some View {
        Group {
            if let thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Color.gray.opacity(0.2)
                    ProgressView()
                }
            }
        }
        .onAppear(perform: loadFirstFrame)
    }

    private func loadFirstFrame() {
        guard thumbnail == nil else { return }
        let asset = AVAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 640, height: 640)
        let time = CMTime(seconds: 0.1, preferredTimescale: 600)
        generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: time)]) { _, cgImage, _, _, _ in
            guard let cgImage else { return }
            DispatchQueue.main.async {
                thumbnail = UIImage(cgImage: cgImage)
            }
        }
    }
}

// MARK: - 媒体缩略图

struct MediaThumbView: View {
    let media: MediaItem
    let roomKey: String

    var body: some View {
        if media.kind == "video" {
            ZStack {
                VideoThumbnailView(url: MediaStore.url(for: media.fileName, roomKey: roomKey))
                // 播放三角：缩小 + 半透明，不遮挡画面
                Image(systemName: "play.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.white.opacity(0.72))
                    .shadow(radius: 2)
            }
        } else {
            thumbImage
        }
    }

    private var thumbImage: some View {
        Group {
            if let image = UIImage(contentsOfFile: MediaStore.url(for: media.fileName, roomKey: roomKey).path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Color.gray.opacity(0.2)
                    Image(systemName: "photo")
                        .foregroundColor(.gray)
                }
            }
        }
    }
}

// MARK: - 房源卡片
// 布局：左上封面 + 右侧信息
//  第一行：房号（加大加粗）+ 价格（加大加粗），状态徽章在右上角
//  第二行：户型 + 实拍图情况
//  第三行：密码
//  第四行：备注

struct HouseCardView: View {
    let house: House

    @State private var previewRoute: PhotoPreviewRoute? = nil
    @State private var playingVideo: MediaItem? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // 封面：有视频 → 视频缩略图 + 播放；无视频 → 首图，点击放大左右滑动浏览全部照片
            Button {
                openCover()
            } label: {
                coverView
            }
            .buttonStyle(.plain)
            .frame(width: 92, height: 76)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 3) {
                // 第一行：房号 + 价格（都加大加粗），状态徽章在右上角
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(house.displayRoomNo)
                        .font(.title3.weight(.bold))
                        .foregroundColor(.primary)
                    Text(house.priceText)
                        .font(.headline.weight(.bold))
                        .foregroundColor(AppTheme.accent)
                    Spacer(minLength: 0)
                    StatusBadge(status: house.status)
                }

                // 第二行：户型 + 实拍图情况
                HStack(spacing: 6) {
                    Text(house.layout.isEmpty ? "户型未填" : house.layout)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    if house.hasPhoto || house.hasVideo {
                        Image(systemName: "photo.fill")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(mediaSummary)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    } else {
                        Text("无实拍图")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }

                // 第三行：密码
                Text("密码：\(house.password.isEmpty ? "—" : house.password)")
                    .font(.footnote)
                    .foregroundColor(.secondary)

                // 第四行：备注
                Text("备注：\(house.remark.isEmpty ? "—" : house.remark)")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .padding(.vertical, 2)
        }
        .padding(10)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 3, x: 0, y: 1)
        .fullScreenCover(item: $previewRoute) { route in
            PhotoPreviewView(photos: house.photos, startIndex: route.index, roomKey: house.mediaRoomKey)
        }
        .fullScreenCover(item: $playingVideo) { media in
            FullScreenVideoPlayer(media: media, roomKey: house.mediaRoomKey)
        }
    }

    private var mediaSummary: String {
        if house.hasPhoto && house.hasVideo { return "照片+视频" }
        return house.hasPhoto ? "有实拍图" : "有视频"
    }

    private var coverView: some View {
        Group {
            if let firstVideo = house.videos.first {
                ZStack {
                    MediaThumbView(media: firstVideo, roomKey: house.mediaRoomKey)
                    // 播放三角：缩小 + 半透明，不遮挡画面
                    Image(systemName: "play.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.white.opacity(0.72))
                        .shadow(radius: 2)
                }
            } else if let first = house.photos.first {
                MediaThumbView(media: first, roomKey: house.mediaRoomKey)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(AppTheme.primary.opacity(0.08))
                    Image(systemName: "house.fill")
                        .font(.system(size: 26))
                        .foregroundColor(AppTheme.primary.opacity(0.35))
                }
            }
        }
    }

    /// 点封面：优先播放视频；没有视频则放大首图，可左右滑动浏览全部照片
    private func openCover() {
        if let firstVideo = house.videos.first {
            playingVideo = firstVideo
        } else if !house.photos.isEmpty {
            previewRoute = PhotoPreviewRoute(index: 0)
        }
    }
}

// MARK: - 可右滑卡片（手指向右滑动卡片，露出左侧「已租 / 删除」按钮）

struct SwipeableHouseCard: View {
    let house: House
    let onToggleStatus: () -> Void
    let onDelete: () -> Void

    @State private var offset: CGFloat = 0
    private let actionWidth: CGFloat = 78
    private var maxOffset: CGFloat { actionWidth * 2 }

    var body: some View {
        ZStack(alignment: .leading) {
            // 底层操作按钮（卡片向右滑开后露出）
            HStack(spacing: 0) {
                actionButton(
                    title: house.status == .available ? "已租" : "待租",
                    icon: house.status == .available ? "checkmark" : "arrow.uturn.backward",
                    color: Color(red: 0.24, green: 0.58, blue: 0.34),
                    action: onToggleStatus
                )
                actionButton(
                    title: "删除",
                    icon: "trash",
                    color: Color.red,
                    action: onDelete
                )
                Spacer(minLength: 0)
            }
            .frame(maxHeight: .infinity)

            HouseCardView(house: house)
                .offset(x: offset)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            if value.translation.width > 0 {
                                // 右滑：露出左侧操作按钮
                                offset = min(value.translation.width, maxOffset)
                            } else if offset > 0 {
                                // 左滑：收回卡片
                                offset = max(offset + value.translation.width, 0)
                            }
                        }
                        .onEnded { value in
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                offset = value.translation.width > actionWidth ? maxOffset : 0
                            }
                        }
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func actionButton(title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { offset = 0 }
            action()
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.body.weight(.semibold))
                Text(title)
                    .font(.footnote.weight(.semibold))
            }
            .foregroundColor(.white)
            .frame(width: actionWidth)
            .frame(maxHeight: .infinity)
            .background(color)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 详情页视频条目（缩略图 + 播放三角，点击全屏播放，播放界面长按可保存视频到相册）

struct HouseDetailVideoItem: View {
    let media: MediaItem
    let roomKey: String
    @State private var playing = false

    var body: some View {
        Button {
            playing = true
        } label: {
            MediaThumbView(media: media, roomKey: roomKey)
        }
        .buttonStyle(.plain)
        .fullScreenCover(isPresented: $playing) {
            FullScreenVideoPlayer(media: media, roomKey: roomKey)
        }
    }
}

// MARK: - 全屏视频播放器（卡片点封面播放用，长按保存视频到相册）

struct FullScreenVideoPlayer: View {
    let media: MediaItem
    let roomKey: String
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var saveMessage: String?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            if let player {
                VideoPlayer(player: player)
                    // 长按播放界面：保存视频到相册
                    .contextMenu {
                        Button {
                            saveVideoToAlbum()
                        } label: {
                            Label("保存到相册", systemImage: "square.and.arrow.down")
                        }
                    }
            }

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 30))
                    .foregroundColor(.white.opacity(0.85))
                    .padding(18)
            }
        }
        .statusBarHidden()
        .alert("保存到相册", isPresented: Binding(
            get: { saveMessage != nil },
            set: { if !$0 { saveMessage = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(saveMessage ?? "")
        }
        .onAppear {
            if player == nil {
                player = AVPlayer(url: MediaStore.url(for: media.fileName, roomKey: roomKey))
                player?.play()
            }
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }

    /// 保存当前视频到系统相册（仅新增写入权限）
    private func saveVideoToAlbum() {
        let url = MediaStore.url(for: media.fileName, roomKey: roomKey)
        guard FileManager.default.fileExists(atPath: url.path) else {
            saveMessage = "视频文件不存在，无法保存"
            return
        }
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            switch status {
            case .authorized, .limited:
                PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
                } completionHandler: { success, error in
                    DispatchQueue.main.async {
                        saveMessage = success
                            ? "已保存到相册"
                            : "保存失败：\(error?.localizedDescription ?? "未知错误")"
                    }
                }
            default:
                DispatchQueue.main.async {
                    saveMessage = "没有相册写入权限，请在 设置 → 隐私与安全 → 照片 中允许"
                }
            }
        }
    }
}

// MARK: - 系统分享面板（UIActivityViewController 封装，可分享到微信）

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - 空状态（占满剩余空间并垂直居中，避免筛选无匹配时内容下沉）

struct EmptyStateView: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 44))
                .foregroundColor(AppTheme.primary.opacity(0.4))
            Text(title)
                .font(.headline)
                .foregroundColor(.secondary)
            Text(subtitle)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 32)
    }
}
