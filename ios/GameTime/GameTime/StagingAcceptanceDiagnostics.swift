import Foundation

/// Stable, staging-only symbolic-breakpoint hooks for the physical acceptance run.
///
/// These are deliberately inert. They expose no fixture route, retry, bypass, or
/// production behavior; their only purpose is to make an ambiguous-response run
/// repeatable without racing a source-line breakpoint.
enum StagingAcceptanceDiagnostics {
  @inline(never)
  static func challengeCreationResponseReceived(_ contestID: UUID) {
    _ = contestID
  }
}
