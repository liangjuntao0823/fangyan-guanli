import SwiftUI
import SwiftData

struct HouseListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \House.createdAt, order: .reverse) private var houses: [House]

    @State private var searchText = ""
    @State private var towerFilter: Int? = nil      // nil = 全部
    @State private var statusFilter: HouseStatus? = .available   // 首页默认显示待租房源
    @State private var layoutFilter: String? = nil
    @State private var showAdd = false
    @State private var houseToDelete: House?

    /// 筛选后的房源：默认待租，并按「座号 + 房号」升序排列（1座在前，同座按房号数字从小到大）
    private var filteredHouses: [House] {
        houses
            .filter { house in
                let matchSearch: Bool = {
                    guard !searchText.isEmpty else { return true }
                    let keyword = searchText.lowercased()
                    return house.roomNo.lowercased().contains(keyword)
                        || house.displayRoomNo.lowercased().contains(keyword)
                        || house.landlord.lowercased().contains(keyword)
                        || house.layout.lowercased().contains(keyword)
                        || house.remark.lowercased().contains(keyword)
                }()
                let matchTower = towerFilter == nil || house.tower == towerFilter
                let matchStatus = statusFilter == nil || house.status == statusFilter
                let matchLayout = layoutFilter == nil || house.layout == layoutFilter
                return matchSearch && matchTower && matchStatus && matchLayout
            }
            .sorted { a, b in
                if a.tower != b.tower { return a.tower < b.tower }
                if a.sortRoomNo != b.sortRoomNo { return a.sortRoomNo < b.sortRoomNo }
                // 同号同层（如 1420上 / 1420下）：按原始房号字符串稳定排序
                return a.roomNo < b.roomNo
            }
    }

    private var layouts: [String] {
        Array(Set(houses.compactMap { $0.layout.isEmpty ? nil : $0.layout })).sorted()
    }

    private var tower1Count: Int { houses.filter { $0.tower == 1 }.count }
    private var tower2Count: Int { houses.filter { $0.tower == 2 }.count }
    private var availableCount: Int { houses.filter { $0.status == .available }.count }

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    statsBar
                    searchBar
                    filterBar
                    houseList
                }
            }
            .navigationTitle("房源管家")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAdd = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.body.weight(.semibold))
                    }
                }
            }
            .sheet(isPresented: $showAdd) {
                HouseEditView(house: nil)
            }
            .confirmationDialog("删除这套房源？", isPresented: Binding(
                get: { houseToDelete != nil },
                set: { if !$0 { houseToDelete = nil } }
            ), titleVisibility: .visible) {
                Button("删除房源", role: .destructive) {
                    if let h = houseToDelete { deleteHouse(h) }
                    houseToDelete = nil
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("将同时删除该房源的照片和视频，且无法恢复。")
            }
        }
    }

    // MARK: - 统计（动态跟随当前筛选）
    // 规则：
    //  - 筛选了座号 / 户型 → 显示筛选口径数量（如「1座 X套」「1座 单间上层 X套」，状态为隐含条件不拼入）
    //  - 仅筛选状态（默认待租）→ 显示「待租 X套 / 已租 X套」
    //  - 无任何筛选 → 显示「1座 X套（已租+待租） 2座 X套（已租+待租） 待租 X套」

    private var statsBar: some View {
        HStack(spacing: 12) {
            Label {
                Text("房源统计")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            } icon: {
                Image(systemName: "building.2.fill")
                    .font(.footnote)
                    .foregroundColor(AppTheme.primary)
            }

            Spacer()

            if towerFilter != nil || layoutFilter != nil {
                Text(statsFilteredLabel)
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(AppTheme.primary)
                    .lineLimit(1)
            } else if let status = statusFilter {
                Text("\(status.label) \(filteredHouses.count) 套")
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(AppTheme.primary)
            } else {
                Text("1座 \(tower1Count) 套")
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(AppTheme.primary)
                Text("2座 \(tower2Count) 套")
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(AppTheme.primary)
                Text("待租 \(availableCount) 套")
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(AppTheme.primary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.white)
    }

    private var statsFilteredLabel: String {
        var parts: [String] = []
        if let t = towerFilter { parts.append("\(t)座") }
        if let l = layoutFilter { parts.append(l) }
        parts.append("\(filteredHouses.count)套")
        return parts.joined(separator: " ")
    }

    // MARK: - 搜索

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            TextField("搜索房号 / 房东 / 户型 / 备注", text: $searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.subheadline)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - 分类检索（第一行：座号 / 状态；第二行：户型）

    private var filterBar: some View {
        VStack(spacing: 8) {
            // 第一行：座号 + 状态
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    filterChip(title: "全部座", isOn: towerFilter == nil) {
                        towerFilter = nil
                    }
                    filterChip(title: "1座", isOn: towerFilter == 1) {
                        towerFilter = 1
                    }
                    filterChip(title: "2座", isOn: towerFilter == 2) {
                        towerFilter = 2
                    }

                    Divider().frame(height: 16)

                    filterChip(title: "全部状态", isOn: statusFilter == nil) {
                        statusFilter = nil
                    }
                    filterChip(title: "待租", isOn: statusFilter == .available) {
                        statusFilter = .available
                    }
                    filterChip(title: "已租", isOn: statusFilter == .rented) {
                        statusFilter = .rented
                    }
                }
                .padding(.horizontal, 16)
            }

            // 第二行：户型筛选（独立一行，选项随已收录房源的户型动态增减）
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    filterChip(title: "全部户型", isOn: layoutFilter == nil) {
                        layoutFilter = nil
                    }
                    ForEach(layouts, id: \.self) { layout in
                        filterChip(title: layout, isOn: layoutFilter == layout) {
                            layoutFilter = layout
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(.bottom, 10)
    }

    private func filterChip(title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.footnote.weight(isOn ? .semibold : .regular))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isOn ? AppTheme.primary : Color.white)
                .foregroundColor(isOn ? .white : .primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 列表（右滑卡片露出 已租/删除 按钮）

    private var houseList: some View {
        Group {
            if houses.isEmpty {
                EmptyStateView(
                    icon: "house",
                    title: "还没有房源",
                    subtitle: "点右上角「+」登记第一套房源"
                )
            } else if filteredHouses.isEmpty {
                EmptyStateView(
                    icon: "magnifyingglass",
                    title: "没有匹配的房源",
                    subtitle: "换个搜索词或筛选条件试试"
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(filteredHouses) { house in
                            NavigationLink {
                                HouseDetailView(house: house)
                            } label: {
                                SwipeableHouseCard(
                                    house: house,
                                    onToggleStatus: { toggleStatus(house) },
                                    onDelete: { houseToDelete = house }
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)
                }
            }
        }
    }

    // MARK: - 右滑操作（切换状态 / 删除）

    private func toggleStatus(_ house: House) {
        house.status = house.status == .available ? .rented : .available
        house.updatedAt = Date()
        try? modelContext.save()
    }

    private func deleteHouse(_ house: House) {
        MediaStore.deleteAll(files: house.mediaItems.map(\.fileName), roomKey: house.mediaRoomKey)
        modelContext.delete(house)
        try? modelContext.save()
    }
}

#Preview {
    HouseListView()
        .modelContainer(for: [House.self, MediaItem.self], inMemory: true)
}
