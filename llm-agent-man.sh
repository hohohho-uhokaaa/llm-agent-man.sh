#!/usr/bin/env bash

# 画面表示で使う色コードを定義する
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 状態・バージョンを確認する CLI ツールと systemd サービスを列挙する
CLI_TARGETS=("qwen" "mimo" "cline" "continue" "aider" "claude" "hf" "tiny-agents" "llama" "unsloth")
SERVICE_TARGETS=("ollama" "llama-server" "lemond" )

# スクリプトのタイトルを色付きで表示する
echo -e "${CYAN}========================================================================${NC}"
echo -e "${CYAN}           LLM Agents & Tools Status & Version Inspector                ${NC}"
echo -e "${CYAN}========================================================================${NC}\n"

# 1. 対象サービスが system/user のどちらで稼働中か、または登録済みかを確認する
echo -e "${YELLOW}[ Systemd Services ]${NC}"
FOUND_SERVICES=()
for svc in "${SERVICE_TARGETS[@]}"; do
    if systemctl is-active --quiet "$svc" 2>/dev/null; then
        echo -e "  $svc: ${GREEN}● ACTIVE (Running)${NC}"
        FOUND_SERVICES+=("system:$svc")
    elif systemctl --user is-active --quiet "$svc" 2>/dev/null; then
        echo -e "  $svc (user): ${GREEN}● ACTIVE (Running)${NC}"
        FOUND_SERVICES+=("user:$svc")
    elif systemctl list-unit-files 2>/dev/null | grep -q "^${svc}\.service" || systemctl --user list-unit-files 2>/dev/null | grep -q "^${svc}\.service"; then
        echo -e "  $svc: ${RED}○ STOPPED${NC}"
        if systemctl list-unit-files 2>/dev/null | grep -q "^${svc}\.service"; then
            FOUND_SERVICES+=("system:$svc")
        else
            FOUND_SERVICES+=("user:$svc")
        fi
    else
        echo -e "  $svc: ${NC}Not Registered${NC}"
    fi
done
echo ""

# 2. インストール済み CLI のバージョン、更新状況、実行中プロセスを確認する
echo -e "${YELLOW}[ Installed CLI Agents, Versions & Status ]${NC}"
printf "%-15s %-12s %-12s %-35s %-15s\n" "Agent/Tool" "Installed?" "Current" "Latest / Update status" "Running Process"
echo "------------------------------------------------------------------------"

# 後続の操作案内と更新処理で使う検出結果を配列に保持する
FOUND_CLIS=()
UPDATE_COMMANDS=()
UPDATE_TYPES=()
UPDATE_PACKAGES=()
UPDATE_UNCHECKED=()

# npm の問い合わせを各 CLI ごとに繰り返さないよう、一覧と更新情報を先に取得する
npm_global_json=""
npm_global_root=""
npm_outdated_json=""
npm_outdated_valid=false
if command -v npm &> /dev/null; then
    npm_global_json=$(npm list -g --depth=0 --json 2>/dev/null || true)
    npm_global_root=$(npm root -g 2>/dev/null || true)
    npm_outdated_json=$(npm outdated -g --json 2>/dev/null || true)
    if command -v node >/dev/null 2>&1 && [ -n "$npm_outdated_json" ] &&
       node -e 'const d=JSON.parse(process.argv[1]); if (!d || Array.isArray(d) || d.error) process.exit(1)' "$npm_outdated_json" 2>/dev/null; then
        npm_outdated_valid=true
    fi
fi

# npm パッケージの bin 定義から、指定した CLI を提供するパッケージ名を特定する
find_npm_package_for_command() {
    local command_name=$1
    [ -n "$npm_global_json" ] && [ -n "$npm_global_root" ] || return 1
    command -v node >/dev/null 2>&1 || return 1

    node -e '
        const fs = require("fs");
        const path = require("path");
        const data = JSON.parse(process.argv[1]);
        const root = process.argv[2];
        const target = process.argv[3];
        const matches = [];
        for (const name of Object.keys(data.dependencies || {})) {
            const manifestPath = path.join(root, name, "package.json");
            if (!fs.existsSync(manifestPath)) continue;
            const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
            const bin = manifest.bin;
            const names = typeof bin === "string"
                ? [path.basename(name)]
                : Object.keys(bin || {});
            if (names.includes(target)) matches.push(name);
        }
        if (matches.length === 1) process.stdout.write(matches[0]);
    ' "$npm_global_json" "$npm_global_root" "$command_name" 2>/dev/null
}

