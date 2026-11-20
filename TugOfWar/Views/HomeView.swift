import SwiftUI
import PhotosUI

struct HomeView: View {
    @Environment(AppModel.self) private var app
    @State private var codeText = ""
    @State private var showCreate = false
    @State private var showPractice = false
    @State private var nfc = NFCService()

    private var typedCode: String? { RoomCode.normalize(codeText) }

    var body: some View {
        NavigationStack {
            Form {
                ProfileSection()

                Section {
                    Button {
                        showCreate = true
                    } label: {
                        Label("Create a Room", systemImage: "plus")
                    }
                    .disabled(!app.isOnline || app.busy)

                    LabeledContent("Room Code") {
                        TextField("ABCD", text: $codeText)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .monospaced()
                            .multilineTextAlignment(.trailing)
                            .submitLabel(.join)
                            .onSubmit(joinTypedCode)
                    }

                    Button("Join Room", action: joinTypedCode)
                        .disabled(!app.isOnline || app.busy || typedCode == nil)

                    if NFCService.isAvailable {
                        Button {
                            nfc.scanForJoinLink { url in
                                if let url { app.handle(url: url) }
                            }
                        } label: {
                            Label("Scan NFC Tag", systemImage: "wave.3.right")
                        }
                        .disabled(!app.isOnline || nfc.isBusy)
                    }
                } header: {
                    Text("Play with Friends")
                } footer: {
                    connectionFooter
                }

                Section {
                    Button {
                        showPractice = true
                    } label: {
                        Label("Practice with Bots", systemImage: "figure.run")
                    }
                    .disabled(app.busy)
                } header: {
                    Text("Practice")
                } footer: {
                    Text("Same rules and physics, without a network.")
                }

                Section("How to Play") {
                    Label("Tilt the phone toward the TUG! arrow to pull steadily.",
                          systemImage: "iphone.gen3.radiowaves.left.and.right")
                    Label("Swipe toward the arrow, tap the field, or press TUG! for a burst.",
                          systemImage: "hand.draw")
                    Label("Team Linear: pull the knot past your goal line.",
                          systemImage: "arrow.left.and.right")
                    Label("Circular: whoever is dragged into the hole is out. Last one standing wins.",
                          systemImage: "circle.dashed")
                }
                .font(.subheadline)
            }
            .navigationTitle("Tug of War")
        }
        .sheet(isPresented: $showCreate) { NewRoomView(practice: false) }
        .sheet(isPresented: $showPractice) { NewRoomView(practice: true) }
        .alert("Can’t Join", isPresented: Binding(get: { app.errorMessage != nil },
                                                  set: { if !$0 { app.errorMessage = nil } })) {
            Button("OK") { app.errorMessage = nil }
        } message: {
            Text(app.errorMessage ?? "")
        }
        .alert("NFC", isPresented: Binding(get: { nfc.statusMessage != nil },
                                           set: { if !$0 { nfc.statusMessage = nil } })) {
            Button("OK") { nfc.statusMessage = nil }
        } message: {
            Text(nfc.statusMessage ?? "")
        }
    }

    private func joinTypedCode() {
        guard let code = typedCode else { return }
        Task { await app.join(code: code) }
    }

    @ViewBuilder
    private var connectionFooter: some View {
        switch app.online {
        case .connecting:
            Text("Connecting…")
        case .ready:
            Text("Signed in anonymously. A friend can also AirDrop you a room link, which opens straight into the room.")
        case .unavailable(let why):
            Label(why, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
    }
}

/// Name, photo and tilt preference, stored on this phone.
struct ProfileSection: View {
    @Environment(AppModel.self) private var app
    @State private var pickerItem: PhotosPickerItem?

    var body: some View {
        @Bindable var app = app
        Section {
            HStack(spacing: 16) {
                PlayerDotView(color: .accentColor, initials: app.profile.initials,
                              image: app.profile.photoImage, size: 56)
                TextField("Your Name", text: $app.profile.name)
                    .font(.title3)
            }
            PhotosPicker(selection: $pickerItem, matching: .images) {
                Label(app.profile.photo == nil ? "Choose Photo" : "Change Photo", systemImage: "photo")
            }
            if app.profile.photo != nil {
                Button("Remove Photo", role: .destructive) { app.profile.photo = nil }
            }
            Toggle("Invert Tilt", isOn: $app.profile.invertTilt)
        } header: {
            Text("Player")
        } footer: {
            Text("Your dot shows your photo, or your initials when there is none.")
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    app.profile.photo = Profile.encode(image)
                }
                pickerItem = nil
            }
        }
    }
}

/// Create an online room, or start an offline practice round.
struct NewRoomView: View {
    let practice: Bool
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var mode: GameMode = .linear
    @State private var teamMode: TeamMode = .teams
    @State private var bots = 3

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Arena", selection: $mode) {
                        ForEach(GameMode.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("Arena")
                } footer: {
                    Text(mode.subtitle)
                }

                Section {
                    if mode == .circular {
                        Picker("Teams", selection: $teamMode) {
                            ForEach(TeamMode.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }
                    if practice {
                        Stepper("Bots: \(bots)", value: $bots, in: 1...9)
                    }
                } header: {
                    Text("Players")
                } footer: {
                    Text(playersFooter)
                }
            }
            .navigationTitle(practice ? "Practice" : "New Room")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(practice ? "Start" : "Create") {
                        Task {
                            if practice {
                                await app.startPractice(mode: mode, teamMode: teamMode, bots: bots)
                            } else {
                                await app.createRoom(mode: mode, teamMode: teamMode)
                            }
                            dismiss()
                        }
                    }
                    .disabled(app.busy)
                }
            }
        }
    }

    private var playersFooter: String {
        switch mode {
        case .linear:
            return "Players pick a side in the lobby, or the host splits everyone randomly."
        case .circular:
            return teamMode == .teams
                ? "Teams and seats around the ring are drawn randomly when the round starts."
                : "Everyone for themselves. Seats are drawn randomly when the round starts."
        }
    }
}
