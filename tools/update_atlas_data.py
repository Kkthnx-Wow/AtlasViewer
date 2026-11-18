#!/usr/bin/env python3
"""Refresh AtlasViewer's bundled atlas data to the latest build.

The client can look up one atlas by name but cannot list names, so the addon
bundles a texture -> atlas map per game type (Data/*.lua). Two sources feed it.

  web     Townlong-Yak's per-build dump for every flavor. It can lag a fresh patch
          by a day or two, and as of 2026-11-18 its download sits behind a browser
          check this script does not bypass, so --check works but the download
          does not. Use the client source below for real updates.
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

Era and Anniversary share the `vanilla` game type, so they share Data_Vanilla.lua;
pick the upstream with --vanilla-source. Standard library only. The old data file
is kept as *.lua.bak, one generation back.
"""
import argparse
import datetime
import glob
import os
import re
import sys
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

# Townlong-Yak answers 402 to browser-like agents and serves plain CLI tools, so
# the request poses as curl. Do not "fix" this to a browser string.
UA = {"User-Agent": "curl/8.5.0"}

HERE = os.path.dirname(os.path.abspath(__file__))
# Works from inside the addon folder, or from a repo where this sits in tools/ next
# to the AtlasViewer addon folder.
ADDON_DIR = HERE if os.path.exists(os.path.join(HERE, "AtlasViewer.toc")) else os.path.abspath(
    os.path.join(HERE, "..", "AtlasViewer"))
DATA_DIR = os.path.join(ADDON_DIR, "Data")


def page_url(segment):
    return "https://www.townlong-yak.com/framexml/%s/Helix/AtlasInfo.lua" % segment


def fetch(url, limit=None, retries=1, timeout=8):
    last = None
    for attempt in range(retries):
        try:
            req = urllib.request.Request(url, headers=UA)
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                return (resp.read(limit) if limit else resp.read()).decode("utf-8", "replace")
        except OSError as exc:  # timeouts and HTTP errors are retried, then reported by the caller
            last = exc
    raise last


SITE_DOWN = False  # set after the first failed request so the rest are skipped


def web_build(segment):
    """Latest build Townlong-Yak has for a flavor, or None. It lives in the page title."""
    global SITE_DOWN
    if SITE_DOWN:
        return None
    try:
        head = fetch(page_url(segment), limit=8192)
    except OSError as exc:
        SITE_DOWN = True
        print("  Townlong-Yak did not answer (%s), skipping the web checks." % exc)
        return None
    match = re.search(r"\(build\s+(\d+)\)", head)
    return int(match.group(1)) if match else None


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
    out = "%s%s\n\n_addon.data = AtlasInfo\n_addon.dataBuild = %s\n_addon.dataExpansion = %s\n" % (
        header, body, build, lua_string(target["label"]))

    dest = os.path.join(DATA_DIR, target["out"])
    os.makedirs(DATA_DIR, exist_ok=True)
    had_old = os.path.exists(dest)
    if had_old:
        os.replace(dest, dest + ".bak")
    with open(dest, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(out)
    print("  wrote Data/%s (%.1f MB)%s" % (target["out"], len(out) / 1048576,
                                         ", previous kept as .bak" if had_old else ""))


# ---------------------------------------------------------------------------
# web source
# ---------------------------------------------------------------------------
def update_from_web(name, target, segment, check_only, force):
    have = current_build(target)
    latest = web_build(segment)
    if not latest:
        status = "latest unknown"
    else:
        status = "up to date" if (have and have >= latest) else "update available"
    print("%-9s have %s, latest %s -> %s" % (name, have or "none", latest or "?", status))
    if check_only:
        return True
    if not force and have and latest and have >= latest:
        return True

    page = page_url(segment)
    try:
        raw = fetch(page + "/get")
    except Exception as exc:
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


def unescape(text):
    text = re.sub(r"\\(\d{1,3})", lambda m: chr(int(m.group(1))), text)
    return text.replace('\\"', '"').replace("\\\\", "\\")


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
            ok = update_from_web(name, target, segment, args.check, args.force) and ok

    if not args.check:
        print("Done. /reload each client to pick up the new data." if ok else "Finished with errors, nothing was changed for the failed targets.")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
