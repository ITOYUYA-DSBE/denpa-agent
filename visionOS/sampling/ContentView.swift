//
//  ContentView.swift
//  sampling
//
//  Denpa Agent v1.2
//

import SwiftUI
import Combine
import RealityKit

struct RunResponse: Decodable {
    let ok: Bool
    let jobId: String
    let status: String
    let engine: String?
    let accessLevel: String?
}

struct StatusResponse: Decodable {
    let id: String
    let repo: String
    let prompt: String
    let engine: String?
    let accessLevel: String?
    let status: String
    let stdout: String?
    let stderr: String?
}

@MainActor
final class DenpaViewModel: ObservableObject {
    @Published var prompt: String = "Reply with exactly: OK"

    @Published var selectedChannel: String = "codex"
    @Published var selectedAccessLevel: String = "listen"

    @Published var isReceiving = false
    @Published var jobId: String?
    @Published var stateText = "Idle"
    @Published var transmissionText = ""
    @Published var errorText = ""

    // 必要に応じて Tailscale IP / ローカルIP に変更
    private let baseURL = "http://100.69.172.128:8787"
    private let repo = "sampling"

    func transmit() async {
        guard !isReceiving else { return }

        isReceiving = true
        jobId = nil
        transmissionText = ""
        errorText = ""
        stateText = "Receiving..."

        do {
            let response = try await startTransmission()
            jobId = response.jobId
            stateText = "Receiving..."

            try await pollUntilComplete(jobId: response.jobId)
        } catch {
            errorText = error.localizedDescription
            stateText = "Failed"
            isReceiving = false
        }
    }

    private func startTransmission() async throws -> RunResponse {
        guard let url = URL(string: "\(baseURL)/run") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = [
            "repo": repo,
            "prompt": prompt,
            "engine": selectedChannel,
            "accessLevel": selectedAccessLevel
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTP(response: response, data: data)

        return try JSONDecoder().decode(RunResponse.self, from: data)
    }

    private func fetchStatus(jobId: String) async throws -> StatusResponse {
        guard let url = URL(string: "\(baseURL)/status/\(jobId)") else {
            throw URLError(.badURL)
        }

        let (data, response) = try await URLSession.shared.data(from: url)
        try validateHTTP(response: response, data: data)

        return try JSONDecoder().decode(StatusResponse.self, from: data)
    }

    private func pollUntilComplete(jobId: String) async throws {
        while true {
            let status = try await fetchStatus(jobId: jobId)

            if status.status == "completed" {
                stateText = "Completed"
                transmissionText = status.stdout ?? "(empty transmission)"
                isReceiving = false
                return
            }

            if status.status == "failed" {
                stateText = "Failed"
                let stderr = status.stderr ?? "(no stderr)"
                throw NSError(
                    domain: "DenpaAgent",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Transmission failed: \(stderr)"]
                )
            }

            stateText = "Receiving..."
            try await Task.sleep(nanoseconds: 2_000_000_000)
        }
    }

    private func validateHTTP(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "(unreadable body)"
            throw NSError(
                domain: "DenpaAgent",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode): \(body)"]
            )
        }
    }
}

struct ContentView: View {
    @StateObject private var vm = DenpaViewModel()
    @FocusState private var promptFocused: Bool

    private let denpaGreen = Color(red: 0.68, green: 1.0, blue: 0.18)
    private let denpaGreenDim = Color(red: 0.22, green: 0.36, blue: 0.10)
    private let deepBlack = Color(red: 0.01, green: 0.012, blue: 0.01)
    private let panelDark = Color(red: 0.055, green: 0.062, blue: 0.055)
    private let panelGray = Color(red: 0.11, green: 0.12, blue: 0.105)
    private let textSoft = Color.white.opacity(0.82)
    private let textDim = Color.white.opacity(0.55)
    private let possessPink = Color(red: 0.78, green: 0.32, blue: 1.0)

