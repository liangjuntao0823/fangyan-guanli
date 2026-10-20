import SwiftUI
import Photos

// MARK: - 主题

enum AppTheme {
    static let primary = Color(red: 0.22, green: 0.44, blue: 0.85)
    static let background = Color(red: 0.96, green: 0.96, blue: 0.97)
}

// MARK: - 首页房源卡片（v1.6 改版布局）
// 徽章在右上角；第一行 房号+价格（加大加粗）；第二行 户型+实拍情况；第三行 密码；第四行 备注

struct HouseCardView: View {
    let house: House

    @State private var previewRoute: PhotoPreviewRoute?
    @State private var playingVideo: MediaItem?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // 左侧：封面（视频优先，带半透明播放三角；无视频显示首图；无媒体显示占位）
            Button(action: openCover) {
                coverView
                    .frame(width: 96, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .top) {
                    // 第一行：房号 + 价格（加大加粗）
                    Text(house.displayRoomNo)
                        .font(.title3.weight(.bold))
                        .foregroundColor(.primary)
                    Spacer()
                    // 右上角：待租 / 已租徽章
                    Text(house.status.label)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(house.status == .available ? Color.green.opacity(0.15) : Color.orange.opacity(0.15))
                        .foregroundColor(house.status == .available ? Color(red: 0.1, green: 0.55, blue: 0.25) : Color.orange)
                        .clipShape(Capsule())
                }

                Text("\(house.price)元/月")
                    .font(.headline.weight(.bold))
                    .foregroundColor(Color(red: 0.85, green: 0.55, blue: 0.1))

                // 第二行：户型 + 实拍图情况
                Text("\(house.layout.isEmpty ? "未填户型" : house.layout) · \(mediaSummary)")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .lineLimit(1)

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

// MARK: - 可右滑卡片（手指向右滑动卡片，露出左侧「编辑 / 已租 / 删除」按钮）

struct SwipeableHouseCard: View {
    let house: House
    let onTap: () -> Void
    let onEdit: () -> Void
    let onToggleStatus: () -> Void
    let onDelete: () -> Void

    @State private var offset: CGFloat = 0
    private let actionWidth: CGFloat = 62
    private var maxOffset: CGFloat { actionWidth * 3 }

    var body: some View {
        ZStack(alignment: .leading) {
            // 底层操作按钮（卡片向右滑开后露出）
            HStack(spacing: 0) {
                actionButton(
                    title: "编辑",
                    icon: "pencil",
                    color: Color(red: 0.36, green: 0.42, blue: 0.55),
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
                .onTapGesture {
                    if offset > 0 {
                        // 已滑开时点卡片 = 收回
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { offset = 0 }
                    } else {
                        onTap()
                    }
                }
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
            ZStack {
                MediaThumbView(media: media, roomKey: roomKey)
                Image(systemName: "play.fill")
                    .font(.system(size: 26))
                    .foregroundColor(.white.opacity(0.85))
                    .shadow(radius: 3)
            }
            .frame(width: 110, height: 110)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .fullScreenCover(isPresented: $playing) {
            FullScreenVideoPlayer(media: media, roomKey: roomKey)
        }
    }
}

// MARK: - 全屏视频播放器（长按视频可保存到相册）

struct FullScreenVideoPlayer: View {
    let media: MediaItem
    let roomKey: String

    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var saveMessage: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
            } else {
                ProgressView()
                    .tint(.white)
            }

            // 关闭按钮
            VStack {
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 30))
                            .foregroundColor(.white.opacity(0.85))
                    }
                    .padding(12)
                }
                Spacer()
            }

            // 长按保存提示
            if let msg = saveMessage {
                Text(msg)
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.75))
                    .foregroundColor(.white)
                    .clipShape(Capsule())
                    .padding(.bottom, 60)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
        .onAppear {
            let url = MediaStore.url(for: media.fileName, roomKey: roomKey)
            player = AVPlayer(url: url)
            player?.play()
        }
        .onDisappear {
            player?.pause()
        }
        .onLongPressGesture {
            saveVideoToAlbum()
        }
    }

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

// MARK: - 媒体缩略图（照片 / 视频首帧，方形裁切填满）

