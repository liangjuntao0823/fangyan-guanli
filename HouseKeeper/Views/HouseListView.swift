import SwiftUI
import SwiftData

struct HouseListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \House.createdAt, order: .reverse) private var houses: [House]

    @State private var searchText = ""
    @State private var towerFilter: Int? = nil      // nil = 全部
    @State private var statusFilter: HouseStatus? = nil
    @State private var layoutFilter: String? = nil
    @State private var showAdd = false

    private var filteredHouses: [House] {
        houses.filter { house in
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
    }

    private var layouts: [String] {
        Array(Set(houses.map(\.layout))).sorted()
    }

    private var tower1Count: Int { houses.filter { $0.tower == 1 }.count }
    private var tower2Count: Int { houses.filter { $0.tower == 2 }.count }

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
        }
    }

    // MARK: - 统计（1座 / 2座分开显示）

    private var statsBar: some View {
        HStack(spacing: 12) {
            Label {
                Text("目前已收录房源总计")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            } icon: {
                Image(systemName: "building.2.fill")
                    .font(.footnote)
                    .foregroundColor(AppTheme.primary)
            }

            Spacer()

            Text("1座 \(tower1Count) 套")
                .font(.footnote.weight(.semibold))
                .foregroundColor(AppTheme.primary)
            Text("2座 \(tower2Count) 套")
                .font(.footnote.weight(.semibold))
                .foregroundColor(AppTheme.primary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.white)
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

    // MARK: - 分类检索（座号 / 状态 / 户型）

    private var filterBar: some View {
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

                if !layouts.isEmpty {
                    Divider().frame(height: 16)
                    Menu {
                        Button("全部户型") { layoutFilter = nil }
                        ForEach(layouts, id: \.self) { layout in
                            Button(layout) { layoutFilter = layout }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "slider.horizontal.3")
                                .font(.caption)
                            Text(layoutFilter ?? "户型")
                                .font(.footnote)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.white)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule().stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
        }
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

    // MARK: - 列表

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
                                HouseCardView(house: house)
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
}

#Preview {
    HouseListView()
        .modelContainer(for: [House.self, MediaItem.self], inMemory: true)
}
