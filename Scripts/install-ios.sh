#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
project_file="${project_root}/TaskTracker.xcodeproj"
project_settings="${project_file}/project.pbxproj"
local_config="${project_root}/.tasktracker-install.conf"
derived_data="${project_root}/.build/InstallDerivedData"
app_path="${derived_data}/Build/Products/Debug-iphoneos/TaskTracker.app"

usage() {
  cat <<'EOF'
用法：./Scripts/install-ios.sh [--team TEAM_ID] [--bundle-id BUNDLE_ID] [--device UDID] [--check]

连接并解锁 iPhone/iPad 后，此脚本用 Xcode 构建、签名、安装并启动 Task Tracker。
第一次使用前：在 Xcode > Settings > Accounts 登录自己的 Apple 账号。
可通过 TASKTRACKER_TEAM_ID、TASKTRACKER_BUNDLE_ID、TASKTRACKER_DEVICE_ID 环境变量覆盖参数。
安装成功后，团队和 Bundle ID 会保存在仅本机使用的 .tasktracker-install.conf。
--check 只检查配置和设备，不构建或安装。
EOF
}

fail() {
  printf '安装未完成：%s\n' "$*" >&2
  exit 1
}

team_option=""
bundle_option=""
device_option=""
check_only=false
while (($#)); do
  case "$1" in
    --team|--bundle-id|--device)
      (($# >= 2)) || fail "$1 缺少参数。"
      case "$1" in
        --team) team_option="$2" ;;
        --bundle-id) bundle_option="$2" ;;
        --device) device_option="$2" ;;
      esac
      shift 2
      ;;
    --check)
      check_only=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      fail "未知参数：$1"
      ;;
  esac
done

[[ "$(uname -s)" == Darwin ]] || fail "真机安装需要 macOS 和 Xcode。"
command -v xcodebuild >/dev/null || fail "找不到 Xcode。请先从 App Store 安装并打开 Xcode。"
command -v xcrun >/dev/null || fail "找不到 xcrun。请完成 Xcode 的首次设置。"
[[ -x /usr/bin/ruby ]] || fail "找不到 macOS 自带的 Ruby，无法读取设备列表。"
if ! xcodebuild -version >/dev/null 2>&1; then
  fail "Xcode 尚未准备好。请打开 Xcode 完成首次设置，并确认命令行工具指向 Xcode。"
fi

saved_team=""
saved_bundle=""
if [[ -f "$local_config" ]]; then
  while IFS='=' read -r key value; do
    case "$key" in
      TEAM_ID) saved_team="$value" ;;
      BUNDLE_ID) saved_bundle="$value" ;;
    esac
  done < "$local_config"
fi