# npm outdated の JSON から指定パッケージの最新バージョンを取り出す
find_npm_latest_version() {
    local package_name=$1
    [ -n "$npm_outdated_json" ] || return 1
    command -v node >/dev/null 2>&1 || return 1

    node -e '
        const data = JSON.parse(process.argv[1]);
        const entry = data[process.argv[2]];
        if (entry && entry.latest) process.stdout.write(entry.latest);
    ' "$npm_outdated_json" "$package_name" 2>/dev/null
}

# インストール済み CLI を調べ、現在のバージョン・更新状況・実行状態を表示する
for cmd in "${CLI_TARGETS[@]}"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        continue
    fi
    FOUND_CLIS+=("$cmd")

    # --version、次に -v を試し、出力からセマンティックバージョンを抽出する
    curr_ver=$("$cmd" --version 2>/dev/null | head -n 1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n 1)
    if [ -z "$curr_ver" ]; then
        curr_ver=$("$cmd" -v 2>/dev/null | head -n 1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n 1)
    fi
    [ -z "$curr_ver" ] && curr_ver="Unknown"

    # npm で更新を確認し、更新対象と安全に実行するための情報を配列に保存する
    latest_ver="--"
    is_outdated=false
    update_checked=false

    pkg_name=""
    if [ "$cmd" = "llama" ]; then
        latest_ver="Source build (manual update)"
    else
        pkg_name=$(find_npm_package_for_command "$cmd")
        if [ -n "$pkg_name" ] && [ "$npm_outdated_valid" = true ]; then
            latest_ver=$(find_npm_latest_version "$pkg_name")
            update_checked=true
            if [ -n "$latest_ver" ]; then
                is_outdated=true
                UPDATE_COMMANDS+=("npm install -g $pkg_name@latest")
                UPDATE_TYPES+=("npm")
                UPDATE_PACKAGES+=("$pkg_name")
            else
                latest_ver="No update reported"
            fi
        # pipx 管理かを確認するが、出力形式による誤判定を避けるため更新確認対象外として示す
        elif command -v pipx >/dev/null 2>&1 && pipx list --json 2>/dev/null |
             python3 -c 'import json,sys; d=json.load(sys.stdin); sys.exit(0 if any(sys.argv[1] in v.get("metadata",{}).get("main_package",{}).get("apps",[]) or n == sys.argv[1] for n,v in d.get("venvs",{}).items()) else 1)' "$cmd" 2>/dev/null; then
            latest_ver="Not checked (pipx)"
            UPDATE_UNCHECKED+=("$cmd")
        else
            UPDATE_UNCHECKED+=("$cmd")
        fi
    fi

    # 更新情報の有無に応じて表示文言と色を決める
    if [ "$update_checked" = true ] && [ -z "$latest_ver" ]; then
        latest_ver="No update reported"
    fi

    if [ "$is_outdated" = true ]; then
        lat_display="${YELLOW}$latest_ver (Updatable)${NC}"
    elif [ "$latest_ver" = "Not checked (pipx)" ] ||
         [ "$latest_ver" = "Source build (manual update)" ]; then
        lat_display="${YELLOW}$latest_ver${NC}"
    else
        lat_display="${GREEN}$latest_ver${NC}"
    fi

    # プロセス名を完全一致で検索し、稼働状態を表示する
    if pgrep -x -- "$cmd" > /dev/null 2>&1; then
        run_status="${GREEN}● Running${NC}"
    else
        run_status="${RED}○ Inactive${NC}"
    fi

    printf "%-15s %-20b %-15s %-35b %-20b\n" "$cmd" "${GREEN}Yes${NC}" "$curr_ver" "$lat_display" "$run_status"
done
echo ""

# 3. ローカル LLM API に制限時間付きで接続し、応答とバージョンを確認する
echo -e "${YELLOW}[ Local LLM API Endpoints ]${NC}"
check_endpoint() {
    local name=$1
    local url=$2
    local version_url=$3
    local version_key=$4
    local status
    local version

    # HTTP 200 の場合だけ詳細バージョンを取得し、応答状態を表示する
    status=$(curl --silent --connect-timeout 1 --max-time 3 --output /dev/null \
        --write-out '%{http_code}' "$url" 2>/dev/null || true)
    if [ "$status" = "200" ]; then
        version=$(get_endpoint_version "$version_url" "$version_key" || true)
        if [ -n "$version" ]; then
            echo -e "  $name ($url): ${GREEN}● Responding (Version: $version)${NC}"
        else
            echo -e "  $name ($url): ${GREEN}● Responding${NC} (Version unavailable)"
        fi
    else
        echo -e "  $name ($url): ${RED}○ No Response (HTTP ${status:-000})${NC}"
    fi
}

