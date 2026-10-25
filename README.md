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
- llama.cpp は、作業ツリーに未コミット変更がなく、追跡先リモートが fast-forward 可能な場合に `llm-agent-man.sh` が更新します。更新後のビルド・インストールは `update-and-build-llama-cpp.sh` で行います。
- pipx 管理の CLI は更新確認を行わず、「Not checked (pipx)」として扱います。最新版とは表示しません。
- npm パッケージの `bin` 定義から CLI 名との対応が一意に特定できない場合、npm パッケージとして更新確認できません。
- CLI のバージョン表示形式はツールごとに異なるため、バージョンを抽出できない場合は `Unknown` と表示されます。
- API の稼働確認には Ollama `/`、llama.cpp `/health`、Lemonade `/` を使います。HTTP 200 のとき、Ollama `/api/version`、llama.cpp `/props`、Lemonade `/api/version` からバージョンを取得します。バージョン情報が取得できない場合も、API の応答状態は別に表示します。
- llama.cpp の GitHub バージョンは GitHub Releases API の最新安定版リリースタグです。通信できない場合は `Unavailable` と表示されます。
- 強制停止コマンドは表示のみで、自動実行しません。実行する場合は対象プロセスを確認してください。

## llama.cpp のビルドとインストール

```bash
./update-and-build-llama-cpp.sh
```

このスクリプトは `/home/tomjerry/Projects/Sources/llama.cpp` の現在のソースを HIP（`gfx902`）向けに構成・ビルドし、`/home/tomjerry/.local` にインストールします。既存の `build` ディレクトリは作り直し、ビルド並列数は 2 に制限します。Git の更新は行いません。

`llm-agent-man.sh` が llama.cpp を更新した場合は、このスクリプトを実行するコマンドを表示します。更新とビルド・インストールは別々に行われるため、ビルド完了まで `llm-agent-man.sh` の実行を待つ必要はありません。

## 作成経緯

Google Gemini が提示した Bash シェルスクリプトを、vscode の Copilot お試し GPT 6 Luna で修正して仕上げました。以降のスクリプト修正作業は、vscode から Copilot の無料枠を利用して行いました。

Copilot に相談しながら修正を重ねていたら、自宅 PC の状態チェック用だったはずのスクリプトが、いつの間にか llama.cpp のリポジトリ更新を気にかけすぎる存在に。便利にはなったものの、「うちの PC の状態チェック、どこへ行った？」と少し違和感を覚えています。
