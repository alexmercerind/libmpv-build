from __future__ import annotations

import argparse
import hashlib
import os
import shutil
import stat
import subprocess
import sys
import tarfile
import urllib.request
import zipfile
from dataclasses import dataclass
from enum import Enum
from pathlib import Path
from typing import NoReturn, TypedDict

import yaml

# ----------------------------------------------------------------------------
# Types
# ----------------------------------------------------------------------------


# Build arch
class BuildArch(str, Enum):
    AARCH64 = "aarch64"
    AMD64 = "amd64"
    ARM64 = "arm64"
    ARM64_V8A = "arm64-v8a"
    ARMEABI_V7A = "armeabi-v7a"
    SIMULATOR_AMD64 = "simulator-amd64"
    SIMULATOR_ARM64 = "simulator-arm64"
    X64 = "x64"
    X86 = "x86"
    X86_64 = "x86_64"

    def __str__(self):
        return self.value


# Build OS
class BuildOS(str, Enum):
    ANDROID = "android"
    IOS = "ios"
    LINUX = "linux"
    MACOS = "macos"
    WINDOWS = "windows"

    def __str__(self):
        return self.value


# Build target
class BuildTarget(str, Enum):
    ANDROID_ARM64_V8A = f"{BuildOS.ANDROID}-{BuildArch.ARM64_V8A}"
    ANDROID_ARMEABI_V7A = f"{BuildOS.ANDROID}-{BuildArch.ARMEABI_V7A}"
    ANDROID_X86 = f"{BuildOS.ANDROID}-{BuildArch.X86}"
    ANDROID_X86_64 = f"{BuildOS.ANDROID}-{BuildArch.X86_64}"
    IOS_ARM64 = f"{BuildOS.IOS}-{BuildArch.ARM64}"
    IOS_SIMULATOR_AMD64 = f"{BuildOS.IOS}-{BuildArch.SIMULATOR_AMD64}"
    IOS_SIMULATOR_ARM64 = f"{BuildOS.IOS}-{BuildArch.SIMULATOR_ARM64}"
    LINUX_AARCH64 = f"{BuildOS.LINUX}-{BuildArch.AARCH64}"
    LINUX_X86_64 = f"{BuildOS.LINUX}-{BuildArch.X86_64}"
    MACOS_AMD64 = f"{BuildOS.MACOS}-{BuildArch.AMD64}"
    MACOS_ARM64 = f"{BuildOS.MACOS}-{BuildArch.ARM64}"
    WINDOWS_ARM64 = f"{BuildOS.WINDOWS}-{BuildArch.ARM64}"
    WINDOWS_X64 = f"{BuildOS.WINDOWS}-{BuildArch.X64}"

    def __str__(self):
        return self.value

    # Build OS
    @property
    def build_os(self) -> BuildOS:
        return BuildOS(self.value.split("-", 1)[0])

    # Build arch
    @property
    def build_arch(self) -> BuildArch:
        return BuildArch(self.value.split("-", 1)[1])


# Build variant
class BuildVariant(str, Enum):
    AUDIO = "audio"
    VIDEO = "video"

    def __str__(self):
        return self.value


# Build tool
class BuildTool(str, Enum):
    CMAKE = "cmake"
    CONFIGURE = "configure"
    MESON = "meson"

    def __str__(self):
        return self.value


# Build env
class BuildEnvCommon(TypedDict):
    BINDIR: str
    CC: str
    CXX: str
    AR: str
    NM: str
    STRIP: str
    CFLAGS: str
    CXXFLAGS: str
    LDFLAGS: str
    PKG_CONFIG_LIBDIR: str
    PKG_CONFIG_PATH: str


class BuildEnv(BuildEnvCommon, total=False):
    # Darwin
    OBJC: str
    OBJCFLAGS: str
    SDKROOT: str
    MACOS_SDK: str
    DSYMUTIL: str
    # Windows
    DLLTOOL: str
    RANLIB: str
    WINDRES: str
    TRIPLE: str
    # Android; iOS; Linux; macOS; Windows
    AS: str
    # Android; Linux; Windows
    OBJCOPY: str


# Dependency
@dataclass
class Dependency:
    name: str
    version: str
    url: str
    sha256: str
    tool: BuildTool
    dependencies: list[str]


# ----------------------------------------------------------------------------
# Constants
# ----------------------------------------------------------------------------

# FFmpeg configure dialect, its arch and OS names differ from ours
FFMPEG_TARGET_ARCH = {
    BuildArch.AARCH64: "aarch64",
    BuildArch.AMD64: "x86_64",
    BuildArch.ARM64: "aarch64",
    BuildArch.ARM64_V8A: "aarch64",
    BuildArch.ARMEABI_V7A: "arm",
    BuildArch.SIMULATOR_AMD64: "x86_64",
    BuildArch.SIMULATOR_ARM64: "aarch64",
    BuildArch.X64: "x86_64",
    BuildArch.X86: "x86_32",
    BuildArch.X86_64: "x86_64",
}
FFMPEG_TARGET_OS = {
    BuildOS.ANDROID: "android",
    BuildOS.IOS: "darwin",
    BuildOS.LINUX: "linux",
    BuildOS.MACOS: "darwin",
    BuildOS.WINDOWS: "mingw32",
}

# Release container per OS
RELEASE_ARCHIVE_EXT = {
    BuildOS.ANDROID: "jar",
    BuildOS.IOS: "zip",
    BuildOS.LINUX: "zip",
    BuildOS.MACOS: "zip",
    BuildOS.WINDOWS: "zip",
}

# Debug symbol container per OS
DEBUG_SYMBOL_ARCHIVE_EXT = {**RELEASE_ARCHIVE_EXT, BuildOS.ANDROID: "zip"}

# C++ runtime link flags per OS
CXX_RUNTIME = {
    BuildOS.ANDROID: "-Wl,-Bstatic -lstdc++ -Wl,-Bdynamic",
    BuildOS.IOS: "",
    BuildOS.LINUX: "-Wl,-Bstatic -lstdc++ -Wl,-Bdynamic",
    BuildOS.MACOS: "",
    BuildOS.WINDOWS: "-nostdlib++ -l:libc++.a -l:libunwind.a",
}


# Dependency metadata inputs
DEPENDENCIES_FILE = "sources/dependencies.yml"

# Input and output dirs
FLAGS_DIR = "flags"
LDFLAGS_DIR = "ldflags"
CROSS_DIR = "cross"
PATCHES_DIR = "patches"
DEPS_DIR = "deps"
BUILD_DIR = "build"
DIST_DIR = "dist"
TOOLCHAIN_DIR = "toolchain"
SYMBOLS_DIR = "symbols"

# File naming fragments
ALL = "all"
PREFIX = "prefix-"

# Host runtime
JOBS = str(os.cpu_count() or 4)


