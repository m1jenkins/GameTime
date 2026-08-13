import SwiftUI

struct OnboardingView: View {
    @Environment(AppModel.self) private var model

    @State private var username = ""
    @State private var displayName: String
    @State private var displayNameWasEdited = false
    @State private var usernameSubmissionAttempted = false
    @State private var showingSignOutConfirmation = false
    @State private var isSigningOut = false
    @FocusState private var focusedField: Field?
    @AccessibilityFocusState private var accessibilityFocus:
        AccessibilityTarget?

    private let initialDisplayName: String

    private enum Field: Hashable {
        case displayName
        case username
    }

    private enum AccessibilityTarget: Hashable {
        case usernameError
        case submissionError
    }

    init(namePrefill: String) {
        initialDisplayName = namePrefill
        _displayName = State(initialValue: namePrefill)
    }

    private var validation: ProfileSetupValidation {
        ProfileSetupValidation(
            displayName: displayName,
            username: username
        )
    }

    private var hasUnsavedChanges: Bool {
        displayName != initialDisplayName || !username.isEmpty
    }

    private var showsUsernameFormatError: Bool {
        !username.isEmpty
            && ProfileUsernameRequirement.allCases.contains {
                !$0.isSatisfied(by: username)
            }
    }

    private var showsUsernameAvailabilityError: Bool {
        if case let .usernameUnavailable(submittedUsername) =
            model.profileSetupSubmissionState
        {
            return submittedUsername == username
        }
        return false
    }

    private var displayNameIssue: ProfileSetupValidationIssue? {
        validation.issues.first { $0.field == .displayName }
    }

    private var showsDisplayNameError: Bool {
        switch displayNameIssue {
        case .displayNameRequired:
            displayNameWasEdited
        case .displayNameTooLong:
            true
        case nil, .usernameTooShort, .usernameTooLong,
            .usernameMustBeginWithLetter,
            .usernameContainsInvalidCharacters:
            false
        }
    }

    private var isRetrying: Bool {
        switch model.profileSetupSubmissionState {
        case .offline, .failed:
            true
        case .idle, .validationFailed, .submitting,
            .usernameUnavailable, .succeeded:
            false
        }
    }