team_id="${team_option:-${TASKTRACKER_TEAM_ID:-$saved_team}}"
if [[ -z "$team_id" ]]; then
  identity_output="$(security find-identity -v -p codesigning 2>/dev/null || true)"
  team_candidates=()
  team_labels=()
  while IFS=$'\t' read -r candidate_id candidate_label; do
    [[ -n "$candidate_id" ]] || continue
    team_candidates+=("$candidate_id")
    team_labels+=("$candidate_label")
  done < <(printf '%s\n' "$identity_output" | /usr/bin/ruby -ne '
    if $_ =~ /"(Apple Development: [^"]+ \(([A-Z0-9]{10})\))"/
      id = Regexp.last_match(2)
      unless ($seen ||= {})[id]
        puts "#{id}\t#{Regexp.last_match(1)}"
        $seen[id] = true
      end
    end
  ')

  if ((${#team_candidates[@]} == 1)); then
    team_id="${team_candidates[0]}"
  elif ((${#team_candidates[@]} > 1)); then
    [[ -t 0 ]] || fail "找到多个 Apple Development 团队，请用 --team TEAM_ID 指定。"
    printf '请选择你自己的 Apple 开发团队：\n'
    for ((index = 0; index < ${#team_candidates[@]}; index++)); do
      printf '  %d) %s\n' "$((index + 1))" "${team_labels[index]}"
    done
    read -r -p '团队序号：' choice
    [[ "$choice" =~ ^[0-9]+$ ]] || fail "无效的团队序号。"
    choice=$((10#$choice))
    ((choice >= 1 && choice <= ${#team_candidates[@]})) \
      || fail "无效的团队序号。"
    team_id="${team_candidates[choice - 1]}"
  else
    # Accept a team selected locally in Xcode, but never silently use the
    # repository owner's committed team when no matching certificate exists.
    project_team="$(/usr/bin/ruby -e '
      teams = File.read(ARGV.fetch(0)).scan(/DEVELOPMENT_TEAM = ([A-Z0-9]{10});/).flatten.uniq
      puts teams.first if teams.length == 1
    ' "$project_settings")"
    if [[ -n "$project_team" && "$project_team" != "TA444477QY" ]]; then
      team_id="$project_team"
    else
      fail "找不到你自己的开发团队。请在 Xcode > Settings > Accounts 登录 Apple 账号，选中自己的 Team，点 Manage Certificates > + > Apple Development，然后重试；也可运行 --team 你的10位TeamID。"
    fi
  fi
fi

team_id="$(printf '%s' "$team_id" | tr '[:lower:]' '[:upper:]')"
[[ "$team_id" =~ ^[A-Z0-9]{10}$ ]] || fail "Team ID 应为 10 位字母或数字。"

if [[ "$team_id" != "$saved_team" && -z "$bundle_option" && -z "${TASKTRACKER_BUNDLE_ID:-}" ]]; then
  saved_bundle=""
fi
bundle_id="${bundle_option:-${TASKTRACKER_BUNDLE_ID:-$saved_bundle}}"
if [[ -z "$bundle_id" ]]; then
  if [[ "$team_id" == "TA444477QY" ]]; then
    # Keep the author's existing installation and its local data intact.
    bundle_id="com.wangfeiyang0845l.TaskTracker"
  else
    team_suffix="$(printf '%s' "$team_id" | tr '[:upper:]' '[:lower:]')"
    bundle_id="com.tasktracker.install.${team_suffix}"
  fi
fi
[[ "$bundle_id" =~ ^[A-Za-z0-9]+([.-][A-Za-z0-9]+)+$ ]] \
  || fail "Bundle ID 格式不正确：$bundle_id"

temporary_dir="$(mktemp -d)"
trap 'rm -f "$temporary_dir/devices.json" "$temporary_dir/devices.tsv"; rmdir "$temporary_dir"' EXIT
if ! xcrun devicectl --json-output "$temporary_dir/devices.json" list devices >/dev/null; then
  fail "无法读取 iPhone/iPad。请解锁设备、信任这台 Mac，并等待 Xcode 完成配对。"
fi
if ! /usr/bin/ruby -rjson -e '
  data = JSON.parse(File.read(ARGV.fetch(0)))
  data.fetch("result", {}).fetch("devices", []).each do |device|
    hardware = device.fetch("hardwareProperties", {})
    connection = device.fetch("connectionProperties", {})
    properties = device.fetch("deviceProperties", {})
    next unless ["iOS", "iPadOS"].include?(hardware["platform"])
    next unless hardware["reality"] == "physical"
    next unless connection["pairingState"] == "paired" && connection["tunnelState"] == "connected"
    udid = hardware["udid"]
    next unless udid
    puts [udid, device["identifier"], properties["name"], properties["developerModeStatus"]].join("\t")
  end
' "$temporary_dir/devices.json" > "$temporary_dir/devices.tsv"; then
  fail "设备列表无法解析。请更新 Xcode 后重试。"
fi

device_ids=()
device_core_ids=()
device_names=()
device_modes=()
while IFS=$'\t' read -r candidate_id candidate_core_id candidate_name candidate_mode; do
  [[ -n "$candidate_id" ]] || continue
  device_ids+=("$candidate_id")
  device_core_ids+=("$candidate_core_id")
  device_names+=("$candidate_name")
  device_modes+=("$candidate_mode")
done < "$temporary_dir/devices.tsv"
((${#device_ids[@]} > 0)) || fail "没有已连接的 iPhone/iPad。请连接设备、解锁并在手机上点按“信任”。"

requested_device="${device_option:-${TASKTRACKER_DEVICE_ID:-}}"
selected_index=-1
if [[ -n "$requested_device" ]]; then
  for ((index = 0; index < ${#device_ids[@]}; index++)); do
    if [[ "$requested_device" == "${device_ids[index]}" || "$requested_device" == "${device_core_ids[index]}" ]]; then
      selected_index=$index
      break
    fi
  done
  ((selected_index >= 0)) || fail "指定的设备当前未连接：$requested_device"
elif ((${#device_ids[@]} == 1)); then
  selected_index=0
else
  [[ -t 0 ]] || fail "连接了多台设备，请用 --device UDID 指定。"
  printf '请选择要安装的设备：\n'
  for ((index = 0; index < ${#device_ids[@]}; index++)); do
    printf '  %d) %s (%s)\n' "$((index + 1))" "${device_names[index]}" "${device_ids[index]}"
  done
  read -r -p '设备序号：' choice
  [[ "$choice" =~ ^[0-9]+$ ]] || fail "无效的设备序号。"
  choice=$((10#$choice))
  ((choice >= 1 && choice <= ${#device_ids[@]})) \
    || fail "无效的设备序号。"
  selected_index=$((choice - 1))
fi

device_id="${device_ids[selected_index]}"
device_name="${device_names[selected_index]}"
[[ "${device_modes[selected_index]}" == "enabled" ]] \
  || fail "${device_name} 尚未开启开发者模式。请到 iPhone/iPad 的“设置 > 隐私与安全性 > 开发者模式”开启并重启。"

printf '设备：%s\nTeam ID：%s\nBundle ID：%s\n' "$device_name" "$team_id" "$bundle_id"
if [[ "$check_only" == true ]]; then
  printf '检查通过；尚未构建或安装。\n'
  exit 0
fi

printf '正在构建并签名（首次需要连接网络，Xcode 可能会请求 Apple 账号授权）…\n'
if ! xcodebuild -quiet \
  -project "$project_file" \
  -scheme TaskTracker \
  -configuration Debug \
  -destination "platform=iOS,id=${device_id}" \
  -derivedDataPath "$derived_data" \
  -allowProvisioningUpdates \
  -allowProvisioningDeviceRegistration \
  DEVELOPMENT_TEAM="$team_id" \
  PRODUCT_BUNDLE_IDENTIFIER="$bundle_id" \
  CODE_SIGN_STYLE=Automatic \
  build; then
  fail "构建或签名失败。请确认 Xcode 已登录这个 Team 的 Apple 账号；必要时打开 TaskTracker.xcodeproj 查看 Signing & Capabilities 的错误。"
fi
[[ -d "$app_path" ]] || fail "构建结束但未找到 iPhone 版 TaskTracker.app。"
built_bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app_path/Info.plist")"
[[ "$built_bundle_id" == "$bundle_id" ]] || fail "构建产物的 Bundle ID 不匹配，已停止安装。"

printf '正在安装到 %s…\n' "$device_name"
if ! xcrun devicectl device install app --device "$device_id" "$app_path"; then
  fail "安装失败。请保持设备解锁，确认已信任此 Mac 并开启开发者模式。"
fi

umask 077
printf 'TEAM_ID=%s\nBUNDLE_ID=%s\n' "$team_id" "$bundle_id" > "$local_config"
printf '已安装，正在启动…\n'
if ! xcrun devicectl device process launch --terminate-existing --device "$device_id" "$bundle_id"; then
  fail "App 已安装但未能启动。请在设备的“设置 > 通用 > VPN 与设备管理”信任开发者 App，然后从主屏幕打开 Task Tracker。"
fi
printf 'Task Tracker 已安装并在 %s 上启动。\n' "$device_name"
