#!/usr/bin/env python3
"""Refresh AtlasViewer's bundled atlas data to the latest build.

The client can look up one atlas by name but cannot list names, so the addon
bundles a texture -> atlas map per game type (Data/*.lua). Two sources feed it.

  web     Townlong-Yak's per-build dump for every flavor. It can lag a fresh patch
          by a day or two, and on 2026-11-18 its download sat behind a browser
          check this script does not bypass. --check works. Requests are paced,
          cached and never retried, see UA below. Prefer the client source.
  client  The running game itself. In game, `/av dump` saves every atlas the
          client knows into the addon's saved variables. After logging out (or
          /reload) run this script with --from-client and it turns that save
          into the Data file. This is always exactly the build you are playing.

Usage:
    python update_atlas_data.py                  # use a fresh /av dump if there is one,
                                                 #   otherwise show current vs latest builds
    python update_atlas_data.py --check          # print current vs latest, change nothing
    python update_atlas_data.py --from-client    # use the saved /av dump
    python update_atlas_data.py --web            # try the web download, every game type
    python update_atlas_data.py --web forever    # web, WoW Forever only
    python update_atlas_data.py --from-client PATH_TO/AtlasViewer.lua
    python update_atlas_data.py vanilla --vanilla-source anniversary
    python update_atlas_data.py --force          # rewrite even when already current
    python update_atlas_data.py --check --recheck  # ignore the 6 hour build-check cache

Era and Anniversary share the `vanilla` game type, so they share Data_Vanilla.lua;
pick the upstream with --vanilla-source. Standard library only. The old data file
is kept as *.lua.bak, one generation back.
"""
import argparse
import datetime
import glob
import json
import os
import random
import re
import sys
import time
import urllib.error
import urllib.request

# game type -> where its data comes from and where it goes.
#   segment  : Townlong-Yak framexml flavor
#   out      : file under Data/
#   gametype : the TOC's AllowLoadGameType tag
#   label    : stored as _addon.dataExpansion
#   project  : WOW_PROJECT_ID the client reports, used to auto-pick a target for a dump
TARGETS = {
    "mainline": {"segment": "live", "out": "Data_Mainline.lua", "gametype": "mainline",
                 "label": "Mainline (Retail)", "project": 1},
    "vanilla": {"segment": "era", "out": "Data_Vanilla.lua", "gametype": "vanilla",
                "label": "Classic Era / Anniversary", "project": 2},
    "mists": {"segment": "classic", "out": "Data_Mists.lua", "gametype": "mists",
              "label": "Mists of Pandaria Classic", "project": None},
    # WoW Forever reports game type "camelot" and project id 18.
    "forever": {"segment": "forever", "out": "Data_Forever.lua", "gametype": "camelot",
                "label": "WoW Forever", "project": 18},
}

# Townlong-Yak is a free community site, so this script behaves like a guest:
#   - it says who it is. A named agent lets the site owner see and throttle it.
#     Posing as curl got 403 on 2026-11-24, while this name got 200.
#   - one request at a time, at least MIN_GAP seconds apart, never retried.
#   - build checks are cached for CACHE_TTL and repeated with If-None-Match, so a
#     second run inside that window sends nothing and a later one usually gets 304.
#   - a 429 or 503 stops every remaining web request for this run.
#   - the 2 MB download only happens when the site has a newer build than the disk.
UA = {"User-Agent": "AtlasViewer-data-updater/2.1 (python-urllib)"}
MIN_GAP = 5.0
CACHE_TTL = 6 * 3600
MAX_BYTES = 32 * 1024 * 1024

HERE = os.path.dirname(os.path.abspath(__file__))
CACHE_FILE = os.path.join(HERE, ".atlas_web_cache.json")
# Works from inside the addon folder, or from a repo where this sits in tools/ next
# to the AtlasViewer addon folder.
ADDON_DIR = HERE if os.path.exists(os.path.join(HERE, "AtlasViewer.toc")) else os.path.abspath(
    os.path.join(HERE, "..", "AtlasViewer"))
DATA_DIR = os.path.join(ADDON_DIR, "Data")


def page_url(segment):
    return "https://www.townlong-yak.com/framexml/%s/Helix/AtlasInfo.lua" % segment


class SiteBusy(OSError):
    """The site asked us to back off (429 or 503)."""


_last_request = 0.0


def _wait_turn():
    """Keep MIN_GAP seconds, plus a little jitter, between requests."""
    global _last_request
    if _last_request:
        gap = time.monotonic() - _last_request
        if gap < MIN_GAP:
            time.sleep(MIN_GAP - gap + random.uniform(0, 1))
    _last_request = time.monotonic()


