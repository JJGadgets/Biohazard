from os import environ
import requests
from operator import itemgetter
import re

repo = environ.get("GITHUB_REPOSITORY")
ghToken = environ.get("GH_TOKEN")

req = requests.get(url = f"https://api.github.com/repos/{repo}/pulls", headers = {"Authorization": f"Token {ghToken}", "Accept": "application/vnd.github+json"})
prData: list[dict[str, str]] = [{k: v for k, v in d.items() if k in ["title", "html_url"]} for d in req.json()] # pyright: ignore[reportAny]]

for d in prData:
    r = re.search(r"(feat|fix|chore)\(([^/]*)/(.*)\)(!*): (?:[a-zA-Z]*) *([^ ]*) *(?:➼|to) v*([^ ]+)[ -]*([a-zA-Z]*)$", d["title"])
    if r.group(4) == "!":
        d["type"] = "1"
    if r.group(1) == "feat":
        d["type"] = "2"
    if r.group(1) == "fix":
        d["type"] = "3"
    if r.group(1) == "chore":
        d["type"] = "4"
    else:
        d["type"] = "5"
    d["datasource"] = r.group(2)
    d["depName"] = r.group(3)
    d["oldVersion"] = r.group(5)
    d["newVersion"] = r.group(6)
    if r.group(7):
        d["cluster"] = r.group(7)
    else:
        d["cluster"] = ""

prData.sort(key = itemgetter("newVersion"), reverse=True)
prData.sort(key = itemgetter("depName", "datasource", "cluster", "type", "oldVersion"))

# print(prData)
for d in prData:
    print(f"[{d['title']}]({d['html_url']})")
