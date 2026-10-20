import SwiftUI
import SwiftData
import PhotosUI

struct HouseEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    /// 传入房源 = 编辑；nil = 新增
    let house: House?

    @State private var roomNo = ""
    @State private var tower = 1
    @State private var landlord = ""
    @State private var layout = ""
    @State private var priceText = ""
    @State private var password = ""
    @State private var remark = ""
    @State private var status: HouseStatus = .available
    @State private var mediaItems: [MediaItem] = []

    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var selectedVideos: [PhotosPickerItem] = []
    @State private var loadingMedia = false
    @State private var showError = false
    @State private var errorMessage = ""

    /// 用户是否手动改过座号（改过后不再被房号前缀自动覆盖）
    @State private var towerTouched = false
    /// 编辑前原房号目录 key（房号变更时迁移媒体目录）
    @State private var originalRoomKey = ""

    private var isEditing: Bool { house != nil }

    var body: some View {
        NavigationStack {
            Form {
                basicInfoSection
                statusSection
                mediaSection
                remarkSection
            }
            .navigationTitle(isEditing ? "编辑房源" : "登记房源")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") { save() }
                        .fontWeight(.semibold)
                }
            }
            .onChange(of: selectedPhotos) { _, newValue in
                guard !newValue.isEmpty else { return }
                Task { await loadPhotos(from: newValue) }
            }
            .onChange(of: selectedVideos) { _, newValue in
                guard !newValue.isEmpty else { return }
                Task { await loadVideos(from: newValue) }
            }
            .alert("无法保存", isPresented: $showError) {
                Button("好", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
            .onAppear(perform: loadFromHouse)
        }
    }

    // MARK: - 表单分区（拆分子视图，避免单表达式类型检查超时）

    private var basicInfoSection: some View {
        Section("基本信息") {
            HStack {
                Text("房号")
                    .foregroundColor(.secondary)
                    .frame(width: 64, alignment: .leading)
                TextField("如 2334 或 2-1418", text: $roomNo)
                    .keyboardType(.numbersAndPunctuation)
                    .onChange(of: roomNo) { _, newValue in
                        guard !towerTouched else { return }
                        if newValue.hasPrefix("2-") || newValue.hasPrefix("2－") {
                            tower = 2
                        } else if !newValue.isEmpty {
                            tower = 1
                        }
                    }
            }

            Picker("座号", selection: $tower) {
                Text("1座").tag(1)
                Text("2座").tag(2)
            }
            .onChange(of: tower) {
                towerTouched = true
            }

            HStack {
                Text("房东")
                    .foregroundColor(.secondary)
                    .frame(width: 64, alignment: .leading)
                TextField("房东姓名", text: $landlord)
            }

            HStack {
                Text("户型")
                    .foregroundColor(.secondary)
                    .frame(width: 64, alignment: .leading)
                TextField("如 单间 / 复式", text: $layout)
            }

            HStack {
                Text("价格")
                    .foregroundColor(.secondary)
                    .frame(width: 64, alignment: .leading)
                TextField("元/月", text: $priceText)
                    .keyboardType(.numberPad)
                Spacer()
                if !priceText.isEmpty {
                    Text("\(Int(priceText) ?? 0)元/月")
                        .font(.footnote)
                        .foregroundColor(.orange)
                }
            }

            HStack {
                Text("密码")
                    .foregroundColor(.secondary)
                    .frame(width: 64, alignment: .leading)
                TextField("进门密码", text: $password)
            }
        }
    }

    private var statusSection: some View {
        Section("状态") {
            Picker("房源状态", selection: $status) {
                Text("待租").tag(HouseStatus.available)
                Text("已租").tag(HouseStatus.rented)
            }
            .pickerStyle(.segmented)
            Text(status == .available ? "待租：可带看" : "已租：已租出，手动更新状态即可")
                .font(.footnote)
                .foregroundColor(.secondary)
        }
    }

    private var mediaSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                mediaPickerRow
                if mediaItems.isEmpty {
                    Text("还没添加照片或视频，添加后可实时预览")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                } else {
                    mediaGrid
                }
            }
        } header: {
            Text("照片 / 视频")
        } footer: {
            Text("照片和视频保存在本机，分享时随房源信息一起发送。")
        }
    }

    private var mediaPickerRow: some View {
        HStack(spacing: 10) {
            PhotosPicker(selection: $selectedPhotos, maxSelectionCount: 9, matching: .images) {
                Label("添加照片", systemImage: "photo.badge.plus")
                    .font(.subheadline)
            }
            .buttonStyle(.bordered)

            PhotosPicker(selection: $selectedVideos, maxSelectionCount: 3, matching: .videos) {
                Label("添加视频", systemImage: "video.badge.plus")
                    .font(.subheadline)
            }
            .buttonStyle(.bordered)

            if loadingMedia {
                ProgressView()
                    .padding(.leading, 4)
            }
        }
    }

    private var mediaGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
            // 用唯一的 fileName 作标识（不用 MediaItem.id：SwiftData 新对象 id 不可靠）
            ForEach(mediaItems, id: \.fileName) { media in
                mediaCell(media)
            }
        }
    }

    /// 单个媒体格子：固定正方形、内容裁切填满；删除按钮限定 32×32 热区（borderless），防止误删全部
    private func mediaCell(_ media: MediaItem) -> some View {
        ZStack(alignment: .topTrailing) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay(
                    MediaThumbView(media: media, roomKey: originalRoomKey.isEmpty ? currentRoomKey : originalRoomKey)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .contentShape(RoundedRectangle(cornerRadius: 8))

            Button {
                // 单条删除：只移除 fileName 完全匹配的这一条，其余不受影响
                removeMedia(fileName: media.fileName)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.white)
                    .shadow(radius: 2)
            }
            .buttonStyle(.borderless)
            .frame(width: 32, height: 32)
            .contentShape(Rectangle())
            .padding(3)
        }
    }

    private var remarkSection: some View {
        Section("备注") {
            HStack(alignment: .top) {
                Text("备注")
                    .foregroundColor(.secondary)
                    .frame(width: 64, alignment: .leading)
                TextField("如 采光好 / 带阳台 / 近电梯", text: $remark, axis: .vertical)
                    .lineLimit(1...4)
            }
        }
    }

    // MARK: - 载入 / 保存

    /// 当前房号对应的媒体目录 key（新增时用临时 key，保存后正式按房号）
    private var currentRoomKey: String {
        let trimmed = roomNo.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "2－", with: "2-")
        let clean = trimmed.hasPrefix("2-") ? String(trimmed.dropFirst(2)) : trimmed
        let key = tower == 2 ? "2-\(clean)" : clean
        let illegal = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        return key.components(separatedBy: illegal).joined(separator: "-")
    }

    private func loadFromHouse() {
        guard let house else { return }
        roomNo = house.roomNo
        tower = house.tower
        landlord = house.landlord
        layout = house.layout
        priceText = house.price > 0 ? "\(house.price)" : ""
        password = house.password
        remark = house.remark
        status = house.status
        // 关键：拷贝构造新数组，与 house.mediaItems（SwiftData 关系数组，引用语义）彻底断开共享，
        // 避免编辑期间的任何增删直接改动数据库关系，导致删除行为异常
        mediaItems = Array(house.mediaItems)
        towerTouched = true
        originalRoomKey = house.mediaRoomKey
    }

    private func save() {
        let trimmedRoomNo = roomNo.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "2－", with: "2-")
        let cleanRoomNo = trimmedRoomNo.hasPrefix("2-") ? String(trimmedRoomNo.dropFirst(2)) : trimmedRoomNo

        guard !cleanRoomNo.isEmpty else {
            errorMessage = "请填写房号"
            showError = true
            return
        }

        let target: House
        if let house {
            target = house
        } else {
            target = House()
            modelContext.insert(target)
        }

        // 编辑时：真正删除「已被移除」的旧媒体（文件 + 记录）
        // 只在保存时执行 → 点「取消」不会落盘，删除可完整回滚
        if let house {
            let removed = house.mediaItems.filter { old in
                !mediaItems.contains { $0.fileName == old.fileName }
            }
            for old in removed {
                MediaStore.delete(fileName: old.fileName, roomKey: originalRoomKey.isEmpty ? house.mediaRoomKey : originalRoomKey)
                modelContext.delete(old)
            }
        }

        // 编辑时房号变更 → 媒体目录整体迁移，文件不丢失
        if isEditing, let house {
            let newRoomKey: String = {
                let key = house.tower == 2 ? "2-\(cleanRoomNo)" : cleanRoomNo
                let illegal = CharacterSet(charactersIn: "/:\\?%*|\"<>")
                return key.components(separatedBy: illegal).joined(separator: "-")
            }()
            MediaStore.migrateHouseDirectory(from: originalRoomKey, to: newRoomKey)
        }

        target.roomNo = cleanRoomNo
        target.tower = tower
        target.landlord = landlord.trimmingCharacters(in: .whitespacesAndNewlines)
        target.layout = layout.trimmingCharacters(in: .whitespacesAndNewlines)
        target.price = Int(priceText) ?? 0
        target.password = password
        target.remark = remark.trimmingCharacters(in: .whitespacesAndNewlines)
        target.status = status
        target.updatedAt = Date()

        for item in mediaItems where item.house == nil {
            item.house = target
            modelContext.insert(item)
        }

        try? modelContext.save()
        dismiss()
    }

    // MARK: - 媒体处理

    /// 删除单条媒体：用「重建数组」方式移除，绝不修改任何共享数组引用，也不依赖模型对象引用
    /// - 已有记录（在 house.mediaItems 里）：只从暂存数组移除，点「保存」才真正删除，点「取消」完整回滚
    /// - 新增媒体（不在 house.mediaItems 里）：立即清理已写盘的文件
    private func removeMedia(fileName target: String) {
        // 判断是否为「已有记录」
        let isExisting = house?.mediaItems.contains(where: { $0.fileName == target }) ?? false
        // 记录被移除条目的文件名（若存在）
        let removedFile = mediaItems.first(where: { $0.fileName == target })?.fileName

        // 重建数组：只排除 fileName 完全匹配的这一条，其余原样保留
        mediaItems = mediaItems.filter { $0.fileName != target }

        // 新增媒体：文件已写盘但尚未关联房源 → 立即清理该文件，避免残留孤儿文件
        if let removedFile, !isExisting {
            MediaStore.delete(fileName: removedFile, roomKey: originalRoomKey.isEmpty ? currentRoomKey : originalRoomKey)
        }
    }

    private func loadPhotos(from items: [PhotosPickerItem]) async {
        loadingMedia = true
        defer { loadingMedia = false }

        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data),
               let jpeg = image.jpegData(compressionQuality: 0.85) {
                let fileName = MediaStore.save(data: jpeg, ext: "jpg", roomKey: currentRoomKey)
                mediaItems.append(MediaItem(fileName: fileName, kind: "image"))
            }
        }
        selectedPhotos = []
    }

    private func loadVideos(from items: [PhotosPickerItem]) async {
        loadingMedia = true
        defer { loadingMedia = false }

        for item in items {
            var savedName: String?

            // 方式一：URL（安全作用域访问后拷贝临时文件）
            if let url = try? await item.loadTransferable(type: URL.self) {
                let didStart = url.startAccessingSecurityScopedResource()
                defer { if didStart { url.stopAccessingSecurityScopedResource() } }
                if FileManager.default.fileExists(atPath: url.path) {
                    savedName = MediaStore.saveFile(from: url, roomKey: currentRoomKey)
                }
            }

            // 方式二：直接读数据（URL 方式拿不到时兜底）
            if savedName == nil,
               let data = try? await item.loadTransferable(type: Data.self) {
                savedName = MediaStore.save(data: data, ext: "mov", roomKey: currentRoomKey)
            }

            if let savedName {
                mediaItems.append(MediaItem(fileName: savedName, kind: "video"))
            }
        }
        selectedVideos = []
    }
}
