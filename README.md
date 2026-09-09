# OMNIZART

[![build](https://github.com/Music-and-Culture-Technology-Lab/omnizart/workflows/general-check/badge.svg)](https://github.com/Music-and-Culture-Technology-Lab/omnizart/actions?query=workflow%3Ageneral-check)
[![docs](https://github.com/Music-and-Culture-Technology-Lab/omnizart/workflows/docs/badge.svg?branch=build_doc)](https://music-and-culture-technology-lab.github.io/omnizart-doc/)
[![PyPI version](https://badge.fury.io/py/omnizart.svg)](https://pypi.org/project/omnizart/)
![PyPI - License](https://img.shields.io/pypi/l/omnizart)
[![PyPI - Downloads](https://img.shields.io/pypi/dm/omnizart)](https://pypistats.org/packages/omnizart)
[![Docker Pulls](https://img.shields.io/docker/pulls/mctlab/omnizart)](https://hub.docker.com/r/mctlab/omnizart)

[![DOI](https://joss.theoj.org/papers/10.21105/joss.03391/status.svg)](https://doi.org/10.21105/joss.03391)
[![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.5769022.svg)](https://doi.org/10.5281/zenodo.5769022)


Omnizart is a Python library that aims for democratizing automatic music transcription.
Given polyphonic music, it is able to transcribe pitched instruments, vocal melody, chords, drum events, and beat.
This is powered by the research outcomes from [Music and Culture Technology (MCT) Lab](https://sites.google.com/view/mctl/home). The paper has been published to [Journal of Open Source Software (JOSS)](https://doi.org/10.21105/joss.03391).

### Transcribe your favorite songs now in Colab [![Open In Colab](https://colab.research.google.com/assets/colab-badge.svg)](https://colab.research.google.com/github/Music-and-Culture-Technology-Lab/omnizart/blob/master/colab.ipynb) or [![Replicate](https://replicate.com/breezewhite/omnizart/badge)](https://replicate.ai/breezewhite/omnizart)

# Quick start

Visit the [complete document](https://music-and-culture-technology-lab.github.io/omnizart-doc/) for detailed guidance.

## Pip
``` bash
# Install omnizart
pip install omnizart

# Download the checkpoints
omnizart download-checkpoints

# Transcribe your songs
omnizart drum transcribe <path/to/audio.wav>
omnizart chord transcribe <path/to/audio.wav>
omnizart music transcribe <path/to/audio.wav>
```

A plain `pip install omnizart` fails on any installer that builds dependencies in
isolation, which includes current pip and uv. See
[Installing on macOS (Apple Silicon)](#installing-on-macos-apple-silicon) for why
and for the working sequence; the build-isolation half of it applies to Linux too.

## Installing on macOS (Apple Silicon)

Verified on an M-series Mac, macOS 26.5.2, Python 3.13.3, with omnizart 0.6.3,
madmom 0.16.1, TensorFlow 2.21.0 and NumPy 2.5.3. All six applications
(`music`, `chord`, `drum`, `vocal`, `vocal-contour`, `beat`) run natively on arm64.

``` bash
# 1. System libraries.
#    portaudio              -> compiling pyaudio, which setup.py insists on
#    fluid-synth            -> loaded at runtime by pyfluidsynth, for `omnizart synth`
#    vamp-plugin-sdk, boost -> rebuilding the Vamp plugin in step 4
brew install portaudio fluid-synth vamp-plugin-sdk boost

# 2. Create the environment and pre-install the build dependencies.
#    madmom and vamp need Cython and NumPy at build time but declare neither,
#    so they must be present before the build starts. omnizart pins setuptools<82.
python3.13 -m venv .venv && source .venv/bin/activate
pip install "setuptools<82" wheel Cython numpy

# 3. Install with build isolation turned off. This is the load-bearing flag.
CFLAGS="-I$(brew --prefix)/include" LDFLAGS="-L$(brew --prefix)/lib" \
    pip install --no-build-isolation omnizart

# 4. Rebuild the Vamp plugin for arm64, in place, in the installed package.
#    Only needed for `omnizart chord`.
git clone https://github.com/mattdennewitz/omnizart /tmp/omnizart-fork
/tmp/omnizart-fork/scripts/build_vamp_plugin.sh --installed

# 5. Download the model weights. Not optional -- see below.
omnizart download-checkpoints
```

With `uv`, steps 2 and 3 are the same commands with `uv venv -p 3.13` and
`uv pip install`.

### Why `--no-build-isolation`

omnizart's `setup.py` bootstraps its awkward dependencies by shelling out to
`pip`/`uv` and installing madmom, vamp, pyaudio and pyfluidsynth into
`sys.executable`. Under PEP 517 build isolation that is the temporary build
environment rather than the one being installed into, so the work is discarded
and the build fails while resolving madmom:

```
ModuleNotFoundError: No module named 'Cython'
help: `madmom` (v0.16.1) was included because `omnizart` (v0.6.3) depends on `madmom>=0.16.1`
```

madmom 0.16.1 declares no PEP 517 build requirements, so nothing puts Cython in
that isolated environment. With isolation disabled `sys.executable` is your venv,
the bootstrap installs into the right place, and the build succeeds.

madmom 0.16.1 dates from 2018 and is the only release on PyPI. It still works
because `omnizart/__init__.py` restores `collections.MutableSequence` (removed in
Python 3.10) and `np.float` (removed in NumPy 1.24) before madmom is imported.
Importing madmom *without* importing omnizart first still fails on a modern
interpreter; that is expected, not a broken install.

pyaudio is not a runtime dependency, but `setup.py` aborts the build if it cannot
install it, and there are no macOS wheels, so it gets compiled against portaudio.
Nothing imports it afterwards; pip leaves it installed and uv prunes it.

### Checkpoints are mandatory

The sdist ships the checkpoint directory structure with empty placeholder weight
files, so `omnizart download-checkpoints` (~750MB) is required before any
transcription. Skipping it fails without mentioning checkpoints:

```
tensorflow.python.framework.errors_impl.OpError:
    .../checkpoints/music/music_piano/variables/variables.data-00000-of-00001; No such file or directory
```

### Short audio files

`omnizart music transcribe` raises `IndexError: list index out of range` from
`create_batches` on clips too short to fill a batch. ~30s is comfortably enough.

## Docker
``` bash
docker pull mctlab/omnizart:latest
docker run -it mctlab/omnizart:latest bash
```

## Conda (install from source)
``` bash
git clone https://github.com/Music-and-Culture-Technology-Lab/omnizart
cd omnizart
# Create a new conda environment
conda env create -f environment.yml
conda activate omnizart
# Install omnizart
pip install .
omnizart download-checkpoints
```

# Supported applications
| Application      | Transcription      | Training           | Evaluation | Description                                      |
|------------------|--------------------|--------------------|------------|--------------------------------------------------|
| music            | :heavy_check_mark: | :heavy_check_mark: |            | Transcribe musical notes of pitched instruments. |
| drum             | :heavy_check_mark: | :interrobang:      |            | Transcribe events of percussive instruments.     |
| vocal            | :heavy_check_mark: | :heavy_check_mark: |            | Transcribe note-level vocal melody.              |
| vocal-contour    | :heavy_check_mark: | :heavy_check_mark: |            | Transcribe frame-level vocal melody (F0).        |
| chord            | :heavy_check_mark: | :heavy_check_mark: |            | Transcribe chord progressions.                   |
| beat             | :heavy_check_mark: | :heavy_check_mark: |            | Transcribe beat position.                        |

**NOTES**
The current implementation for the drum model has unknown bugs, preventing loss convergence when training from scratch.
Fortunately, you can still enjoy drum transcription with the provided checkpoints.

## Platform notes
**Apple Silicon (macOS arm64) works, after rebuilding one plugin.** All six
applications run natively once the bundled NNLS Chroma Vamp plugin is rebuilt;
see [Installing on macOS (Apple Silicon)](#installing-on-macos-apple-silicon).
The plugin ships with x86_64 and i386 slices only, so until it is rebuilt
`omnizart chord` fails with `TypeError: Failed to load plugin: nnls-chroma:nnls-chroma`,
a message that never mentions architecture. The earlier claim that Omnizart was
wholly incompatible with ARM macOS, and the numpy and TensorFlow theories in
[issue #38](https://github.com/Music-and-Culture-Technology-Lab/omnizart/issues/38),
did not survive testing on 0.6.3.

**Linux on arm64 has the same problem.** The bundled `nnls-chroma.so` is x86-64
only. `scripts/build_vamp_plugin.sh` covers Linux and should produce the missing
binary, but this is untested there.

This fork ships no prebuilt plugin of its own, only the script that builds one.
Nobody distributes an arm64 build of NNLS Chroma — no GitHub release, no Homebrew
formula, and its upstream last shipped in 2020 — so the choice is between
building from canonical source and trusting a stranger's binary.

## Citation
If you use this software in your work, please cite:

```
@article{Wu2021,
  doi = {10.21105/joss.03391},
  url = {https://doi.org/10.21105/joss.03391},
  year = {2021},
  publisher = {The Open Journal},
  volume = {6},
  number = {68},
  pages = {3391},
  author = {Yu-Te Wu and Yin-Jyun Luo and Tsung-Ping Chen and I-Chieh Wei and Jui-Yang Hsu and Yi-Chin Chuang and Li Su},
  title = {Omnizart: A General Toolbox for Automatic Music Transcription},
  journal = {Journal of Open Source Software}
}
```
