"""Exercise the pinned CLI with the real config in a disposable repository."""

import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile


def verify(config):
    with tempfile.TemporaryDirectory(prefix="backlog-contract-") as directory:
        root = Path(directory)
        shutil.copyfile(config, root / "backlog.config.yml")
        # Match tracked repository layout; complete expects its destination.
        for folder in ["tasks", "completed", "archive/tasks"]:
            (root / "docs/product/backlog" / folder).mkdir(parents=True, exist_ok=True)
        subprocess.run(["git", "init", "-q", directory], check=True)
        env = dict(os.environ, NO_COLOR="1")

        def run(*args):
            result = subprocess.run(
                ["backlog", *args],
                cwd=root,
                env=env,
                check=False,
                text=True,
                capture_output=True,
            )
            assert result.returncode == 0, (args, result.stdout, result.stderr)
            return result.stdout

        created = run(
            "task",
            "create",
            "Disposable lifecycle check",
            "--type",
            "research",
            "--priority",
            "P1",
            "-l",
            "size:S,area:testing",
            "--ac",
            "The CLI persists and reloads the configured lifecycle.",
            "--plain",
        )
        match = re.search(r"\bPB-\d+\b", created)
        assert match, created
        task_id = match.group()
        assert "Backlog" in run("task", task_id, "--plain")
        assert "P1" in run("task", task_id, "--plain")
        for status in ["Ready", "In Progress", "Blocked", "In Progress", "Review"]:
            run("task", "edit", task_id, "-s", status)
            assert status in run("task", task_id, "--plain")
        run(
            "task",
            "edit",
            task_id,
            "--check-ac",
            "1",
            "--final-summary",
            "Verified in a disposable repository.",
            "-s",
            "Done",
        )
        run("task", "complete", task_id)
        completed = list((root / "docs/product/backlog/completed").glob("*.md"))
        assert len(completed) == 1
        assert task_id in completed[0].read_text()
        assert "[x]" in completed[0].read_text()

        created = run("task", "create", "Disposable archive check", "--plain")
        match = re.search(r"\bPB-\d+\b", created)
        assert match, created
        second_id = match.group()
        assert second_id != task_id, "Completed IDs must not be reused"
        run("task", "archive", second_id)
        archived = list((root / "docs/product/backlog/archive/tasks").glob("*.md"))
        assert len(archived) == 1
        assert second_id in archived[0].read_text()
        run("doctor")
        assert not (root / "backlog").exists(), "Custom storage path was ignored"
        log = subprocess.run(
            ["git", "rev-parse", "--verify", "HEAD"], cwd=root, capture_output=True
        )
        assert log.returncode != 0, "CLI must not auto-commit"
    print("Backlog lifecycle, persistence, custom storage, and no-auto-commit passed.")


if __name__ == "__main__":
    verify(Path(sys.argv[1]).resolve())
