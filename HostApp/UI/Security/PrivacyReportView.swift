import SwiftUI
import Charts

/// 隐私记录内容视图。
/// 统计结果在 init 时算一次，避免 body 每次刷新都全量遍历 entries。
struct PrivacyReportView: View {
    private let entries: [TraceEntry]
    private let capCounts: [CapCount]
    private let timelinePoints: [TimelinePoint]
    private let ratioSlices: [RatioSlice]
    private let total: Int
    private let sensitiveCount: Int
    private let blockedCount: Int

    init(entries: [TraceEntry]) {
        self.entries = entries
        self.total = entries.count
        self.sensitiveCount = entries.filter { SecurityMode.isSensitive($0.module) }.count
        self.blockedCount = entries.filter { $0.status == "blocked" }.count

        var dict: [String: Int] = [:]
        for e in entries {
            dict[SecurityMode.displayName(for: e.module), default: 0] += 1
        }
        self.capCounts = dict.map { CapCount(name: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }

        self.timelinePoints = entries
            .filter { SecurityMode.isSensitive($0.module) }
            .map { TimelinePoint(time: $0.timestamp,
                                 capability: SecurityMode.displayName(for: $0.module),
                                 blocked: $0.status == "blocked") }

        let s = entries.filter { SecurityMode.isSensitive($0.module) }.count
        let n = entries.count - s
        self.ratioSlices = [
            RatioSlice(name: "敏感能力", value: s, color: .orange),
            RatioSlice(name: "普通能力", value: n, color: .gray)
        ].filter { $0.value > 0 }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if entries.isEmpty {
                    emptyView
                } else {
                    summaryCard
                    barCard
                    timelineCard
                    ratioCard
                }
            }
            .padding(16)
        }
    }

    // MARK: - 空态

    private var emptyView: some View {
        VStack(spacing: 8) {
            Image(systemName: "shield.slash")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("还没有隐私记录")
                .font(.headline)
            Text("开启安全模式后，小程序的能力调用会记录在这里。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .padding(.horizontal, 24)
        .background(cardBackground)
    }

    // MARK: - 概览


    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("概览")
            HStack(spacing: 8) {
                metric("\(total)", "总调用", .primary)
                metric("\(sensitiveCount)", "敏感能力", .orange)
                metric("\(blockedCount)", "已拦截", .red)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    private func metric(_ value: String, _ caption: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(color)
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 能力分布

    private struct CapCount: Identifiable {
        var id: String { name }
        let name: String
        let count: Int
    }


    private var barCard: some View {
        let data = Array(capCounts.prefix(8))
        return VStack(alignment: .leading, spacing: 8) {
            sectionTitle("能力调用分布")
            Chart(data) { item in
                BarMark(
                    x: .value("次数", item.count),
                    y: .value("能力", item.name)
                )
                .foregroundStyle(Color.accentColor)
                .annotation(position: .trailing) {
                    Text("\(item.count)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .chartXAxis {
                AxisMarks(position: .bottom)
            }
            .chartYAxis {
                AxisMarks(position: .leading) { AxisValueLabel() }
            }
            .frame(height: CGFloat(max(data.count, 1)) * 34 + 30)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    // MARK: - 时间轴

    private struct TimelinePoint: Identifiable {
        let id = UUID()
        let time: Date
        let capability: String
        let blocked: Bool
    }


    private var timelineCard: some View {
        let points = timelinePoints
        let cats = Array(Set(points.map { $0.capability })).sorted()
        return VStack(alignment: .leading, spacing: 8) {
            sectionTitle("敏感能力时间轴")
            if points.isEmpty {
                Text("本次没有敏感能力调用")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 12)
            } else {
                Text("红点 = 被拦截")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Chart {
                    ForEach(points) { p in
                        PointMark(
                            x: .value("时间", p.time),
                            y: .value("能力", p.capability)
                        )
                        .foregroundStyle(p.blocked ? Color.red : Color.orange)
                        .symbolSize(p.blocked ? 70 : 40)
                    }
                }
                .chartYScale(domain: cats)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) {
                        AxisValueLabel(format: .dateTime.hour().minute())
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { AxisValueLabel() }
                }
                .frame(height: CGFloat(max(cats.count, 1)) * 40 + 40)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    // MARK: - 占比

    private struct RatioSlice: Identifiable {
        var id: String { name }
        let name: String
        let value: Int
        let color: Color
    }


    private var ratioCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("调用占比")
            Chart(ratioSlices) { s in
                SectorMark(
                    angle: .value("次数", s.value),
                    innerRadius: .ratio(0.55),
                    angularInset: 2
                )
                .foregroundStyle(s.color)
            }
            .chartLegend(position: .bottom, alignment: .center, spacing: 12)
            .frame(height: 180)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    // MARK: - 组件

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 15, weight: .semibold))
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color(uiColor: .secondarySystemGroupedBackground))
    }
}
