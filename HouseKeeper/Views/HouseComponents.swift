import SwiftUI
import UIKit
import AVKit

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

// MARK: - 媒体缩略图

struct MediaThumbView: View {
    let media: MediaItem
    let roomKey: String

    var body: some View {
        if media.kind == "video" {
            ZStack {
                thumbImage
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 30))
                    .foregroundColor(.white)
                    .shadow(radius: 3)
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

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(house.displayRoomNo)
                        .font(.headline)
                        .foregroundColor(AppTheme.primary)
                    StatusBadge(status: house.status)
                    Spacer(minLength: 0)
                }

                Text(house.towerLabel)
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                if !house.layout.isEmpty {
                    Text(house.layout)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 6) {
                    Text(house.priceText)
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(AppTheme.accent)
                    if house.hasPhoto || house.hasVideo {
                        Image(systemName: "photo.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(house.hasPhoto && house.hasVideo ? "照片+视频" : (house.hasPhoto ? "有实拍图" : "有视频"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("无实拍图")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
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

    private var coverView: some View {
        Group {
            if let firstVideo = house.videos.first {
                ZStack {
                    MediaThumbView(media: firstVideo, roomKey: house.mediaRoomKey)
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.white)
                        .shadow(radius: 3)
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

// MARK: - 全屏视频播放器（卡片点封面播放用）

struct FullScreenVideoPlayer: View {
    let media: MediaItem
    let roomKey: String
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            if let player {
                VideoPlayer(player: player)
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
}

// MARK: - 系统分享面板（UIActivityViewController 封装，可分享到微信）

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - 空状态

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
        .padding(.vertical, 60)
    }
}
