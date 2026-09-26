#!/usr/bin/env bash
# Canonical release-notes renderer for the owner's macOS app sites. Copy it unchanged to
# scripts/render-release-notes.sh in each app with a site/; project-setup alignment reports a
# drifted copy.
#
# Writes every released CHANGELOG.md entry into a staged copy of the site, for the deploy workflow:
#   release-notes/index.html                every version, each title linked to its page
#   release-notes/X.Y.Z/index.html          one version as a site page, with the site's chrome
#   release-notes/X.Y.Z/update/index.html   the version section alone, for Sparkle's update window
# The entries come from scripts/release-notes.sh --json, so both scripts read the changelog with
# one parser. The name comes from CFBundleName in Support/Info.plist. The two full pages carry the
# breadcrumb and BreadcrumbList every inner page needs, with the product name from the staged
# index.html's og:site_name and the host from its CNAME, so the staged copy passes
# validate-site.sh; the update page has neither, by that script's update-page exemption (#385). The header, the footer and the
# head's icon, stylesheet and script tags come from the staged 404.html, so the site keeps one
# source for them; its header and footer must carry the site-header and site-footer classes. Every
# page carries noindex. The update page's styles (body.is-update, .notes-type, .notes-list) live in
# the site's own stylesheet.
#
# Writes only <staged-dir>/release-notes/ and refuses the tracked site/ itself: nothing it
# generates is committed. Stdout stays empty; a summary goes to stderr.
set -euo pipefail
cd "$(dirname "$0")/.."

usage() {
  cat <<'USAGE'
usage: scripts/render-release-notes.sh --site <staged-dir> [--changelog <path>]
  --site <staged-dir>   a staged copy of site/ to write release-notes/ into
  --changelog <path>    the changelog to read (default CHANGELOG.md)
  --help                show this help
USAGE
}