struct MediaThumbView: View {
    let media: MediaItem
    let roomKey: String
    @State private var image: UIImage?
    @State private var videoFrame: UIImage?

    var body: some View {
        Group {
            if media.kind == "image" {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    placeholder
                }
            } else {
                if let frame = videoFrame {
                    Image(uiImage: frame)
                        .resizable()
                        .scaledToFill()
                } else {
                    placeholder
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .onAppear { load() }
    }

    private var placeholder: some View {
        ZStack {
            Color(red: 0.9, green: 0.92, blue: 0.94)
            Image(systemName: media.kind == "image" ? "photo" : "video")
                .foregroundColor(.gray)
        }
    }

    private func load() {
        let url = MediaStore.url(for: media.fileName, roomKey: roomKey)
        if media.kind == "image" {
            image = UIImage(contentsOfFile: url.path)
        } else {
            // 视频首帧异步提取（AVAssetImageGenerator）
            let asset = AVAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 600, height: 600)
            generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: .zero)]) { _, cgImage, _, _, _ in
                if let cgImage {
                    DispatchQueue.main.async {
                        self.videoFrame = UIImage(cgImage: cgImage)
                    }
                }
            }
        }
    }
}

// MARK: - 图片全屏预览（左右滑动浏览全部照片；长按图片保存到相册，和微信一致）

struct PhotoPreviewRoute: Identifiable, Hashable {
    let index: Int
    var id: Int { index }
}

struct PhotoPreviewView: View {
    let photos: [MediaItem]
    let startIndex: Int
    let roomKey: String

    @Environment(\.dismiss) private var dismiss
    @State private var currentIndex: Int
    @State private var saveMessage: String?

    init(photos: [MediaItem], startIndex: Int, roomKey: String) {
        self.photos = photos
        self.startIndex = startIndex
        self.roomKey = roomKey
        _currentIndex = State(initialValue: startIndex)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TabView(selection: $currentIndex) {
                ForEach(Array(photos.enumerated()), id: \.element.id) { index, media in
                    ZoomablePhotoView(media: media, roomKey: roomKey, onSave: {
                        saveToAlbum(media)
                    })
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))

            // 关闭按钮
            VStack {
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 30))
                            .foregroundColor(.white.opacity(0.85))
                    }
                    .padding(12)
                }
                Spacer()
            }

            if photos.count > 1 {
                VStack {
                    Spacer()
                    Text("\(currentIndex + 1) / \(photos.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.5))
                        .clipShape(Capsule())
                        .padding(.bottom, 24)
                }
            }

            if let msg = saveMessage {
                Text(msg)
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.75))
                    .foregroundColor(.white)
                    .clipShape(Capsule())
                    .padding(.bottom, 80)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
    }

    private func saveToAlbum(_ media: MediaItem) {
        let url = MediaStore.url(for: media.fileName, roomKey: roomKey)
        guard FileManager.default.fileExists(atPath: url.path) else {
            saveMessage = "图片文件不存在，无法保存"
            return
        }
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            switch status {
            case .authorized, .limited:
                PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: url)
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

// MARK: - 可缩放图片（双击 / 双指缩放，长按弹出保存）

struct ZoomablePhotoView: View {
    let media: MediaItem
    let roomKey: String
    let onSave: () -> Void

    @State private var image: UIImage?
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var showSave = false

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(scale)
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                scale = lastScale * value
                            }
                            .onEnded { _ in
                                lastScale = scale
                            }
                    )
                    .onTapGesture(count: 2) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            scale = scale > 1 ? 1 : 2
                            lastScale = scale
                        }
                    }
                    .onLongPressGesture(minimumDuration: 0.5, pressing: { pressing in
                        if pressing { showSave = true }
                    }, perform: {})
            } else {
                ProgressView()
                    .tint(.white)
            }
        }
        .onAppear {
            let url = MediaStore.url(for: media.fileName, roomKey: roomKey)
            image = UIImage(contentsOfFile: url.path)
        }
        .confirmationDialog("保存到相册？", isPresented: $showSave, titleVisibility: .visible) {
            Button("保存到相册") { onSave() }
            Button("取消", role: .cancel) {}
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

// MARK: - 空状态（紧贴筛选栏下方，不再大幅下沉）

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
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
    }
}