# ----------------------------------------------------------------------------
# Entry
# ----------------------------------------------------------------------------


# Runs one full build from flags to artifacts
def main() -> int:
    parser = argparse.ArgumentParser(prog="build.py")
    parser.add_argument("target", type=BuildTarget)
    parser.add_argument("variant", type=BuildVariant)
    args = parser.parse_args()
    build_target = args.target
    build_variant = args.variant
    print(f"building {build_target} {build_variant}", flush=True)
    base = Path(__file__).resolve().parent
    dependencies = get_dependencies(base)
    cross_file = base / CROSS_DIR / f"{build_target}.txt"
    prefix = base / DEPS_DIR / f"{PREFIX}{build_target}"
    build_env = get_target_env(base, build_target, prefix)
    for dependency in dependencies:
        print(f"building {dependency.name}", flush=True)
        build_dependency(base, dependency, build_target, build_variant, cross_file, prefix, build_env)
    split_debug(prefix, build_target, build_env)
    path = package_release(base, build_target, build_variant, prefix)
    debug_path = package_debug(base, build_target, build_variant, prefix)
    print(path)
    print(debug_path)
    return 0


# ----------------------------------------------------------------------------
# Dependencies
# ----------------------------------------------------------------------------


# Gets dependencies in topological build order
def get_dependencies(base: Path) -> list[Dependency]:
    entries = {}
    for item in yaml.safe_load((base / DEPENDENCIES_FILE).read_text()):
        entries[item["name"]] = Dependency(
            name=item["name"],
            version=item["version"],
            url=item["url"],
            sha256=item["sha256"],
            tool=BuildTool(item["tool"]),
            dependencies=item["dependencies"],
        )
    tree = {name: entry.dependencies for name, entry in entries.items()}
    order = []
    done = set()
    # Builds each dependency after the ones it links against
    while len(order) < len(tree):
        ready = sorted(name for name, dependencies in tree.items() if name not in done and all(edge in done for edge in dependencies))
        if not ready:
            abort("dependency cycle")
        first = ready[0]
        done.add(first)
        order.append(first)
    return [entries[name] for name in order]


# Downloads and extracts the Android NDK once; returns its root
def fetch_android_ndk(base: Path) -> Path:
    root = base / TOOLCHAIN_DIR / "android"
    if (root / "toolchains").is_dir():
        return root
    root.mkdir(parents=True, exist_ok=True)
    archive = base / TOOLCHAIN_DIR / "android-ndk-r27-linux.zip"
    download("https://dl.google.com/android/repository/android-ndk-r27-linux.zip", "2f17eb8bcbfdc40201c0b36e9a70826fcd2524ab7a2a235e2c71186c302da1dc", archive)
    unarchive(archive, root)
    kids = [kid for kid in root.iterdir() if not kid.name.startswith(".")]
    if len(kids) == 1 and kids[0].is_dir():
        inner = kids[0]
        for leaf in inner.iterdir():
            shutil.move(str(leaf), str(root))
        inner.rmdir()
    archive.unlink()
    return root


# Downloads and extracts llvm-mingw once; returns its root
def fetch_llvm_mingw(base: Path) -> Path:
    root = base / TOOLCHAIN_DIR / "windows"
    if (root / "bin").is_dir():
        return root
    root.mkdir(parents=True, exist_ok=True)
    archive = base / TOOLCHAIN_DIR / "llvm-mingw-20251118-ucrt-ubuntu-22.04-x86_64.tar.xz"
    download(
        "https://github.com/mstorsjo/llvm-mingw/releases/download/20251118/llvm-mingw-20251118-ucrt-ubuntu-22.04-x86_64.tar.xz",
        "53a0c22caa46b501e1c089e1c31b24a7c0e0d5a86f8ad12b131aafd4cee01ef4",
        archive,
    )
    unarchive(archive, root)
    kids = [kid for kid in root.iterdir() if not kid.name.startswith(".")]
    if len(kids) == 1 and kids[0].is_dir():
        inner = kids[0]
        for leaf in inner.iterdir():
            shutil.move(str(leaf), str(root))
        inner.rmdir()
    archive.unlink()
    return root


# ----------------------------------------------------------------------------
# Target env
# ----------------------------------------------------------------------------


# Gets the Linux pkg-config search path
def get_linux_pc_path() -> str:
    done = subprocess.run(["pkg-config", "--variable", "pc_path", "pkg-config"], capture_output=True, text=True)
    if done.returncode != 0:
        abort("pkg-config pc_path lookup failed")
    return done.stdout.strip()


# Resolves a Darwin SDK tool to its path
def darwin_xcrun(sdk: str, tool: str) -> str:
    done = subprocess.run(["xcrun", "-sdk", sdk, "-f", tool], capture_output=True, text=True)
    if done.returncode != 0:
        abort(f"xcrun lookup failed: {sdk} {tool}")
    return done.stdout.strip()


# Gets a Darwin SDK path
def darwin_sdk_path(sdk: str) -> str:
    done = subprocess.run(["xcrun", "-sdk", sdk, "--show-sdk-path"], capture_output=True, text=True)
    if done.returncode != 0:
        abort(f"sdk lookup failed: {sdk}")
    return done.stdout.strip()


