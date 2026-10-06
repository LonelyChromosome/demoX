"""One bounded validation pass. Missing tools are SKIP, never a pass claim."""
from pathlib import Path
import ast
import importlib.util
import re
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
failures = []
scripts = sorted([*ROOT.glob("src/**/*.gd"), *ROOT.glob("tests/**/*.gd")])


def check(ok, description):
    print(("PASS " if ok else "FAIL ") + description)
    if not ok:
        failures.append(description)


source = (ROOT / "src/core/localization.gd").read_text()
catalogs = {}
for locale in ("VI", "EN"):
    block = re.search(rf"const {locale} := {{(.*?)^}}", source, re.S | re.M).group(1)
    pairs = re.findall(r'^\s*"([^"\n]+)":\s*("(?:[^"\\]|\\.)*"),?$', block, re.M)
    catalogs[locale] = {key: ast.literal_eval(value) for key, value in pairs}
    check(len(pairs) == len(catalogs[locale]), locale + " catalog has no duplicate keys")
check(catalogs["VI"].keys() == catalogs["EN"].keys(), "VI/EN key parity")
placeholder_errors = []
for key in catalogs["VI"].keys() & catalogs["EN"].keys():
    placeholders = [set(re.findall(r"\{([^}]+)\}", catalogs[locale][key])) for locale in ("VI", "EN")]
    if placeholders[0] != placeholders[1]:
        placeholder_errors.append(key)
check(not placeholder_errors, "placeholder parity " + str(placeholder_errors))
missing = []
for path in scripts:
    if "tests" in path.parts:
        continue
    for key in re.findall(r'Localization\.text\("([\w.-]+)"', path.read_text()):
        if key not in catalogs["VI"] and not key.endswith("."):
            missing.append(f"{path.relative_to(ROOT)}:{key}")
check(not missing, "literal localization keys exist " + str(missing))

random_paths = []
for path in [*ROOT.glob("src/systems/*.gd"), *ROOT.glob("src/core/*.gd")]:
    if re.search(r"\b(randf|randi|randf_range|randi_range|randomize|RandomNumberGenerator)\b", path.read_text()):
        random_paths.append(str(path.relative_to(ROOT)))
check(not random_paths, "no unseeded gameplay RNG calls " + str(random_paths))
check(subprocess.run(["git", "diff", "--check"], cwd=ROOT).returncode == 0, "git diff --check")

if importlib.util.find_spec("gdtoolkit"):
    from gdtoolkit.parser import parser
    parse_errors = []
    for path in scripts:
        try:
            parser.parse(path.read_text())
        except Exception as error:
            parse_errors.append(f"{path.relative_to(ROOT)}: {error}")
    check(not parse_errors, f"GDScript grammar parse: {len(scripts)} files")
    for error in parse_errors:
        print(error)
else:
    print("SKIP GDScript grammar parse: gdtoolkit unavailable")

godot = shutil.which("godot") or shutil.which("godot4")
if godot:
    command = [godot, "--headless", "--path", str(ROOT)]
    imported = subprocess.run(command + ["--editor", "--import", "--quit"], timeout=60)
    check(imported.returncode == 0, "Godot import")
    if imported.returncode == 0:
        for name in ("s14_balance_crisis_test", "s13_localization_ending_test", "s12b_visual_social_integration_test"):
            result = subprocess.run(command + ["--script", f"tests/{name}.gd"], timeout=45)
            check(result.returncode == 0, name)
else:
    print("SKIP Godot runtime/import/S14/S13/S12-B regression: Godot unavailable")
    print("SKIP actual gameplay screenshot: no Godot renderer")
sys.exit(bool(failures))
