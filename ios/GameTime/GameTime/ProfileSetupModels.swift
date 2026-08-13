import Foundation

enum ProfileSetupField: Hashable, Sendable {
    case displayName
    case username
    case submission
}

enum ProfileSetupValidationIssue: Equatable, Hashable, Sendable {
    case displayNameRequired
    case displayNameTooLong
    case usernameTooShort
    case usernameTooLong
    case usernameMustBeginWithLetter
    case usernameContainsInvalidCharacters

    var field: ProfileSetupField {
        switch self {
        case .displayNameRequired, .displayNameTooLong:
            .displayName
        case .usernameTooShort, .usernameTooLong,
            .usernameMustBeginWithLetter,
            .usernameContainsInvalidCharacters:
            .username
        }
    }

    var message: String {
        switch self {
        case .displayNameRequired:
            "Enter the name you want us to use."
        case .displayNameTooLong:
            "Keep your name to 50 characters or fewer."
        case .usernameTooShort:
            "Use at least 3 characters."
        case .usernameTooLong:
            "Use no more than 30 characters."
        case .usernameMustBeginWithLetter:
            "Begin your username with a letter."
        case .usernameContainsInvalidCharacters:
            "Use only letters, numbers, or underscores."
        }
    }
}

enum ProfileUsernameRequirement:
    CaseIterable,
    Hashable,
    Identifiable,
    Sendable
{
    case length
    case beginsWithLetter
    case allowedCharacters

    var id: Self { self }

    var label: String {
        switch self {
        case .length:
            "3–30 characters"
        case .beginsWithLetter:
            "Begins with a letter"
        case .allowedCharacters:
            "Letters, numbers, or underscores only"
        }
    }

    func isSatisfied(by username: String) -> Bool {
        switch self {
        case .length:
            return (3...30).contains(username.count)
        case .beginsWithLetter:
            guard let first = username.unicodeScalars.first else {
                return false
            }
            return ProfileSetupValidation.asciiLetters.contains(first)
        case .allowedCharacters:
            return !username.isEmpty
                && username.unicodeScalars.allSatisfy { scalar in
                    ProfileSetupValidation.allowedUsernameCharacters.contains(
                        scalar
                    )
                }
        }
    }
}

struct ProfileSetupValidation: Equatable, Sendable {
    fileprivate static let asciiLetters = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
    )
    fileprivate static let allowedUsernameCharacters = CharacterSet(
        charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_"
    )

    let displayName: String
    let username: String
    let issues: [ProfileSetupValidationIssue]

    init(displayName: String, username: String) {
        let cleanDisplayName = displayName.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        self.displayName = cleanDisplayName
        self.username = username

        var issues: [ProfileSetupValidationIssue] = []
        if cleanDisplayName.isEmpty {
            issues.append(.displayNameRequired)
        } else if cleanDisplayName.count > 50 {
            issues.append(.displayNameTooLong)
        }

        if username.count < 3 {
            issues.append(.usernameTooShort)
        } else if username.count > 30 {
            issues.append(.usernameTooLong)
        }
        if !ProfileUsernameRequirement.beginsWithLetter.isSatisfied(
            by: username
        ) {
            issues.append(.usernameMustBeginWithLetter)
        }
        if !ProfileUsernameRequirement.allowedCharacters.isSatisfied(
            by: username
        ) {
            issues.append(.usernameContainsInvalidCharacters)
        }

        self.issues = issues
    }

    var isValid: Bool {
        issues.isEmpty
    }

    var firstInvalidField: ProfileSetupField? {
        issues.first?.field
    }
}

enum ProfileSetupSubmissionState: Equatable, Sendable {
    case idle
    case validationFailed([ProfileSetupValidationIssue])
    case submitting
    case usernameUnavailable(username: String)
    case offline
    case failed
    case succeeded
}

enum ProfileCreationServerConflict: Equatable, Sendable {
    case usernameUnavailable
    case existingProfile
    case unrelated

    static func classify(
        code: String?,
        message: String,
        detail: String?
    ) -> ProfileCreationServerConflict {
        let description = [code, message, detail]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()

        if description.contains("profiles_handle_key")
            || description.contains("profiles_handle_not_reserved")
            || description.contains("handle is not available")
        {
            return .usernameUnavailable
        }
        if description.contains("profiles_pkey") {
            return .existingProfile
        }
        return .unrelated
    }
}