# Gets build env per combo
def get_target_env(base: Path, build_target: BuildTarget, prefix: Path) -> BuildEnv:
    pkgconfig = prefix / "lib" / "pkgconfig"
    if build_target == BuildTarget.ANDROID_ARM64_V8A:
        bindir = fetch_android_ndk(base) / "toolchains" / "llvm" / "prebuilt" / "linux-x86_64" / "bin"
        triple = "aarch64-linux-android21"
        return {
            "BINDIR": str(bindir),
            "CC": f"{bindir}/{triple}-clang",
            "CXX": f"{bindir}/{triple}-clang++",
            "AR": f"{bindir}/llvm-ar",
            "NM": f"{bindir}/llvm-nm",
            "STRIP": f"{bindir}/llvm-strip",
            "CFLAGS": f"-g -fPIC -I{prefix}/include -O3 -ffunction-sections -fdata-sections",
            "CXXFLAGS": f"-g -fPIC -I{prefix}/include -O3 -ffunction-sections -fdata-sections",
            "LDFLAGS": "-Wl,-O1,--icf=safe -Wl,-z,max-page-size=16384 -Wl,--gc-sections",
            "PKG_CONFIG_LIBDIR": str(pkgconfig),
            "PKG_CONFIG_PATH": str(pkgconfig),
            "OBJCOPY": f"{bindir}/llvm-objcopy",
        }
    elif build_target == BuildTarget.ANDROID_ARMEABI_V7A:
        bindir = fetch_android_ndk(base) / "toolchains" / "llvm" / "prebuilt" / "linux-x86_64" / "bin"
        triple = "armv7a-linux-androideabi21"
        return {
            "BINDIR": str(bindir),
            "CC": f"{bindir}/{triple}-clang",
            "CXX": f"{bindir}/{triple}-clang++",
            "AR": f"{bindir}/llvm-ar",
            "NM": f"{bindir}/llvm-nm",
            "STRIP": f"{bindir}/llvm-strip",
            "CFLAGS": f"-g -fPIC -I{prefix}/include -O3 -ffunction-sections -fdata-sections",
            "CXXFLAGS": f"-g -fPIC -I{prefix}/include -O3 -ffunction-sections -fdata-sections",
            "LDFLAGS": "-Wl,-O1,--icf=safe -Wl,-z,max-page-size=16384 -Wl,--gc-sections",
            "PKG_CONFIG_LIBDIR": str(pkgconfig),
            "PKG_CONFIG_PATH": str(pkgconfig),
            "OBJCOPY": f"{bindir}/llvm-objcopy",
        }
    elif build_target == BuildTarget.ANDROID_X86:
        bindir = fetch_android_ndk(base) / "toolchains" / "llvm" / "prebuilt" / "linux-x86_64" / "bin"
        triple = "i686-linux-android21"
        return {
            "BINDIR": str(bindir),
            "CC": f"{bindir}/{triple}-clang",
            "CXX": f"{bindir}/{triple}-clang++",
            "AR": f"{bindir}/llvm-ar",
            "NM": f"{bindir}/llvm-nm",
            "STRIP": f"{bindir}/llvm-strip",
            "CFLAGS": f"-g -fPIC -I{prefix}/include -O3 -ffunction-sections -fdata-sections",
            "CXXFLAGS": f"-g -fPIC -I{prefix}/include -O3 -ffunction-sections -fdata-sections",
            "LDFLAGS": "-Wl,-O1,--icf=safe -Wl,-z,max-page-size=16384 -Wl,--gc-sections",
            "PKG_CONFIG_LIBDIR": str(pkgconfig),
            "PKG_CONFIG_PATH": str(pkgconfig),
            "AS": "nasm",
            "OBJCOPY": f"{bindir}/llvm-objcopy",
        }
    elif build_target == BuildTarget.ANDROID_X86_64:
        bindir = fetch_android_ndk(base) / "toolchains" / "llvm" / "prebuilt" / "linux-x86_64" / "bin"
        triple = "x86_64-linux-android21"
        return {
            "BINDIR": str(bindir),
            "CC": f"{bindir}/{triple}-clang",
            "CXX": f"{bindir}/{triple}-clang++",
            "AR": f"{bindir}/llvm-ar",
            "NM": f"{bindir}/llvm-nm",
            "STRIP": f"{bindir}/llvm-strip",
            "CFLAGS": f"-g -fPIC -I{prefix}/include -O3 -ffunction-sections -fdata-sections",
            "CXXFLAGS": f"-g -fPIC -I{prefix}/include -O3 -ffunction-sections -fdata-sections",
            "LDFLAGS": "-Wl,-O1,--icf=safe -Wl,-z,max-page-size=16384 -Wl,--gc-sections",
            "PKG_CONFIG_LIBDIR": str(pkgconfig),
            "PKG_CONFIG_PATH": str(pkgconfig),
            "AS": "nasm",
            "OBJCOPY": f"{bindir}/llvm-objcopy",
        }
    elif build_target == BuildTarget.WINDOWS_ARM64:
        bindir = fetch_llvm_mingw(base) / "bin"
        triple = "aarch64-w64-mingw32"
        return {
            "BINDIR": str(bindir),
            "CC": f"{bindir}/{triple}-clang",
            "CXX": f"{bindir}/{triple}-clang++",
            "AR": f"{bindir}/llvm-ar",
            "NM": f"{bindir}/llvm-nm",
            "STRIP": f"{bindir}/llvm-strip",
            "CFLAGS": f"-g -fPIC -I{prefix}/include -O3 -ffunction-sections -fdata-sections",
            "CXXFLAGS": f"-g -fPIC -I{prefix}/include -O3 -ffunction-sections -fdata-sections",
            "LDFLAGS": "-Wl,--gc-sections",
            "PKG_CONFIG_LIBDIR": str(pkgconfig),
            "PKG_CONFIG_PATH": str(pkgconfig),
            "DLLTOOL": f"{bindir}/llvm-dlltool",
            "RANLIB": f"{bindir}/{triple}-ranlib",
            "WINDRES": f"{bindir}/{triple}-windres",
            "TRIPLE": triple,
            "OBJCOPY": f"{bindir}/llvm-objcopy",
        }
    elif build_target == BuildTarget.WINDOWS_X64:
        bindir = fetch_llvm_mingw(base) / "bin"
        triple = "x86_64-w64-mingw32"
        return {
            "BINDIR": str(bindir),
            "CC": f"{bindir}/{triple}-clang",
            "CXX": f"{bindir}/{triple}-clang++",
            "AR": f"{bindir}/llvm-ar",
            "NM": f"{bindir}/llvm-nm",
            "STRIP": f"{bindir}/llvm-strip",
            "CFLAGS": f"-g -fPIC -I{prefix}/include -O3 -ffunction-sections -fdata-sections",
            "CXXFLAGS": f"-g -fPIC -I{prefix}/include -O3 -ffunction-sections -fdata-sections",
            "LDFLAGS": "-Wl,--gc-sections",
            "PKG_CONFIG_LIBDIR": str(pkgconfig),
            "PKG_CONFIG_PATH": str(pkgconfig),
            "DLLTOOL": f"{bindir}/llvm-dlltool",
            "RANLIB": f"{bindir}/{triple}-ranlib",
            "WINDRES": f"{bindir}/{triple}-windres",
            "TRIPLE": triple,
            "AS": "nasm",
            "OBJCOPY": f"{bindir}/llvm-objcopy",
        }
    elif build_target == BuildTarget.LINUX_AARCH64:
        return {
            "BINDIR": "/usr/bin",
            "CC": "gcc",
            "CXX": "g++",
            "AR": "ar",
            "NM": "nm",
            "STRIP": "strip",
            "CFLAGS": f"-g -fPIC -I{prefix}/include -O3 -ffunction-sections -fdata-sections",
            "CXXFLAGS": f"-g -fPIC -I{prefix}/include -O3 -ffunction-sections -fdata-sections",
            "LDFLAGS": "-Wl,--gc-sections",
            "PKG_CONFIG_LIBDIR": str(pkgconfig),
            "PKG_CONFIG_PATH": str(pkgconfig) + ":" + get_linux_pc_path(),
            "OBJCOPY": "objcopy",
        }
    elif build_target == BuildTarget.LINUX_X86_64:
        return {
            "BINDIR": "/usr/bin",
            "CC": "gcc",
            "CXX": "g++",
            "AR": "ar",
            "NM": "nm",
            "STRIP": "strip",
            "CFLAGS": f"-g -fPIC -I{prefix}/include -O3 -ffunction-sections -fdata-sections",
            "CXXFLAGS": f"-g -fPIC -I{prefix}/include -O3 -ffunction-sections -fdata-sections",
            "LDFLAGS": "-Wl,--gc-sections",
            "PKG_CONFIG_LIBDIR": str(pkgconfig),
            "PKG_CONFIG_PATH": str(pkgconfig) + ":" + get_linux_pc_path(),
            "AS": "nasm",
            "OBJCOPY": "objcopy",
        }
    elif build_target == BuildTarget.IOS_ARM64:
        clang = darwin_xcrun("iphoneos", "clang")
        return {
            "BINDIR": str(Path(clang).parent),
            "CC": clang,
            "CXX": darwin_xcrun("iphoneos", "clang++"),
            "AR": darwin_xcrun("iphoneos", "ar"),
            "NM": darwin_xcrun("iphoneos", "nm"),
            "STRIP": darwin_xcrun("iphoneos", "strip"),
            "CFLAGS": f"-g -arch arm64 -miphoneos-version-min=14.0 -fPIC -I{prefix}/include -O3 -ffunction-sections -fdata-sections",
            "CXXFLAGS": f"-g -arch arm64 -miphoneos-version-min=14.0 -stdlib=libc++ -fPIC -I{prefix}/include -O3 -ffunction-sections -fdata-sections",
            "LDFLAGS": "-arch arm64 -miphoneos-version-min=14.0 -Wl,-dead_strip",
            "PKG_CONFIG_LIBDIR": str(pkgconfig),
            "PKG_CONFIG_PATH": str(pkgconfig),
            "OBJC": clang,
            "OBJCFLAGS": "-g -arch arm64 -miphoneos-version-min=14.0",
            "SDKROOT": darwin_sdk_path("iphoneos"),
            "MACOS_SDK": darwin_sdk_path("iphoneos"),
            "DSYMUTIL": darwin_xcrun("iphoneos", "dsymutil"),
        }
    elif build_target == BuildTarget.IOS_SIMULATOR_AMD64:
        clang = darwin_xcrun("iphonesimulator", "clang")
        return {
            "BINDIR": str(Path(clang).parent),
            "CC": clang,
            "CXX": darwin_xcrun("iphonesimulator", "clang++"),
            "AR": darwin_xcrun("iphonesimulator", "ar"),
            "NM": darwin_xcrun("iphonesimulator", "nm"),
            "STRIP": darwin_xcrun("iphonesimulator", "strip"),
            "CFLAGS": f"-g -arch x86_64 -mios-simulator-version-min=14.0 -fPIC -I{prefix}/include -O3 -ffunction-sections -fdata-sections",
            "CXXFLAGS": f"-g -arch x86_64 -mios-simulator-version-min=14.0 -stdlib=libc++ -fPIC -I{prefix}/include -O3 -ffunction-sections -fdata-sections",
            "LDFLAGS": "-arch x86_64 -mios-simulator-version-min=14.0 -Wl,-dead_strip",
            "PKG_CONFIG_LIBDIR": str(pkgconfig),
            "PKG_CONFIG_PATH": str(pkgconfig),
            "OBJC": clang,
            "OBJCFLAGS": "-g -arch x86_64 -mios-simulator-version-min=14.0",
            "SDKROOT": darwin_sdk_path("iphonesimulator"),
            "MACOS_SDK": darwin_sdk_path("iphonesimulator"),
            "DSYMUTIL": darwin_xcrun("iphonesimulator", "dsymutil"),
            "AS": "nasm",
        }
    elif build_target == BuildTarget.IOS_SIMULATOR_ARM64:
        clang = darwin_xcrun("iphonesimulator", "clang")
        return {
            "BINDIR": str(Path(clang).parent),
            "CC": clang,
            "CXX": darwin_xcrun("iphonesimulator", "clang++"),
            "AR": darwin_xcrun("iphonesimulator", "ar"),
            "NM": darwin_xcrun("iphonesimulator", "nm"),
            "STRIP": darwin_xcrun("iphonesimulator", "strip"),
            "CFLAGS": f"-g -arch arm64 -mios-simulator-version-min=14.0 -fPIC -I{prefix}/include -O3 -ffunction-sections -fdata-sections",
            "CXXFLAGS": f"-g -arch arm64 -mios-simulator-version-min=14.0 -stdlib=libc++ -fPIC -I{prefix}/include -O3 -ffunction-sections -fdata-sections",
            "LDFLAGS": "-arch arm64 -mios-simulator-version-min=14.0 -Wl,-dead_strip",
            "PKG_CONFIG_LIBDIR": str(pkgconfig),
            "PKG_CONFIG_PATH": str(pkgconfig),
            "OBJC": clang,
            "OBJCFLAGS": "-g -arch arm64 -mios-simulator-version-min=14.0",
            "SDKROOT": darwin_sdk_path("iphonesimulator"),
            "MACOS_SDK": darwin_sdk_path("iphonesimulator"),
            "DSYMUTIL": darwin_xcrun("iphonesimulator", "dsymutil"),
        }
    elif build_target == BuildTarget.MACOS_AMD64:
        clang = darwin_xcrun("macosx", "clang")
        return {
            "BINDIR": str(Path(clang).parent),
            "CC": clang,
            "CXX": darwin_xcrun("macosx", "clang++"),
            "AR": darwin_xcrun("macosx", "ar"),
            "NM": darwin_xcrun("macosx", "nm"),
            "STRIP": darwin_xcrun("macosx", "strip"),
            "CFLAGS": f"-g -arch x86_64 -mmacosx-version-min=10.15 -fPIC -I{prefix}/include -O3 -ffunction-sections -fdata-sections",
            "CXXFLAGS": f"-g -arch x86_64 -mmacosx-version-min=10.15 -stdlib=libc++ -fPIC -I{prefix}/include -O3 -ffunction-sections -fdata-sections",
            "LDFLAGS": "-arch x86_64 -mmacosx-version-min=10.15 -Wl,-dead_strip",
            "PKG_CONFIG_LIBDIR": str(pkgconfig),
            "PKG_CONFIG_PATH": str(pkgconfig),
            "OBJC": clang,
            "OBJCFLAGS": "-g -arch x86_64 -mmacosx-version-min=10.15",
            "SDKROOT": darwin_sdk_path("macosx"),
            "DSYMUTIL": darwin_xcrun("macosx", "dsymutil"),
            "AS": "nasm",
        }
    elif build_target == BuildTarget.MACOS_ARM64:
        clang = darwin_xcrun("macosx", "clang")
        return {
            "BINDIR": str(Path(clang).parent),
            "CC": clang,
            "CXX": darwin_xcrun("macosx", "clang++"),
            "AR": darwin_xcrun("macosx", "ar"),
            "NM": darwin_xcrun("macosx", "nm"),
            "STRIP": darwin_xcrun("macosx", "strip"),
            "CFLAGS": f"-g -arch arm64 -mmacosx-version-min=10.15 -fPIC -I{prefix}/include -O3 -ffunction-sections -fdata-sections",
            "CXXFLAGS": f"-g -arch arm64 -mmacosx-version-min=10.15 -stdlib=libc++ -fPIC -I{prefix}/include -O3 -ffunction-sections -fdata-sections",
            "LDFLAGS": "-arch arm64 -mmacosx-version-min=10.15 -Wl,-dead_strip",
            "PKG_CONFIG_LIBDIR": str(pkgconfig),
            "PKG_CONFIG_PATH": str(pkgconfig),
            "OBJC": clang,
            "OBJCFLAGS": "-g -arch arm64 -mmacosx-version-min=10.15",
            "SDKROOT": darwin_sdk_path("macosx"),
            "DSYMUTIL": darwin_xcrun("macosx", "dsymutil"),
        }


