import SwiftUI

struct LaunchingView: View {
  let errorMessage: String?
  let retry: () -> Void

  var body: some View {
    ZStack {
      CompetitiveTrustTheme.paper
        .ignoresSafeArea()

      if let errorMessage {
        ViewThatFits(in: .vertical) {
          LaunchRetryContent(
            message: retryMessage(for: errorMessage),
            retry: retry
          )
          .padding(24)

          ScrollView {
            LaunchRetryContent(
              message: retryMessage(for: errorMessage),
              retry: retry
            )
            .frame(maxWidth: .infinity)
            .padding(24)
            .padding(.bottom, isOffline ? 44 : 0)
          }
        }
        .accessibilityIdentifier("launch.retry")
      } else {
        LaunchLoadingContent()
          .padding(24)
          .accessibilityIdentifier("launch.loading")
      }

      if isOffline {
        VStack {
          Spacer()
          Text("Offline")
            .font(
              CompetitiveTrustTheme.uiFont(
                size: 12,
                relativeTo: .caption
              )
            )
            .foregroundStyle(
              CompetitiveTrustTheme.tertiaryText
            )
            .padding(.horizontal, 34)
            .padding(.bottom, 30)
            .accessibilityIdentifier("launch.offline")
        }
      }
    }
    .environment(\.colorScheme, .light)
    .onChange(of: errorMessage) { _, message in
      guard let message else { return }
      GameTimeAccessibility.announce(
        "Couldn’t load your challenges. \(retryMessage(for: message))"
      )
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
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var hasAppeared = false

  var body: some View {
    VStack(spacing: 18) {
      BetterBetWordmark()
      DaybreakSpinner()
      Text("Loading…")
        .font(
          CompetitiveTrustTheme.uiFont(
            size: 16,
            relativeTo: .body,
            weight: .bold
          )
        )
        .foregroundStyle(CompetitiveTrustTheme.primaryText)
    }
    .opacity(hasAppeared ? 1 : 0)
    .offset(y: reduceMotion || hasAppeared ? 0 : 6)
    .onAppear {
      if reduceMotion {
        hasAppeared = true
      } else {
        withAnimation(.easeOut(duration: 0.5)) {
          hasAppeared = true
        }
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(GameTimePublicIdentity.name) is loading")
  }
}

private struct LaunchRetryContent: View {
  let message: String
  let retry: () -> Void

  var body: some View {
    VStack(spacing: 16) {
      BetterBetWordmark()

      Text("!")
        .font(
          CompetitiveTrustTheme.uiFont(
            size: 18,
            relativeTo: .headline,
            weight: .bold
          )
        )
        .foregroundStyle(CompetitiveTrustTheme.sunInk)
        .frame(width: 34, height: 34)
        .background(CompetitiveTrustTheme.sunTint, in: Circle())
        .accessibilityHidden(true)

      Text("Couldn’t load your challenges")
        .font(
          CompetitiveTrustTheme.uiFont(
            size: 16,
            relativeTo: .body,
            weight: .bold
          )
        )
        .foregroundStyle(CompetitiveTrustTheme.primaryText)
        .multilineTextAlignment(.center)
        .accessibilityAddTraits(.isHeader)

      Text(message)
        .font(
          CompetitiveTrustTheme.uiFont(
            size: 13,
            relativeTo: .subheadline
          )
        )
        .foregroundStyle(CompetitiveTrustTheme.secondaryText)
        .multilineTextAlignment(.center)
        .lineSpacing(1.5)

      Button("Try again") {
        GameTimeAccessibility.announce("Trying again.")
        retry()
      }
        .buttonStyle(TrustSecondaryButtonStyle())
        .padding(.top, 4)
        .accessibilityIdentifier("launch.retry.button")
    }
    .frame(maxWidth: 280)
  }
}

private struct BetterBetWordmark: View {
  var body: some View {
    Text(GameTimePublicIdentity.name)
      .font(
        CompetitiveTrustTheme.displayFont(
          size: 30,
          relativeTo: .title2
        )
      )
      .tracking(-0.6)
      .foregroundStyle(CompetitiveTrustTheme.coralInk)
      .accessibilityLabel(Text(GameTimePublicIdentity.name))
  }
}

private struct DaybreakSpinner: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var rotation = 0.0

  var body: some View {
    Circle()
      .stroke(
        CompetitiveTrustTheme.coral.opacity(0.2),
        lineWidth: 3
      )
      .overlay {
        Circle()
          .trim(from: 0, to: 0.24)
          .stroke(
            CompetitiveTrustTheme.coral,
            style: StrokeStyle(
              lineWidth: 3,
              lineCap: .round
            )
          )
      }
      .frame(width: 34, height: 34)
      .rotationEffect(.degrees(rotation))
      .animation(
        reduceMotion
          ? nil
          : .linear(duration: 0.9)
            .repeatForever(autoreverses: false),
        value: rotation
      )
      .onAppear {
        updateAnimation()
      }
      .onChange(of: reduceMotion) {
        updateAnimation()
      }
      .accessibilityHidden(true)
  }

  private func updateAnimation() {
    if reduceMotion {
      var transaction = Transaction()
      transaction.disablesAnimations = true
      withTransaction(transaction) {
        rotation = 0
      }
    } else {
      rotation = 360
    }
  }
}

#Preview("Launching") {
  LaunchingView(errorMessage: nil, retry: {})
}

#Preview("Launch retry") {
  LaunchingView(
    errorMessage: "You appear to be offline.",
    retry: {}
  )
}
