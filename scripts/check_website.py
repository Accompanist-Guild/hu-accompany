"""Checks the website folder: balanced HTML, one h1 per page, unique ids, and that every relative link and
#anchor points at something that exists. Exits 1 on any problem, so the publish workflow stops.

    python3 scripts/check_website.py website
"""
import sys, pathlib, re
from html.parser import HTMLParser
root = pathlib.Path(sys.argv[1])
class P(HTMLParser):
    VOID={"meta","link","br","hr","img","input"}
    def __init__(s):
        super().__init__(); s.ids=set(); s.links=[]; s.stack=[]; s.problems=[]; s.dup=set(); s.h1=0
    def handle_starttag(s,t,a):
        a=dict(a)
        if "id" in a:
            if a["id"] in s.ids: s.dup.add(a["id"])
            s.ids.add(a["id"])
        if t=="a" and "href" in a: s.links.append(a["href"])
        if t=="h1": s.h1+=1
        if t not in s.VOID: s.stack.append(t)
    def handle_endtag(s,t):
        if t in s.VOID: return
        if not s.stack or s.stack[-1]!=t: s.problems.append(f"unexpected </{t}> (open: {s.stack[-3:]})")
        else: s.stack.pop()
pages={}
for f in sorted(root.rglob("*.html")):
    p=P(); p.feed(f.read_text()); p.close()
    if p.stack: p.problems.append(f"never closed: {p.stack}")
    pages[f]=p
bad=0
for f,p in pages.items():
    rel=f.relative_to(root)
    for msg in p.problems: print("HTML", rel, msg); bad+=1
    if p.dup: print("DUP ids", rel, p.dup); bad+=1
    if p.h1!=1: print("h1 count", rel, p.h1); bad+=1
    for href in p.links:
        if re.match(r"(https?:|mailto:|#$)",href):
            if href.startswith("http://"): print("insecure link",rel,href); bad+=1
            continue
        path,_,frag=href.partition("#")
        target=(f.parent/path) if path else f
        if target.is_dir(): target=target/"index.html"
        if not target.exists(): print("BROKEN", rel, "->", href); bad+=1; continue
        if frag and target in pages and frag not in pages[target].ids and target.suffix==".html":
            print("BROKEN anchor", rel, "->", href); bad+=1
print("pages:", len(pages), "problems:", bad)
sys.exit(1 if bad else 0)