# ----------------------------------------------------------------------------
# Flags and patches
# ----------------------------------------------------------------------------


# Lists flag and patch layer names from generic to specific
def layers(name: str, build_target: BuildTarget, build_variant: BuildVariant) -> list[str]:
    return [
        f"{ALL}-{name}",
        f"{build_variant}-{name}",
        f"{ALL}-{name}-{build_target.build_os}",
        f"{build_variant}-{name}-{build_target.build_os}",
        f"{ALL}-{name}-{build_target.build_os}-{build_target.build_arch}",
        f"{build_variant}-{name}-{build_target.build_os}-{build_target.build_arch}",
    ]


# Gets patch files matching variant, name, os, and arch
def get_patch_files(base: Path, name: str, build_target: BuildTarget, build_variant: BuildVariant) -> list[Path]:
    out = []
    for layer in sorted(layers(name, build_target, build_variant)):
        top = base / PATCHES_DIR / layer
        if top.is_dir():
            out += sorted(top.iterdir())
    return out


# Gets concatenated flag layers for a dependency
def get_flags(base: Path, name: str, build_target: BuildTarget, build_variant: BuildVariant) -> list[str]:
    seen = {}
    lines = []
    for layer in layers(name, build_target, build_variant):
        path = base / FLAGS_DIR / layer
        if not path.is_file():
            continue
        for raw in path.read_text().splitlines():
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            if line in seen:
                abort(f"duplicate flag: {line} in {seen[line]} and {path}")
            seen[line] = path
            lines.append(line)
    return lines


