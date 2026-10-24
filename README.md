# LLM Agents & Tools Status Inspector

ローカル環境にある LLM 関連 CLI ツール、systemd サービス、HTTP API の状態を確認する Bash スクリプトです。

## 機能

- Ollama、llama-server、lemonade-server の systemd サービス状態を確認します。
- 指定した CLI ツールのインストール状況、バージョン、プロセス実行状況を表示します。
- npm で管理されている CLI の更新候補を調べ、確認後に更新できます。
- Ollama、llama.cpp、Lemonade のローカル API エンドポイントを確認し、HTTP 200 の場合は取得可能なサーバーバージョンを表示します。
- llama.cpp の最新 GitHub リリースタグも表示します。
- 検出したサービスや CLI の操作コマンドを表示します。

## 対象ツール

CLI: `qwen`、`mimo`、`cline`、`continue`、`aider`、`claude`、`hf`、`tiny-agents`、`llama`、`unsloth`

systemd サービス: `ollama`、`llama-server`、`lemonade-server`

## 実行方法

```bash
bash llm-agent-man.sh
```

または、実行権限を設定したうえで直接実行します。

```bash
./llm-agent-man.sh
```

## 必要なコマンド

- Bash
- `systemctl`
- `curl`
- `pgrep`
- `npm` と Node.js（npm パッケージ対応 CLI の更新確認に使用）
- `python3`（pipx 管理 CLI の有無の判定に使用）

環境にないコマンドや確認できない情報は、スクリプトの判定結果に反映されない場合があります。

## 更新確認に関する注意

- npm の更新は `npm outdated -g --json` で報告された候補のみを表示します。更新の実行前に確認を求めます。
- `llama` はソースビルドを想定し、このスクリプトからの自動更新対象外として表示します。更新する場合は使用している clone/build 手順で管理してください。
- llama.cpp の更新と、タグバージョンが変わった場合の HIP ビルドは `update-and-build-llama-cpp.sh` で個別に実行できます。`llm-agent-man.sh` からは呼び出されません。
- pipx 管理の CLI は更新確認を行わず、「Not checked (pipx)」として扱います。最新版とは表示しません。
- npm パッケージの `bin` 定義から CLI 名との対応が一意に特定できない場合、npm パッケージとして更新確認できません。
- CLI のバージョン表示形式はツールごとに異なるため、バージョンを抽出できない場合は `Unknown` と表示されます。
- API の稼働確認には Ollama `/`、llama.cpp `/health`、Lemonade `/` を使います。HTTP 200 のとき、Ollama `/api/version`、llama.cpp `/props`、Lemonade `/api/version` からバージョンを取得します。バージョン情報が取得できない場合も、API の応答状態は別に表示します。
- llama.cpp の GitHub バージョンは GitHub Releases API の最新安定版リリースタグです。通信できない場合は `Unavailable` と表示されます。
- 強制停止コマンドは表示のみで、自動実行しません。実行する場合は対象プロセスを確認してください。

## llama.cpp の更新とビルド

```bash
./update-and-build-llama-cpp.sh
```

スクリプトは `/home/tomjerry/Projects/Sources/llama.cpp` で `git pull` を実行し、`git describe --tags` の結果が変わった場合だけ既存の `build` ディレクトリを削除して HIP 向けに再構成・ビルドします。ビルド並列数は 2 に制限しています。
`llm-agent-man.sh` 側で `git pull` を実行してバージョンが変わった場合は、更新済みソースをビルドするコマンドとして次を表示します。

```bash
./update-and-build-llama-cpp.sh --build-current
```

`--build-current` は追加の `git pull` をせず、現在のチェックアウトをビルドします。

## 作成経緯

Google Gemini が提示した Bash シェルスクリプトを、vscode の Copilot お試し GPT 6 Luna で修正して仕上げました。以降のスクリプト修正作業は、vscode から Copilot の無料枠を利用して行いました。
