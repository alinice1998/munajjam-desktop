# Munajjam Desktop | AI-Powered Quranic Audio-Text Alignment Platform

[![Flutter](https://img.shields.io/badge/Flutter-Desktop%20Windows-02569B?logo=flutter&logoColor=white)](https://flutter.dev/)
[![Python](https://img.shields.io/badge/Python-3.9%2B-3776AB?logo=python&logoColor=white)](https://python.org)
[![FastAPI](https://img.shields.io/badge/FastAPI-Local%20Engine-009688?logo=fastapi&logoColor=white)](https://fastapi.tiangolo.com/)
[![ONNX Runtime](https://img.shields.io/badge/ONNX%20Runtime-DirectML%20%2F%20CUDA-005CED?logo=onnx&logoColor=white)](https://onnxruntime.ai/)
[![License](https://img.shields.io/badge/License-Apache%202.0-green.svg)](LICENSE)

An advanced, open-source workstation designed for precise, millisecond-accurate forced alignment of Holy Quran recitations at the Ayah, Waqf (breath), and Word levels.

**Munajjam Desktop** bridges modern **Flutter Desktop** UI aesthetics with a cutting-edge **Python & ONNX Runtime** neural audio processing backend, offering real-time waveform visualization, interactive time correction (QA Editor), and batch processing for complete Quran recitations (Khatmas).

---

## 🌟 Alignment Engines

Munajjam offers tailored alignment engines for different hardware setups and recitation styles:

| Engine | Identifier | Status | Technology & Highlights |
| :--- | :---: | :---: | :--- |
| **High-Precision Hybrid Engine (Munajjam v2)** | `hybrid` | **Default (Recommended)** | Neural breath & waqf segmentation via `recitation-segmenter-v2` (GPU accelerated) + Zipformer v3 landmark detection + Wav2Vec2 forced micro-alignment. |
| **Smart Experimental Engine (Fuzzy Matching)** | `hybrid_fuzzy` | **Experimental** | Neural breath segmentation + Zipformer CTC free-text decoding with dynamic Levenshtein fuzzy matching. Ideal for slow *Tahqiq* recitations and verse repetitions. |
| **Classic Zipformer Engine** | `zipformer` | **Lightweight & Fast** | Direct phoneme/word alignment powered by `QuranLab/zipformer_p-arabic-v3`. Runs lightning-fast on any standard CPU without requiring dedicated GPU hardware. |
| **Pre-computed JSON Import** | `json_file` | **Import Tool** | Instantly load, visualize, audit, and fine-tune existing alignment JSON files in the interactive waveform editor. |

---

## 🚀 Key Features

* **Desktop Native Performance**: Built with Flutter for Windows, featuring smooth animations, modern dark mode, and responsive layout.
* **Smart Filename Surah Detection**: Intelligent heuristic detector recognizes Surah names and numbers from complex filename patterns (e.g., `_001`, `سورة يس`, `طه.mp3`, `112_Al-Ikhlas`).
* **Interactive Waveform & QA Editor**: Visual timeline showing word and ayah boundaries with zoom, drag-and-drop boundary adjustment, playback scrubbing, and instant playback.
* **Karaoke-Style Audio Player**: Synchronized word-by-word visual highlight during playback.
* **Batch Khatma Alignment**: Queue dozens or hundreds of Surahs for automated alignment with automatic computer shutdown upon completion and export manifest generation.
* **Dual Riwaya Support**: Built-in, fully verified Quranic text and glyph tokens for both **Hafs 'an 'Asim** and **Warsh 'an Nafi'**.
* **Bilingual UI**: Complete Arabic and English interface with instantaneous runtime locale switching.
* **Hardware-Accelerated Backend**: Runs ONNX models via Microsoft DirectML (supporting modern AMD, Intel, and NVIDIA GPUs) or CUDA.

---

## 🏗️ Repository Architecture

```text
munajjam-desktop/
├── backend/                      # Python AI Engine & Backend Server
│   ├── hybrid_aligner/           # Neural pipeline, segmentation & forced aligner
│   ├── munajjam_server.py        # Local FastAPI REST API server
│   ├── neural_aligner.py         # Zipformer neural alignment wrapper
│   ├── download_models.py        # Script to download pre-trained models
│   ├── upload_models_to_hf.py    # Script to publish models to Hugging Face
│   └── requirements.txt          # Python dependencies
├── lib/                          # Flutter Desktop source code
│   ├── core/                     # Architecture, themes, localization, and server manager
│   ├── models/                   # Data structures and Surah detector
│   ├── providers/                # State management (ChangeNotifiers)
│   ├── services/                 # Audio, API, and batch services
│   └── views/                    # Screens, waveform editor, and dialogs
├── assets/                       # Quran texts (Hafs/Warsh) and application icons
├── data/                         # Shared Quran reference datasets
├── test/                         # Automated unit and integration tests
├── windows/                      # Windows runner and native C++ configurations
├── installer.iss                 # Inno Setup Windows installer script
├── run_local.bat                 # One-click launcher for the backend server
├── pubspec.yaml                  # Flutter dependencies and asset definitions
└── README.md
```

---

## 🛠️ Getting Started

### Prerequisites

* [Flutter SDK](https://flutter.dev/docs/get-started/install/windows) (v3.19+ recommended)
* [Python 3.9 - 3.12](https://www.python.org/downloads/)
* [Git](https://git-scm.com/)

### 1. Set Up the Python AI Backend

```bash
# Navigate to the backend directory
cd backend

# Install Python requirements
pip install -r requirements.txt

# Download required AI models
python download_models.py

# Start the local server
python munajjam_server.py
```
*(On Windows, you can also double-click `run_local.bat` in the project root to perform this automatically).*

### 2. Run the Desktop Application

From the root directory:

```bash
# Fetch Flutter packages
flutter pub get

# Launch Flutter Desktop in Debug Mode
flutter run -d windows
```

The application will automatically detect, initialize, and communicate with the local backend server.

---

## 🧠 AI Models

Pre-exported, GPU-optimized ONNX models for Munajjam are available on Hugging Face:

* **Repository**: [`Alimalas/munajjam-onnx-models`](https://huggingface.co/Alimalas/munajjam-onnx-models)
* **Zipformer v3**: `Quran-Lab/zipformer_p-arabic-v3`
* **Recitation Segmenter v2**: `obadx/recitation-segmenter-v2`
* **Silero VAD**: Voice activity detection engine

---

## 📦 Building the Windows Standalone Installer

The desktop application, embedded runtime, and engines can be packaged into a single, offline Windows installer using **Inno Setup**:

1. Build the Flutter Windows Release executable:
   ```bash
   flutter build windows --release
   ```
2. Open `installer.iss` in **Inno Setup Compiler** and click **Compile**.
3. The standalone setup executable will be generated in `installer_output/`.

---

## 👨‍💻 Author & Credits

* **Author**: Ali Malas (علي ملص) - [Itqan Projects](https://github.com/alinice1998)
* Dedicated to serving the Holy Quran, its reciters, researchers, and developers in Arabic Speech Processing.

## 📄 License

This project is licensed under the [Apache License 2.0](LICENSE).
