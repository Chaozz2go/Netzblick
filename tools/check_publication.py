"""Check tracked source and reachable Git history without printing secret values."""
import os
import re
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PATTERNS = [
    re.compile(rb"(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{40,})"),
    re.compile(rb"(?:AKIA|ASIA)[A-Z0-9]{16}"),
    re.compile(rb"-----BEGIN (?:RSA |EC |OPENSSH |DSA |ENCRYPTED )?PRIVATE KEY-----"),
    re.compile(rb"(?i)(?:client_secret|api_key|password|passwd)\s*[:=]\s*[\"']([A-Za-z0-9/+_=.-]{24,})[\"']"),
]

def git(repo, *args):
    return subprocess.check_output(["git", "-C", str(repo), *args], stderr=subprocess.PIPE)

def scan(repo):
    records = git(repo, "rev-list", "--objects", "--all").decode().splitlines()
    objects = {}
    for record in records:
        sha, _, name = record.partition(" ")
        objects.setdefault(sha, name)
    process = subprocess.Popen(["git", "-C", str(repo), "cat-file", "--batch"], stdin=subprocess.PIPE, stdout=subprocess.PIPE)
    bundles = []
    count = 0
    findings = []
    try:
        for sha, name in objects.items():
            process.stdin.write((sha + "\n").encode()); process.stdin.flush()
            header = process.stdout.readline().split()
            if len(header) != 3:
                raise RuntimeError("Git object could not be read")
            size = int(header[2]); data = process.stdout.read(size)
            if len(data) != size or process.stdout.read(1) != b"\n":
                raise RuntimeError("Incomplete Git object")
            if header[1] != b"blob":
                continue
            if name.endswith(".bundle"):
                bundles.append((sha, data))
            if b"\x00" in data:
                continue
            count += 1
            if any(pattern.search(data) for pattern in PATTERNS):
                findings.append(name or sha)
    finally:
        process.stdin.close(); process.stdout.close(); process.wait(timeout=15)
    if process.returncode:
        raise RuntimeError("Git object scan failed")
    return count, findings, bundles

count, findings, bundles = scan(ROOT)
with tempfile.TemporaryDirectory(prefix="Netzblick-publication-") as work:
    for index, (sha, data) in enumerate(bundles):
        bundle = Path(work) / (str(index) + ".bundle")
        bundle.write_bytes(data)
        restored = Path(work) / (str(index) + "-history.git")
        subprocess.run(["git", "clone", "--bare", "--quiet", str(bundle), str(restored)], check=True, capture_output=True)
        total, found, nested = scan(restored)
        count += total
        findings.extend("history-bundle/" + name for name in found)
        if nested:
            raise RuntimeError("Nested history archives require inspection")
if findings:
    raise SystemExit("Publication blocked: possible credential in " + ", ".join(sorted(set(findings))))
print("PASS: %s text objects and %s embedded history archives checked for credential patterns; no matching values found." % (count, len(bundles)))
