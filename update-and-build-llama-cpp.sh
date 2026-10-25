#!/usr/bin/env bash

# llama.cpp の更新状況を確認し、ビルド・インストール後に実行バージョンを表示する
set -euo pipefail

# 対象となる llama.cpp の作業ツリー
LLAMA_CPP_REPO="/home/tomjerry/Projects/Sources/llama.cpp"

# --build-current を指定すると git pull を省略して現在のソースをビルドする
build_current=false
if [ "$#" -gt 1 ] || { [ "$#" -eq 1 ] && [ "$1" != "--build-current" ]; }; then
    echo "使い方: $0 [--build-current]" >&2
    exit 2
fi
if [ "${1:-}" = "--build-current" ]; then
    build_current=true
fi

# 対象ディレクトリが Git リポジトリか確認する
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
    # 更新前後のタグを比較し、ソースに変化がなければビルドを省略する
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

# インストールされた llama-server が起動し、バージョンを返すことを確認する
if ! llama-server --version; then
    echo "llama-server のバージョン確認に失敗しました。" >&2
    exit 1
fi
