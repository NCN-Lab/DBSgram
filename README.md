# Multimodal Biomarker-Guided Deep Brain Stimulation Programming in Parkinson’s Disease: The DBSgram Framework


## General Information

This repository contains the code and interactive software suite supporting the manuscript:

> **"Multimodal Biomarker-Guided Deep Brain Stimulation Programming in Parkinson’s Disease: The DBSgram Framework"**  
> Pedro Melo\*, Eduardo Carvalho, Andreia M. Oliveira, Ricardo Peres, Carolina Soares, Maria J. Rosas, Adriana Arrais, Rita Vieira, Daniel Dias, João P. S. Cunha, Manuel J. Ferreira-Pinto, & Paulo Aguiar (\*)  
> *Currently under review for publication in a Q1 Journal in Rehabilitation Engineering.*  
>  
> **Core Maintainers:** Pedro Melo\*, Eduardo Carvalho, Paulo Aguiar  
> **Correspondence to:** [pauloaguiar@i3s.up.pt](mailto:pauloaguiar@i3s.up.pt)  
>  
> **Preprint (medRxiv):** [https://doi.org/10.64898/2026.03.29.26349663](https://doi.org/10.64898/2026.03.29.26349663)

---

## Highlights: Video Demonstration, User Guide & Runnable Examples

* **Video Demonstration:** A complete walkthrough demonstrating the DBSgram GUI pipelines in action (showing data ingestion, sub-second cross-modal synchronization, SVD cardiac artifact removal, kinematic cycle auditing, and final PDF compilation) is available in the repository: 👉 **[`VIDEO_DEMO`](./VideoDemo_DBSgram.mp4)**
* **Step-by-Step User Guide:** Detailed operational instructions for navigating the graphical interfaces and formatting input telemetry are provided in: 👉 **[`USER_GUIDE`](./UserGuide_DBSgram_Final.pdf)**
* **Runnable Clinical Example Datasets:** Ready-to-run, anonymized multimodal patient recordings (`sub013`, `sub014`, `sub017`) combining Medtronic Percept™ LFP JSON streams, 4-sensor wearable IMU CSV packs, and clinical scoring logs are provided in: 👉 **[`data/`](./data/)**

---

## 🛠️ Computational Tools & Repository Structure

The repository is organized into modular preprocessing, auditing, and reporting packages launched from a centralized master interface:

```text
DBSgram_Toolbox/
├── DBSgram_MainUI.m                     # Master entry-point GUI orchestrating the DBSgram workflow
├── DBSgram_setup.m                      # File to double-check the correct linkage to DBScope
├── apps/                                # Modular graphical user interfaces for each pipeline stage
│   ├── DBSgram_DataQualityUI.m          # Stage 1: Raw telemetry ingestion, dropout repair & task mapping
│   ├── DBSgram_DataQualityPart2UI.m     # Stage 2: Stimulation plateau & protocol completeness auditor
│   ├── DBSgram_SyncUI.m                 # Prominence-driven sub-second LFP <-> IMU synchronization UI
│   ├── DBSgram_EcgCleanUI.m             # Interactive SVD subspace cardiac (ECG) artifact removal tool
│   ├── DBSgram_KinematicSelectorUI.m    # Automated & manual cycle-level kinematic sweep segmentation
│   ├── DBSgram_KinematicsClinicalUI.m   # Symptom-specific feature extraction (Tremor, Rigidity, Bradykinesia)
│   └── DBSgram_ClinicalOverUI.m         # UPDRS integration & multi-page vector A4 DBSgram PDF compiler
│
├── data/                                # Pre-packaged clinical example datasets for validation & testing
│   ├── sub013/                          # Bilateral STN LFP + 4-sensor IMU titration dataset
│   ├── sub014/                          # Bilateral STN LFP + 4-sensor IMU titration dataset
│   └── sub017/                          # Bilateral STN LFP + 4-sensor IMU titration dataset
│
├── external/
│   └── DBScope/                          # External NCN-Lab core library for Percept JSON signal parsing
│
└── utils/
   └── DBSgram_ReportEngine.m/           # Engine integrating all retrieved information, calculating metrics and formatting the report
```

## 📁 Detailed Folder Descriptions
### 1. **[`apps/`](./apps/)** — Interactive Signal Processing & Auditing Suite
Contains the human-in-the-loop MATLAB App Designer/UIFigure modules that translate raw neurophysiological and inertial streams into standardized clinical biomarkers:

+ `DBSgram_DataQualityUI.m` & `DBSgram_DataQualityPart2UI.m`: Dual-stage quality control and cross-alignment auditors performing packet-drop interpolation, stimulation-aware task auto-mapping, and titration step verification (minimum 15 s plateau validation).

+ `DBSgram_SyncUI.m`: Prominence-driven bilateral alignment workspace that co-registers the Implantable Pulse Generator (IPG) master clock with wearable IMU timelines using percussive synchronization transients.

+ `DBSgram_EcgCleanUI.m`: Interactive Singular Value Decomposition (SVD) subspace projection interface for isolating and suppressing volume-conducted cardiac (ECG) QRS complexes from subthalamic LFPs without distorting beta-band activity.

+ `DBSgram_KinematicSelectorUI.m` & `DBSgram_KinematicsClinicalUI.m`: Interactive cycle segmentation and feature extraction engines for quantifying Tremor (band-limited accelerometric power), Wrist Rigidity (Range of Motion and 4–8 Hz Cogwheel RMS Ratio across passive and Froment-activated sweeps), and Bradykinesia (mean opening excursion and asymmetry ratio).

  `DBSgram_ClinicalOverUI.m`: Synthesizes electrophysiological beta-band suppression curves, objective wearable kinematics, and clinician-rated UPDRS.xlsx scores into a compiled, multi-page vector A4 DBSgram PDF report.

### 2. **[`data/`](./data/)** — Example Clinical Titration Datasets
Contains de-identified clinical monopolar review sessions (sub013, sub014, sub017) recorded during routine postoperative DBS programming, ready for immediate loading via DBSgram_MainUI.

### 3. **[`external/DBScope/`](./external/DBScope/)** — Core LFP Parsing Dependency
Submodule linking to the NCN-Lab DBScope library, responsible for decoding raw Medtronic Percept™ BrainSense JSON files, extracting packet timing metadata, and reconstructing continuous LFP time series.

### 4. **[`utils`](./utils)** - Engine for DBSgram Generation
Contains the script used to generate the final DBSgram report

## 💻 System Requirements & Dependencies
If you are using the standalone compiled application, you can skip the MATLAB requirements below, as all dependencies are handled automatically during installation.

For users running the MATLAB source code, please ensure the following are installed:

+ MATLAB R2025a (or a more recent version)
+ DSP System Toolbox
+ Optimization Toolbox
+ Signal Processing Toolbox
+ Statistics and Machine Learning Toolbox
+ Wavelet Toolbox

## 🚀 Installation, Setup & Launching
This toolbox relies on the DBScope core library (external/DBScope) as an external dependency. You can download and configure the toolbox using either of the two methods below:

### + Option A: Direct ZIP Download (Recommended for Non-Git Users)
Download the DBSgram_Main repository by clicking the green <> Code button on GitHub and selecting Download ZIP, then unzip it on your computer.

Because GitHub ZIP downloads do not automatically bundle external submodules, the external/DBScope folder will initially be empty.

Go to https://github.com/NCN-Lab/DBScope, click <> Code -> Download ZIP, and unzip the downloaded file.

Move the unzipped contents into DBSgram_Main/external/DBScope (ensure the folder is named DBScope and not DBScope-main).


### + Option B: Command Line Clone (Recommended for Developers)
To clone the repository and automatically fetch the DBScope submodule in a single step, run:

> git clone --recurse-submodules [(https://github.com/NCN-Lab/DBSgram](https://github.com/NCN-Lab/DBSgram)



## Troubleshooting Empty Submodules
If you already cloned the repository without the recursive flag and your external/DBScope folder is empty, run the following command inside the DBSgram_Main root directory:

> git submodule update --init --recursive

Alternatively, download the DBScope .zip archive directly from https://github.com/NCN-Lab/DBScope and extract its contents into the external/DBScope/ directory.

## Launching the Toolbox (MATLAB Users)
Open MATLAB and add the DBSgram_Main folder (with subfolders) to your search path (Home Tab >> Set Path >> Add Folder with Subfolders), or navigate directly to the DBSgram_Main root directory.

In the MATLAB Command Window, launch the main framework suite by running:

> DBSgram_MainUI

## 📋 Release Notes
### DBSgram Version 1.0 (02.09.2026)

Initial release of the DBSgram Titration Preprocessing & Reporting Framework Suite.

+ Automated ingestion and telemetry dropout repair for Medtronic Percept™ JSON streams and 4-sensor wearable IMU CSV packs.
+ Stimulation-aware task auto-mapping and prominence-driven sub-second synchronization UI.
+ Dual-stage Multi-Modal Data Quality and Cross-Alignment Auditor.
+ Interactive SVD subspace cardiac (ECG) artifact suppression.
+ Automated and manual cycle-level kinematic feature extraction for Tremor, Wrist Rigidity (passive vs. Froment's activated), and Bradykinesia.
+ Automated clinical scoring ingestion (UPDRS.xlsx) and multi-page vector A4 DBSgram PDF report compilation.

## 📊 Data Availability & Open Science
Preprint & Theoretical Validation: Full methodological descriptions, synchronization validation, and clinical case studies are detailed in our medRxiv preprint: https://doi.org/10.64898/2026.03.29.26349663.

Source Code: All software tools and future updates are publicly maintained on GitHub (https://github.com/NCN-Lab/DBSgram) and the NCN-Lab organization (https://github.com/NCN-Lab).

In accordance with NCN-Lab practice, the computational pipelines, and source code are open and adhere to FAIR data principles.

## 📧 Support & Contact
For questions or assistance regarding software installation, data formatting, or running the example datasets:

+ Neuroengineering and Computational Neuroscience (NCN) Lab: pauloaguiar@i3s.up.pt

THIS SOFTWARE IS TO BE USED IN RESEARCH CONTEXT. IT IS NOT YET READY/VALIDATED FOR CLINICAL PRACTICE

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
