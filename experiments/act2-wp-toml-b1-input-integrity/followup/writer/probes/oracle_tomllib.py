# nim-check: skip
# Reference-parser cross-check oracle.
# LIMITATION (explicit): Python 3.12 tomllib implements TOML v1.0.0 ONLY.
# It is a valid auxiliary oracle for v1.0.0 verdicts (Toml_v100 flavor
# emissions) and MUST NOT be used to judge v1.1.0-only output (\e, \xHH,
# multi-line inline tables, trailing commas in inline tables, omitted
# seconds). Any "RAISE" recorded here for a v1.1.0-specific emission is
# expected and carries no v1.1.0 verdict weight.
# Usage: oracle_tomllib.py <dir-with-emitted-toml-files>
import sys, os, tomllib

d = sys.argv[1] if len(sys.argv) > 1 else "."
for name in sorted(os.listdir(d)):
    if not name.endswith(".toml"):
        continue
    path = os.path.join(d, name)
    with open(path, "rb") as f:
        data = f.read()
    try:
        tomllib.loads(data.decode("utf-8"))
        print(f"{name}: OK")
    except UnicodeDecodeError as e:
        print(f"{name}: RAISE UnicodeDecodeError: {e}")
    except tomllib.TOMLDecodeError as e:
        msg = str(e).replace("\n", " ")
        print(f"{name}: RAISE TOMLDecodeError: {msg}")
