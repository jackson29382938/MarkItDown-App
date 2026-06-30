#!/usr/bin/env python3
import importlib.metadata
import json
import os
import sys
import time
import traceback


def response(payload):
    sys.stdout.write(json.dumps(payload, ensure_ascii=False))
    sys.stdout.flush()


def main():
    started = time.perf_counter()

    try:
        request = json.load(sys.stdin)
        engine_path = request["enginePath"]
        source_path = request["inputPath"]
        output_path = request["outputPath"]

        site_packages = os.path.join(engine_path, "site-packages")
        if site_packages not in sys.path:
            sys.path.insert(0, site_packages)

        from markitdown import MarkItDown

        converter = MarkItDown()
        result = converter.convert(source_path)
        markdown = getattr(result, "text_content", None)
        if markdown is None:
            markdown = getattr(result, "markdown", None)
        if markdown is None:
            raise RuntimeError("MarkItDown returned no markdown text")

        output_directory = os.path.dirname(output_path)
        if output_directory:
            os.makedirs(output_directory, exist_ok=True)

        with open(output_path, "w", encoding="utf-8") as handle:
            handle.write(markdown)

        response(
            {
                "success": True,
                "markdownPath": output_path,
                "markitdownVersion": importlib.metadata.version("markitdown"),
                "elapsedTime": time.perf_counter() - started,
                "errorMessage": None,
                "traceback": None,
            }
        )
        return 0
    except Exception as exc:
        response(
            {
                "success": False,
                "markdownPath": None,
                "markitdownVersion": None,
                "elapsedTime": time.perf_counter() - started,
                "errorMessage": f"{type(exc).__name__}: {exc}",
                "traceback": traceback.format_exc(),
            }
        )
        return 0


if __name__ == "__main__":
    raise SystemExit(main())
