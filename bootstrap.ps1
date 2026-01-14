param([string]$RepoIconUrl="https://raw.githubusercontent.com/<USER>/<REPO>/main/icon.png")
Set-Location $PSScriptRoot

$info = [ordered]@{
  author="local"
  compatibility=@(2)
  description="Queue TrueHD/MLP files when VF/VO lacks AC3/EAC3 fallback."
  icon=$RepoIconUrl
  id="jf_truehd_vf_filetest"
  name="TrueHD and VF Filter"
  platform=@("all")
  priorities=@{ on_library_management_file_test = 50 }
  tags="library file test"
  version="0.0.1"
} | ConvertTo-Json -Depth 10

$readme = @"
# TrueHD and VF Filter (Unmanic plugin)

Queues files during **Library Management -> File test** when:
- File contains **TrueHD/MLP**
- **VF/FR** (and/or original language) does **not** already have an **AC3/EAC3** fallback
- A **TrueHD/MLP** source exists for the language(s) that need conversion

## Install (local)
Copy this folder to:
`/config/.unmanic/plugins/jf_truehd_vf_filetest`

Restart Unmanic, then add the plugin in:
Library -> Plugin Flow -> Library Management - File test
"@

$license = @"
MIT License

Copyright (c) 2026

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
"@

$plugin = @"
#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import json
import logging
import os
import subprocess

from unmanic.libs.unplugins.settings import PluginSettings

logger = logging.getLogger("Unmanic.Plugin.jf_truehd_vf_filetest")

VIDEO_EXTS = {".mkv", ".mp4", ".avi", ".mov", ".ts", ".rmvb"}
TRUEHD = {"truehd", "mlp"}
COMPAT = {"ac3", "eac3"}


class Settings(PluginSettings):
    settings = {}

    def __init__(self, *args, **kwargs):
        super(Settings, self).__init__(*args, **kwargs)


def _n(x):
    return (x or "").strip().lower()


def _is_fr(lang, title):
    lang = _n(lang)
    title = _n(title)
    return (lang in {"fr", "fra", "fre"}) or ("vf" in title) or ("french" in title)


def _probe(path):
    cmd = [
        "ffprobe", "-v", "error",
        "-select_streams", "a",
        "-show_entries", "stream=index,codec_name:stream_tags=language,title",
        "-of", "json",
        path
    ]
    p = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if p.returncode != 0:
        raise RuntimeError((p.stderr or "").strip() or "ffprobe failed")
    j = json.loads(p.stdout or "{}")
    out = []
    for s in (j.get("streams") or []):
        tags = s.get("tags") or {}
        out.append({
            "codec": _n(s.get("codec_name")),
            "lang":  _n(tags.get("language")),
            "title": _n(tags.get("title")),
        })
    return out


def _orig_lang(streams):
    for s in streams:
        if s["lang"] and s["lang"] != "und" and not _is_fr(s["lang"], s["title"]):
            return s["lang"]
    return ""


def _orig_compat(streams):
    ol = _orig_lang(streams)
    if ol:
        return any(s["lang"] == ol and s["codec"] in COMPAT for s in streams)
    return any(s["codec"] in COMPAT for s in streams)


def _orig_truehd(streams):
    ol = _orig_lang(streams)
    if ol:
        return any(s["lang"] == ol and s["codec"] in TRUEHD for s in streams)
    return any(s["codec"] in TRUEHD for s in streams)


def _vf_exists(streams):
    return any(_is_fr(s["lang"], s["title"]) for s in streams)


def _vf_compat(streams):
    return any(_is_fr(s["lang"], s["title"]) and s["codec"] in COMPAT for s in streams)


def _vf_truehd(streams):
    return any(_is_fr(s["lang"], s["title"]) and s["codec"] in TRUEHD for s in streams)


def on_library_management_file_test(data):
    if data.get("library_id"):
        _ = Settings(library_id=data.get("library_id"))
    else:
        _ = Settings()

    if data.get("issues") is None:
        data["issues"] = []

    path = data.get("path") or ""
    ext = os.path.splitext(path)[-1].lower()
    if ext not in VIDEO_EXTS:
        data["add_file_to_pending_tasks"] = False
        return data

    try:
        streams = _probe(path)
    except Exception as e:
        data["add_file_to_pending_tasks"] = False
        data["issues"].append({"id": "jf_truehd_vf_filetest", "message": f"ffprobe error: {e}"})
        logger.debug("ffprobe error on '%s': %s", path, e)
        return data

    if not streams:
        data["add_file_to_pending_tasks"] = False
        data["issues"].append({"id": "jf_truehd_vf_filetest", "message": "No audio streams"})
        return data

    # If no TrueHD/MLP anywhere -> skip
    if not any(s["codec"] in TRUEHD for s in streams):
        data["add_file_to_pending_tasks"] = False
        return data

    vf = _vf_exists(streams)
    orig_ok = _orig_compat(streams)
    vf_ok = (not vf) or _vf_compat(streams)

    # If already have compatible fallback for required languages -> skip
    if orig_ok and vf_ok:
        data["add_file_to_pending_tasks"] = False
        return data

    need_orig = not orig_ok
    need_vf = vf and (not vf_ok)

    can_orig = (not need_orig) or _orig_truehd(streams)
    can_vf = (not need_vf) or _vf_truehd(streams)

    if can_orig and can_vf:
        data["add_file_to_pending_tasks"] = True
        return data

    data["add_file_to_pending_tasks"] = False
    return data
"@

Set-Content -Encoding UTF8 -Path ".\info.json" -Value $info
Set-Content -Encoding UTF8 -Path ".\README.md" -Value $readme
Set-Content -Encoding UTF8 -Path ".\LICENSE" -Value $license
Set-Content -Encoding UTF8 -Path ".\plugin.py" -Value $plugin
New-Item -ItemType File -Path ".\requirements.txt" -Force | Out-Null
if (-not (Test-Path ".\icon.png")) { New-Item -ItemType File -Path ".\icon.png" | Out-Null }
if (-not (Test-Path ".\__init__.py")) { New-Item -ItemType File -Path ".\__init__.py" | Out-Null }

if (-not (Test-Path ".\.git")) { git init | Out-Null }
git add -A
git status
