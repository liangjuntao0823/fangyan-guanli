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

// MARK: - 视频首帧缩略图（异步提取第一帧，避免灰色占位；fit=true 时完整显示不裁切）

struct VideoThumbnailView: View {
    let url: URL
    var fit: Bool = false
    @State private var thumbnail: UIImage?

    var body: some View {
        Group {
            if let thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        generator.maximumSize = CGSize(width: 1280, height: 1280)
        let time = CMTime(seconds: 0.1, preferredTimescale: 600)
        generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: time)]) { _, cgImage, _, _, _ in
            guard let cgImage else { return }
            DispatchQueue.main.async {
                thumbnail = UIImage(cgImage: cgImage)
            }
        }
    }
}

// MARK: - 媒体缩略图（fit=true 用于详情页视频条目，完整显示竖版视频，不再裁切成横图）

struct MediaThumbView: View {
    let media: MediaItem
    let roomKey: String
    var fit: Bool = false

    var body: some View {
        if media.kind == "video" {
            ZStack {
                VideoThumbnailView(url: MediaStore.url(for: media.fileName, roomKey: roomKey), fit: fit)
                // 播放三角：缩小 + 半透明，不遮挡画面
                Image(systemName: "play.fill")
                    .font(.system(size: fit ? 0 : 20))
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

// MARK: - 可左滑卡片（手指向左滑动卡片，露出右侧「编辑 / 已租 / 删除」按钮）
// v1.11：轻点/轻扫不再误触发左滑（minimumDistance 24 + 只认横向 + 滑过半程才展开 + 点击已展开卡片先收回）

struct SwipeableHouseCard: View {
    let house: House
    let onToggleStatus: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var offset: CGFloat = 0
    @State private var isDragging = false
    @State private var dragStartOffset: CGFloat = 0
    private let actionWidth: CGFloat = 64
    private var maxOffset: CGFloat { actionWidth * 3 }

    var body: some View {
        ZStack(alignment: .trailing) {
            // 底层操作按钮（卡片向左滑开后露出）：编辑 | 已租/待租 | 删除
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                actionButton(
                    title: "编辑",
                    icon: "pencil",
                    color: AppTheme.primary,
                    action: onEdit
                )
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
            }
            .frame(maxHeight: .infinity)

            HouseCardView(house: house)
                .offset(x: offset)
                .contentShape(Rectangle())
                // 已展开时轻点卡片任意区域先收回（不干扰按钮；未展开时不影响内部封面按钮点击）
                .simultaneousGesture(
                    TapGesture().onEnded {
                        if offset != 0 {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { offset = 0 }
                        }
                    }
                )
                .gesture(
                    DragGesture(minimumDistance: 24)
                        .onChanged { value in
                            // 只认横向拖动（横向位移大于纵向才处理），纵向交给外层滚动
                            guard abs(value.translation.width) > abs(value.translation.height) else { return }
                            if !isDragging {
                                isDragging = true
                                dragStartOffset = offset
                            }
                            let proposed = dragStartOffset + value.translation.width
                            offset = min(max(proposed, -maxOffset), 0)
                        }
                        .onEnded { _ in
                            isDragging = false
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                // 滑过半程才展开，否则弹回，避免轻微滑动就露出红边
                                offset = offset <= -actionWidth * 1.5 ? -maxOffset : 0
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

// MARK: - 详情页视频条目（按视频原始比例完整显示首帧，竖版视频不再被裁成横图；播放界面长按可保存视频）

struct HouseDetailVideoItem: View {
    let media: MediaItem
    let roomKey: String
    @State private var playing = false
    @State private var isPortrait = false

    var body: some View {
        Button {
            playing = true
        } label: {
            ZStack {
                Color.black.opacity(0.07)
                MediaThumbView(media: media, roomKey: roomKey, fit: true)
                // 大播放三角：一眼可辨这是视频，不是图片
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 36))
                    .foregroundColor(.white.opacity(0.92))
                    .shadow(radius: 3)
            }
            .frame(maxWidth: .infinity)
            .frame(height: isPortrait ? 300 : 200)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .fullScreenCover(isPresented: $playing) {
            FullScreenVideoPlayer(media: media, roomKey: roomKey)
        }
        .onAppear(perform: detectOrientation)
    }

    /// 读取视频原始宽高比：竖版视频用更高容器，完整显示不裁切
    private func detectOrientation() {
        let url = MediaStore.url(for: media.fileName, roomKey: roomKey)
        let asset = AVAsset(url: url)
        guard let track = asset.tracks(withMediaType: .video).first else { return }
        let size = track.naturalSize.applying(track.preferredTransform)
        if abs(size.height) > abs(size.width) {
            isPortrait = true
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
        // 空内容保护：UIActivityViewController 不接受空 activityItems，否则直接崩溃
        let safeItems = items.isEmpty ? [""] : items
        let controller = UIActivityViewController(activityItems: safeItems, applicationActivities: nil)
        // iPad 上必须指定 popover 锚点，否则系统直接崩溃；iPhone 自动跳过
        if UIDevice.current.userInterfaceIdiom == .pad,
           let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.windows.first?.rootViewController {
            controller.popoverPresentationController?.sourceView = root.view
            controller.popoverPresentationController?.sourceRect = CGRect(x: root.view.bounds.midX, y: root.view.bounds.midY, width: 0, height: 0)
            controller.popoverPresentationController?.permittedArrowDirections = []
        }
        return controller
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
