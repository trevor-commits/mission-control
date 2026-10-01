from pathlib import Path
import re
root = Path(__file__).resolve().parents[1]
s = (root / ".github/workflows/verify.yml").read_text()
assert re.search(r"uses: actions/setup-python@[0-9a-f]{40}", s), "pinned Python setup missing"
assert 'python-version: "3.11"' in s, "Python 3.11 missing"
assert "brew install shellcheck" in s, "ShellCheck install missing"
assert "@fission-ai/openspec@1.5.0" in s, "pinned OpenSpec CLI missing"
assert "playwright@1.62.0" in s, "pinned Playwright client missing"
assert (root / "scripts/verify-offline.sh").is_file(), "offline verifier script required"
assert (root / "CONTRIBUTING.md").is_file(), "CONTRIBUTING.md required"
assert (root / ".node-version").read_text().strip() == "22", "Node 22 pin missing"
# Every `uses:` must be SHA-pinned (40-hex) — no mutable tag refs.
for line in s.splitlines():
    if "uses:" in line:
        assert re.search(r"uses:\s*\S+@[0-9a-f]{40}\b", line), \
            "unpinned action ref: %s" % line.strip()
assert "concurrency:" in s and "cancel-in-progress" in s, "missing run concurrency control"
assert "permissions:" in s and "contents: read" in s, "workflow must be least-privilege"
assert (root / ".github/dependabot.yml").is_file(), "dependabot config required"
lock = root / "dashboard/vendor/cytoscape.min.js.sha256"
assert lock.is_file(), "vendored cytoscape hash lock required"
print("CI workflow prerequisites: PASS")
