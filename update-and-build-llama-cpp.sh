#!/usr/bin/env bash

# 現在の llama.cpp ソースをビルドしてインストールする
set -euo pipefail

# 対象となる llama.cpp の作業ツリー
LLAMA_CPP_REPO="/home/tomjerry/Projects/Sources/llama.cpp"

if [ ! -f "$LLAMA_CPP_REPO/CMakeLists.txt" ]; then
    echo "llama.cpp のソースが見つかりません: $LLAMA_CPP_REPO" >&2
    exit 1
fi

echo "llama.cpp をビルドします。"
# Fedora 44、Ryzen 5 2400G、メモリ 16 GB の低スペック PC をターゲットとする
# 以前の CMake 設定が残らないよう既存のビルドディレクトリを作り直す
rm -rf -- "$LLAMA_CPP_REPO/build"

# HIP を有効にし、gfx902 向けの Release ビルドを構成する
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

# ビルドが成功した場合に限り、ユーザーのローカル領域へインストールする
if ! (cd "$LLAMA_CPP_REPO" && cmake --install build --prefix /home/tomjerry/.local); then
    echo "llama.cpp のインストールに失敗しました。" >&2
    exit 1
fi

echo "llama.cpp のインストールが完了しました。"
