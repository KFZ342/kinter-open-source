import ActivityKit
import SwiftUI
import WidgetKit

@available(iOS 16.1, *)
struct KinterActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: KinterActivityAttributes.self) { context in
            // 锁屏 / 通知中心
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(context.attributes.appName)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                    if let status = context.state.status {
                        Text(status)
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(.accentColor)
                    }
                }

                Text(context.state.title)
                    .font(.headline)
                    .lineLimit(1)

                if let subtitle = context.state.subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                if let progress = context.state.progress {
                    ProgressView(value: progress)
                        .tint(.accentColor)
                }
            }
            .padding(14)
            .activityBackgroundTint(Color(.systemBackground))
            .widgetURL(deepLinkURL(context))

        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.attributes.appName)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.leading, 6)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if let status = context.state.status {
                        Text(status)
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(.accentColor)
                            .padding(.trailing, 6)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if let progress = context.state.progress {
                        ProgressView(value: progress)
                            .tint(.accentColor)
                            .padding(.horizontal, 8)
                    } else if let subtitle = context.state.subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            } compactLeading: {
                Image(systemName: "app.badge")
                    .foregroundColor(.accentColor)
            } compactTrailing: {
                Text(context.state.status ?? "·")
                    .font(.caption2)
            } minimal: {
                Image(systemName: "app.badge")
                    .foregroundColor(.accentColor)
            }
            .widgetURL(deepLinkURL(context))
        }
    }

    /// 拼接 kinter:// 深链
    private func deepLinkURL(_ context: ActivityViewContext<KinterActivityAttributes>) -> URL? {
        var comps = URLComponents()
        comps.scheme = "kinter"
        comps.host = "open"
        var items = [URLQueryItem(name: "appId", value: context.attributes.appId)]
        if let link = context.state.deepLink {
            items.append(URLQueryItem(name: "deepLink", value: link))
        }
        comps.queryItems = items
        return comps.url
    }
}
