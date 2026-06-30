#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="$ROOT_DIR/Resources/QuickAction/Convert to Markdown.workflow"
BUNDLE_ID="app.markitdown.menubar"

mkdir -p "$OUTPUT_DIR/Contents"

cat >"$OUTPUT_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key>
  <string>com.apple.automator.Convert-to-Markdown</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>Convert to Markdown</string>
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

python3 - "$BUNDLE_ID" "$OUTPUT_DIR/Contents/document.wflow" <<'PY'
import plistlib
import sys

bundle_id = sys.argv[1]
output_path = sys.argv[2]
script = f'''#!/bin/bash
for f in "$@"; do
  encoded=$(python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1], safe=''))" "$f")
  /usr/bin/open "markitdown://convert?path=$encoded"
done
'''

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
                "InputUUID": "markitdown-input",
                "Keywords": ["Shell", "Script", "Command", "Run", "Unix"],
                "OutputUUID": "markitdown-output",
                "UUID": "markitdown-shell",
                "UnlocalizedApplications": ["Automator"],
                "arguments": {},
                "conversionLabel": 0,
                "isViewVisible": True,
                "location": "449.000000:173.000000",
                "nestedActions": [],
                "savedInputUUID": "markitdown-input",
            }
        }
    ],
    "connectors": {},
    "workflowMetaData": {
        "workflowTypeIdentifier": "com.apple.Automator.servicesMenu",
        "serviceInputTypeIdentifier": "com.apple.Automator.fileSystemObject",
        "serviceOutputTypeIdentifier": "com.apple.Automator.nothing",
        "serviceApplicationBundleID": "com.apple.finder",
        "workflowSubtitle": "Convert selected files to Markdown",
        "workflowTitle": "Convert to Markdown",
    },
}

with open(output_path, "wb") as fp:
    plistlib.dump(workflow, fp, fmt=plistlib.FMT_XML)
PY

echo "Generated $OUTPUT_DIR"