# Gets concatenated link layers for a dependency
def get_ldflags(base: Path, name: str, build_target: BuildTarget, build_variant: BuildVariant) -> list[str]:
    seen = {}
    lines = []
    for layer in layers(name, build_target, build_variant):
        path = base / LDFLAGS_DIR / layer
        if not path.is_file():
            continue
        for raw in path.read_text().splitlines():
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            if line in seen:
                abort(f"duplicate link flag: {line} in {seen[line]} and {path}")
            seen[line] = path
            lines.append(line)
    return lines


# ----------------------------------------------------------------------------
# Builders
# ----------------------------------------------------------------------------


# Fetches, patches, and builds one dependency
def build_dependency(base: Path, dependency: Dependency, build_target: BuildTarget, build_variant: BuildVariant, cross_file: Path, prefix: Path, build_env: BuildEnv) -> None:
    src = fetch_dependency(base, dependency.name, dependency.url, dependency.sha256)
    for path in get_patch_files(base, dependency.name, build_target, build_variant):
        print(f"applying {path}", flush=True)
        run(["patch", "-p1", "-i", str(path)], src)
    flags = get_flags(base, dependency.name, build_target, build_variant)
    # Upstream opt-out: float formatting without std::to_chars (missing at runtime on old iOS).
    build_env = {**build_env, "CXXFLAGS": f"{build_env['CXXFLAGS']} -DHAS_STD_TO_CHARS_FP=0"}
    # Only mpv symbols stay public; support libraries build hidden
    if dependency.name != "mpv":
        build_env = {**build_env, "CFLAGS": build_env["CFLAGS"] + " -fvisibility=hidden", "CXXFLAGS": build_env["CXXFLAGS"] + " -fvisibility=hidden"}
    link = get_ldflags(base, dependency.name, build_target, build_variant)
    if link:
        build_env = {**build_env, "LDFLAGS": f"{build_env['LDFLAGS']} -L{prefix / 'lib'} {CXX_RUNTIME[build_target.build_os]} {' '.join(link)}".strip()}
    if dependency.name == "ffmpeg":
        build_ffmpeg(src, build_target, prefix, flags, build_env)
    elif dependency.tool == BuildTool.MESON:
        build_meson(src, prefix, cross_file, flags, build_env)
    elif dependency.tool == BuildTool.CMAKE:
        build_cmake(src, prefix, flags, build_env)
    else:
        build_configure(src, prefix, flags, build_env)


# Fetches the hash-pinned source into a fresh dir
def fetch_dependency(base: Path, name: str, url: str, sha: str) -> Path:
    dest = base / DEPS_DIR / name
    (base / DEPS_DIR).mkdir(parents=True, exist_ok=True)
    archive = base / DEPS_DIR / url.rsplit("/", 1)[-1]
    download(url, sha, archive)
    unarchive(archive, dest)
    kids = list(dest.iterdir())
    if len(kids) == 1 and kids[0].is_dir():
        inner = kids[0]
        for leaf in inner.iterdir():
            shutil.move(str(leaf), str(dest))
        inner.rmdir()
    return dest


