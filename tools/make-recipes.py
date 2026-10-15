#!/usr/bin/env python3
"""Generate TaxTheFools/recipedata.lua from LibCrafts-1.0 (MIT).

usage: make-recipes.py Tailoring [--input FILE] [--out FILE]
Stdlib only. Fails loudly (naming the line) on anything it does not understand.
"""
import argparse
import re
import sys
import urllib.request

COMMIT = "e0cc17e13307ac0fc4bfd469b1e4d145b9eb6194"
URL = "https://raw.githubusercontent.com/refaim/LibCrafts-1.0/%s/Professions/%s.lua"

SRC_ORDER = ["trainer", "auto", "vendor", "drop", "quest", "other"]
SPELL_SRC = {"Trainer": "trainer", "LearnedAutomatically": "auto", "Quest": "quest", "WorldObject": "other"}
RECIPE_SRC = {"Vendor": "vendor", "Drop": "drop", "Quest": "quest",
              "Chest": "other", "Fishing": "other", "Pickpocket": "other", "WorldObject": "other"}

NAME = r'"((?:[^"\\]|\\.)*)"'
RE_CRAFT = re.compile(r'^module:NewCraft\((\d+), ' + NAME + r', (\d+), \{([^}]*)\}\)$')
RE_RESULT = re.compile(r'^:SetResult\((\d+)\)$')
RE_RECIPE = re.compile(r'^:AddRecipe\((\d+), Quality\.[A-Za-z]+, \{([^}]*)\}\)$')
RE_REAGENT = re.compile(r'^:AddReagent\((\d+), (\d+)\)$')
RE_SPELLSRC = re.compile(r'^SpellSource\.([A-Za-z]+)$')
RE_RECSRC = re.compile(r'^RecipeSource\.([A-Za-z]+)$')
RE_PRELUDE = [
    re.compile(r'^local lib = LibCraftsGetLibrary\(\)$'),
    re.compile(r'^local name, version = '),
    re.compile(r'^local module = '),
    re.compile(r'^if not module then return end$'),
    re.compile(r'^local Quality = lib\.constants\.qualities$'),
    re.compile(r'^local SpellSource = lib\.constants\.spell_sources$'),
    re.compile(r'^local RecipeSource = lib\.constants\.recipe_sources$'),
]


class ParseError(Exception):
    pass


def strip_comment(s):
    # comments in the upstream only follow a closing paren; names with "--" are not expected
    return re.sub(r'(\)) --.*$', r'\1', s)


def map_sources(text, regex, table, lineno, line):
    out = []
    for part in [p.strip() for p in text.split(",")]:
        if not part:
            continue
        m = regex.match(part)
        if not m or m.group(1) not in table:
            raise ParseError("line %d: unknown source %r: %s" % (lineno, part, line))
        out.append(table[m.group(1)])
    return out


def parse(text):
    """Return {spellId: entry dict} for crafts that have a result."""
    crafts = {}
    cur = None
    turtle = False
    in_turtle = False
    for lineno, raw in enumerate(text.splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("--"):
            continue
        line = strip_comment(line).strip()
        if line == "if lib.env.is_turtle_wow then":
            if cur or in_turtle:
                raise ParseError("line %d: unexpected turtle block: %s" % (lineno, raw))
            in_turtle = True
            continue
        if line == "end" and cur is None:
            if not in_turtle:
                raise ParseError("line %d: stray end: %s" % (lineno, raw))
            in_turtle = False
            continue
        m = RE_CRAFT.match(line)
        if m:
            if cur:
                raise ParseError("line %d: NewCraft before :Save(): %s" % (lineno, raw))
            sid = int(m.group(1))
            # A Turtle block entry overrides the vanilla craft of the same spell (Turtle changed it).
            if sid in crafts and not (in_turtle and not crafts[sid]["turtle"]):
                raise ParseError("line %d: duplicate spell %d: %s" % (lineno, sid, raw))
            name = re.sub(r'\\(.)', r'\1', m.group(2))
            cur = {"id": sid, "n": name, "skill": int(m.group(3)), "item": None, "pat": [], "r": [],
                   "src": map_sources(m.group(4), RE_SPELLSRC, SPELL_SRC, lineno, raw), "turtle": in_turtle}
            continue
        if cur is None:
            if any(r.match(line) for r in RE_PRELUDE):
                continue
            raise ParseError("line %d: unrecognised line: %s" % (lineno, raw))
        m = RE_RESULT.match(line)
        if m:
            if cur["item"] is not None:
                raise ParseError("line %d: second SetResult: %s" % (lineno, raw))
            cur["item"] = int(m.group(1))
            continue
        m = RE_RECIPE.match(line)
        if m:
            cur["pat"].append(int(m.group(1)))
            cur["src"] += map_sources(m.group(2), RE_RECSRC, RECIPE_SRC, lineno, raw)
            continue
        m = RE_REAGENT.match(line)
        if m:
            cur["r"] += [int(m.group(1)), int(m.group(2))]
            continue
        if line == ":Save()":
            if cur["item"] is not None:
                crafts[cur["id"]] = cur
            cur = None
            continue
        raise ParseError("line %d: unrecognised chain line: %s" % (lineno, raw))
    if cur:
        raise ParseError("end of file: craft %d has no :Save()" % cur["id"])
    if in_turtle:
        raise ParseError("end of file: unterminated turtle block")
    return crafts


def lua_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'


def render(profession, crafts, url):
    out = [
        "-- Generated by tools/make-recipes.py. Do not edit by hand.",
        "-- Source: " + url,
        "-- Commit: " + COMMIT,
        "-- Licence: LibCrafts-1.0 is MIT, see licenses/LibCrafts-1.0.txt",
        "TaxTheFools = TaxTheFools or {}",
        "TaxTheFools.RecipeData = TaxTheFools.RecipeData or {}",
        "local t = {}",
        "TaxTheFools.RecipeData[%s] = t" % lua_str(profession),
    ]
    for sid in sorted(crafts):
        c = crafts[sid]
        src = [s for s in SRC_ORDER if s in c["src"]]
        fields = ["n = " + lua_str(c["n"]), "skill = %d" % c["skill"], "item = %d" % c["item"]]
        if c["pat"]:
            fields.append("pat = { %s }" % ", ".join(str(p) for p in c["pat"]))
        fields.append("src = { %s }" % ", ".join(lua_str(s) for s in src))
        fields.append("r = { %s }" % ", ".join(str(x) for x in c["r"]))
        if c["turtle"]:
            fields.append("turtle = true")
        out.append("t[%d] = { %s }" % (sid, ", ".join(fields)))
    return "\n".join(out) + "\n"


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("profession")
    ap.add_argument("--input")
    ap.add_argument("--out", default="TaxTheFools/recipedata.lua")
    a = ap.parse_args(argv)
    url = URL % (COMMIT, a.profession)
    if a.input:
        with open(a.input, encoding="utf-8") as f:
            text = f.read()
    else:
        with urllib.request.urlopen(url) as r:
            text = r.read().decode("utf-8")
    try:
        crafts = parse(text)
    except ParseError as e:
        sys.exit("make-recipes: " + str(e))
    with open(a.out, "w", encoding="utf-8", newline="\n") as f:
        f.write(render(a.profession, crafts, url))
    print("%s: %d recipes (%d turtle) -> %s" % (a.profession, len(crafts),
          sum(1 for c in crafts.values() if c["turtle"]), a.out))


if __name__ == "__main__":
    main()
