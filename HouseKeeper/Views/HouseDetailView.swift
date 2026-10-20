import SwiftUI
import Photos

// MARK: - 房源详情

struct HouseDetailView: View {
    let house: House

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var showShare = false
    @State private var shareItems: [Any] = []
    @State private var showDeleteConfirm = false
    @State private var previewRoute: PhotoPreviewRoute?

    // 多选状态
    @State private var isSelecting = false
    @State private var selectedIDs = Set<UUID>()
    @State private var saveMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // 视频条目（缩略图 + 播放三角，点击全屏播放）
                if !house.videos.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label {
                            Text("视频")
                                .font(.headline)
                        } icon: {
                            Image(systemName: "video.fill")
                                .foregroundColor(AppTheme.primary)
                        }
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(house.videos) { media in
                                    HouseDetailVideoItem(media: media, roomKey: house.mediaRoomKey)
                                }
                            }
                        }
                    }
                }

                // 房源信息卡片
                infoCard

                // 操作按钮（标记已租 / 分享 / 删除房源，上下缩窄）
                actionCard

                // 实拍照片与视频（多选 / 取消胶囊按钮，长按单图也可保存）
                mediaSection
            }
            .padding(16)
        }
        .background(AppTheme.background.ignoresSafeArea())
        .navigationTitle(house.displayRoomNo)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("删除这套房源？", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("删除房源", role: .destructive) {
                deleteHouse()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将同时删除该房源的照片和视频，且无法恢复。")
        }
        .fullScreenCover(item: $previewRoute) { route in
            PhotoPreviewView(photos: house.photos, startIndex: route.index, roomKey: house.mediaRoomKey)
        }
        .onAppear { prepareShareItems() }
    }

    // MARK: - 媒体预览

    private var mediaSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label {
                    Text("实拍照片与视频")
                        .font(.headline)
                } icon: {
                    Image(systemName: "camera.fill")
                        .foregroundColor(AppTheme.primary)
                }
                Spacer()
                if house.hasPhoto || house.hasVideo {
                    if isSelecting {
                        // 多选模式：取消按钮（与「多选」同款胶囊样式）
                        Button {
                            exitSelecting()
                        } label: {
                            Label("取消", systemImage: "xmark")
                                .font(.subheadline.weight(.medium))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 5)
                                .background(AppTheme.primary)
                                .foregroundColor(.white)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    } else {
                        // 多选入口（胶囊形，大小随文字自适应）
                        Button {
                            isSelecting = true
                            selectedIDs = []
                        } label: {
                            Label("多选", systemImage: "checkmark.circle")
                                .font(.subheadline.weight(.medium))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 5)
                                .background(AppTheme.primary)
                                .foregroundColor(.white)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if isSelecting {
                HStack {
                    Text("已选 \(selectedIDs.count) 项")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button {
                        saveSelectedToAlbum()
                    } label: {
                        Text("保存到相册（\(selectedIDs.count)）")
                            .font(.footnote.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(AppTheme.primary)
                            .foregroundColor(.white)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedIDs.isEmpty)
                    .opacity(selectedIDs.isEmpty ? 0.4 : 1)
                }
            }

            if let msg = saveMessage {
                Text(msg)
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }

            // 媒体网格
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(house.mediaItems) { media in
                    mediaCell(media)
                }
            }
        }
        .padding(14)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func mediaCell(_ media: MediaItem) -> some View {
        ZStack(alignment: .topLeading) {
            Button {
                if isSelecting {
                    toggleSelect(media)
                } else if media.kind == "image" {
                    if let idx = house.photos.firstIndex(where: { $0.id == media.id }) {
                        previewRoute = PhotoPreviewRoute(index: idx)
                    }
                }
                // 视频在详情页统一走 HouseDetailVideoItem，网格内不重复播放
            } label: {
                MediaThumbView(media: media, roomKey: house.mediaRoomKey)
            }
            .buttonStyle(.plain)

            if isSelecting {
                Image(systemName: selectedIDs.contains(media.id) ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundColor(.white)
                    .padding(4)
                    .shadow(radius: 1)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func toggleSelect(_ media: MediaItem) {
        if selectedIDs.contains(media.id) {
            selectedIDs.remove(media.id)
        } else {
            selectedIDs.insert(media.id)
        }
    }

    private func exitSelecting() {
        isSelecting = false
        selectedIDs = []
    }

    private func saveSelectedToAlbum() {
        let targets = house.mediaItems.filter { selectedIDs.contains($0.id) }
        guard !targets.isEmpty else { return }
        var saved = 0
        let group = DispatchGroup()
        for media in targets {
            group.enter()
            let url = MediaStore.url(for: media.fileName, roomKey: house.mediaRoomKey)
            guard FileManager.default.fileExists(atPath: url.path) else {
                group.leave()
                continue
            }
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                switch status {
                case .authorized, .limited:
                    PHPhotoLibrary.shared().performChanges {
                        if media.kind == "image" {
                            PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: url)
                        } else {
                            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
                        }
                    } completionHandler: { success, _ in
                        if success { saved += 1 }
                        group.leave()
                    }
                default:
                    group.leave()
                }
            }
        }
        group.notify(queue: .main) {
            saveMessage = "已保存 \(saved) 项到相册"
            exitSelecting()
        }
    }

    // MARK: - 房源信息卡片

    private var infoCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(house.displayRoomNo)
                    .font(.title.bold())
                Spacer()
                Text(house.status.label)
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(house.status == .available ? Color.green.opacity(0.15) : Color.orange.opacity(0.15))
                    .foregroundColor(house.status == .available ? Color(red: 0.1, green: 0.55, blue: 0.25) : Color.orange)
                    .clipShape(Capsule())
            }

            Divider()

            infoRow(label: "座号", value: house.towerLabel)
            infoRow(label: "房东", value: house.landlord.isEmpty ? "—" : house.landlord)
            infoRow(label: "户型", value: house.layout.isEmpty ? "—" : house.layout)
            infoRow(label: "价格", value: house.priceText)
            infoRow(label: "密码", value: house.password.isEmpty ? "—" : house.password)
            infoRow(label: "备注", value: house.remark.isEmpty ? "—" : house.remark)
        }
        .padding(14)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(width: 52, alignment: .leading)
            Text(value)
                .font(.subheadline)
                .foregroundColor(.primary)
            Spacer()
        }
        .padding(.vertical, 2)
    }

    // MARK: - 操作按钮（上下缩窄）

    private var actionCard: some View {
        VStack(spacing: 8) {
            Button {
                toggleStatus()
            } label: {
                Label(house.status == .available ? "标记为已租" : "标记为待租", systemImage: house.status == .available ? "checkmark" : "arrow.uturn.backward")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .background(Color(red: 0.24, green: 0.58, blue: 0.34).opacity(0.9))
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)

            Button {
                prepareShareItems()
                showShare = true
            } label: {
                Label("分享", systemImage: "square.and.arrow.up")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .background(AppTheme.primary)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)

            Button {
                showDeleteConfirm = true
            } label: {
                Label("删除房源", systemImage: "trash")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .background(Color.red.opacity(0.9))
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - 操作

    private func toggleStatus() {
        house.status = house.status == .available ? .rented : .available
        house.updatedAt = Date()
        try? modelContext.save()
    }

    private func deleteHouse() {
        MediaStore.deleteAll(files: house.mediaItems.map(\.fileName), roomKey: house.mediaRoomKey)
        modelContext.delete(house)
        try? modelContext.save()
        dismiss()
    }

    // MARK: - 分享（完整房源信息 + 照片 + 视频）

    private func prepareShareItems() {
        var items: [Any] = [house.fullShareText]
        for media in house.mediaItems {
            let url = MediaStore.url(for: media.fileName, roomKey: house.mediaRoomKey)
            if FileManager.default.fileExists(atPath: url.path) {
                items.append(url)
            }
        }
        shareItems = items
    }

    private func share() {
        let controller = UIActivityViewController(activityItems: shareItems, applicationActivities: nil)
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.windows.first?.rootViewController {
            root.present(controller, animated: true)
        }
    }
}
