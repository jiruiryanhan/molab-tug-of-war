import SwiftUI
import PhotosUI

struct HomeView: View {
    @Environment(AppModel.self) private var app
    @State private var codeText = ""
    @State private var showCreate = false
    @State private var showPractice = false
    @State private var nfc = NFCService()

    var body: some View {
        @Bindable var app = app
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    ProfileCard()

                    onlineBanner

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Play with friends").font(.headline)
                        Button {
                            showCreate = true
                        } label: {
                            Label("Create a room", systemImage: "plus.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(!app.isOnline || app.busy)

                        HStack {
                            TextField("ROOM CODE or link", text: $codeText)
                                .textInputAutocapitalization(.characters)
                                .autocorrectionDisabled()
                                .font(.system(.title3, design: .monospaced))
                                .padding(10)
                                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
                                .onSubmit { Task { await app.join(code: codeText) } }
                            Button("Join") { Task { await app.join(code: codeText) } }
                                .buttonStyle(.bordered)
                                .controlSize(.large)
                                .disabled(!app.isOnline || app.busy || codeText.isEmpty)
                        }

                        Button {
                            nfc.scanForJoinLink { url in
                                if let url { app.handle(url: url) }
                            }
                        } label: {
                            Label("Tap an NFC tag to join", systemImage: "wave.3.right.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .disabled(!app.isOnline || !NFCService.isAvailable || nfc.isBusy)

                        Text("Or open a link a friend AirDrops you — it lands straight in the room.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Practice").font(.headline)
                        Button {
                            showPractice = true
                        } label: {
                            Label("Practice vs bots (offline)", systemImage: "figure.run")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        Text("Same rules, same physics, no network. Good for learning the tilt.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))

                    HowToPlay()
                }
                .padding()
            }
            .background(Palette.paper.ignoresSafeArea())
            .navigationTitle("Tug of War")
        }
        .sheet(isPresented: $showCreate) { CreateRoomSheet(practice: false) }
        .sheet(isPresented: $showPractice) { CreateRoomSheet(practice: true) }
        .alert("Hmm", isPresented: Binding(get: { app.errorMessage != nil }, set: { if !$0 { app.errorMessage = nil } })) {
            Button("OK") { app.errorMessage = nil }
        } message: {
            Text(app.errorMessage ?? "")
        }
        .alert("NFC", isPresented: Binding(get: { nfc.statusMessage != nil }, set: { if !$0 { nfc.statusMessage = nil } })) {
            Button("OK") { nfc.statusMessage = nil }
        } message: {
            Text(nfc.statusMessage ?? "")
        }
    }

    @ViewBuilder
    private var onlineBanner: some View {
        switch app.online {
        case .connecting:
            Label("Connecting…", systemImage: "antenna.radiowaves.left.and.right")
                .font(.footnote).foregroundStyle(.secondary)
        case .ready:
            Label("Online · anonymous Firebase sign-in", systemImage: "checkmark.circle.fill")
                .font(.footnote).foregroundStyle(.green)
        case .unavailable(let why):
            Label(why, systemImage: "exclamationmark.triangle.fill")
                .font(.footnote).foregroundStyle(.orange)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        }
    }
}

struct ProfileCard: View {
    @Environment(AppModel.self) private var app
    @State private var pickerItem: PhotosPickerItem?

    var body: some View {
        @Bindable var app = app
        HStack(spacing: 14) {
            PlayerDotView(color: Palette.red, initials: app.profile.initials, image: app.profile.photoImage, size: 72)
            VStack(alignment: .leading, spacing: 8) {
                TextField("Your name", text: $app.profile.name)
                    .font(.title3.bold())
                    .textFieldStyle(.roundedBorder)
                HStack {
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Label("Photo", systemImage: "photo")
                    }
                    if app.profile.photo != nil {
                        Button("Remove") { app.profile.photo = nil }
                    }
                    Spacer()
                    Toggle("Invert tilt", isOn: $app.profile.invertTilt)
                        .labelsHidden()
                        .overlay(alignment: .leading) {
                            Text("Invert tilt").font(.caption2).foregroundStyle(.secondary).offset(x: -62)
                        }
                }
                .font(.subheadline)
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
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

struct HowToPlay: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("How to play").font(.headline)
            Label("Tilt the phone toward the TUG! arrow to pull steadily.", systemImage: "iphone.gen3.radiowaves.left.and.right")
            Label("Swipe toward the arrow, tap the screen, or hit TUG! for a burst.", systemImage: "hand.draw")
            Label("Team Linear: drag the knot past your goal line.", systemImage: "arrow.left.and.right")
            Label("Circular: everyone is tied around a hole. Pull the others in. Last one standing wins.", systemImage: "circle.dashed")
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

struct CreateRoomSheet: View {
    let practice: Bool
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var mode: GameMode = .linear
    @State private var teamMode: TeamMode = .teams
    @State private var bots = 3

    var body: some View {
        NavigationStack {
            Form {
                Section("Arena") {
                    ForEach(GameMode.allCases) { m in
                        Button {
                            mode = m
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(m.title).bold()
                                    Text(m.subtitle).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if mode == m { Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint) }
                            }
                        }
                        .tint(.primary)
                    }
                }
                if mode == .circular {
                    Section("Players") {
                        Picker("Team mode", selection: $teamMode) {
                            ForEach(TeamMode.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        Text(teamMode == .teams
                             ? "Random teams, randomly seated around the ring."
                             : "Everyone for themselves. Last dot standing wins.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    Section("Players") {
                        Text("Players pick a team in the lobby, or the host splits everyone randomly.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if practice {
                    Section("Bots") {
                        Stepper("\(bots) bots", value: $bots, in: 1...9)
                    }
                }
                Section {
                    Button(practice ? "Start practice" : "Create room") {
                        Task {
                            if practice {
                                await app.startPractice(mode: mode, teamMode: teamMode, bots: bots)
                            } else {
                                await app.createRoom(mode: mode, teamMode: teamMode)
                            }
                            dismiss()
                        }
                    }
                    .bold()
                    .disabled(app.busy)
                }
            }
            .navigationTitle(practice ? "Practice" : "New room")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }
}