    private var canSubmit: Bool {
        validation.isValid
            && !model.isMutating
            && !showsUsernameAvailabilityError
            && model.profileSetupSubmissionState != .succeeded
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    DaybreakSectionLabel(text: "Your profile")
                    DaybreakCard {
                        VStack(alignment: .leading, spacing: 18) {
                            displayNameField
                            Divider()
                                .overlay(CompetitiveTrustTheme.border)
                            usernameField
                            submissionFeedback
                            submitButton
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 4)
                .padding(.bottom, 28)
            }
            .scrollDismissesKeyboard(.interactively)
            .daybreakScreenChrome()
            .navigationTitle("Set your profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Sign out", action: requestSignOut)
                        .disabled(model.isMutating || isSigningOut)
                        .fixedSize(horizontal: true, vertical: false)
                        .frame(minHeight: 48)
                        .contentShape(Rectangle())
                        .accessibilityIdentifier("onboarding.sign-out")
                }
            }
            .alert(
                "Sign out before finishing your profile?",
                isPresented: $showingSignOutConfirmation
            ) {
                Button("Keep editing", role: .cancel) {}
                    .accessibilityIdentifier("onboarding.sign-out.cancel")
                Button("Sign out", role: .destructive) {
                    signOut()
                }
                .accessibilityIdentifier("onboarding.sign-out.confirm")
            } message: {
                Text("Your name and username won’t be saved.")
            }
            .onAppear {
                focusedField = displayName.isEmpty
                    ? .displayName
                    : .username
            }
            .onChange(of: model.profileSetupSubmissionState) {
                _, state in
                handleSubmissionStateChange(state)
            }
        }
    }

    private var displayNameField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Name")
                .font(
                    CompetitiveTrustTheme.uiFont(
                        size: 15,
                        relativeTo: .headline,
                        weight: .bold
                    )
                )

            TextField(
                "Your name",
                text: $displayName,
                prompt: Text("Your name")
                    .foregroundStyle(CompetitiveTrustTheme.tertiaryText)
            )
                .textContentType(.name)
                .textInputAutocapitalization(.words)
                .submitLabel(.next)
                .focused($focusedField, equals: .displayName)
                .profileSetupFieldStyle(
                    isFocused: focusedField == .displayName,
                    showsError: showsDisplayNameError
                )
                .disabled(model.isMutating)
                .accessibilityLabel("Your name")
                .onSubmit {
                    displayNameWasEdited = true
                    guard let displayNameIssue else {
                        focusedField = .username
                        return
                    }
                    retainKeyboardFocus(on: .displayName)
                    GameTimeAccessibility.announce(displayNameIssue.message)
                }
                .onChange(of: displayName) {
                    displayNameWasEdited = true
                    model.profileSetupInputDidChange(.displayName)
                }

            if showsDisplayNameError, let displayNameIssue {
                Label(
                    displayNameIssue == .displayNameRequired
                        ? "Enter the name you want us to use."
                        : "Keep your name to 50 characters or fewer.",
                    systemImage: "exclamationmark.circle.fill"
                )
                .font(
                    CompetitiveTrustTheme.uiFont(
                        size: 13,
                        relativeTo: .caption,
                        weight: .semibold
                    )
                )
                .foregroundStyle(CompetitiveTrustTheme.coralInk)
                .accessibilityIdentifier("onboarding.name.error")
            } else {
                Text("Up to 50 characters.")
                    .font(.caption)
                    .foregroundStyle(CompetitiveTrustTheme.tertiaryText)
            }
        }
    }

    private var usernameField: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Username")
                .font(
                    CompetitiveTrustTheme.uiFont(
                        size: 15,
                        relativeTo: .headline,
                        weight: .bold
                    )
                )

            TextField(
                "Username",
                text: $username,
                prompt: Text("Username")
                    .foregroundStyle(CompetitiveTrustTheme.tertiaryText)
            )
                .textContentType(.username)
                .keyboardType(.asciiCapable)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused($focusedField, equals: .username)
                .profileSetupFieldStyle(
                    isFocused: focusedField == .username,
                    showsError: showsUsernameFormatError
                        || showsUsernameAvailabilityError
                )
                .disabled(model.isMutating)
                .accessibilityLabel("Username")
                .onSubmit {
                    submitProfile()
                }
                .onChange(of: username) {
                    model.profileSetupInputDidChange(.username)
                }

            VStack(alignment: .leading, spacing: 7) {
                ForEach(ProfileUsernameRequirement.allCases) { requirement in
                    ProfileUsernameRequirementRow(
                        requirement: requirement,
                        username: username
                    )
                }
            }

            if usernameSubmissionAttempted,
               let usernameFormatIssue = validation.issues.first(where: {
                   $0.field == .username
               })
            {
                Label(
                    usernameFormatIssue.message,
                    systemImage: "exclamationmark.circle.fill"
                )
                .font(
                    CompetitiveTrustTheme.uiFont(
                        size: 13,
                        relativeTo: .caption,
                        weight: .semibold
                    )
                )
                .foregroundStyle(CompetitiveTrustTheme.coralInk)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("onboarding.username.format-error")
            }

            if showsUsernameAvailabilityError {
                Label(
                    "That username isn’t available. Try another.",
                    systemImage: "person.crop.circle.badge.xmark"
                )
                .font(
                    CompetitiveTrustTheme.uiFont(
                        size: 13,
                        relativeTo: .caption,
                        weight: .semibold
                    )
                )
                .foregroundStyle(CompetitiveTrustTheme.coralInk)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("onboarding.username.error")
                .accessibilityFocused(
                    $accessibilityFocus,
                    equals: .usernameError
                )
            }

            Label(
                "You can’t change your username after you continue.",
                systemImage: "lock.fill"
            )
            .font(.caption)
            .foregroundStyle(CompetitiveTrustTheme.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 2)
            .accessibilityIdentifier("onboarding.username.permanence")
        }
    }

    @ViewBuilder
    private var submissionFeedback: some View {
        switch model.profileSetupSubmissionState {
        case .offline:
            ProfileSetupSubmissionMessage(
                title: "You’re offline",
                detail: "Check your connection, then try again.",
                systemImage: "wifi.slash"
            )
            .accessibilityIdentifier("onboarding.submission.offline")
            .accessibilityFocused(
                $accessibilityFocus,
                equals: .submissionError
            )
        case .failed:
            ProfileSetupSubmissionMessage(
                title: "We couldn’t save your profile",
                detail: "Try again. Your entries are still here.",
                systemImage: "arrow.clockwise.circle.fill"
            )
            .accessibilityIdentifier("onboarding.submission.error")
            .accessibilityFocused(
                $accessibilityFocus,
                equals: .submissionError
            )
        case .idle, .validationFailed, .submitting,
            .usernameUnavailable, .succeeded:
            EmptyView()
        }
    }

    private var submitButton: some View {
        Button(action: submitProfile) {
            HStack(spacing: 9) {
                if model.profileSetupSubmissionState == .submitting {
                    ProgressView()
                        .tint(.white)
                        .accessibilityHidden(true)
                }
                Text(submitTitle)
            }
        }
        .buttonStyle(TrustPrimaryButtonStyle())
        .disabled(!canSubmit)
        .accessibilityIdentifier(submitAccessibilityIdentifier)
        .accessibilityLabel(submitTitle)
        .accessibilityValue(submitAccessibilityValue)
        .accessibilityHint(submitAccessibilityHint)
    }

    private var submitTitle: String {
        switch model.profileSetupSubmissionState {
        case .submitting:
            "Saving profile…"
        case .offline, .failed:
            "Try again"
        case .succeeded:
            "Profile saved"
        case .idle, .validationFailed, .usernameUnavailable:
            "Enter GameTime"
        }
    }

    private var submitAccessibilityValue: String {
        switch model.profileSetupSubmissionState {
        case .submitting:
            "Profile is being saved"
        case .succeeded:
            "Profile saved"
        case .idle, .validationFailed, .usernameUnavailable,
            .offline, .failed:
            ""
        }
    }

    private var submitAccessibilityIdentifier: String {
        if model.profileSetupSubmissionState == .submitting {
            return "onboarding.submit.loading"
        }
        return isRetrying ? "onboarding.retry" : "onboarding.submit"
    }

    private var submitAccessibilityHint: String {
        switch model.profileSetupSubmissionState {
        case .submitting, .succeeded:
            ""
        case .usernameUnavailable:
            "Choose a different username to continue."
        case .offline, .failed:
            "Tries to save your profile again."
        case .idle, .validationFailed:
            canSubmit
                ? "Saves your profile and enters GameTime."
                : "Complete your name and all username requirements to continue."
        }
    }

    private func submitProfile() {
        displayNameWasEdited = true
        usernameSubmissionAttempted = true
        guard canSubmit else {
            focusFirstValidationIssue()
            return
        }
        focusedField = nil
        accessibilityFocus = nil
        Task {
            await model.completeOnboarding(
                handle: username,
                displayName: displayName
            )
            if model.profileSetupSubmissionState == .succeeded {
                GameTimeAccessibility.announce(
                    "Profile saved. Welcome to GameTime."
                )
            }
        }
    }

    private func focusFirstValidationIssue() {
        guard let issue = validation.issues.first else { return }
        let field = issue.field
        switch field {
        case .displayName:
            displayNameWasEdited = true
            retainKeyboardFocus(on: .displayName)
        case .username:
            retainKeyboardFocus(on: .username)
        case .submission:
            break
        }
        GameTimeAccessibility.announce(issue.message)
    }

    private func handleSubmissionStateChange(
        _ state: ProfileSetupSubmissionState
    ) {
        switch state {
        case let .validationFailed(issues):
            if issues.contains(where: { $0.field == .displayName }) {
                displayNameWasEdited = true
                retainKeyboardFocus(on: .displayName)
            } else {
                usernameSubmissionAttempted = true
                retainKeyboardFocus(on: .username)
            }
            if let issue = issues.first {
                GameTimeAccessibility.announce(issue.message)
            }
        case .usernameUnavailable:
            focusedField = .username
            moveAccessibilityFocus(to: .usernameError)
        case .offline, .failed:
            moveAccessibilityFocus(to: .submissionError)
        case .idle, .submitting, .succeeded:
            accessibilityFocus = nil
        }
    }

    private func moveAccessibilityFocus(to target: AccessibilityTarget) {
        Task { @MainActor in
            await Task.yield()
            accessibilityFocus = target
        }
    }

    private func retainKeyboardFocus(on field: Field) {
        Task { @MainActor in
            await Task.yield()
            focusedField = field
        }
    }

    private func requestSignOut() {
        focusedField = nil
        if hasUnsavedChanges {
            showingSignOutConfirmation = true
        } else {
            signOut()
        }
    }

    private func signOut() {
        isSigningOut = true
        Task {
            await model.signOut()
            isSigningOut = false
        }
    }
}