    var body: some View {
        ZStack {
            panelDark.opacity(0.96)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    headerView

                    cubeReceiverView

                    channelView

                    accessLevelView

                    promptView

                    transmitButton

                    stateView

                    transmissionView

                    Spacer(minLength: 16)
                }
                .padding(24)
                .frame(width: 640, alignment: .leading)
            }
            .scrollContentBackground(.hidden)
        }
    }

    private var backgroundView: some View {
        LinearGradient(
            colors: [
                Color.black,
                deepBlack,
                Color(red: 0.025, green: 0.035, blue: 0.018)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
        .overlay(
            RadialGradient(
                colors: [
                    denpaGreen.opacity(0.16),
                    .clear
                ],
                center: .topTrailing,
                startRadius: 40,
                endRadius: 620
            )
            .ignoresSafeArea()
        )
    }

    private var headerView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Denpa Agent 📡")
                .font(.largeTitle)
                .bold()
                .foregroundStyle(.white)

            Text("A spatial receiver for local AI agents.")
                .font(.headline)
                .foregroundStyle(textDim)
        }
    }

    private var cubeReceiverView: some View {
        HStack(alignment: .center, spacing: 20) {
            ZStack {
                RoundedRectangle(cornerRadius: 22)
                    .fill(denpaGreen.opacity(vm.isReceiving ? 0.16 : 0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22)
                            .stroke(
                                denpaGreen.opacity(vm.isReceiving ? 0.92 : 0.36),
                                lineWidth: vm.isReceiving ? 2 : 1
                            )
                    )
                    .shadow(
                        color: denpaGreen.opacity(vm.isReceiving ? 0.88 : 0.28),
                        radius: vm.isReceiving ? 30 : 14
                    )
                    .frame(width: 150, height: 150)

                TimelineView(.animation) { timeline in
                    let time = timeline.date.timeIntervalSinceReferenceDate

                    let jitterX = vm.isReceiving ? sin(time * 70) * 2.2 : 0
                    let jitterY = vm.isReceiving ? cos(time * 86) * 1.8 : 0
                    let jitterZ = vm.isReceiving ? sin(time * 52) * 1.4 : 0

                    let tiltX = vm.isReceiving ? sin(time * 46) * 2.4 : 0
                    let tiltY = vm.isReceiving ? cos(time * 58) * 3.2 : 0

                    let pulse = vm.isReceiving ? 1.0 + sin(time * 16) * 0.035 : 1.0

                    Model3D(named: "cube") { model in
                        model
                            .resizable()
                            .scaledToFit()
                            .padding(18)
                    } placeholder: {
                        ProgressView()
                            .tint(denpaGreen)
                    }
                    .frame(width: 125, height: 125)
                    .scaleEffect(pulse)
                    .offset(x: jitterX, y: jitterY)
                    .rotation3DEffect(
                        .degrees(tiltX),
                        axis: (x: 1, y: 0, z: 0)
                    )
                    .rotation3DEffect(
                        .degrees(tiltY + jitterZ),
                        axis: (x: 0, y: 1, z: 0)
                    )
                }
            }

            VStack(alignment: .leading, spacing: 9) {
                Text(vm.isReceiving ? "Receiving signal..." : "Receiver idle")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(textSoft)

                Text("Tune into a local agent and transmit a prompt.")
                    .font(.footnote)
                    .foregroundStyle(textDim)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(denpaGreen)
                            .frame(width: 8, height: 8)
                            .shadow(color: denpaGreen.opacity(0.8), radius: 8)

                        Text("Mac Signal: Online")
                            .font(.footnote)
                            .foregroundStyle(textDim)
                    }

                    HStack(spacing: 8) {
                        Circle()
                            .fill(vm.isReceiving ? denpaGreen : Color.gray.opacity(0.8))
                            .frame(width: 8, height: 8)
                            .shadow(
                                color: vm.isReceiving ? denpaGreen.opacity(0.9) : .clear,
                                radius: 8
                            )

                        Text(vm.stateText)
                            .font(.footnote)
                            .foregroundStyle(textDim)
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(panelGray.opacity(0.55))
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(.white.opacity(0.05), lineWidth: 1)
                )
        )
    }

    private var channelView: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Channel")

            HStack(spacing: 12) {
                Button {
                    vm.selectedChannel = "codex"
                } label: {
                    Text("Codex")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .tint(vm.selectedChannel == "codex" ? denpaGreen : Color.gray.opacity(0.55))
                .foregroundStyle(vm.selectedChannel == "codex" ? .black : .white)

                Button {
                    vm.selectedChannel = "claude"
                } label: {
                    Text("Claude Code")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .tint(vm.selectedChannel == "claude" ? denpaGreen : Color.gray.opacity(0.55))
                .foregroundStyle(vm.selectedChannel == "claude" ? .black : .white)
            }
        }
    }

    private var accessLevelView: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Access Level")

            HStack(spacing: 12) {
                accessButton(
                    title: "Listen",
                    value: "listen",
                    tint: denpaGreen,
                    selectedTextColor: .black
                )

                accessButton(
                    title: "Touch",
                    value: "touch",
                    tint: denpaGreen,
                    selectedTextColor: .black
                )

                accessButton(
                    title: "Possess",
                    value: "possess",
                    tint: possessPink,
                    selectedTextColor: .white
                )
            }

            Text(accessDescription)
                .font(.footnote)
                .foregroundStyle(textDim)
        }
    }

    private func accessButton(
        title: String,
        value: String,
        tint: Color,
        selectedTextColor: Color
    ) -> some View {
        let isSelected = vm.selectedAccessLevel == value

        return Button {
            vm.selectedAccessLevel = value
        } label: {
            Text(title)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
        }
        .buttonStyle(.borderedProminent)
        .tint(isSelected ? tint : Color.gray.opacity(0.55))
        .foregroundStyle(isSelected ? selectedTextColor : .white)
    }

    private var accessDescription: String {
        switch vm.selectedAccessLevel {
        case "listen":
            return "Listen: receive answers without intentionally modifying files."
        case "touch":
            return "Touch: allow the agent to edit files."
        case "possess":
            return "Possess: allow stronger agent actions. Use only in trusted repos."
        default:
            return ""
        }
    }

    private var promptView: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Prompt")

            HStack(alignment: .top, spacing: 12) {
                TextField("Transmit a signal to your agent...", text: $vm.prompt, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(3...8)
                    .focused($promptFocused)
                    .foregroundStyle(.white)
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.black.opacity(0.55))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(denpaGreen.opacity(promptFocused ? 0.8 : 0.18), lineWidth: 1)
                            )
                    )

                Button {
                    promptFocused = true
                } label: {
                    Image(systemName: "mic.fill")
                        .font(.title3)
                        .padding(12)
                }
                .buttonStyle(.borderedProminent)
                .tint(denpaGreen)
                .foregroundStyle(.black)
                .accessibilityLabel("Focus prompt for voice input")
            }

            Text("Tip: Focus the prompt field, then use Vision Pro’s system dictation.")
                .font(.footnote)
                .foregroundStyle(textDim)
        }
    }

    private var transmitButton: some View {
        Button {
            Task {
                await vm.transmit()
            }
        } label: {
            Text(vm.isReceiving ? "Receiving..." : "Transmit")
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
        }
        .buttonStyle(.borderedProminent)
        .tint(vm.isReceiving ? denpaGreenDim : denpaGreen)
        .foregroundStyle(.black)
        .shadow(color: denpaGreen.opacity(vm.isReceiving ? 0.65 : 0.38), radius: vm.isReceiving ? 22 : 12)
        .disabled(
            vm.isReceiving ||
            vm.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        )
    }

    private var stateView: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("State")

            Text(vm.stateText)
                .font(.body)
                .foregroundStyle(textSoft)

            HStack(spacing: 12) {
                Text("Channel: \(channelLabel)")
                Text("Access: \(accessLabel)")
            }
            .font(.footnote)
            .foregroundStyle(textDim)

            if let jobId = vm.jobId {
                Text("Transmission ID: \(jobId)")
                    .font(.footnote)
                    .foregroundStyle(textDim)
                    .textSelection(.enabled)
            }

            if !vm.errorText.isEmpty {
                Text("Interference")
                    .font(.headline)
                    .foregroundStyle(possessPink)

                Text(vm.errorText)
                    .foregroundStyle(possessPink)
                    .textSelection(.enabled)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(panelGray.opacity(0.42))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(.white.opacity(0.05), lineWidth: 1)
                )
        )
    }

    private var transmissionView: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Transmission")

            ScrollView {
                Text(vm.transmissionText.isEmpty ? "No transmission yet." : vm.transmissionText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(textSoft)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 320)
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.black.opacity(0.48))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(denpaGreen.opacity(0.16), lineWidth: 1)
                    )
            )
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.headline)
            .foregroundStyle(textSoft)
    }

    private var channelLabel: String {
        vm.selectedChannel == "claude" ? "Claude Code" : "Codex"
    }

    private var accessLabel: String {
        switch vm.selectedAccessLevel {
        case "listen":
            return "Listen"
        case "touch":
            return "Touch"
        case "possess":
            return "Possess"
        default:
            return vm.selectedAccessLevel
        }
    }
}

#Preview {
    ContentView()
}
