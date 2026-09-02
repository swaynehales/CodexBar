enum OverviewGridLayout: String, CaseIterable {
    case list
    case grid

    var label: String {
        switch self {
        case .list: L("overview_layout_list")
        case .grid: L("overview_layout_grid")
        }
    }
}