private enum ProfileUsernameRequirementStatus {
    case pending
    case met
    case unmet

    var systemImage: String {
        switch self {
        case .pending:
            "circle"
        case .met:
            "checkmark.circle.fill"
        case .unmet:
            "xmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .pending:
            CompetitiveTrustTheme.tertiaryText
        case .met:
            CompetitiveTrustTheme.mintInk
        case .unmet:
            CompetitiveTrustTheme.coralInk
        }
    }

    var accessibilityValue: String {
        switch self {
        case .pending:
            "Not checked"
        case .met:
            "Met"
        case .unmet:
            "Not met"
        }
    }
}

private struct ProfileUsernameRequirementRow: View {
    let requirement: ProfileUsernameRequirement
    let username: String

    private var status: ProfileUsernameRequirementStatus {
        guard !username.isEmpty else { return .pending }
        return requirement.isSatisfied(by: username) ? .met : .unmet
    }

    var body: some View {
        Label(requirement.label, systemImage: status.systemImage)
            .font(
                CompetitiveTrustTheme.uiFont(
                    size: 13,
                    relativeTo: .caption,
                    weight: .semibold
                )
            )
            .foregroundStyle(status.color)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(requirement.label)
            .accessibilityValue(status.accessibilityValue)
            .accessibilityIdentifier(accessibilityIdentifier)
    }

