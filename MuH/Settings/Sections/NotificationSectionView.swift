import SwiftUI
import AppKit

enum RemoteMultiplexerKind: String, CaseIterable, Identifiable {
    case luvus = "Luvus"
    case herdr = "Herdr"

    var id: String { rawValue }
}

struct NotificationSectionView: View {
    let theme: AppTheme
    @State private var manager = NotificationManager.shared
    @State private var isCopied = false
    @State private var selectedBackend: RemoteMultiplexerKind = .luvus

    @Environment(\.locale) private var locale

    private var setupCommand: String {
        let scriptName = selectedBackend == .luvus ? "setup-luvus.sh" : "setup-herdr.sh"
        let scriptPath = (Bundle.main.resourcePath ?? "") + "/\(scriptName)"
        let fallbackPath = NSHomeDirectory() + "/Code/MuH/Resources/scripts/\(scriptName)"
        let finalPath = FileManager.default.fileExists(atPath: scriptPath) ? scriptPath : fallbackPath
        return "ssh <user@host> 'bash -s' < \"\(finalPath)\""
    }

    private var remoteSetupTitle: LocalizedStringResource {
        selectedBackend == .luvus
            ? L10n.Settings.Notification.remoteSetupLuvusTitle
            : L10n.Settings.Notification.remoteSetupTitle
    }

    private var remoteSetupDesc: LocalizedStringResource {
        selectedBackend == .luvus
            ? L10n.Settings.Notification.remoteSetupLuvusDesc
            : L10n.Settings.Notification.remoteSetupDesc
    }

    var body: some View {
        Form {
            Section {
                Toggle(
                    String(localized: L10n.Settings.Notification.enableNotifications.withLocale(locale)),
                    isOn: $manager.enableNotifications
                )
                .onChange(of: manager.enableNotifications) { _, enabled in
                    if enabled {
                        manager.requestAuthorization()
                    }
                }

                if manager.enableNotifications {
                    Toggle(
                        String(localized: L10n.Settings.Notification.notifyOnBlocked.withLocale(locale)),
                        isOn: $manager.notifyOnBlocked
                    )
                    .padding(.leading, DT.Space.md)

                    Toggle(
                        String(localized: L10n.Settings.Notification.notifyOnCompleted.withLocale(locale)),
                        isOn: $manager.notifyOnCompleted
                    )
                    .padding(.leading, DT.Space.md)

                    Button {
                        manager.sendTestNotification()
                    } label: {
                        HStack(spacing: DT.Space.xs) {
                            Image(systemName: "bell.badge")
                            Text(String(localized: L10n.Settings.Notification.sendTestNotification.withLocale(locale)))
                        }
                    }
                    .padding(.leading, DT.Space.md)
                    .padding(.top, DT.Space.xs)
                }
            }

            Section {
                Toggle(
                    String(localized: L10n.Settings.Notification.enableSound.withLocale(locale)),
                    isOn: $manager.enableSound
                )

                if manager.enableSound {
                    HStack(spacing: DT.Space.sm) {
                        Picker(
                            String(localized: L10n.Settings.Notification.soundName.withLocale(locale)),
                            selection: $manager.soundName
                        ) {
                            ForEach(NotificationManager.systemSounds, id: \.self) { sound in
                                Text(sound).tag(sound)
                            }
                        }
                        .onChange(of: manager.soundName) { _, newSound in
                            manager.playSound(name: newSound)
                        }

                        Button {
                            manager.playSound()
                        } label: {
                            Image(systemName: "speaker.wave.2")
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.borderless)
                        .help(String(localized: L10n.Settings.Notification.playTestSound.withLocale(locale)))
                    }
                    .padding(.leading, DT.Space.md)
                }
            }

            Section(header: Text(remoteSetupTitle)) {
                VStack(alignment: .leading, spacing: DT.Space.xs) {
                    Picker(
                        String(localized: L10n.Settings.Notification.backendSelector.withLocale(locale)),
                        selection: $selectedBackend
                    ) {
                        ForEach(RemoteMultiplexerKind.allCases) { kind in
                            Text(kind.rawValue).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.bottom, 2)

                    Text(remoteSetupDesc)
                        .font(Font(DT.Font.small))
                        .foregroundColor(Color(theme.textSecondary))

                    HStack(spacing: DT.Space.sm) {
                        Text(setupCommand)
                            .font(Font(DT.Font.mono))
                            .foregroundColor(Color(theme.textPrimary))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .padding(.horizontal, DT.Space.sm)
                            .padding(.vertical, DT.Space.xs)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(theme.sidebar))
                            .cornerRadius(DT.Radius.sm)

                        Button {
                            let pb = NSPasteboard.general
                            pb.clearContents()
                            pb.setString(setupCommand, forType: .string)
                            isCopied = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                isCopied = false
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                                Text(isCopied ? L10n.Settings.Notification.copied : L10n.Settings.Notification.copyCommand)
                            }
                            .font(Font(DT.Font.small))
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
}
