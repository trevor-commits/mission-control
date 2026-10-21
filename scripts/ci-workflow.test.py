from pathlib import Path
import re
root = Path(__file__).resolve().parents[1]
s = (root / ".github/workflows/verify.yml").read_text()
assert re.search(r"uses: actions/setup-python@[0-9a-f]{40}", s), "pinned Python setup missing"
assert 'python-version: "3.11"' in s, "Python 3.11 missing"
def native_prerequisites(workflow):
    assert "runs-on: macos-15" in workflow, "AppKit/Keychain tests require standard macOS"
    assert "brew install shellcheck" in workflow, "macOS ShellCheck install missing"
    assert "xcrun --find swiftc" in workflow, "native compiler preflight missing"
    assert 'test -x "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"' in workflow, "Chrome preflight missing"

native_prerequisites(s)
for broken in (s.replace("runs-on: macos-15", "runs-on: ubuntu-latest"),
               s.replace("brew install shellcheck", "sudo apt-get install -y shellcheck")):
    try:
        native_prerequisites(broken)
    except AssertionError:
        pass
    else:
        raise AssertionError("incompatible runner/prerequisite must fail")
assert "workflow_dispatch:" in s, "manual verification trigger missing"
assert not re.search(r"(?m)^\s+(push|pull_request|schedule):", s), "routine tests must remain manual"
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
