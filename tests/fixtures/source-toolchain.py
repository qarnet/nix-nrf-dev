"""Toolchain-only sdk-manager peer; source installation calls are errors."""

import json
import os
from pathlib import Path
import shlex
import sys

args = sys.argv[1:]
state = Path(os.environ["SOURCE_TEST_STATE"])
with (state / "toolchain.jsonl").open("a") as log:
    log.write(json.dumps(args) + "\n")
if args[:3] == ["sdk-manager", "toolchain", "env"]:
    if (state / "missing-toolchain").exists():
        sys.exit(1)
    print(f"export PATH={shlex.quote(os.environ['SOURCE_REAL_TOOLS'])}:$PATH")
    print("export FAKE_TOOLCHAIN_ENV=loaded")
    print("export LD_LIBRARY_PATH=source-test-child-only")
elif args[:3] == ["sdk-manager", "toolchain", "install"]:
    if "--skip-cmake-registration" not in args:
        sys.exit("toolchain install must not register CMake packages")
    (state / "missing-toolchain").unlink(missing_ok=True)
else:
    sys.exit(f"unexpected SDK source operation: {args}")