    private var accessibilityIdentifier: String {
        switch requirement {
        case .length:
            "onboarding.username.requirement.length"
        case .beginsWithLetter:
            "onboarding.username.requirement.leading-letter"
        case .allowedCharacters:
            "onboarding.username.requirement.characters"
        }
    }
}

private struct ProfileSetupSubmissionMessage: View {
    let title: String
    let detail: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(CompetitiveTrustTheme.coralInk)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.bold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(CompetitiveTrustTheme.secondaryText)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            CompetitiveTrustTheme.coralTint,
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .accessibilityElement(children: .combine)
    }
}

private struct ProfileSetupFieldModifier: ViewModifier {
    let isFocused: Bool
    let showsError: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        content
            .font(
                CompetitiveTrustTheme.uiFont(
                    size: 17,
                    relativeTo: .body,
                    weight: .semibold
                )
            )
            .foregroundStyle(CompetitiveTrustTheme.primaryText)
            .tint(CompetitiveTrustTheme.coralInk)
            .padding(.horizontal, 14)
            .frame(minHeight: 52)
            .background(CompetitiveTrustTheme.paperSunk, in: shape)
            .overlay {
                shape.stroke(
                    showsError
                        ? CompetitiveTrustTheme.coralInk
                        : isFocused
                            ? CompetitiveTrustTheme.coralInk
                            : CompetitiveTrustTheme.border,
                    lineWidth: showsError || isFocused ? 2 : 1
                )
            }
    }
}

private extension View {
    func profileSetupFieldStyle(
        isFocused: Bool,
        showsError: Bool
    ) -> some View {
        modifier(
            ProfileSetupFieldModifier(
                isFocused: isFocused,
                showsError: showsError
            )
        )
    }
}