# JSON 応答から指定キーの値を安全に取り出し、表示可能な長さに整える
get_endpoint_version() {
    local url=$1
    local json_key=$2
    local response
    local status
    local body

    command -v python3 >/dev/null 2>&1 || return 1
    response=$(curl --silent --connect-timeout 1 --max-time 3 \
        --write-out $'\n%{http_code}' "$url" 2>/dev/null) || return 1
    status=${response##*$'\n'}
    [ "$status" = "200" ] || return 1
    body=${response%$'\n'*}

    python3 -c '
import json
import re
import sys

# 予期しない HTTP 応答や JSON 形式では、バージョンを取得できなかったものとして扱う
try:
    value = json.loads(sys.argv[2]).get(sys.argv[1])
except (json.JSONDecodeError, AttributeError):
    sys.exit(1)
if value is not None and not isinstance(value, (dict, list)):
    print(re.sub(r"[\x00-\x1f\x7f]", "", str(value))[:128])
' "$json_key" "$body" 2>/dev/null
}

get_github_latest_release() {
    local response
    local status
    local body

    command -v python3 >/dev/null 2>&1 || return 1
    response=$(curl --silent --connect-timeout 2 --max-time 5 \
        --header 'Accept: application/vnd.github+json' \
        --header 'X-GitHub-Api-Version: 2022-11-28' \
        --write-out $'\n%{http_code}' \
        "https://api.github.com/repos/ggml-org/llama.cpp/releases/latest" 2>/dev/null) || return 1
    status=${response##*$'\n'}
    [ "$status" = "200" ] || return 1
    body=${response%$'\n'*}

    python3 -c '
import json
import re
import sys

try:
    tag = json.loads(sys.argv[1]).get("tag_name")
except (json.JSONDecodeError, AttributeError):
    sys.exit(1)
if isinstance(tag, str) and re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._+-]{0,127}", tag):
    print(tag)
else:
    sys.exit(1)
' "$body" 2>/dev/null
}

check_endpoint "Ollama API" "http://127.0.0.1:11434/" "http://127.0.0.1:11434/api/version" "version"
check_endpoint "Llama.cpp" "http://127.0.0.1:9931/health" "http://127.0.0.1:9931/props" "build_info"
llama_cpp_latest=$(get_github_latest_release || true)
if [ -n "$llama_cpp_latest" ]; then
    echo -e "  Llama.cpp latest GitHub release: ${GREEN}$llama_cpp_latest${NC}"
else
    echo -e "  Llama.cpp latest GitHub release: ${YELLOW}Unavailable${NC}"
fi
check_endpoint "Lemonade API" "http://127.0.0.1:13305" "http://127.0.0.1:13305/api/version" "version"
echo ""

# 4. 検出したサービスの実行スコープに合わせて操作コマンドを案内する
echo -e "${YELLOW}[ Control Commands for Detected Items ]${NC}"
echo "------------------------------------------------------------------------"

# systemd サービスは登録元に合った systemctl コマンドを提示する
for service in "${FOUND_SERVICES[@]}"; do
    scope=${service%%:*}
    svc=${service#*:}
    if [ "$scope" = "user" ]; then
        systemctl_cmd="systemctl --user"
        echo -e "${CYAN}• User service: $svc${NC}"
    else
        systemctl_cmd="sudo systemctl"
        echo -e "${CYAN}• System service: $svc${NC}"
    fi
    echo -e "  - 開始:   ${YELLOW}$systemctl_cmd start $svc${NC}"
    echo -e "  - 停止:   ${YELLOW}$systemctl_cmd stop $svc${NC}"
    echo -e "  - 再起動: ${YELLOW}$systemctl_cmd restart $svc${NC}"
    echo -e "  - 状態:   ${YELLOW}$systemctl_cmd status $svc${NC}"
    echo ""
done

# CLI は起動方法と、プロセス名を指定した停止方法を提示する
for cmd in "${FOUND_CLIS[@]}"; do
    echo -e "${CYAN}• CLI Tool: $cmd${NC}"
    echo -e "  - 起動/実行: ${YELLOW}$cmd${NC}"
    echo -e "  - 強制停止:   ${YELLOW}pkill -x $cmd${NC}"
    echo ""
done

# 5. npm の更新候補を表示し、利用者の同意があった場合だけ適用する
if [ ${#UPDATE_COMMANDS[@]} -gt 0 ]; then
    echo -e "${CYAN}========================================================================${NC}"
    echo -e "${YELLOW}以下のアップデートが見つかりました:${NC}"
    for u_cmd in "${UPDATE_COMMANDS[@]}"; do
        echo -e "  -> ${CYAN}$u_cmd${NC}"
    done
    echo -e "${CYAN}========================================================================${NC}"

    read -p "今すぐこれらのアップデートを適用しますか？ (y/N): " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo -e "\n${YELLOW}アップデートを実行しています...${NC}"
        # 表示用のコマンド文字列ではなく保存したパッケージ名を使って更新し、失敗数を集計する
        update_failures=0
        for i in "${!UPDATE_COMMANDS[@]}"; do
            echo -e "${CYAN}Executing: ${UPDATE_COMMANDS[$i]}${NC}"
            if [ "${UPDATE_TYPES[$i]}" = "npm" ]; then
                if ! npm install -g "${UPDATE_PACKAGES[$i]}@latest"; then
                    echo -e "${RED}更新に失敗しました: ${UPDATE_PACKAGES[$i]}${NC}"
                    update_failures=$((update_failures + 1))
                fi
            elif ! pipx upgrade "${UPDATE_PACKAGES[$i]}"; then
                echo -e "${RED}更新に失敗しました: ${UPDATE_PACKAGES[$i]}${NC}"
                update_failures=$((update_failures + 1))
            fi
        done
        if [ "$update_failures" -eq 0 ]; then
            echo -e "${GREEN}すべてのアップデートが完了しました！${NC}"
        else
            echo -e "${RED}${update_failures} 件のアップデートに失敗しました。${NC}"
        fi
    else
        # 明示的に y/Y が選ばれなければ、更新を行わず終了する
        echo -e "アップデートをスキップしました。"
    fi
else
    # 更新候補がない場合も、確認できなかったツールを最新版とは扱わず明示する
    if [ "${#UPDATE_UNCHECKED[@]}" -eq 0 ]; then
        echo -e "${GREEN}確認できたツール・エージェントに更新はありません。${NC}"
    else
        echo -e "${YELLOW}確認できたツールに更新はありません。${NC}"
        printf '更新を確認できなかったツール: %s\n' "${UPDATE_UNCHECKED[*]}"
    fi
fi

LLAMA_CPP_REPO="/home/tomjerry/Projects/Sources/llama.cpp"
echo ""
echo -e "${YELLOW}[ llama.cpp Source Update ]${NC}"
if [ ! -d "$LLAMA_CPP_REPO/.git" ]; then
    echo -e "${RED}Git リポジトリが見つかりません: $LLAMA_CPP_REPO${NC}"
else
    read -p "llama.cpp を git pull で更新しますか？ (y/N): " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        if ! llama_cpp_version_before=$(git -C "$LLAMA_CPP_REPO" describe --tags); then
            echo -e "${RED}更新前の llama.cpp バージョンを取得できませんでした。${NC}"
        else
            echo -e "更新前の llama.cpp バージョン: ${CYAN}$llama_cpp_version_before${NC}"
            if git -C "$LLAMA_CPP_REPO" pull; then
                if llama_cpp_version_after=$(git -C "$LLAMA_CPP_REPO" describe --tags); then
                    echo -e "更新後の llama.cpp バージョン: ${CYAN}$llama_cpp_version_after${NC}"
                    if [ "$llama_cpp_version_before" = "$llama_cpp_version_after" ]; then
                        echo -e "${YELLOW}llama.cpp のバージョンに変化はありません。${NC}"
                    else
                        echo -e "${GREEN}llama.cpp のバージョンが更新されました。${NC}"
                        llama_cpp_build_script="$(dirname -- "${BASH_SOURCE[0]}")/update-and-build-llama-cpp.sh"
                        echo -e "ビルドする場合は次のコマンドを実行してください:"
                        echo -e "${CYAN}bash \"$llama_cpp_build_script\" --build-current${NC}"
                    fi
                else
                    echo -e "${RED}更新後の llama.cpp バージョンを取得できませんでした。${NC}"
                fi
            else
                echo -e "${RED}llama.cpp の git pull に失敗しました。${NC}"
            fi
        fi
    else
        echo -e "llama.cpp の更新をスキップしました。"
    fi
fi

echo -e "${CYAN}========================================================================${NC}"