fail_usage() { echo "error: $1" >&2; usage >&2; exit 2; }
need_value() { [[ $# -ge 2 && -n $2 && $2 != --* ]] || fail_usage "$1 needs a value"; }

site=''
changelog=CHANGELOG.md
while [[ $# -gt 0 ]]; do
  case $1 in
    --site) need_value "$@"; site=$2; shift 2 ;;
    --changelog) need_value "$@"; changelog=$2; shift 2 ;;
    --help) usage; exit 0 ;;
    *) fail_usage "unknown option $1" ;;
  esac
done
[[ -n $site ]] || fail_usage '--site is required'
[[ -d $site ]] || { echo "error: $site is not a directory" >&2; exit 1; }
site=$(cd "$site" && pwd -P)
if [[ -d site && $site == "$(cd site && pwd -P)" ]]; then
  fail_usage 'render into a staged copy of site/, never site/ itself'
fi
[[ -f $site/404.html ]] || { echo "error: $site/404.html not found; the pages take their chrome from it" >&2; exit 1; }
entries=$(scripts/release-notes.sh --json --changelog "$changelog")

python3 - "$site" "$entries" <<'PY'
import datetime
import html
import json
import os
import plistlib
import re
import sys

site, entries = sys.argv[1], json.loads(sys.argv[2])
PLIST = "Support/Info.plist"


def die(message):
    sys.stderr.write("error: %s\n" % message)
    sys.exit(1)


if not os.path.isfile(PLIST):
    die("%s not found; run this from an app repository" % PLIST)
with open(PLIST, "rb") as handle:
    name = plistlib.load(handle).get("CFBundleName")
if not isinstance(name, str) or not name:
    die("%s has no CFBundleName" % PLIST)

with open(os.path.join(site, "404.html"), encoding="utf-8") as handle:
    template = handle.read()
header = re.search(r'[ \t]*<header class="site-header"[^>]*>.*?</header>', template, re.S)
footer = re.search(r'[ \t]*<footer class="site-footer">.*?</footer>', template, re.S)
for part, found in (('<header class="site-header">', header), ('<footer class="site-footer">', footer)):
    if not found:
        die("404.html has no %s element; the notes pages take the site's chrome from it" % part)
header = header.group(0).replace('<a href="/release-notes/">', '<a href="/release-notes/" aria-current="page">') + "\n"
footer = footer.group(0) + "\n"
def site_file(name):
    path = os.path.join(site, name)
    if not os.path.isfile(path):
        die("%s not found in the staged site; the breadcrumb needs it" % name)
    with open(path, encoding="utf-8") as handle:
        return handle.read()


host = site_file("CNAME").strip()
base = "https://%s/" % host
site_name = re.search(r'<meta\s+property="og:site_name"\s+content="([^"]*)"', site_file("index.html"))
product = html.unescape(site_name.group(1)) if site_name else name
head = re.search(r"<head>(.*?)</head>", template, re.S)
head_tags = "".join(
    "  %s\n" % tag.group(0)
    for tag in re.finditer(
        r'<link\b[^>]*\brel="(?:icon|stylesheet)"[^>]*>|<script\b[^>]*>.*?</script>',
        head.group(1) if head else "", re.S)
)


def inline(text):
    """Escapes the text first, then turns the changelog's inline Markdown into HTML."""
    text = html.escape(text, quote=False)
    text = re.sub(r"`([^`]+)`", r"<code>\1</code>", text)
    text = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", text)
    return re.sub(r'\[([^\]]+)\]\((https://[^)\s"]+)\)',
                  r'<a target="_blank" href="\2" rel="noopener">\1</a>', text)


def blocks(body):
    """[(kind, value)]: ("p", text), ("h3", text) or ("ul", [items]), in changelog order."""
    out = []
    paragraph = False
    for line in body.split("\n"):
        if not line.strip():
            paragraph = False
        elif line.startswith("### "):
            out.append(("h3", line[4:].strip()))
            paragraph = False
        elif line.startswith("- "):
            if not out or out[-1][0] != "ul":
                out.append(("ul", []))
            out[-1][1].append(line[2:].strip())
            paragraph = False
        elif line.startswith("  ") and out and out[-1][0] == "ul":
            # An indented continuation line belongs to the bullet above it.
            out[-1][1][-1] += " " + line.strip()
        elif paragraph:
            out[-1] = ("p", out[-1][1] + " " + line.strip())
        else:
            out.append(("p", line.strip()))
            paragraph = True
    return out


def body_html(body):
    parts = []
    for kind, value in blocks(body):
        if kind == "h3":
            parts.append('      <h3 class="notes-type">%s</h3>' % html.escape(value))
        elif kind == "ul":
            parts.append('      <ul class="notes-list">%s</ul>'
                         % "".join("<li>%s</li>" % inline(item) for item in value))
        else:
            parts.append("      <p>%s</p>" % inline(value))
    return "\n".join(parts)


def long_date(iso):
    day = datetime.date.fromisoformat(iso)
    return "%d %s" % (day.day, day.strftime("%B %Y"))


def section(entry, link):
    version, date = entry["version"], entry["date"]
    title = "%s %s" % (html.escape(name), version)
    if link:
        title = '<a href="/release-notes/%s/">%s</a>' % (version, title)
    eyebrow = '      <p class="eyebrow"><time datetime="%s">%s</time></p>\n' % (date, long_date(date)) if date else ""
    return ('    <section class="section" id="v%s" aria-labelledby="title-%s">\n%s'
            '      <h2 id="title-%s">%s</h2>\n%s\n    </section>'
            % (version, version, eyebrow, version, title, body_html(entry["body"])))


def hero(crumbs, title, lead):
    return ('    <section class="page-hero" aria-labelledby="notes-title">\n'
            '%s'
            '      <h1 id="notes-title">%s</h1>\n'
            '      <p class="hero-summary">%s</p>\n'
            "    </section>" % (breadcrumb(crumbs), title, lead))


def breadcrumb(crumbs):
    """[(label, path)] from the product to the current page, whose path is its own."""
    items = "".join('<li><a href="/%s">%s</a></li>' % (path, html.escape(label)) for label, path in crumbs[:-1])
    items += '<li aria-current="page">%s</li>' % html.escape(crumbs[-1][0])
    return '      <nav class="breadcrumb" aria-label="Breadcrumb"><ol>%s</ol></nav>\n' % items


def breadcrumb_list(crumbs):
    return ('  <script type="application/ld+json">%s</script>\n' % json.dumps({
        "@context": "https://schema.org",
        "@type": "BreadcrumbList",
        "itemListElement": [
            {"@type": "ListItem", "position": index, "name": label, "item": base + path}
            for index, (label, path) in enumerate(crumbs, 1)],
    }, ensure_ascii=False).replace("</", "<\\/"))


def page(title, description, content, chrome, body_class="notes-page", crumbs=None):
    skip = '  <a class="skip-link" href="#main">Skip to content</a>\n' if chrome else ""
    return ("<!doctype html>\n"
            '<html lang="en">\n'
            "<head>\n"
            '  <meta charset="utf-8">\n'
            '  <meta name="viewport" content="width=device-width, initial-scale=1">\n'
            '  <meta name="color-scheme" content="light dark">\n'
            '  <meta name="robots" content="noindex">\n'
            "  <title>%s</title>\n"
            '  <meta name="description" content="%s">\n'
            "%s%s"
            "</head>\n"
            '<body class="%s">\n'
            "%s%s"
            '  <main id="main">\n%s\n  </main>\n'
            "%s"
            "</body>\n"
            "</html>\n"
            % (html.escape(title), html.escape(description), head_tags,
               breadcrumb_list(crumbs) if crumbs else "", body_class,
               skip, header if chrome else "", content, footer if chrome else ""))


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(text)


root = os.path.join(site, "release-notes")
index_crumbs = [(product, ""), ("Release notes", "release-notes/")]
for entry in entries:
    version, date = entry["version"], entry["date"]
    released = "Released on %s. " % long_date(date) if date else ""
    version_crumbs = [(product, ""), ("Release notes", "release-notes/"), (version, "release-notes/%s/" % version)]
    write(os.path.join(root, version, "index.html"), page(
        "%s %s release notes" % (name, version),
        "What changed in %s %s%s." % (name, version, ", released on %s" % long_date(date) if date else ""),
        hero(version_crumbs, "%s %s" % (html.escape(name), version),
             '%s<a href="/release-notes/">All release notes</a>.' % released)
        + "\n" + section(entry, link=False),
        chrome=True, crumbs=version_crumbs))
    write(os.path.join(root, version, "update", "index.html"), page(
        "What’s new in %s %s" % (name, version),
        "The changes in %s %s." % (name, version),
        section(entry, link=False),
        chrome=False, body_class="notes-page is-update"))
write(os.path.join(root, "index.html"), page(
    "%s release notes" % name,
    "What changed in every %s release." % name,
    hero(index_crumbs, "Release notes.",
         "What changed in each version of %s. The app shows the same notes when it updates."
         % html.escape(name))
    + "\n" + "\n".join(section(entry, link=True) for entry in entries),
    chrome=True, crumbs=index_crumbs))
sys.stderr.write("release notes: %d versions, newest %s\n" % (len(entries), entries[0]["version"]))
PY
