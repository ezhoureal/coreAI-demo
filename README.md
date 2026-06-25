# Core AI Studio

A macOS 27 SwiftUI app that runs Stable Diffusion 1.5 locally through Apple's Core AI framework and the official `CoreAIDiffusion` Swift package.

## Requirements

- Apple silicon Mac running macOS 27
- Xcode 27
- Enough free disk space for the source model and exported Core AI assets
- `uv` 0.9 or newer for model export

## Export Stable Diffusion 1.5

Apple does not publish a PyPI package named `coreai`. Update `uv`, then use the exporter from Apple's `coreai-models` repository:

```bash
uv self update
./script/export_sd15.sh
```

If `uv self update` is unavailable because `uv` was installed with Homebrew, run `brew upgrade uv` instead.

The script clones Apple's exporter into the ignored `.tools/` directory and writes the converted model to `.tools/coreai-models/exports/stable-diffusion-v1-5`. It downloads the source weights from Hugging Face and may take substantial disk space and time.

The Xcode project copies that complete export into the app bundle, including `metadata.json`, the tokenizer, and all four `.aimodel` components. The app loads the bundled model automatically. Use **Choose Different Model** only to override it with another compatible export.

The equivalent manual commands are:

```bash
git clone https://github.com/apple/coreai-models.git .tools/coreai-models
cd .tools/coreai-models
uv run --no-dev coreai.diffusion.export \
  runwayml/stable-diffusion-v1-5 \
  --output-dir exports
```

## Build and run

Open `coreAI.xcodeproj` in Xcode 27, select **My Mac**, and run the `coreAI` scheme. From the terminal:

```bash
./script/build_and_run.sh
```

The first build resolves Apple's [`coreai-models`](https://github.com/apple/coreai-models) package and its Swift dependencies.
