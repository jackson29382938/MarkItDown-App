#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="$ROOT_DIR/dist/MarkItDown.app"
ENGINE="$APP_BUNDLE/Contents/Resources/Engine"
PYTHON="$ENGINE/python/bin/python3.12"
WORKER="$APP_BUNDLE/Contents/Resources/Worker/markitdown_worker.py"

cd "$ROOT_DIR"
"$ROOT_DIR/script/build_and_run.sh" --build-only

MARKITDOWN_TEST_ENGINE="$ENGINE" \
MARKITDOWN_TEST_PYTHON="$PYTHON" \
MARKITDOWN_TEST_WORKER="$WORKER" \
swift test --filter PythonWorkerIntegrationTests

"$PYTHON" - "$ENGINE" "$WORKER" <<'PY'
import json
import os
import subprocess
import sys
import tempfile
import zipfile

engine = sys.argv[1]
worker = sys.argv[2]
python = os.path.join(engine, "python", "bin", "python3.12")
site_packages = os.path.join(engine, "site-packages")

root = tempfile.mkdtemp(prefix="markitdown-worker-")


def write(path, content, mode="w"):
    with open(path, mode, encoding=None if "b" in mode else "utf-8") as handle:
        handle.write(content)


def make_pdf(path):
    content = b"BT /F1 24 Tf 72 720 Td (Hello PDF) Tj ET"
    objects = [
        b"<< /Type /Catalog /Pages 2 0 R >>",
        b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>",
        b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
        b"<< /Length " + str(len(content)).encode("ascii") + b" >>\nstream\n" + content + b"\nendstream",
    ]
    data = bytearray(b"%PDF-1.4\n")
    offsets = [0]
    for index, obj in enumerate(objects, start=1):
        offsets.append(len(data))
        data.extend(f"{index} 0 obj\n".encode("ascii"))
        data.extend(obj)
        data.extend(b"\nendobj\n")
    xref_offset = len(data)
    data.extend(f"xref\n0 {len(objects) + 1}\n".encode("ascii"))
    data.extend(b"0000000000 65535 f \n")
    for offset in offsets[1:]:
        data.extend(f"{offset:010d} 00000 n \n".encode("ascii"))
    data.extend(
        f"trailer\n<< /Size {len(objects) + 1} /Root 1 0 R >>\nstartxref\n{xref_offset}\n%%EOF\n".encode("ascii")
    )
    with open(path, "wb") as handle:
        handle.write(data)


def make_docx(path):
    with zipfile.ZipFile(path, "w") as archive:
        archive.writestr(
            "[Content_Types].xml",
            """<?xml version="1.0" encoding="UTF-8"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
</Types>""",
        )
        archive.writestr(
            "_rels/.rels",
            """<?xml version="1.0" encoding="UTF-8"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>""",
        )
        archive.writestr(
            "word/document.xml",
            """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body>
    <w:p><w:r><w:t>Hello DOCX</w:t></w:r></w:p>
  </w:body>
</w:document>""",
        )


sys.path.insert(0, site_packages)
from openpyxl import Workbook
from pptx import Presentation

fixtures = {
    "sample.txt": "Hello TXT",
    "sample.html": "<html><body><h1>Hello HTML</h1></body></html>",
    "sample.csv": "name,value\nalpha,1\n",
    "sample.json": json.dumps({"message": "Hello JSON"}),
    "sample.xml": "<root><message>Hello XML</message></root>",
}

for name, content in fixtures.items():
    write(os.path.join(root, name), content)

make_pdf(os.path.join(root, "sample.pdf"))
make_docx(os.path.join(root, "sample.docx"))

workbook = Workbook()
sheet = workbook.active
sheet["A1"] = "Hello XLSX"
workbook.save(os.path.join(root, "sample.xlsx"))

presentation = Presentation()
slide = presentation.slides.add_slide(presentation.slide_layouts[5])
slide.shapes.title.text = "Hello PPTX"
presentation.save(os.path.join(root, "sample.pptx"))

environment = os.environ.copy()
environment["PYTHONNOUSERSITE"] = "1"
environment["PYTHONPATH"] = site_packages

failed = []
for name in sorted(os.listdir(root)):
    source = os.path.join(root, name)
    stem, extension = os.path.splitext(name)
    output = os.path.join(root, f"{stem}-{extension.lstrip('.')}.md")
    request = {"inputPath": source, "outputPath": output, "enginePath": engine}
    completed = subprocess.run(
        [python, worker],
        input=json.dumps(request).encode("utf-8"),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=environment,
        check=False,
    )
    try:
        payload = json.loads(completed.stdout.decode("utf-8"))
    except Exception:
        payload = {"success": False, "errorMessage": completed.stderr.decode("utf-8")}
    if not payload.get("success") or not os.path.exists(output):
        failed.append((name, payload.get("errorMessage")))

if failed:
    for name, message in failed:
        print(f"{name}: {message}", file=sys.stderr)
    raise SystemExit(1)

print(f"Worker converted {len(os.listdir(root)) // 2} fixture files in {root}")
PY