# Cross compiles and installs with FFmpeg configure
def build_ffmpeg(src: Path, build_target: BuildTarget, prefix: Path, args: list[str], build_env: BuildEnv) -> None:
    if build_target.build_os == BuildOS.IOS or build_target.build_os == BuildOS.MACOS:
        # Builds host tools against the macOS SDK; the target SDKROOT makes them un-runnable
        sysroot = darwin_sdk_path("macosx")
        host = [
            "--host-cc=cc",
            f"--host-cflags=-g -isysroot {sysroot}",
            f"--host-ldflags=-isysroot {sysroot}",
        ]
    else:
        host = []
    try:
        run(
            [
                "./configure",
                f"--prefix={prefix}",
                "--enable-cross-compile",
                f"--extra-cflags=-I{prefix / 'include'}",
                f"--extra-ldflags=-L{prefix / 'lib'}",
                f"--target-os={FFMPEG_TARGET_OS[build_target.build_os]}",
                f"--arch={FFMPEG_TARGET_ARCH[build_target.build_arch]}",
                f"--cc={build_env['CC']}",
                f"--cxx={build_env['CXX']}",
                f"--ar={build_env['AR']}",
                f"--nm={build_env['NM']}",
                f"--strip={build_env['STRIP']}",
                "--pkg-config=pkg-config",
            ]
            + host
            + args,
            src,
            build_env,
        )
    except SystemExit:
        print("\n".join((src / "ffbuild" / "config.log").read_text().splitlines()[-40:]), flush=True)
        raise
    if build_target.build_os == BuildOS.WINDOWS:
        # Configure leaves dlltool and windres untargeted; point them at the toolchain
        mak = src / "ffbuild" / "config.mak"
        lines = []
        for line in mak.read_text().splitlines():
            if line.startswith("DLLTOOL="):
                line = f"DLLTOOL={build_env['DLLTOOL']}"
            if line.startswith("WINDRES="):
                line = f"WINDRES={build_env['WINDRES']} --target={build_env['TRIPLE']}"
            lines.append(line)
        mak.write_text("\n".join(lines) + "\n")
    run(["make", f"-j{JOBS}"], src, build_env)
    run(["make", "install"], src, build_env)


# Builds and installs with meson
def build_meson(src: Path, prefix: Path, cross_file: Path, args: list[str], build_env: BuildEnv) -> None:
    builddir = src / BUILD_DIR
    shutil.rmtree(builddir, ignore_errors=True)
    run(
        ["meson", "setup", str(builddir), str(src), f"--prefix={prefix}", f"--cross-file={cross_file}"] + args,
        src,
        build_env,
    )
    run(["meson", "compile", "-C", str(builddir)], src, build_env)
    run(["meson", "install", "-C", str(builddir)], src, build_env)


# Builds and installs with cmake
def build_cmake(src: Path, prefix: Path, args: list[str], build_env: BuildEnv) -> None:
    builddir = src / BUILD_DIR
    shutil.rmtree(builddir, ignore_errors=True)
    builddir.mkdir()
    run(
        [
            "cmake",
            f"-DCMAKE_INSTALL_PREFIX={prefix}",
            f"-DCMAKE_C_COMPILER={build_env['CC']}",
            f"-DCMAKE_CXX_COMPILER={build_env['CXX']}",
        ]
        + args
        + [str(src)],
        builddir,
        build_env,
    )
    run(["cmake", "--build", ".", "--parallel", JOBS], builddir, build_env)
    run(["cmake", "--install", "."], builddir, build_env)


# Builds and installs with configure
def build_configure(src: Path, prefix: Path, args: list[str], build_env: BuildEnv) -> None:
    run(["./configure", f"--prefix={prefix}"] + args, src, build_env)
    run(["make", f"-j{JOBS}"], src, build_env)
    run(["make", "install"], src, build_env)


# ----------------------------------------------------------------------------
# Debug symbols
# ----------------------------------------------------------------------------


# Moves debug info to sidecars
def split_debug(prefix: Path, build_target: BuildTarget, build_env: BuildEnv) -> None:
    symbols = prefix / SYMBOLS_DIR
    symbols.mkdir(exist_ok=True)
    if build_target.build_os == BuildOS.IOS or build_target.build_os == BuildOS.MACOS:
        leaves = [leaf for leaf in (prefix / "lib").iterdir() if leaf.is_file() and not leaf.is_symlink() and leaf.suffix != ".a"]
        for leaf in sorted(leaves):
            bundle = symbols / f"{leaf.name}.dSYM"
            run(build_env["DSYMUTIL"].split() + [str(leaf), "-o", str(bundle)], prefix)
            run(build_env["STRIP"].split() + ["-S", str(leaf)], prefix)
    elif build_target.build_os == BuildOS.WINDOWS:
        leaves = [leaf for leaf in (prefix / "lib").iterdir() if leaf.is_file() and not leaf.is_symlink() and leaf.suffix == ".dll"]
        bindir = prefix / "bin"
        if bindir.is_dir():
            leaves += [leaf for leaf in bindir.iterdir() if leaf.is_file() and not leaf.is_symlink() and leaf.suffix in (".dll", ".exe")]
        for leaf in sorted(leaves):
            debug = symbols / f"{leaf.name}.debug"
            run(build_env["OBJCOPY"].split() + ["--only-keep-debug", str(leaf), str(debug)], prefix)
            run(build_env["STRIP"].split() + [str(leaf)], prefix)
            run(build_env["OBJCOPY"].split() + [f"--add-gnu-debuglink={debug.name}", str(leaf)], symbols)
    else:
        leaves = [leaf for leaf in (prefix / "lib").iterdir() if leaf.is_file() and not leaf.is_symlink() and leaf.suffix != ".a"]
        for leaf in sorted(leaves):
            debug = symbols / f"{leaf.name}.debug"
            run(build_env["OBJCOPY"].split() + ["--only-keep-debug", str(leaf), str(debug)], prefix)
            run(build_env["STRIP"].split() + [str(leaf)], prefix)
            run(build_env["OBJCOPY"].split() + [f"--add-gnu-debuglink={debug.name}", str(leaf)], symbols)


# Assembles debug symbols and static archives under one dir
def assemble_debug_symbols(prefix: Path, dest: Path) -> None:
    dest.mkdir(parents=True, exist_ok=True)
    for leaf in sorted((prefix / SYMBOLS_DIR).iterdir()):
        if leaf.is_dir():
            shutil.copytree(leaf, dest / leaf.name)
        else:
            shutil.copy2(leaf, dest / leaf.name)
    for leaf in sorted((prefix / "lib").glob("*.a")):
        shutil.copy2(leaf, dest / leaf.name)


# ----------------------------------------------------------------------------
# Packaging
# ----------------------------------------------------------------------------


# Packages the release artifact for one target
def package_release(base: Path, build_target: BuildTarget, build_variant: BuildVariant, prefix: Path) -> Path:
    if build_target.build_os == BuildOS.IOS or build_target.build_os == BuildOS.MACOS:
        return package_release_darwin(base, build_target, build_variant, prefix)
    if build_target.build_os == BuildOS.ANDROID:
        return package_release_android(base, build_target, build_variant, prefix)
    if build_target.build_os == BuildOS.WINDOWS:
        return package_release_windows(base, build_target, build_variant, prefix)
    return package_release_linux(base, build_target, build_variant, prefix)


