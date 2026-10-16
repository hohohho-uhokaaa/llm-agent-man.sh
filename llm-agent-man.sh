#!/usr/bin/env bash

# 表示に使用する色コードを定義する
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 状態やバージョンを確認する CLI ツールと systemd サービスを列挙する
CLI_TARGETS=("qwen" "mimo" "cline" "continue" "aider" "claude" "hf" "tiny-agents" "llama" "unsloth")
SERVICE_TARGETS=("ollama" "llama-server" "lemonade-server")

# スクリプトのタイトルを色付きで表示する
echo -e "${CYAN}========================================================================${NC}"
echo -e "${CYAN}           LLM Agents & Tools Status & Version Inspector                ${NC}"
echo -e "${CYAN}========================================================================${NC}\n"

# 1. 対象サービスがシステムまたはユーザー単位で稼働中か、登録済みかを確認する
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

FOUND_CLIS=()
UPDATE_COMMANDS=()
UPDATE_TYPES=()
UPDATE_PACKAGES=()
UPDATE_UNCHECKED=()

# npm のグローバルパッケージ一覧と更新情報をまとめて取得する
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

# npm パッケージの bin 定義を調べ、CLI 名に一致するパッケージ名を返す
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

# npm outdated の JSON から指定パッケージの最新バージョンを取得する
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

for cmd in "${CLI_TARGETS[@]}"; do
    cmd_path=$(command -v "$cmd" 2>/dev/null)
    if [ -n "$cmd_path" ]; then
        inst_status="${GREEN}Yes${NC}"
        FOUND_CLIS+=("$cmd")
    else
        continue
    fi

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

    # npm パッケージの判定
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

    if [ "$update_checked" = true ] && [ -z "$latest_ver" ]; then
        latest_ver="No update reported"
    fi

    if [ "$is_outdated" = true ]; then
        lat_display="${YELLOW}$latest_ver (Updatable)${NC}"
    elif [ "$latest_ver" = "Not checked (pipx)" ]; then
        lat_display="${YELLOW}$latest_ver${NC}"
    else
        lat_display="${GREEN}$latest_ver${NC}"
    fi

    # コマンド名との完全一致でプロセスの有無を確認する
    if pgrep -x -- "$cmd" > /dev/null 2>&1; then
        run_status="${GREEN}● Running${NC}"
    else
        run_status="${RED}○ Inactive${NC}"
    fi

    printf "%-15s %-20b %-15s %-35b %-20b\n" "$cmd" "$inst_status" "$curr_ver" "$lat_display" "$run_status"
done
echo ""

# 3. ローカル LLM API の HTTP 応答を制限時間付きで確認する
echo -e "${YELLOW}[ Local LLM API Endpoints ]${NC}"
check_endpoint() {
    local name=$1
    local url=$2
    if curl --fail --silent --connect-timeout 1 --max-time 3 "$url" > /dev/null 2>&1; then
        echo -e "  $name ($url): ${GREEN}● Responding${NC}"
    else
        echo -e "  $name ($url): ${RED}○ No Response${NC}"
    fi
}

check_endpoint "Ollama API" "http://127.0.0.1:11434/"
check_endpoint "llama.cpp / llama-server" "http://127.0.0.1:8080/health"
echo ""

# 4. 検出したサービスの種類と CLI に応じた操作コマンドを案内する
echo -e "${YELLOW}[ Control Commands for Detected Items ]${NC}"
echo "------------------------------------------------------------------------"

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

for cmd in "${FOUND_CLIS[@]}"; do
    echo -e "${CYAN}• CLI Tool: $cmd${NC}"
    echo -e "  - 起動/実行: ${YELLOW}$cmd${NC}"
    echo -e "  - 強制停止:   ${YELLOW}pkill -x $cmd${NC}"
    echo ""
done

# 5. npm の更新候補を表示し、利用者の確認後に個別に更新する
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
        # 登録した更新情報を使って実行し、失敗件数を集計する
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

echo -e "${CYAN}========================================================================${NC}"
