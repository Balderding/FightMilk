"""Makes the public snapshot of FightMilk in work/pub (its own git repo, remote = GitHub).

- takes only what git tracks at HEAD (keys/, work/, release/ and ledgers are never tracked)
- refuses to run with uncommitted changes
- scans every file for e-mail addresses, keys, passwords and private files; stops on any hit
- commits as the GitHub no-reply address
Run: python -I tools/export_public.py "message"   (then push from work/pub)
"""
import io, pathlib, re, subprocess, sys, tarfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
PUB = ROOT / "work" / "pub"
EMAIL = "51464052+Balderding@users.noreply.github.com"
msg = sys.argv[1] if len(sys.argv) > 1 else "Snapshot"


def git(*a, cwd=ROOT):
    return subprocess.run(["git", *a], cwd=cwd, capture_output=True, text=True, check=True).stdout


if git("status", "--porcelain").strip():
    sys.exit("uncommitted changes - commit first")

BAD_NAMES = re.compile(r"\.(jks|keystore|p12|gguf|exe|dll|so|apk|zip)$|(^|/)(keys|work|release|\.superpowers)/|key\.properties|local\.properties", re.I)
NOTES = re.compile(r"(^|/)HANDOFF[^/]*\.md$")  # session notes (case-sensitive: "handoff.dart" is the feature)
BAD_TEXT = [
    (re.compile(r"[A-Za-z0-9._%+-]+@(gmail|yahoo|hotmail|outlook)\.[a-z]+", re.I), "e-mail address"),
    (re.compile("tre" + "nss", re.I), "personal handle"),
    (re.compile(r"sk-ant-[A-Za-z0-9_-]{10,}"), "Anthropic key"),
    (re.compile(r"sk-[A-Za-z0-9]{32,}"), "API key"),
    (re.compile(r"AIza[0-9A-Za-z_-]{30,}"), "Google key"),
    (re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----"), "private key"),
    (re.compile(r'(store|key)Password\s*=\s*"[^"]{6,}"'), "password"),
    (re.compile(r"^(store|key)Password=\S{6,}", re.M), "password"),
    (re.compile(r'"seed"\s*:\s*"[A-Za-z0-9+/=]{20,}"'), "pack signing seed"),
]

data = subprocess.run(["git", "archive", "--format=tar", "HEAD"], cwd=ROOT, capture_output=True, check=True).stdout
tar = tarfile.open(fileobj=io.BytesIO(data))
members = [m for m in tar.getmembers() if m.isfile()]
problems = []
for m in members:
    if BAD_NAMES.search(m.name) or NOTES.search(m.name):
        problems.append(f"{m.name}: file type/place not allowed")
        continue
    body = tar.extractfile(m).read()
    try:
        text = body.decode("utf-8")
    except UnicodeDecodeError:
        continue  # binary assets (wav) are ours
    for rx, what in BAD_TEXT:
        if rx.search(text):
            problems.append(f"{m.name}: {what}")
if problems:
    print("\n".join(problems))
    sys.exit("SCAN FAILED - nothing exported")

PUB.mkdir(parents=True, exist_ok=True)
if not (PUB / ".git").exists():
    git("init", "-q", "-b", "main", cwd=PUB)
git("config", "user.name", "balderding", cwd=PUB)
git("config", "user.email", EMAIL, cwd=PUB)
# sync: overwrite what HEAD has, drop tracked files HEAD no longer has; build output is left alone
keep = {m.name for m in members}
for f in git("ls-files", cwd=PUB).splitlines():
    if f not in keep:
        (PUB / f).unlink(missing_ok=True)
tar.extractall(PUB, members=members)
git("add", "-A", cwd=PUB)
if not git("status", "--porcelain", cwd=PUB).strip():
    print("nothing changed")
    sys.exit(0)
git("commit", "-q", "-m", msg, cwd=PUB)
print(f"scanned {len(members)} files, clean; committed in {PUB}: {git('log', '--oneline', '-1', cwd=PUB).strip()}")