# Packs *.xcframework in a zip
# Release zip:
#   Mpv.xcframework/
#     Info.plist
#     <slice>/
#       Mpv.framework/
def package_release_darwin(base: Path, build_target: BuildTarget, build_variant: BuildVariant, prefix: Path) -> Path:
    dist = base / DIST_DIR
    dist.mkdir(exist_ok=True)
    stem = f"libmpv_{build_target.build_os}_{build_target.build_arch}_{build_variant}"
    version = "1.0"
    work = base / DEPS_DIR / f"framework-{build_target}"
    shutil.rmtree(work, ignore_errors=True)
    vers = work / "Mpv.framework" / "Versions" / "A"
    (vers / "Headers").mkdir(parents=True)
    (vers / "Modules").mkdir(parents=True)
    (vers / "Resources").mkdir(parents=True)
    dylibs = sorted(leaf for leaf in (prefix / "lib").iterdir() if leaf.suffix == ".dylib" and not leaf.is_symlink())
    if len(dylibs) != 1:
        abort(f"expected one dylib in {prefix / 'lib'}")
    shutil.copy(dylibs[0], vers / "Mpv")
    run(["install_name_tool", "-id", "@rpath/Mpv.framework/Mpv", str(vers / "Mpv")], base)
    for leaf in sorted((prefix / "include" / "mpv").glob("*.h")):
        shutil.copy(leaf, vers / "Headers" / leaf.name)
    (vers / "Headers" / "Mpv.h").write_text('#import "client.h"\n#import "render.h"\n#import "render_gl.h"\n#import "stream_cb.h"\n')
    (vers / "Modules" / "module.modulemap").write_text('framework module Mpv {\n  umbrella header "Mpv.h"\n  export *\n  module * { export * }\n}\n')
    (vers / "Resources" / "Info.plist").write_text(f"""<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>Mpv</string>
  <key>CFBundleIdentifier</key>
  <string>io.mpv.Mpv</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>Mpv</string>
  <key>CFBundlePackageType</key>
  <string>FMWK</string>
  <key>CFBundleShortVersionString</key>
  <string>{version}</string>
  <key>CFBundleVersion</key>
  <string>{version}</string>
</dict>
</plist>
""")
    framework = work / "Mpv.framework"
    (framework / "Versions" / "Current").symlink_to("A")
    (framework / "Headers").symlink_to("Versions/Current/Headers")
    (framework / "Mpv").symlink_to("Versions/Current/Mpv")
    (framework / "Modules").symlink_to("Versions/Current/Modules")
    (framework / "Resources").symlink_to("Versions/Current/Resources")
    xcframework = work / "Mpv.xcframework"
    run(["xcodebuild", "-create-xcframework", "-framework", str(framework), "-output", str(xcframework)], base)
    path = dist / f"{stem}.{RELEASE_ARCHIVE_EXT[build_target.build_os]}"
    archive(work, path, ["Mpv.xcframework"])
    return path


# Packs release shared libraries and headers in a zip
# Release jar:
#   lib/<arch>/
#     libmpv.so
#     <needed>.so
def package_release_android(base: Path, build_target: BuildTarget, build_variant: BuildVariant, prefix: Path) -> Path:
    dist = base / DIST_DIR
    dist.mkdir(exist_ok=True)
    stem = f"libmpv_{build_target.build_os}_{build_target.build_arch}_{build_variant}"
    libs = sorted(leaf for leaf in (prefix / "lib").iterdir() if not leaf.is_dir() and leaf.suffix != ".a")
    names = {"libmpv.so"}
    for leaf in libs:
        out = subprocess.run(["strings", "-a", leaf.resolve()], capture_output=True, check=True)
        text = out.stdout.decode("utf-8", "replace")
        names |= {token for token in text.split() if token.startswith("lib") and ".so" in token}
    libs = [leaf for leaf in libs if leaf.name in names]
    path = dist / f"{stem}.{RELEASE_ARCHIVE_EXT[build_target.build_os]}"
    src = base / DEPS_DIR / f"src-{build_target}"
    shutil.rmtree(src, ignore_errors=True)
    (src / "lib" / build_target.build_arch).mkdir(parents=True)
    for leaf in libs:
        shutil.copy2(leaf, src / "lib" / build_target.build_arch / leaf.name)
    archive(src, path, ["lib"])
    shutil.rmtree(src, ignore_errors=True)
    return path


# Packs release shared libraries and headers in a jar
# Release zip:
#   include/mpv/*.h
#   *.dll.a
#   *.dll
def package_release_windows(base: Path, build_target: BuildTarget, build_variant: BuildVariant, prefix: Path) -> Path:
    dist = base / DIST_DIR
    dist.mkdir(exist_ok=True)
    stem = f"libmpv_{build_target.build_os}_{build_target.build_arch}_{build_variant}"
    path = dist / f"{stem}.{RELEASE_ARCHIVE_EXT[build_target.build_os]}"
    src = base / DEPS_DIR / f"src-{build_target}"
    shutil.rmtree(src, ignore_errors=True)
    (src / "include" / "mpv").mkdir(parents=True)
    for leaf in sorted((prefix / "include" / "mpv").glob("*.h")):
        shutil.copy(leaf, src / "include" / "mpv" / leaf.name)
    members = ["include"]
    for leaf in sorted((prefix / "lib").glob("*.dll.a")):
        shutil.copy(leaf, src / leaf.name)
        members.append(leaf.name)
    for leaf in sorted((prefix / "bin").glob("*.dll")):
        shutil.copy(leaf, src / leaf.name)
        members.append(leaf.name)
    archive(src, path, members)
    shutil.rmtree(src, ignore_errors=True)
    return path


# Packs release shared libraries and headers in a zip
# Release zip:
#   lib/
#     *.so*
#   include/
def package_release_linux(base: Path, build_target: BuildTarget, build_variant: BuildVariant, prefix: Path) -> Path:
    dist = base / DIST_DIR
    dist.mkdir(exist_ok=True)
    stem = f"libmpv_{build_target.build_os}_{build_target.build_arch}_{build_variant}"
    path = dist / f"{stem}.{RELEASE_ARCHIVE_EXT[build_target.build_os]}"
    src = base / DEPS_DIR / f"src-{build_target}"
    shutil.rmtree(src, ignore_errors=True)
    (src / "lib").mkdir(parents=True)
    for leaf in sorted((prefix / "lib").iterdir()):
        if not leaf.is_dir() and leaf.suffix != ".a":
            shutil.copy2(leaf, src / "lib" / leaf.name)
    shutil.copytree(prefix / "include", src / "include")
    archive(src, path, ["lib", "include"])
    shutil.rmtree(src, ignore_errors=True)
    return path


# Packages the debug symbols artifact for one target
def package_debug(base: Path, build_target: BuildTarget, build_variant: BuildVariant, prefix: Path) -> Path:
    if build_target.build_os == BuildOS.IOS or build_target.build_os == BuildOS.MACOS:
        return package_debug_darwin(base, build_target, build_variant, prefix)
    if build_target.build_os == BuildOS.ANDROID:
        return package_debug_android(base, build_target, build_variant, prefix)
    if build_target.build_os == BuildOS.WINDOWS:
        return package_debug_windows(base, build_target, build_variant, prefix)
    return package_debug_linux(base, build_target, build_variant, prefix)


