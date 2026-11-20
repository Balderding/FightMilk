"""Sets the app version everywhere: python tools/bump_version.py 0.7.1
(pubspec.yaml version + build number, lib/version.dart)."""
import pathlib, re, sys

v = sys.argv[1]
assert re.fullmatch(r"\d+\.\d+\.\d+", v), "version like 0.7.1"
root = pathlib.Path(__file__).resolve().parent.parent / "app"
ps = root / "pubspec.yaml"
s = ps.read_text()
build = int(re.search(r"^version: [\d.]+\+(\d+)", s, re.M).group(1)) + 1
ps.write_text(re.sub(r"^version: .*$", f"version: {v}+{build}", s, count=1, flags=re.M))
vd = root / "lib" / "version.dart"
vd.write_text(re.sub(r"const appVersion = '[^']*';", f"const appVersion = '{v}';", vd.read_text()))
print(f"version {v}+{build}")
