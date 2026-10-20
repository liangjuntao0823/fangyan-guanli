import SwiftUI
import SwiftData
import AVKit
import Photos

struct HouseDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let house: House

    @State private var showEdit = false
    @State private var showShare = false
    @State private var showDeleteConfirm = false
    @State private var showStatusConfirm = false
    @State private var previewRoute: PhotoPreviewRoute? = nil
    @State private var shareItems: [Any] = []
    @State private var isSelecting = false          // 多选模式
    @State private var selectedMediaNames = Set<String>()   // 用唯一 fileName 标记选中
    @State private var saveTip: String?
    @State private var isSharing = false           // 生成分享卡片中
    @State private var shareError: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                mediaSection
                infoCard
                actionCard
            }
            .padding(16)
        }
        .background(AppTheme.background.ignoresSafeArea())
        .navigationTitle(house.displayRoomNo)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(\u{22}编辑\u{22}) { showEdit = true }
            }
        }
        .sheet(isPresented: $showEdit) {
            HouseEditView(house: house)
        }
        .sheet(isPresented: $showShare) {
            ShareSheet(items: shareItems)
                .presentationDetents([.medium, .large])
        }
        .confirmationDialog(\u{22}切换房源状态\u{22}, isPresented: $showStatusConfirm, titleVisibility: .visible) {
            if house.status == .available {
                Button(\u{22}标记为已租\u{22}, role: .destructive) { setStatus(.rented) }
            } else {
                Button(\u{22}标记为待租\u{22}) { setStatus(.available) }
            }
            Button(\u{22}取消\u{22}, role: .cancel) {}
        } message: {
            Text(house.status == .available ? \u{22}确认这套已租出？\u{22} : \u{22}确认这套恢复可带看？\u{22})
        }
        .confirmationDialog(\u{22}删除这套房源？\u{22}, isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button(\u{22}删除房源\u{22}, role: .destructive) { deleteHouse() }
            Button(\u{22}取消\u{22}, role: .cancel) {}
        } message: {
            Text(\u{22}将同时删除该房源的照片和视频，且无法恢复。\u{22})
        }
        .fullScreenCover(item: $previewRoute) { route in
            PhotoPreviewView(photos: house.photos, startIndex: route.index, roomKey: house.mediaRoomKey)
        }
        .overlay {
            if isSharing {
                ZStack {
                    Color.black.opacity(0.35).ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView()
                            .tint(.white)
                        Text(\u{22}正在生成分享卡片，上传照片和视频…\u{22})
                            .font(.footnote)
                            .foregroundColor(.white)
                    }
                    .padding(20)
                    .background(Color.black.opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }
        }
        .alert(\u{22}无法分享\u{22}, isPresented: Binding(
            get: { shareError != nil },
            set: { if !$0 { shareError = nil } }
        )) {
            Button(\u{22}好\u{22}, role: .cancel) {}
        } message: {
            Text(shareError ?? \u{22}\u{22})
        }
    }

    // MARK: - 媒体预览

    private var mediaSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label {
                    Text(\u{22}实拍照片与视频\u{22})
                        .font(.headline)
                } icon: {
                    Image(systemName: \u{22}camera.fill\u{22})
                        .foregroundColor(AppTheme.primary)
                }
                Spacer()
                if house.hasPhoto || house.hasVideo {
                    if isSelecting {
                        // 多选模式：取消按钮（与「多选」按钮同款品牌色胶囊）
                        Button {
                            exitSelecting()
                        } label: {
                            Label(\u{22}取消\u{22}, systemImage: \u{22}xmark\u{22})
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
                        } label: {
                            Label(\u{22}多选\u{22}, systemImage: \u{22}checkmark.circle\u{22})
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

            if house.photos.isEmpty && house.videos.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: \u{22}photo.on.rectangle.angled\u{22})
                        .foregroundColor(.secondary)
                    Text(\u{22}暂无照片和视频，点「编辑」添加\u{22})
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                if !house.photos.isEmpty {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                        // 用唯一 fileName 作标识（MediaItem.id 在 SwiftData 新对象上可能相同）
                        ForEach(Array(house.photos.enumerated()), id: \.element.fileName) { index, media in
                            // 固定正方形格子，内容缩放裁切填满，横屏照片也不会溢出重叠
                            Color.clear
                                .aspectRatio(1, contentMode: .fit)
                                .overlay(
                                    MediaThumbView(media: media, roomKey: house.mediaRoomKey)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .contentShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(alignment: .topLeading) {
                                    if isSelecting {
                                        Image(systemName: selectedMediaNames.contains(media.fileName) ? \u{22}checkmark.circle.fill\u{22} : \u{22}circle\u{22})
                                            .font(.system(size: 20))
                                            .foregroundColor(.white)
                                            .shadow(radius: 2)
                                            .padding(5)
                                    }
                                }
                                .onTapGesture {
                                    if isSelecting {
                                        toggleSelect(media)
                                    } else {
                                        previewRoute = PhotoPreviewRoute(index: index)
                                    }
                                }
                        }
                    }
                }

                if !house.videos.isEmpty {
                    ForEach(house.videos, id: \.fileName) { media in
                        if isSelecting {
                            // 多选模式下视频显示为缩略图，点击选中
                            Color.clear
                                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                                .overlay(
                                    MediaThumbView(media: media, roomKey: house.mediaRoomKey)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .contentShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(alignment: .topLeading) {
                                    Image(systemName: selectedMediaNames.contains(media.fileName) ? \u{22}checkmark.circle.fill\u{22} : \u{22}circle\u{22})
                                        .font(.system(size: 20))
                                        .foregroundColor(.white)
                                        .shadow(radius: 2)
                                        .padding(5)
                                }
                                .onTapGesture {
                                    toggleSelect(media)
                                }
                        } else {
                            // 视频条目：缩略图 + 播放三角，点击全屏播放
                            HouseDetailVideoItem(media: media, roomKey: house.mediaRoomKey)
                                .frame(height: 200)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }

                // 多选模式：底部保存按钮
                if isSelecting {
                    Button {
                        saveSelectedToAlbum()
                    } label: {
                        Label(selectedMediaNames.isEmpty ? \u{22}请选择要保存的照片或视频\u{22} : \u{22}保存到相册（\(selectedMediaNames.count)）\u{22}, systemImage: \u{22}square.and.arrow.down\u{22})
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.primary)
                    .disabled(selectedMediaNames.isEmpty)
                }
            }
        }
        .padding(14)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .alert(\u{22}保存到相册\u{22}, isPresented: Binding(
            get: { saveTip != nil },
            set: { if !$0 { saveTip = nil } }
        )) {
            Button(\u{22}好\u{22}, role: .cancel) {}
        } message: {
            Text(saveTip ?? \u{22}\u{22})
        }
    }

    // MARK: - 多选 / 保存到相册

    private func toggleSelect(_ media: MediaItem) {
        if selectedMediaNames.contains(media.fileName) {
            selectedMediaNames.remove(media.fileName)
        } else {
            selectedMediaNames.insert(media.fileName)
        }
    }

    private func exitSelecting() {
        isSelecting = false
        selectedMediaNames.removeAll()
    }

    private func saveSelectedToAlbum() {
        let selected = house.mediaItems.filter { selectedMediaNames.contains($0.fileName) }
        guard !selected.isEmpty else { return }

        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            switch status {
            case .authorized, .limited:
                PHPhotoLibrary.shared().performChanges {
                    for media in selected {
                        let url = MediaStore.url(for: media.fileName, roomKey: house.mediaRoomKey)
                        if media.kind == \u{22}image\u{22},
                           let image = UIImage(contentsOfFile: url.path) {
                            PHAssetChangeRequest.creationRequestForAsset(from: image)
                        } else if media.kind == \u{22}video\u{22},
                                  FileManager.default.fileExists(atPath: url.path) {
                            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
                        }
                    }
                } completionHandler: { success, error in
                    DispatchQueue.main.async {
                        if success {
                            saveTip = \u{22}已保存 \(selected.count) 个到相册\u{22}
                            exitSelecting()
                        } else {
                            saveTip = \u{22}保存失败：\(error?.localizedDescription ?? \u{22}未知错误\u{22})\u{22}
                        }
                    }
                }
            default:
                DispatchQueue.main.async {
                    saveTip = \u{22}没有相册写入权限，请在 设置 → 隐私与安全 → 照片 中允许\u{22}
                }
            }
        }
    }

    // MARK: - 房源信息

    private var infoCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(house.displayRoomNo)
                        .font(.title2.weight(.bold))
                        .foregroundColor(AppTheme.primary)
                    Text(\u{22}\(house.towerLabel) · \(house.layout.isEmpty ? \u{22}户型未填\u{22} : house.layout)\u{22})
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
                StatusBadge(status: house.status)
            }
            .padding(.bottom, 12)

            Divider()

            infoRow(icon: \u{22}person.fill\u{22}, title: \u{22}房东\u{22}, value: house.landlord.isEmpty ? \u{22}—\u{22} : house.landlord)
            infoRow(icon: \u{22}yensign\u{22}, title: \u{22}价格\u{22}, value: house.priceText)
            infoRow(icon: \u{22}key.fill\u{22}, title: \u{22}密码\u{22}, value: house.password.isEmpty ? \u{22}—\u{22} : house.password)
            infoRow(icon: \u{22}text.alignleft\u{22}, title: \u{22}备注\u{22}, value: house.remark.isEmpty ? \u{22}—\u{22} : house.remark)
        }
        .padding(14)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func infoRow(icon: String, title: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundColor(AppTheme.primary)
                .frame(width: 22)
            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(width: 40, alignment: .leading)
            Text(value)
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 9)
    }

    // MARK: - 操作区（三个按钮上下继续缩窄）

    private var actionCard: some View {
        VStack(spacing: 8) {
            Button {
                showStatusConfirm = true
            } label: {
                Label {
                    Text(house.status == .available ? \u{22}标记为已租\u{22} : \u{22}标记为待租\u{22})
                } icon: {
                    Image(systemName: house.status == .available ? \u{22}checkmark.circle\u{22} : \u{22}arrow.uturn.backward.circle\u{22})
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .tint(house.status == .available ? Color(red: 0.24, green: 0.58, blue: 0.34) : Color(red: 0.47, green: 0.49, blue: 0.55))

            Button {
                shareHouseCard()
            } label: {
                Label(\u{22}分享\u{22}, systemImage: \u{22}square.and.arrow.up\u{22})
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.bordered)

            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                Label(\u{22}删除房源\u{22}, systemImage: \u{22}trash\u{22})
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.bordered)
        }
        .padding(14)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - 操作

    private func setStatus(_ newStatus: HouseStatus) {
        house.status = newStatus
        house.updatedAt = Date()
        try? modelContext.save()
    }

    private func deleteHouse() {
        MediaStore.deleteAll(files: house.mediaItems.map(\.fileName), roomKey: house.mediaRoomKey)
        modelContext.delete(house)
        try? modelContext.save()
        dismiss()
    }

    /// 分享：生成 H5 卡片链接（上传照片视频到腾讯云 COS），系统分享面板发出链接
    private func shareHouseCard() {
        guard let config = CosConfig.load(), config.isValid else {
            shareError = \u{22}请先在首页左上角「设置」里填写云存储配置（腾讯云 COS），再分享卡片链接\u{22}
            return
        }
        isSharing = true
        Task {
            do {
                let url = try await CosUploader.shareCard(for: house, config: config)
                await MainActor.run {
                    isSharing = false
                    shareItems = [url]
                    showShare = true
                }
            } catch {
                await MainActor.run {
                    isSharing = false
                    shareError = error.localizedDescription
                }
            }
        }
    }
}

// MARK: - 照片大图预览路由

struct PhotoPreviewRoute: Identifiable {
    let id = UUID()
    let index: Int
}

// MARK: - 照片大图预览

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
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            TabView(selection: $currentIndex) {
                ForEach(Array(photos.enumerated()), id: \.element.fileName) { index, media in
                    if let image = UIImage(contentsOfFile: MediaStore.url(for: media.fileName, roomKey: roomKey).path) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .tag(index)
                            // 长按弹出菜单：保存到相册（和微信一致）
                            .contextMenu {
                                Button {
                                    saveImageToAlbum(image)
                                } label: {
                                    Label(\u{22}保存到相册\u{22}, systemImage: \u{22}square.and.arrow.down\u{22})
                                }
                            }
                    }
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .automatic))

            Button {
                dismiss()
            } label: {
                Image(systemName: \u{22}xmark.circle.fill\u{22})
                    .font(.system(size: 30))
                    .foregroundColor(.white.opacity(0.85))
                    .padding(18)
            }
        }
        .statusBarHidden()
        .alert(\u{22}保存到相册\u{22}, isPresented: Binding(
            get: { saveMessage != nil },
            set: { if !$0 { saveMessage = nil } }
        )) {
            Button(\u{22}好\u{22}, role: .cancel) {}
        } message: {
            Text(saveMessage ?? \u{22}\u{22})
        }
    }

    /// 保存当前图片到系统相册（仅新增写入权限）
    private func saveImageToAlbum(_ image: UIImage) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            switch status {
            case .authorized, .limited:
                PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest.creationRequestForAsset(from: image)
                } completionHandler: { success, error in
                    DispatchQueue.main.async {
                        saveMessage = success
                            ? \u{22}已保存到相册\u{22}
                            : \u{22}保存失败：\(error?.localizedDescription ?? \u{22}未知错误\u{22})\u{22}
                    }
                }
            default:
                DispatchQueue.main.async {
                    saveMessage = \u{22}没有相册写入权限，请在 设置 → 隐私与安全 → 照片 中允许\u{22}
                }
            }
        }
    }
}
