#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
derived_data="${project_root}/.build/DerivedData"
project_file="${project_root}/TaskTracker.xcodeproj"
app_path="${derived_data}/Build/Products/Debug-iphonesimulator/TaskTracker.app"
action="${1:-}"

select_simulator() {
  xcrun simctl list devices available -j | /usr/bin/ruby -rjson -e '
    devices = JSON.parse(STDIN.read).fetch("devices").values.flatten
    iphones = devices.select { |device| device["isAvailable"] && device["name"].start_with?("iPhone") }
    preferred = ENV["TASKTRACKER_SIMULATOR_NAME"]
    device = if preferred && !preferred.empty?
      iphones.find { |item| item["name"] == preferred }
    else
      iphones.find { |item| item["state"] == "Booted" } || iphones.first
    end
    abort "No available iPhone Simulator#{preferred ? ": #{preferred}" : ""}. Install an iOS Simulator runtime in Xcode." unless device
    puts device.fetch("udid")
  '
}

build_simulator() {
  xcodebuild -quiet \
    -project "$project_file" \
    -scheme TaskTracker \
    -configuration Debug \
    -destination 'generic/platform=iOS Simulator' \
    -derivedDataPath "$derived_data" \
    CODE_SIGNING_ALLOWED=NO \
    build
}

case "$action" in
  build)
    build_simulator
    printf '模拟器版构建成功。\n'
    ;;
  test)
    simulator_id="$(select_simulator)"
    xcodebuild -quiet \
      -project "$project_file" \
      -scheme TaskTracker \
      -configuration Debug \
      -destination "platform=iOS Simulator,id=${simulator_id}" \
      -derivedDataPath "$derived_data" \
      CODE_SIGNING_ALLOWED=NO \
      test
    printf '自动测试通过。\n'
    ;;
  run)
    simulator_id="$(select_simulator)"
    if ! xcrun simctl list devices booted -j | /usr/bin/ruby -rjson -e '
      devices = JSON.parse(STDIN.read).fetch("devices").values.flatten
      exit(devices.any? { |device| device["udid"] == ARGV.fetch(0) } ? 0 : 1)
    ' "$simulator_id"; then
      xcrun simctl boot "$simulator_id"
    fi
    xcrun simctl bootstatus "$simulator_id" -b
    open -a Simulator
    build_simulator
    xcrun simctl install "$simulator_id" "$app_path"
    bundle_identifier="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app_path/Info.plist")"
    xcrun simctl launch --terminate-running-process "$simulator_id" "$bundle_identifier"
    printf '已在 iPhone 模拟器启动 Task Tracker。\n'
    ;;
  *)
    printf '用法：%s {build|test|run}\n' "$0" >&2
    exit 2
    ;;
esac
