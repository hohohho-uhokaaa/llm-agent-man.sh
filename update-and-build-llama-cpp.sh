#!/usr/bin/env bash

set -euo pipefail

LLAMA_CPP_REPO="/home/tomjerry/Projects/Sources/llama.cpp"

build_current=false
if [ "$#" -gt 1 ] || { [ "$#" -eq 1 ] && [ "$1" != "--build-current" ]; }; then
    echo "使い方: $0 [--build-current]" >&2
    exit 2
fi
if [ "${1:-}" = "--build-current" ]; then
    build_current=true
fi

if ! git -C "$LLAMA_CPP_REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "Git リポジトリが見つかりません: $LLAMA_CPP_REPO" >&2
    exit 1
fi

if [ "$build_current" = true ]; then
    if ! current_version=$(git -C "$LLAMA_CPP_REPO" describe --tags); then
        echo "現在の llama.cpp バージョンを取得できませんでした。" >&2
        exit 1
    fi
    echo "現在の llama.cpp バージョンをビルドします: $current_version"
else
    if ! version_before=$(git -C "$LLAMA_CPP_REPO" describe --tags); then
        echo "更新前の llama.cpp バージョンを取得できませんでした。" >&2
        exit 1
    fi
    echo "更新前の llama.cpp バージョン: $version_before"

    if ! git -C "$LLAMA_CPP_REPO" pull; then
        echo "llama.cpp の git pull に失敗しました。" >&2
        exit 1
    fi

    if ! version_after=$(git -C "$LLAMA_CPP_REPO" describe --tags); then
        echo "更新後の llama.cpp バージョンを取得できませんでした。" >&2
        exit 1
    fi
    echo "更新後の llama.cpp バージョン: $version_after"

    if [ "$version_before" = "$version_after" ]; then
        echo "llama.cpp のバージョンに変化はありません。ビルドをスキップします。"
        exit 0
    fi
fi

echo "llama.cpp をビルドします。"
rm -rf -- "$LLAMA_CPP_REPO/build"

if ! (
    cd "$LLAMA_CPP_REPO" &&
        cmake -B build \
            -DGGML_HIP=ON \
            -DAMDGPU_TARGETS=gfx902 \
            -DCMAKE_BUILD_TYPE=Release
); then
    echo "llama.cpp の CMake 構成に失敗しました。" >&2
    exit 1
fi

if ! (cd "$LLAMA_CPP_REPO" && cmake --build build --parallel 2); then
    echo "llama.cpp のビルドに失敗しました。" >&2
    exit 1
fi

echo "llama.cpp のビルドが完了しました。"
