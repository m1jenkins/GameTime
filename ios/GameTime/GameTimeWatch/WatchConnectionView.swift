import SwiftUI

struct WatchConnectionView: View {
    let connection: WatchConnectionModel

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: connection.symbolName)
                .font(.title2)
                .foregroundStyle(connection.tint)
                .accessibilityHidden(true)

            Text(connection.title)
                .font(.headline)
                .multilineTextAlignment(.center)

            Text(connection.detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if let lastUpdated = connection.lastUpdated {
                Text(lastUpdated, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(
                        "Last setup update from iPhone "
                            + lastUpdated.formatted()
                    )
            }

            Text("Test only")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.orange)
        }
        .padding(.horizontal, 8)
    }
}

private struct WatchConnectionViewPreviews: PreviewProvider {
    static var previews: some View {
        WatchConnectionView(connection: .previewReady)
    }
}
