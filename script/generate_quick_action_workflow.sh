#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_ROOT="$ROOT_DIR/Resources/QuickAction"
ALLOWLIST_CONVERT="csv docx htm html json msg pdf pptx txt xls xlsx xml"
ALLOWLIST_COMBINE="csv docx htm html json markdown md mdown mkd msg pdf pptx txt xls xlsx xml"

generate_workflow() {
  local title="$1"
  local host="$2"
  local subtitle="$3"
  local allowlist="$4"
  local output_dir="$OUTPUT_ROOT/${title}.workflow"

  mkdir -p "$output_dir/Contents"

  cat >"$output_dir/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key>
  <string>com.apple.automator.${title// /-}</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>${title}</string>
  <key>CFBundlePackageType</key>
  <string>BNDL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>NSHumanReadableCopyright</key>
  <string>MarkItDown</string>
</dict>
</plist>
PLIST

  python3 - "$host" "$subtitle" "$title" "$allowlist" "$output_dir/Contents/document.wflow" <<'PY'
import plistlib
import sys

host = sys.argv[1]
subtitle = sys.argv[2]
title = sys.argv[3]
allowlist = sys.argv[4]
output_path = sys.argv[5]

script = """#!/bin/bash
ALLOWLIST="__ALLOWLIST__"
urls=()
for f in "$@"; do
  if [[ -d "$f" ]]; then
    encoded=$(/usr/bin/osascript -l JavaScript -e 'function run(argv){return encodeURIComponent(argv[0])}' "$f")
    urls+=("markitdown://__HOST__?path=$encoded")
    continue
  fi
  [[ -f "$f" ]] || continue
  ext="${f##*.}"
  ext_lc=$(printf '%s' "$ext" | /usr/bin/tr '[:upper:]' '[:lower:]')
  case " $ALLOWLIST " in
    *" $ext_lc "*)
      encoded=$(/usr/bin/osascript -l JavaScript -e 'function run(argv){return encodeURIComponent(argv[0])}' "$f")
      urls+=("markitdown://__HOST__?path=$encoded")
      ;;
  esac
done
if [[ ${#urls[@]} -eq 0 ]]; then
  /usr/bin/osascript -e 'display notification "No supported files were selected." with title "MarkItDown"'
  exit 0
fi
/usr/bin/open "${urls[@]}"
""".replace("__ALLOWLIST__", allowlist).replace("__HOST__", host)

workflow = {
    "AMApplicationBuild": "523",
    "AMApplicationVersion": "2.10",
    "AMDocumentVersion": "2",
    "actions": [
        {
            "action": {
                "AMAccepts": {
                    "Container": "List",
                    "Optional": True,
                    "Types": ["com.apple.cocoa.path"],
                },
                "AMActionVersion": "2.0.3",
                "AMApplication": ["Automator"],
                "ActionBundlePath": "/System/Library/Automator/Run Shell Script.action",
                "ActionName": "Run Shell Script",
                "ActionParameters": {
                    "COMMAND_STRING": script,
                    "CheckedForUserDefaultShell": True,
                    "inputMethod": 1,
                    "shell": "/bin/bash",
                    "source": "",
                },
                "BundleIdentifier": "com.apple.RunShellScript",
                "CFBundleVersion": "2.0.3",
                "CanShowSelectedItemsWhenRun": False,
                "CanShowWhenRun": True,
                "Category": ["AMCategoryUtilities"],
                "Class Name": "RunShellScriptAction",
                "InputUUID": f"markitdown-{host}-input",
                "Keywords": ["Shell", "Script", "Command", "Run", "Unix"],
                "OutputUUID": f"markitdown-{host}-output",
                "UUID": f"markitdown-{host}-shell",
                "UnlocalizedApplications": ["Automator"],
                "arguments": {},
                "conversionLabel": 0,
                "isViewVisible": True,
                "location": "449.000000:173.000000",
                "nestedActions": [],
                "savedInputUUID": f"markitdown-{host}-input",
            }
        }
    ],
    "connectors": {},
    "workflowMetaData": {
        "workflowTypeIdentifier": "com.apple.Automator.servicesMenu",
        "serviceInputTypeIdentifier": "com.apple.Automator.fileSystemObject",
        "serviceOutputTypeIdentifier": "com.apple.Automator.nothing",
        "serviceApplicationBundleID": "com.apple.finder",
        "workflowSubtitle": subtitle,
        "workflowTitle": title,
    },
}

with open(output_path, "wb") as fp:
    plistlib.dump(workflow, fp, fmt=plistlib.FMT_XML)
PY

  echo "Generated $output_dir"
}

generate_workflow "Convert to Markdown" "convert" "Convert selected files to Markdown" "$ALLOWLIST_CONVERT"
generate_workflow "Combine Markdown" "combine" "Combine selected files into one Markdown file" "$ALLOWLIST_COMBINE"
