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
