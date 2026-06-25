import AppKit
import Combine
import CoreAIDiffusionPipeline
import Foundation
import ImageIO
import UniformTypeIdentifiers

@MainActor
final class DiffusionController: ObservableObject {
    enum PipelineState: Equatable {
        case noModel
        case ready
        case loading
        case generating
        case failed(String)

        var message: String {
            switch self {
            case .noModel: "Stable Diffusion 1.5 model is unavailable"
            case .ready: "Ready"
            case .loading: "Loading model"
            case .generating: "Generating"
            case .failed(let message): message
            }
        }
    }

    @Published var prompt = "A cinematic photograph of a lighthouse above a stormy sea at dusk"
    @Published var negativePrompt = "blurry, low quality, distorted"
    @Published var steps = 20
    @Published var guidanceScale = 7.5
    @Published var seed: UInt32 = 42
    @Published var state: PipelineState = .noModel
    @Published var progress = 0.0
    @Published var generatedImage: CGImage?
    @Published private(set) var modelURL: URL?

    private var pipeline: StableDiffusionPipeline?
    private var generationTask: Task<Void, Never>?
    private var hasSecurityScope = false
    private let bookmarkKey = "StableDiffusionModelBookmark"
    private let bundledModelName = "stable-diffusion-v1-5"

    var canGenerate: Bool {
        modelURL != nil && state != .loading && state != .generating && !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var modelName: String {
        modelURL?.lastPathComponent ?? "No model selected"
    }

    init() {
        if !restoreModelBookmark(), let bundledModelURL {
            selectModel(at: bundledModelURL, saveBookmark: false)
        }
    }

    func chooseModelFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose Stable Diffusion 1.5 Model"
        panel.prompt = "Choose"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        selectModel(at: url, saveBookmark: true)
    }

    func generate() {
        guard canGenerate else { return }
        generationTask?.cancel()

        let configuration = PipelineConfiguration(
            prompt: prompt.trimmingCharacters(in: .whitespacesAndNewlines),
            negativePrompt: negativePrompt.trimmingCharacters(in: .whitespacesAndNewlines),
            seed: seed,
            stepCount: steps,
            guidanceScale: Float(guidanceScale),
            schedulerType: .dpmSolverMultistep,
            lazyModelLoading: true
        )

        generationTask = Task { [weak self] in
            guard let self else { return }
            do {
                let activePipeline = try await self.loadPipelineIfNeeded()
                guard !Task.isCancelled else { return }

                self.state = .generating
                self.progress = 0
                let result = try await activePipeline.generateImages(configuration: configuration) { [weak self] update in
                    let fraction = Double(update.step + 1) / Double(max(update.totalSteps, 1))
                    Task { @MainActor in
                        self?.progress = fraction
                    }
                    return !Task.isCancelled
                }

                guard !Task.isCancelled else {
                    self.state = .ready
                    self.progress = 0
                    return
                }
                self.generatedImage = result.images.first
                self.progress = 1
                self.state = .ready
            } catch is CancellationError {
                self.state = self.modelURL == nil ? .noModel : .ready
                self.progress = 0
            } catch {
                self.state = .failed(error.localizedDescription)
                self.progress = 0
            }
        }
    }

    func cancel() {
        generationTask?.cancel()
    }

    func randomizeSeed() {
        seed = .random(in: .min ... .max)
    }

    func saveImage() {
        guard let generatedImage else { return }

        let panel = NSSavePanel()
        panel.title = "Save Generated Image"
        panel.nameFieldStringValue = "coreai-\(seed).png"
        panel.allowedContentTypes = [.png]
        guard panel.runModal() == .OK, let destinationURL = panel.url else { return }

        guard let destination = CGImageDestinationCreateWithURL(
            destinationURL as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            state = .failed("Could not create the output file")
            return
        }

        CGImageDestinationAddImage(destination, generatedImage, nil)
        if !CGImageDestinationFinalize(destination) {
            state = .failed("Could not write the PNG file")
        }
    }

    private func loadPipelineIfNeeded() async throws -> StableDiffusionPipeline {
        if let pipeline { return pipeline }
        guard let modelURL else { throw ModelError.noModel }

        state = .loading
        progress = 0
        let loaded = try await StableDiffusionPipeline.load(from: modelURL)
        pipeline = loaded
        return loaded
    }

    private func selectModel(at url: URL, saveBookmark: Bool) {
        stopAccessingCurrentModel()

        hasSecurityScope = url.startAccessingSecurityScopedResource()
        modelURL = url
        pipeline = nil
        generatedImage = nil
        progress = 0

        guard isModelDirectory(url) else {
            stopAccessingCurrentModel()
            modelURL = nil
            state = .failed("The selected folder does not contain an exported Core AI diffusion model")
            return
        }

        state = .ready
        if saveBookmark {
            do {
                let bookmark = try url.bookmarkData(
                    options: .withSecurityScope,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
                UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
            } catch {
                state = .failed("The model was selected, but its permission could not be saved")
            }
        }
    }

    private var bundledModelURL: URL? {
        Bundle.main.url(forResource: bundledModelName, withExtension: nil)
    }

    @discardableResult
    private func restoreModelBookmark() -> Bool {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return false }
        do {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: data,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            selectModel(at: url, saveBookmark: isStale)
            return modelURL != nil
        } catch {
            UserDefaults.standard.removeObject(forKey: bookmarkKey)
            return false
        }
    }

    private func isModelDirectory(_ url: URL) -> Bool {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: url.appendingPathComponent("metadata.json").path) {
            return true
        }
        guard let contents = try? fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return false }
        return contents.contains { $0.pathExtension == "aimodel" }
    }

    private func stopAccessingCurrentModel() {
        if hasSecurityScope {
            modelURL?.stopAccessingSecurityScopedResource()
        }
        hasSecurityScope = false
    }

    enum ModelError: LocalizedError {
        case noModel

        var errorDescription: String? {
            "Choose a Stable Diffusion model folder first"
        }
    }
}
