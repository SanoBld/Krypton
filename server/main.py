# server/main.py
# Minimal yt-dlp REST API server.
# Endpoint: POST /extract  { url, format? }
# Returns:  { url, filename, audioUrl? }
#
# Run locally:   python main.py
# Run via Docker: docker compose up

import json
import subprocess
from flask import Flask, request, jsonify

app = Flask(__name__)


def run_ytdlp(page_url: str, fmt: str) -> dict:
    result = subprocess.run(
        [
            "yt-dlp",
            "--dump-json",
            "--no-playlist",
            "--no-warnings",
            "-f", fmt,
            page_url,
        ],
        capture_output=True,
        text=True,
        timeout=30,
    )
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or "yt-dlp failed")

    return json.loads(result.stdout)


@app.post("/extract")
def extract():
    data = request.get_json(silent=True) or {}
    page_url = data.get("url", "").strip()
    fmt      = data.get("format", "bestvideo+bestaudio/best")

    if not page_url:
        return jsonify({"error": "url is required"}), 400

    try:
        info = run_ytdlp(page_url, fmt)
    except RuntimeError as e:
        return jsonify({"error": str(e)}), 400
    except subprocess.TimeoutExpired:
        return jsonify({"error": "yt-dlp timed out"}), 504

    # Best direct URL
    direct_url = info.get("url") or ""
    audio_url  = None

    # Some extractors return a list of requested_formats
    if not direct_url:
        formats = info.get("requested_formats") or info.get("formats") or []
        videos  = [f for f in formats if f.get("vcodec") not in (None, "none")]
        audios  = [f for f in formats if f.get("acodec") not in (None, "none")
                   and f.get("vcodec") in (None, "none")]
        if videos:
            direct_url = videos[-1].get("url", "")
        if audios:
            audio_url = audios[-1].get("url")

    if not direct_url:
        return jsonify({"error": "No direct URL found"}), 400

    title    = info.get("title",     "download")
    ext      = info.get("ext",       "mp4")
    filename = f"{title}.{ext}"

    return jsonify({
        "url":      direct_url,
        "filename": filename,
        "audioUrl": audio_url,
    })


@app.get("/ping")
def ping():
    return jsonify({"status": "ok"})


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080, debug=False)