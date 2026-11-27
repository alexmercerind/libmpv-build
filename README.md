# libmpv-build

libmpv for Android, iOS, Linux, macOS & Windows.

## Requirements

System packages:

- `cmake`
- `git`
- `make`
- `nasm`
- `pkg-config`

Linux only:

- `libasound2-dev`
- `libpulse-dev`

macOS only:

- Xcode CLT

Python packages:

- `jinja2`
- `meson`
- `ninja`
- `pyyaml`

## Build

```
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
.venv/bin/python build.py <target> <variant>
```

### Targets

<table>
<tr><th>Host</th><th>Target</th></tr>
<tr><td rowspan="8">Linux</td><td><code>android-arm64-v8a</code></td></tr>
<tr><td><code>android-armeabi-v7a</code></td></tr>
<tr><td><code>android-x86</code></td></tr>
<tr><td><code>android-x86_64</code></td></tr>
<tr><td><code>linux-aarch64</code></td></tr>
<tr><td><code>linux-x86_64</code></td></tr>
<tr><td><code>windows-arm64</code></td></tr>
<tr><td><code>windows-x64</code></td></tr>
<tr><td rowspan="5">macOS</td><td><code>ios-arm64</code></td></tr>
<tr><td><code>ios-simulator-amd64</code></td></tr>
<tr><td><code>ios-simulator-arm64</code></td></tr>
<tr><td><code>macos-amd64</code></td></tr>
<tr><td><code>macos-arm64</code></td></tr>
</table>

### Variants

- `video`
- `audio`

Release & debug symbol archives land in `dist/`.

## Flags

```
flags/<variant>-<dependency>[-<target>]
```

Examples:

- `flags/all-ffmpeg`: hits everything
- `flags/all-ffmpeg-windows`: hits Windows only
- `flags/audio-ffmpeg-windows-x64`: hits Windows x64 audio only

## Link flags

```
ldflags/<variant>-<dependency>[-<target>]
```

Examples:

- `ldflags/all-mpv`: static deps for every build
- `ldflags/all-mpv-windows`: Windows system libs only

## Patches

```
patches/<variant>-<dependency>[-<target>]
```

Examples:

- `patches/all-mpv/`: hits everything
- `patches/all-mpv-android/`: hits Android only
- `patches/audio-ffmpeg-android-arm64-v8a/`: hits Android arm64-v8a audio only

## Dependencies

| Dependency       | Version   |
| ---------------- | --------- |
| `fast-float`     | `8.4.0`   |
| `ffmpeg`         | `9.1`     |
| `libplacebo`     | `7.387.0` |
| `libxml2`        | `2.15.4`  |
| `mbedtls`        | `3.6.8`   |
| `mimalloc`       | `3.7.1`   |
| `mpv`            | `0.42.0`  |
| `vulkan-headers` | `1.4.369` |
| `zlib`           | `1.4`     |

The full list of pinned libraries and checksums is in [sources/dependencies.yml](sources/dependencies.yml).

## Toolchains

- Android: `NDK r29`, `API 21`
- iOS, macOS: `Xcode 16`
- Linux: system `gcc`
- Windows: [llvm-mingw 20261117](https://github.com/mstorsjo/llvm-mingw/releases/tag/20261117)
