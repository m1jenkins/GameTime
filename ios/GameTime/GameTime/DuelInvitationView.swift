#if DEBUG || STAGING
import SwiftUI

struct DuelInvitationView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    private var store: DuelStore { model.duels }

    var body: some View {
        Group {
            if let id = store.resolvedInvitationID {
                DuelDetailView(challengeID: id).id(model.userID)
            } else {
                Form {
                    DuelDisclosure()
                    Text(store.invitationError ?? "Opening your invitation does not mean you agreed. Review the rules before deciding.")
                    Button("Open invitation") { Task { await store.openPendingInvitation() } }
                        .accessibilityIdentifier("duel.open-link")
                    Button("Dismiss invitation") { store.dismissInvitation(); dismiss() }
                }
                .navigationTitle("Duel invitation")
            }
        }
        .task(id: "\(model.userID?.uuidString ?? ""):\(store.pendingInvitationToken?.uuidString ?? "")") {
            await store.openPendingInvitation()
        }
    }
}
#endif
