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
                Button("编辑") { showEdit = true }
            }
        }
        .sheet(isPresented: $showEdit) {
            HouseEditView(house: house)
        }
        .sheet(isPresented: $showShare) {
            ShareSheet(items: shareItems)
                .presentationDetents([.medium, .large])
        }
        .confirmationDialog("切换房源状态", isPresented: $showStatusConfirm, titleVisibility: .visible) {
            if house.status == .available {
                Button("标记为已租", role: .destructive) { setStatus(.rented) }
            } else {
                Button("标记为待租") { setStatus(.available) }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text(house.status == .available ? "确认这套已租出？" : "确认这套恢复可带看？")
        }
        .confirmationDialog("删除这套房源？", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("删除房源", role: .destructive) { deleteHouse() }
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
                        // 多选模式下：取消按钮（紧凑高度）
                        Button {
                            exitSelecting()
                        } label: {
                            Label("取消", systemImage: "xmark")
                                .font(.subheadline.weight(.medium))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 2)
                        }
                        .buttonStyle(.bordered)
                    } else {
                        // 多选入口：按钮状（上下缩窄，不过高）
                        Button {
                            isSelecting = true
                        } label: {
                            Label("多选", systemImage: "checkmark.circle")
                                .font(.subheadline.weight(.medium))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 2)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }

            if house.photos.isEmpty && house.videos.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .foregroundColor(.secondary)
                    Text("暂无照片和视频，点「编辑」添加")
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
                                        Image(systemName: selectedMediaNames.contains(media.fileName) ? "checkmark.circle.fill" : "circle")
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
                                    Image(systemName: selectedMediaNames.contains(media.fileName) ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 20))
                                        .foregroundColor(.white)
                                        .shadow(radius: 2)
                                        .padding(5)
                                }
                                .onTapGesture {
                                    toggleSelect(media)
                                }
                        } else {
                            HouseVideoPlayer(media: media, roomKey: house.mediaRoomKey)
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
                        Label(selectedMediaNames.isEmpty ? "请选择要保存的照片或视频" : "保存到相册（\(selectedMediaNames.count)）", systemImage: "square.and.arrow.down")
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
        .alert("保存到相册", isPresented: Binding(
            get: { saveTip != nil },
            set: { if !$0 { saveTip = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(saveTip ?? "")
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
                        if media.kind == "image",
                           let image = UIImage(contentsOfFile: url.path) {
                            PHAssetChangeRequest.creationRequestForAsset(from: image)
                        } else if media.kind == "video",
                                  FileManager.default.fileExists(atPath: url.path) {
                            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
                        }
                    }
                } completionHandler: { success, error in
                    DispatchQueue.main.async {
                        if success {
                            saveTip = "已保存 \(selected.count) 个到相册"
                            exitSelecting()
                        } else {
                            saveTip = "保存失败：\(error?.localizedDescription ?? "未知错误")"
                        }
                    }
                }
            default:
                DispatchQueue.main.async {
                    saveTip = "没有相册写入权限，请在 设置 → 隐私与安全 → 照片 中允许"
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
                    Text("\(house.towerLabel) · \(house.layout.isEmpty ? "户型未填" : house.layout)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
                StatusBadge(status: house.status)
            }
            .padding(.bottom, 12)

            Divider()

            infoRow(icon: "person.fill", title: "房东", value: house.landlord.isEmpty ? "—" : house.landlord)
            infoRow(icon: "yensign", title: "价格", value: house.priceText)
            infoRow(icon: "key.fill", title: "密码", value: house.password.isEmpty ? "—" : house.password)
            infoRow(icon: "text.alignleft", title: "备注", value: house.remark.isEmpty ? "—" : house.remark)
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

    // MARK: - 操作区

    private var actionCard: some View {
        VStack(spacing: 8) {
            Button {
                showStatusConfirm = true
            } label: {
                Label {
                    Text(house.status == .available ? "标记为已租" : "标记为待租")
                } icon: {
                    Image(systemName: house.status == .available ? "checkmark.circle" : "arrow.uturn.backward.circle")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(house.status == .available ? Color(red: 0.24, green: 0.58, blue: 0.34) : Color(red: 0.47, green: 0.49, blue: 0.55))

            Button {
                prepareShareItems()
                showShare = true
            } label: {
                Label("分享", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.bordered)

            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                Label("删除房源", systemImage: "trash")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
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

    /// 分享内容：完整文案 + 实拍照片 + 视频文件（微信可接收）
    private func prepareShareItems() {
        var items: [Any] = [house.fullShareText]
        items += house.photos.compactMap { media in
            UIImage(contentsOfFile: MediaStore.url(for: media.fileName, roomKey: house.mediaRoomKey).path)
        }
        items += house.videos.map { media in
            MediaStore.url(for: media.fileName, roomKey: house.mediaRoomKey)
        }
        shareItems = items
    }
}

// MARK: - 照片大图预览路由

struct PhotoPreviewRoute: Identifiable {
    let id = UUID()
    let index: Int
}

// MARK: - 视频播放器（持有 player，避免视图重建时频繁创建；长按可保存视频到相册）

struct HouseVideoPlayer: View {
    let media: MediaItem
    let roomKey: String
    @State private var player: AVPlayer?
    @State private var saveMessage: String?

    var body: some View {
        VideoPlayer(player: player)
            // 长按播放界面：保存视频到相册（和微信一致）
            .contextMenu {
                Button {
                    saveVideoToAlbum()
                } label: {
                    Label("保存到相册", systemImage: "square.and.arrow.down")
                }
            }
            .onAppear {
                if player == nil {
                    player = AVPlayer(url: MediaStore.url(for: media.fileName, roomKey: roomKey))
                }
            }
            .onDisappear {
                player?.pause()
                player = nil
            }
            .alert("保存到相册", isPresented: Binding(
                get: { saveMessage != nil },
                set: { if !$0 { saveMessage = nil } }
            )) {
                Button("好", role: .cancel) {}
            } message: {
                Text(saveMessage ?? "")
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
                                    Label("保存到相册", systemImage: "square.and.arrow.down")
                                }
                            }
                    }
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .automatic))

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