# Packs debug symbols and static archives in a zip
# Debug zip:
#   lib/
#     *.dSYM/
#     *.a
def package_debug_darwin(base: Path, build_target: BuildTarget, build_variant: BuildVariant, prefix: Path) -> Path:
    dist = base / DIST_DIR
    dist.mkdir(exist_ok=True)
    stem = f"libmpv_{build_target.build_os}_{build_target.build_arch}_{build_variant}"
    debug = dist / f"{stem}-debug.{DEBUG_SYMBOL_ARCHIVE_EXT[build_target.build_os]}"
    src = base / DEPS_DIR / f"src-{build_target}"
    shutil.rmtree(src, ignore_errors=True)
    assemble_debug_symbols(prefix, src / "lib")
    archive(src, debug, ["lib"])
    shutil.rmtree(src, ignore_errors=True)
    return debug


# Packs debug symbols and static archives in a zip
# Debug zip:
#   lib/<arch>/
#     *.debug
#     *.a
def package_debug_android(base: Path, build_target: BuildTarget, build_variant: BuildVariant, prefix: Path) -> Path:
    dist = base / DIST_DIR
    dist.mkdir(exist_ok=True)
    stem = f"libmpv_{build_target.build_os}_{build_target.build_arch}_{build_variant}"
    debug = dist / f"{stem}-debug.{DEBUG_SYMBOL_ARCHIVE_EXT[build_target.build_os]}"
    src = base / DEPS_DIR / f"src-{build_target}"
    shutil.rmtree(src, ignore_errors=True)
    src.mkdir(parents=True)
    assemble_debug_symbols(prefix, src / "lib" / build_target.build_arch)
    archive(src, debug, ["lib"])
    shutil.rmtree(src, ignore_errors=True)
    return debug


# Packs debug symbols and static archives in a zip
# Debug zip:
#   *.debug
#   *.a
def package_debug_windows(base: Path, build_target: BuildTarget, build_variant: BuildVariant, prefix: Path) -> Path:
    dist = base / DIST_DIR
    dist.mkdir(exist_ok=True)
    stem = f"libmpv_{build_target.build_os}_{build_target.build_arch}_{build_variant}"
    debug = dist / f"{stem}-debug.{DEBUG_SYMBOL_ARCHIVE_EXT[build_target.build_os]}"
    src = base / DEPS_DIR / f"src-{build_target}"
    shutil.rmtree(src, ignore_errors=True)
    src.mkdir(parents=True)
    assemble_debug_symbols(prefix, src)
    archive(src, debug, sorted(leaf.name for leaf in src.iterdir()))
    shutil.rmtree(src, ignore_errors=True)
    return debug


# Packs debug symbols and static archives in a zip
# Debug zip:
#   lib/
#     *.debug
#     *.a
def package_debug_linux(base: Path, build_target: BuildTarget, build_variant: BuildVariant, prefix: Path) -> Path:
    dist = base / DIST_DIR
    dist.mkdir(exist_ok=True)
    stem = f"libmpv_{build_target.build_os}_{build_target.build_arch}_{build_variant}"
    debug = dist / f"{stem}-debug.{DEBUG_SYMBOL_ARCHIVE_EXT[build_target.build_os]}"
    src = base / DEPS_DIR / f"src-{build_target}"
    shutil.rmtree(src, ignore_errors=True)
    src.mkdir(parents=True)
    assemble_debug_symbols(prefix, src / "lib")
    archive(src, debug, ["lib"])
    shutil.rmtree(src, ignore_errors=True)
    return debug


# ----------------------------------------------------------------------------
# Files
# ----------------------------------------------------------------------------


# Downloads a file
def download(url: str, sha: str, dest: Path) -> None:
    def verify() -> None:
        digest = hashlib.sha256()
        with open(dest, "rb") as handle:
            for chunk in iter(lambda: handle.read(65536), b""):
                digest.update(chunk)
        if digest.hexdigest() != sha:
            dest.unlink()
            abort(f"bad sha256: {dest}")

    if dest.exists():
        verify()
        return
    for attempt in (1, 2, 3):
        try:
            with urllib.request.urlopen(url, timeout=120) as response, open(dest, "wb") as handle:
                shutil.copyfileobj(response, handle)
            verify()
            return
        except (OSError, ValueError):
            if attempt == 3:
                raise


# Archives a zip file
def archive(src: Path, dest: Path, members: list[str]) -> None:
    def visit(leaf: Path, archive_name: str) -> None:
        if leaf.is_symlink():
            info = zipfile.ZipInfo(archive_name)
            info.external_attr = (stat.S_IFLNK | 0o777) << 16
            bundle.writestr(info, os.readlink(leaf))
        elif leaf.is_dir():
            for kid in sorted(leaf.iterdir()):
                visit(kid, f"{archive_name}/{kid.name}")
        else:
            bundle.write(leaf, archive_name)

    dest.unlink(missing_ok=True)
    with zipfile.ZipFile(dest, "w", zipfile.ZIP_DEFLATED) as bundle:
        for member in members:
            visit(src / member, member)


# Unarchives a zip or tarball file
def unarchive(src: Path, dest: Path) -> Path:
    shutil.rmtree(dest, ignore_errors=True)
    dest.mkdir(parents=True)
    if zipfile.is_zipfile(src):
        with zipfile.ZipFile(src) as bundle:
            for info in bundle.infolist():
                attrs = info.external_attr >> 16
                if stat.S_ISLNK(attrs):
                    target = dest / info.filename
                    target.parent.mkdir(parents=True, exist_ok=True)
                    target.symlink_to(bundle.read(info).decode())
                else:
                    target = Path(bundle.extract(info, dest))
                    mode = stat.S_IMODE(attrs)
                    if mode:
                        target.chmod(mode)
    else:
        with tarfile.open(src) as bundle:
            bundle.extractall(dest)
    return dest


# ----------------------------------------------------------------------------
# Commandline
# ----------------------------------------------------------------------------


# Runs a command and aborts on failure
def run(cmd: list[str], cwd: Path, build_env: BuildEnv = {}) -> None:
    env = {**os.environ, **build_env}
    if "BINDIR" in build_env:
        env["PATH"] = build_env["BINDIR"] + os.pathsep + env["PATH"]
    done = subprocess.run(cmd, cwd=cwd, env=env)
    if done.returncode != 0:
        abort(f"failed in {cwd}: {' '.join(str(part) for part in cmd)}")


# Aborts with a message
def abort(message: str) -> NoReturn:
    sys.exit(message)


if __name__ == "__main__":
    sys.exit(main())
