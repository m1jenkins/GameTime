import AuthenticationServices
import CryptoKit
import Foundation
import Security
import SwiftUI

enum AppleSignInNonce {
    static func random(length: Int = 32) throws -> String {
        precondition(length > 0)
        let alphabet = Array(
            "0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._"
        )
        var result = ""
        var remaining = length

        while remaining > 0 {
            var random: UInt8 = 0
            let status = SecRandomCopyBytes(
                kSecRandomDefault,
                1,
                &random
            )
            guard status == errSecSuccess else {
                throw AppleSignInNonceError.randomnessUnavailable(status)
            }
            guard Int(random) < alphabet.count * (256 / alphabet.count) else {
                continue
            }
            result.append(alphabet[Int(random) % alphabet.count])
            remaining -= 1
        }
        return result
    }

    static func hash(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

enum AppleSignInNonceError: LocalizedError {
    case randomnessUnavailable(OSStatus)

    var errorDescription: String? {
        switch self {
        case .randomnessUnavailable:
            "We couldn’t start Sign in with Apple. Try again."
        }
    }
}

enum AppleAuthorizationError: LocalizedError {
    case identityTokenUnavailable
    case authorizationCodeUnavailable

    var errorDescription: String? {
        switch self {
        case .identityTokenUnavailable:
            "Apple did not return a usable identity token."
        case .authorizationCodeUnavailable:
            "Apple did not return the confirmation needed to continue. Try again."
        }
    }
}

struct NativeAppleSignInButton: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(AppModel.self) private var model
    @State private var rawNonce: String?

    var body: some View {
        SignInWithAppleButton(.signIn) { request in
            do {
                let nonce = try AppleSignInNonce.random()
                rawNonce = nonce
                request.requestedScopes = [.fullName]
                request.nonce = AppleSignInNonce.hash(nonce)
            } catch {
                model.presentedError = error.localizedDescription
            }
        } onCompletion: { result in
            handle(result)
        }
        .signInWithAppleButtonStyle(
            colorScheme == .dark ? .white : .black
        )
        .frame(height: 52)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityLabel("Sign in with Apple")
    }

    private func handle(
        _ result: Result<ASAuthorization, Error>
    ) {
        switch result {
        case .failure(let error):
            if let authorizationError = error as? ASAuthorizationError,
                authorizationError.code == .canceled
            {
                return
            }
            model.presentedError = error.localizedDescription
        case .success(let authorization):
            guard
                let credential = authorization.credential
                    as? ASAuthorizationAppleIDCredential,
                let tokenData = credential.identityToken,
                let token = String(data: tokenData, encoding: .utf8),
                let rawNonce
            else {
                model.presentedError =
                    "Apple did not return a usable identity token."
                return
            }

            let formatter = PersonNameComponentsFormatter()
            let capturedName = credential.fullName.map {
                formatter.string(from: $0)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            let nonemptyName = capturedName?.isEmpty == false
                ? capturedName
                : nil

            Task {
                await model.signInWithApple(
                    AppleIdentity(
                        idToken: token,
                        rawNonce: rawNonce,
                        firstSignInDisplayName: nonemptyName,
                        authorizationCode: credential.authorizationCode.flatMap {
                            String(data: $0, encoding: .utf8)
                        }
                    )
                )
            }
        }
    }
}

struct NativeAppleReauthenticationButton: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var rawNonce: String?

    let completion: (Result<AppleIdentity, Error>) -> Void

    @ViewBuilder
    var body: some View {
        #if DEBUG || STAGING
        if ProcessInfo.processInfo.arguments.contains(
            "--fixture-account-deletion-failure"
        ) {
            Button {
                completion(
                    .success(
                        AppleIdentity(
                            idToken: "fixture-reauthentication-token",
                            rawNonce: "fixture-reauthentication-nonce",
                            firstSignInDisplayName: nil,
                            authorizationCode:
                                "fixture-reauthentication-authorization-code"
                        )
                    )
                )
            } label: {
                Label("Continue with Apple", systemImage: "apple.logo")
                    .frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(TrustPrimaryButtonStyle())
            .accessibilityLabel("Continue with Apple to delete your account")
            .accessibilityIdentifier("account-deletion.fixture-reauthenticate")
        } else {
            nativeButton
        }
        #else
        nativeButton
        #endif
    }

    private var nativeButton: some View {
        SignInWithAppleButton(.continue) { request in
            do {
                let nonce = try AppleSignInNonce.random()
                rawNonce = nonce
                request.requestedScopes = []
                request.nonce = AppleSignInNonce.hash(nonce)
            } catch {
                completion(.failure(error))
            }
        } onCompletion: { result in
            handle(result)
        }
        .signInWithAppleButtonStyle(
            colorScheme == .dark ? .white : .black
        )
        .frame(height: 52)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityLabel("Continue with Apple to delete your account")
    }

    private func handle(
        _ result: Result<ASAuthorization, Error>
    ) {
        switch result {
        case .failure(let error):
            if let authorizationError = error as? ASAuthorizationError,
                authorizationError.code == .canceled
            {
                return
            }
            completion(.failure(error))
        case .success(let authorization):
            guard
                let credential = authorization.credential
                    as? ASAuthorizationAppleIDCredential,
                let tokenData = credential.identityToken,
                let token = String(data: tokenData, encoding: .utf8),
                let rawNonce
            else {
                completion(.failure(AppleAuthorizationError.identityTokenUnavailable))
                return
            }
            guard
                let authorizationCodeData = credential.authorizationCode,
                let authorizationCode = String(
                    data: authorizationCodeData,
                    encoding: .utf8
                ),
                !authorizationCode.isEmpty
            else {
                completion(.failure(AppleAuthorizationError.authorizationCodeUnavailable))
                return
            }
            completion(
                .success(
                    AppleIdentity(
                        idToken: token,
                        rawNonce: rawNonce,
                        firstSignInDisplayName: nil,
                        authorizationCode: authorizationCode
                    )
                )
            )
        }
    }
}
