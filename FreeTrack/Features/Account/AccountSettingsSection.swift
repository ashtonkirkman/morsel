import SwiftUI

/// Settings > Account. Signed out: the sign-in buttons and the server URL field. Signed in:
/// who you are, when the last sync finished, Sync now / Sign out / Delete account.
struct AccountSettingsSection: View {
    @Environment(AppServices.self) private var services
    @Environment(AppSettings.self) private var settings

    @State private var showDeleteConfirm = false
    @State private var showServerField = false

    private var account: AccountService { services.account }
    private var sync: SyncEngine { services.sync }

    var body: some View {
        SettingsSection(title: "Account", footer: footerText) {
            if let user = account.user {
                signedIn(user)
            } else {
                signedOut
            }
        }
        .confirmationDialog("Delete your account?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete account", role: .destructive) {
                Task { try? await account.deleteAccount() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Removes your account and everything synced to it from the server. The data on this phone stays.")
        }
    }

    private var footerText: String? {
        if account.user != nil {
            return "Your log, favorites, goals and body scans sync to your account. Local data is never deleted by sync."
        }
        return account.isConfigured ? nil : "No account server configured for this build. Enter the URL of your deployed account-api Worker."
    }

    // MARK: - Signed out

    private var signedOut: some View {
        @Bindable var settings = settings
        return VStack(spacing: Spacing.s) {
            SignInButtonsView(showsWhy: true)
                .padding(.vertical, Spacing.xs)
            SettingsSeparator()
            Button {
                withAnimation { showServerField.toggle() }
            } label: {
                HStack {
                    Text("Server URL").font(FreeTrackFont.body).foregroundStyle(Color.mText)
                    Spacer()
                    Text(settings.accountAPIURL?.host ?? (account.isConfigured ? "Default" : "Not set"))
                        .font(FreeTrackFont.callout)
                        .foregroundStyle(Color.mTextSecondary)
                        .lineLimit(1)
                    Image(systemName: showServerField ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(Color.mTextTertiary)
                }
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Account server URL")
            if showServerField || !account.isConfigured {
                TextField("https://freetrack-account-api.<you>.workers.dev", text: $settings.accountAPIURLString)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(FreeTrackFont.body)
                    .padding(.vertical, 6)
                    .accessibilityLabel("Account server URL field")
            }
        }
    }

    // MARK: - Signed in

    private func signedIn(_ user: AccountUser) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: Spacing.m) {
                Text(user.initials)
                    .font(FreeTrackFont.headline)
                    .foregroundStyle(Color.mAccent)
                    .frame(width: 44, height: 44)
                    .background(Color.mAccentSoft, in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(user.primaryLabel)
                        .font(FreeTrackFont.headline)
                        .foregroundStyle(Color.mText)
                        .lineLimit(1)
                    if let email = user.email, !email.isEmpty, email != user.primaryLabel {
                        Text(email)
                            .font(FreeTrackFont.caption)
                            .foregroundStyle(Color.mTextSecondary)
                            .lineLimit(1)
                    }
                    if let providers = user.providers, !providers.isEmpty {
                        Text("via " + providers.map { AuthProvider(rawValue: $0)?.title ?? $0 }.joined(separator: ", "))
                            .font(FreeTrackFont.caption)
                            .foregroundStyle(Color.mTextTertiary)
                    }
                }
                Spacer()
            }
            .padding(.vertical, 8)
            SettingsSeparator()
            HStack {
                Text("Last synced").font(FreeTrackFont.body).foregroundStyle(Color.mText)
                Spacer()
                if sync.isSyncing {
                    ProgressView().controlSize(.small)
                } else if let error = sync.lastError {
                    Text(error).font(FreeTrackFont.caption).foregroundStyle(Color.mWarning).lineLimit(2).multilineTextAlignment(.trailing)
                } else if let date = sync.lastSyncedAt {
                    Text("\(date, style: .relative) ago").font(FreeTrackFont.callout).foregroundStyle(Color.mTextSecondary)
                } else {
                    Text("Never").font(FreeTrackFont.callout).foregroundStyle(Color.mTextSecondary)
                }
            }
            .padding(.vertical, 6)
            SettingsSeparator()
            Button {
                Task { await sync.syncNow() }
            } label: {
                row(symbol: "arrow.triangle.2.circlepath", title: "Sync now", tint: .mAccent)
            }
            .buttonStyle(.plain)
            .disabled(sync.isSyncing || account.isBusy)
            SettingsSeparator()
            Button {
                Task { await account.signOut() }
            } label: {
                row(symbol: "rectangle.portrait.and.arrow.right", title: "Sign out", tint: .mText)
            }
            .buttonStyle(.plain)
            .disabled(account.isBusy)
            SettingsSeparator()
            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                row(symbol: "person.crop.circle.badge.xmark", title: "Delete account", tint: .mDanger)
            }
            .buttonStyle(.plain)
            .disabled(account.isBusy)
            if let error = account.lastError {
                Text(error).font(FreeTrackFont.caption).foregroundStyle(Color.mDanger).padding(.top, 4)
            }
        }
    }

    private func row(symbol: String, title: String, tint: Color) -> some View {
        HStack(spacing: Spacing.m) {
            Image(systemName: symbol).foregroundStyle(tint).frame(width: 22)
            Text(title).font(FreeTrackFont.body).foregroundStyle(tint)
            Spacer()
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}
