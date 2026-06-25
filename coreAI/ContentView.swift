import SwiftUI

struct ContentView: View {
    @StateObject private var controller = DiffusionController()

    var body: some View {
        NavigationSplitView {
            controls
                .navigationSplitViewColumnWidth(min: 300, ideal: 340, max: 390)
        } detail: {
            output
        }
        .navigationTitle("Core AI Studio")
        .toolbar {
            ToolbarItemGroup {
                Button(action: controller.saveImage) {
                    Label("Save Image", systemImage: "square.and.arrow.down")
                }
                .disabled(controller.generatedImage == nil)
                .help("Save image")
            }
        }
    }

    private var controls: some View {
        Form {
            Section("Model") {
                LabeledContent("Stable Diffusion 1.5") {
                    Text(controller.modelName)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Button(action: controller.chooseModelFolder) {
                    Label("Choose Different Model", systemImage: "folder")
                }
            }

            Section("Prompt") {
                TextEditor(text: $controller.prompt)
                    .font(.body)
                    .frame(minHeight: 110)

                LabeledContent("Negative") {
                    TextField("Optional", text: $controller.negativePrompt, axis: .vertical)
                        .lineLimit(2...4)
                        .multilineTextAlignment(.leading)
                }
            }

            Section("Generation") {
                Stepper("Steps: \(controller.steps)", value: $controller.steps, in: 5...50, step: 1)

                LabeledContent("Guidance") {
                    HStack(spacing: 10) {
                        Slider(value: $controller.guidanceScale, in: 1...15, step: 0.5)
                        Text(controller.guidanceScale, format: .number.precision(.fractionLength(1)))
                            .monospacedDigit()
                            .frame(width: 34, alignment: .trailing)
                    }
                }

                LabeledContent("Seed") {
                    HStack(spacing: 8) {
                        TextField("Seed", value: $controller.seed, format: .number)
                            .monospacedDigit()
                        Button(action: controller.randomizeSeed) {
                            Image(systemName: "dice")
                        }
                        .buttonStyle(.borderless)
                        .help("Randomize seed")
                    }
                }
            }

            Section {
                if controller.state == .generating || controller.state == .loading {
                    Button(role: .cancel, action: controller.cancel) {
                        Label("Cancel", systemImage: "xmark")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button(action: controller.generate) {
                        Label("Generate", systemImage: "sparkles")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!controller.canGenerate)
                    .keyboardShortcut(.return, modifiers: .command)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var output: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
                .ignoresSafeArea()

            if let image = controller.generatedImage {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFit()
                    .padding(32)
            } else {
                ContentUnavailableView(
                    "No Image",
                    systemImage: "photo",
                    description: Text(controller.state.message)
                )
            }

            if controller.state == .generating || controller.state == .loading {
                VStack(spacing: 12) {
                    ProgressView(value: controller.progress)
                        .frame(width: 240)
                    Text(controller.state.message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(20)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .safeAreaInset(edge: .bottom) {
            statusBar
        }
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            Image(systemName: statusIcon)
                .foregroundStyle(statusColor)
            Text(controller.state.message)
                .lineLimit(1)
            Spacer()
            if controller.generatedImage != nil {
                Text("512 x 512")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .font(.caption)
        .padding(.horizontal, 14)
        .frame(height: 30)
        .background(.bar)
    }

    private var statusIcon: String {
        switch controller.state {
        case .failed: "exclamationmark.triangle.fill"
        case .generating, .loading: "circle.dotted"
        case .ready: "checkmark.circle.fill"
        case .noModel: "circle"
        }
    }

    private var statusColor: Color {
        switch controller.state {
        case .failed: .red
        case .ready: .green
        default: .secondary
        }
    }
}

#Preview {
    ContentView()
        .frame(width: 1120, height: 760)
}
