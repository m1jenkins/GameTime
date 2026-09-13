import SwiftUI

struct LaunchingView: View {
  let errorMessage: String?
  let retry: () -> Void

  var body: some View {
    ZStack {
      SignalTheme.canvas
        .ignoresSafeArea()

      if let errorMessage {
        LaunchRetryContent(
          message: retryMessage(for: errorMessage),
          retry: retry
        )
        .padding(24)
      } else {
        LaunchLoadingContent()
          .padding(24)
          .accessibilityElement(children: .contain)
          .accessibilityIdentifier("launch.loading")
      }

      if isOffline {
        VStack {
          Spacer()
          Text("Offline")
            .font(
              SignalTheme.uiFont(
                size: 12,
                relativeTo: .caption
              )
            )
            .foregroundStyle(
              SignalTheme.textSecondary
            )
            .padding(.horizontal, 34)
            .padding(.bottom, 30)
            .accessibilityIdentifier("launch.offline")
        }
      }
    }

  }

  private var isOffline: Bool {
    errorMessage?.localizedCaseInsensitiveContains("offline") == true
  }

  private func retryMessage(for errorMessage: String) -> String {
    if isOffline {
      return "Check your connection and try again."
    }
    return errorMessage
  }
}

private struct LaunchLoadingContent: View {
  var body: some View {
    VStack(spacing: 18) {
      SignalWordmark()
      ProgressView()
        .accessibilityLabel("Loading \(GameTimePublicIdentity.name)")
        .tint(SignalTheme.accent)
      Text("Loading…")
        .font(.body)
        .foregroundStyle(SignalTheme.textSecondary)
    }
  }
}

private struct LaunchRetryContent: View {
  let message: String
  let retry: () -> Void

  var body: some View {
    VStack(spacing: 16) {
      SignalWordmark()

      Text("!")
        .font(
          SignalTheme.uiFont(
            size: 18,
            relativeTo: .headline,
            weight: .bold
          )
        )
        .foregroundStyle(SignalTheme.textPrimary)
        .frame(width: 34, height: 34)
        .background(SignalTheme.soft, in: Circle())
        .accessibilityHidden(true)

      Text("Couldn’t load your challenges")
        .font(
          SignalTheme.uiFont(
            size: 16,
            relativeTo: .body,
            weight: .bold
          )
        )
        .foregroundStyle(SignalTheme.textPrimary)
        .multilineTextAlignment(.center)
        .accessibilityIdentifier("launch.retry")

      Text(message)
        .font(
          SignalTheme.uiFont(
            size: 13,
            relativeTo: .subheadline
          )
        )
        .foregroundStyle(SignalTheme.textSecondary)
        .multilineTextAlignment(.center)
        .lineSpacing(1.5)

      Button("Try again", action: retry)
        .buttonStyle(SignalSecondaryButtonStyle())
        .padding(.top, 4)
        .accessibilityIdentifier("launch.retry.button")
    }
    .frame(maxWidth: 280)
  }
}

private struct SignalWordmark: View {
  var body: some View {
    Text(GameTimePublicIdentity.name)
      .modifier(SignalDisplay(size: 30))
      .tracking(-0.6)
      .foregroundStyle(SignalTheme.accent)
      .accessibilityLabel(Text(GameTimePublicIdentity.name))
  }
}

#Preview("Launching") {
  LaunchingView(errorMessage: nil, retry: {})
}

#Preview("Launch retry") {
  LaunchingView(errorMessage: "You appear to be offline.", retry: {})
}