def fetch(url, limit=None, etag=None, timeout=15):
    """One GET, never retried. Returns (text, etag), or (None, etag) on 304."""
    _wait_turn()
    headers = dict(UA)
    if etag:
        headers["If-None-Match"] = etag
    try:
        req = urllib.request.Request(url, headers=headers)
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            data = resp.read(limit or MAX_BYTES + 1)
            if not limit and len(data) > MAX_BYTES:
                raise OSError("response larger than %d MB, refusing it" % (MAX_BYTES // 1048576))
            return data.decode("utf-8", "replace"), resp.headers.get("ETag")
    except urllib.error.HTTPError as exc:
        if exc.code == 304:
            return None, etag
        if exc.code in (429, 503):
            wait = exc.headers.get("Retry-After") if exc.headers else None
            raise SiteBusy("HTTP %d, the site asked to slow down%s" % (
                exc.code, (", retry after %s s" % wait) if wait else ""))
        raise


def load_cache():
    try:
        with open(CACHE_FILE, encoding="utf-8") as handle:
            data = json.load(handle)
        return data if isinstance(data, dict) else {}
    except (OSError, ValueError):
        return {}


def save_cache(cache):
    try:
        with open(CACHE_FILE, "w", encoding="utf-8") as handle:
            json.dump(cache, handle, indent=1, sort_keys=True)
    except OSError as exc:
        print("  (could not save the build cache: %s)" % exc)


SITE_DOWN = False  # set after the first failed request so the rest are skipped
CACHE = None


def web_build(segment, recheck=False):
    """Latest build Townlong-Yak has for a flavor, or None. It lives in the page title."""
    global SITE_DOWN, CACHE
    if CACHE is None:
        CACHE = load_cache()
    entry = CACHE.get(segment) or {}
    if not recheck and entry.get("build") and time.time() - entry.get("checked", 0) < CACHE_TTL:
        return entry["build"]
    if SITE_DOWN:
        return None
    try:
        head, etag = fetch(page_url(segment), limit=8192, etag=entry.get("etag") if entry.get("build") else None)
    except OSError as exc:
        SITE_DOWN = True
        print("  Townlong-Yak did not answer (%s), skipping the rest of the web work." % exc)
        return None
    if head is None:  # 304, nothing changed since the cached check
        build = entry.get("build")
    else:
        match = re.search(r"\(build\s+(\d+)\)", head)
        build = int(match.group(1)) if match else None
    if build:
        CACHE[segment] = {"build": build, "etag": etag, "checked": int(time.time())}
        save_cache(CACHE)
    return build


def current_build(target):
    """Build of the Data file already on disk, or None."""
    path = os.path.join(DATA_DIR, target["out"])
    if not os.path.exists(path):
        return None
    with open(path, encoding="utf-8") as handle:
        text = handle.read()
    match = re.search(r"_addon\.dataBuild\s*=\s*(\d+)", text)
    return int(match.group(1)) if match else None


def lua_string(text):
    return '"%s"' % text.replace("\\", "\\\\").replace('"', '\\"')


def number(value):
    return ("%.8g" % value) if isinstance(value, float) else str(value)


def write_data(name, target, body, build, source):
    """Wrap an AtlasInfo table body in the addon's Data file shape and save it."""
    header = (
        "local _, _addon = ...\n\n"
        "--[[\n"
        "\tAtlasViewer - %s   (GENERATED - do not hand-edit)\n"
        "\t---------------------------------------------------------------------------\n"
        "\tWritten by update_atlas_data.py. Edits here are lost on the next run, so\n"
        "\tchange the script instead. Refresh after a patch with:\n\n"
        "\t    python update_atlas_data.py %s\n\n"
        "\tGame type : %s\n"
        "\tSource    : %s\n"
        "\tBuild     : %s\n"
        "\tPulled    : %s\n"
        "--]]\n\n"
    ) % (target["out"], name, target["gametype"], source, build, datetime.date.today().isoformat())
    # The table sits inside a loader the addon calls on first open, so players who
    # never open the window do not hold the built table in memory.
    out = ("%s_addon.loadData = function()\n%s\n\nreturn AtlasInfo\nend\n\n"
           "_addon.dataBuild = %s\n_addon.dataExpansion = %s\n") % (
        header, body, build, lua_string(target["label"]))

    dest = os.path.join(DATA_DIR, target["out"])
    os.makedirs(DATA_DIR, exist_ok=True)
    # Write the new file in full first, so a failed write never leaves the addon
    # without its data file.
    tmp = dest + ".tmp"
    try:
        with open(tmp, "w", encoding="utf-8", newline="\n") as handle:
            handle.write(out)
    except OSError:
        if os.path.exists(tmp):
            os.remove(tmp)
        raise
    had_old = os.path.exists(dest)
    if had_old:
        os.replace(dest, dest + ".bak")
    os.replace(tmp, dest)
    print("  wrote Data/%s (%.1f MB)%s" % (target["out"], len(out) / 1048576,
                                         ", previous kept as .bak" if had_old else ""))


# ---------------------------------------------------------------------------
# web source
# ---------------------------------------------------------------------------
def update_from_web(name, target, segment, check_only, force, recheck):
    have = current_build(target)
    latest = web_build(segment, recheck)
    if not latest:
        status = "latest unknown"
    else:
        status = "up to date" if (have and have >= latest) else "update available"
    print("%-9s have %s, latest %s -> %s" % (name, have or "none", latest or "?", status))
    if check_only:
        return True
    if SITE_DOWN:
        return False
    if not latest and not force:
        # Without a known build there is nothing to compare, so do not pull 2 MB blind.
        print("  skipped, the latest build is unknown (--force downloads anyway)")
        return False
    if not force and have and latest and have >= latest:
        return True

    page = page_url(segment)
    try:
        raw, _ = fetch(page + "/get")
    except OSError as exc:
        print("  ERROR: could not download %s (%s)" % (page, exc))
        return False
    start, end = raw.find("local AtlasInfo"), raw.rfind("return AtlasInfo")
    if start == -1 or end == -1:
        if "Please hold" in raw or "cross.js" in raw:
            # The site now answers the download with a browser check page. This script
            # does not try to get around it, the in-game dump needs no website at all.
            print("  The download is behind a browser check, so the web source is unavailable.")
            print("  Use the client dump instead: /av dump in game, /reload, then")
            print("  update_atlas_data.cmd --from-client")
        else:
            print("  ERROR: unexpected format, no AtlasInfo table found")
        return False
    body = raw[start:end].rstrip()
    # Spaced path keys like "Interface/ Garrison/..." never load with SetTexture.
    body, fixed = re.subn(r"/ +", "/", body)
    if fixed:
        print("  normalized %d spaced path slash(es)" % fixed)
    write_data(name, target, body, latest or have or 0, page)
    return True


# ---------------------------------------------------------------------------
# client source: the saved /av dump
# ---------------------------------------------------------------------------
def find_saved_variables():
    """Newest AtlasViewer.lua saved-variables file near this addon's game folder."""
    game_root = os.path.abspath(os.path.join(ADDON_DIR, "..", "..", ".."))
    pattern = os.path.join(game_root, "WTF", "Account", "*", "SavedVariables", "AtlasViewer.lua")
    found = glob.glob(pattern)
    return max(found, key=os.path.getmtime) if found else None


ESCAPE = re.compile(r"\\(\d{1,3}|.)", re.S)
SIMPLE_ESCAPES = {"n": "\n", "t": "\t", "r": "\r", "a": "\a", "b": "\b", "f": "\f", "v": "\v"}


def unescape(text):
    """Undo Lua string escapes in one pass, so an escaped backslash before a digit
    stays a backslash instead of turning into a decimal escape."""
    def one(match):
        code = match.group(1)
        if code.isdigit():
            return chr(int(code))
        return SIMPLE_ESCAPES.get(code, code)
    return ESCAPE.sub(one, text)


STRING = re.compile(r'\s*"((?:[^"\\]|\\.)*)"\s*,?')


def read_dump(path):
    """Return (build, project, lines) from the saved variables, or raise ValueError."""
    with open(path, encoding="utf-8", errors="replace") as handle:
        text = handle.read()
    spot = text.find('["harvest"]')
    if spot == -1:
        raise ValueError("no dump in %s, run /av dump in game, then /reload" % path)
    block = text[spot:]
    build = re.search(r'\["build"\]\s*=\s*(\d+)', block)
    project = re.search(r'\["project"\]\s*=\s*(\d+)', block)
    lines_at = block.find('["lines"]')
    if lines_at == -1:
        raise ValueError("the dump has no atlas lines")
    brace = block.find("{", lines_at)
    pos, lines = brace + 1, []
    while True:
        match = STRING.match(block, pos)
        if not match:
            break
        lines.append(unescape(match.group(1)))
        pos = match.end()
    if not lines:
        raise ValueError("the dump is empty")
    return (int(build.group(1)) if build else 0, int(project.group(1)) if project else None, lines)


def update_from_client(path, forced_target):
    path = path if path and path != "auto" else find_saved_variables()
    if not path or not os.path.exists(path):
        print("ERROR: could not find AtlasViewer.lua saved variables. Pass the path explicitly.")
        return False
    print("reading %s" % path)
    try:
        build, project, lines = read_dump(path)
    except ValueError as exc:
        print("ERROR: %s" % exc)
        return False

    name = forced_target
    if not name:
        for key, target in TARGETS.items():
            if target["project"] is not None and target["project"] == project:
                name = key
        if not name:
            print("ERROR: unknown project id %s, pass --target" % project)
            return False
    target = TARGETS[name]

    files = {}
    skipped = 0
    for line in lines:
        parts = line.rsplit("|", 9)
        if len(parts) != 10:
            skipped += 1
            continue
        atlas, file_key = parts[0], parts[1]
        try:
            w, h = int(float(parts[2])), int(float(parts[3]))
            l, r, t, b = (float(parts[i]) for i in range(4, 8))
        except ValueError:
            skipped += 1
            continue
        tiles_h, tiles_v = parts[8] == "1", parts[9] == "1"
        files.setdefault(file_key, {})[atlas] = (w, h, l, r, t, b, tiles_h, tiles_v)

    out = ["local AtlasInfo = {"]
    for file_key in sorted(files):
        out.append("\t[%s] = {" % lua_string(file_key))
        for atlas in sorted(files[file_key]):
            w, h, l, r, t, b, th, tv = files[file_key][atlas]
            out.append("\t\t[%s] = { %d, %d, %s, %s, %s, %s, %s, %s, \"1x\" }," % (
                lua_string(atlas), w, h, number(l), number(r), number(t), number(b),
                "true" if th else "false", "true" if tv else "false"))
        out.append("\t},")
    out.append("}")

    print("%s: %d atlases in %d files from build %s%s" % (
        name, sum(len(v) for v in files.values()), len(files), build,
        ", %d unreadable lines skipped" % skipped if skipped else ""))
    write_data(name, target, "\n".join(out), build, "game client dump (/av dump)")
    return True


def dump_is_fresh(path):
    """True when the saved dump is newer than the Data file it would replace."""
    try:
        build, project, _ = read_dump(path)
    except (ValueError, OSError):
        return False
    for target in TARGETS.values():
        if target["project"] is not None and target["project"] == project:
            have = current_build(target)
            return have is None or build > have
    return False


def main():
    ap = argparse.ArgumentParser(description="Refresh AtlasViewer's bundled atlas data.")
    ap.add_argument("targets", nargs="*", choices=list(TARGETS), help="game types (default: all)")
    ap.add_argument("--vanilla-source", choices=("era", "anniversary"), default="era",
                    help="Townlong-Yak flavor behind Data_Vanilla.lua (default: era)")
    ap.add_argument("--check", action="store_true", help="report current vs latest build, change nothing")
    ap.add_argument("--web", action="store_true", help="download from Townlong-Yak (may be blocked)")
    ap.add_argument("--force", action="store_true", help="rewrite even when already current")
    ap.add_argument("--recheck", action="store_true",
                    help="ask the site again even if a build check is cached (still paced)")
    ap.add_argument("--from-client", nargs="?", const="auto", metavar="PATH",
                    help="build from the /av dump in saved variables (auto-finds the file)")
    ap.add_argument("--target", choices=list(TARGETS), help="game type for --from-client (default: auto)")
    args = ap.parse_args()

    # Plain run: take a fresh in-game dump when one is waiting, otherwise just report.
    if not (args.check or args.web or args.from_client):
        saved = find_saved_variables()
        if saved and dump_is_fresh(saved):
            print("A newer /av dump is waiting, using it.")
            args.from_client = saved
        else:
            print("No fresh /av dump found. Data files on disk:")
            for name, target in TARGETS.items():
                print("  %-9s build %s" % (name, current_build(target) or "none"))
            print()
            print("To update: in game type /av dump, then /reload, then run this again.")
            print("(--check compares against the website, --web tries to download from it.)")
            return 0

    if args.from_client:
        ok = update_from_client(args.from_client, args.target or (args.targets[0] if args.targets else None))
    else:
        ok = True
        for name in args.targets or list(TARGETS):
            target = TARGETS[name]
            segment = args.vanilla_source if name == "vanilla" else target["segment"]
            ok = update_from_web(name, target, segment, args.check, args.force, args.recheck) and ok

    if not args.check:
        print("Done. /reload each client to pick up the new data." if ok else "Finished with errors, nothing was changed for the failed targets.")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
