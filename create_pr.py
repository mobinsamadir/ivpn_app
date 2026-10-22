import urllib.request
import json
import os

token = os.environ.get("GITHUB_TOKEN")
repo = "mobinsamadir/ivpn_app"
branch = "feat/growth-monetization-cxx20-pr-162"

url = f"https://api.github.com/repos/{repo}/pulls"
headers = {
    "Accept": "application/vnd.github.v3+json",
    "Authorization": f"token {token}",
    "Content-Type": "application/json"
}
data = {
    "title": "Final Architecture: C++20 MSVC Patch via local dependency",
    "head": branch,
    "base": "main",
    "body": "Fixes GitHub Actions C4596 MSVC error by properly converting the submodule into a normal directory."
}

req = urllib.request.Request(url, data=json.dumps(data).encode('utf-8'), headers=headers, method='POST')
try:
    with urllib.request.urlopen(req) as response:
        res_data = json.loads(response.read().decode('utf-8'))
        print("\n=== SUCCESS ===")
        print("PR URL:", res_data.get('html_url'))
except urllib.error.HTTPError as e:
    print("Error creating PR:", e)
    print(e.read().decode('utf-8'))
