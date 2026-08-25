from pathlib import Path
import re
s = (Path(__file__).resolve().parents[1] / ".github/workflows/verify.yml").read_text()
assert re.search(r"uses: actions/setup-python@[0-9a-f]{40}", s), "pinned Python setup missing"
assert 'python-version: "3.11"' in s, "Python 3.11 missing"
assert "brew install shellcheck" in s, "ShellCheck install missing"
print("CI workflow prerequisites: PASS")
