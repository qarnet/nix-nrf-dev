"""Bounded local-only SDK fixture preparation; never calls west update/fetch."""

import hashlib
import os
from pathlib import Path
import shutil
import subprocess

import yaml
from west.configuration import Configuration
from west.manifest import Manifest


class FixtureError(RuntimeError):
    pass


def isolated_env():
    env = dict(
        os.environ,
        GIT_CONFIG_NOSYSTEM="1",
        GIT_CONFIG_GLOBAL=os.devnull,
        GIT_CONFIG_SYSTEM=os.devnull,
        GIT_OPTIONAL_LOCKS="0",
        GIT_NO_LAZY_FETCH="1",
        GIT_TERMINAL_PROMPT="0",
        GIT_LFS_SKIP_SMUDGE="1",
        WEST_CONFIG_GLOBAL=os.devnull,
        WEST_CONFIG_SYSTEM=os.devnull,
        PYTHONDONTWRITEBYTECODE="1",
    )
    for key in (
        "WEST_CONFIG_LOCAL",
        "ZEPHYR_BASE",
        "Zephyr_DIR",
        "GIT_DIR",
        "GIT_WORK_TREE",
    ):
        env.pop(key, None)
    return env


def git(path, *args, check=True):
    result = subprocess.run(
        [
            "git",
            "-c",
            "core.hooksPath=" + os.devnull,
            "-c",
            "core.fsmonitor=false",
            "-C",
            str(path),
            *args,
        ],
        env=isolated_env(),
        capture_output=True,
        text=True,
        timeout=120,
    )
    if check and result.returncode:
        raise FixtureError(
            f"local git {' '.join(args)} failed in {path}: {result.stderr.strip()}"
        )
    return result.stdout.strip()


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest() if path.is_file() else None


def snapshot(path):
    gitdir = Path(git(path, "rev-parse", "--absolute-git-dir"))
    return dict(
        head=git(path, "rev-parse", "HEAD"),
        refs=git(path, "show-ref", "--head"),
        tracked=git(path, "status", "--porcelain=v1", "--untracked-files=no"),
        git_files={
            name: digest(gitdir / name)
            for name in ("HEAD", "config", "index", "packed-refs")
        },
    )


def inspect_sdk(sdk, excluded_projects=()):
    sdk = Path(sdk).resolve()
    if not (sdk / ".west/config").is_file():
        raise FixtureError(f"not an existing SDK workspace: {sdk}")
    # Isolate configuration without changing caller process globals.
    old = {
        key: os.environ.get(key)
        for key in ("WEST_CONFIG_GLOBAL", "WEST_CONFIG_SYSTEM", "WEST_CONFIG_LOCAL")
    }
    try:
        os.environ["WEST_CONFIG_GLOBAL"] = os.devnull
        os.environ["WEST_CONFIG_SYSTEM"] = os.devnull
        os.environ.pop("WEST_CONFIG_LOCAL", None)
        manifest = Manifest.from_topdir(topdir=sdk)
    finally:
        for key, value in old.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value
    config = Configuration(topdir=sdk)
    nrf = (sdk / config.get("manifest.path")).resolve()
    if not (nrf / "Kconfig.nrf").is_file():
        raise FixtureError("seed must be an SDK-owned Nordic manifest workspace")
    nrf_sha = git(nrf, "rev-parse", "HEAD")
    pinned = yaml.safe_load(git(nrf, "show", f"{nrf_sha}:west.yml"))
    zephyr_entry = next(
        project
        for project in pinned["manifest"]["projects"]
        if project["name"] == "zephyr"
    )
    allowlist = zephyr_entry["import"]["name-allowlist"]
    projects = []
    for project in manifest.projects:
        if project.name in excluded_projects:
            continue
        if project.name == "manifest":
            path, name, destination = nrf, "nrf", "sdk/nrf"
        elif manifest.is_active(project):
            path, name = Path(project.abspath).resolve(), project.name
            destination = "sdk/rtos" if name == "zephyr" else "sdk/" + project.path
        else:
            continue
        if not path.is_relative_to(sdk):
            raise FixtureError(f"source project escapes the seed workspace: {path}")
        state = snapshot(path)
        if state["tracked"]:
            raise FixtureError(f"dirty source input refused: {path}")
        if name != "nrf":
            expected = git(
                path, "rev-parse", "--verify", project.revision + "^{commit}"
            )
            if state["head"] != expected:
                raise FixtureError(
                    f"source HEAD does not match manifest revision: {name}"
                )
        tree = git(path, "ls-tree", "-r", "-l", state["head"])
        size = 0
        unpopulated_submodules = []
        for line in tree.splitlines():
            attrs, _, filename = line.partition("\t")
            mode, kind, oid, length = attrs.split()
            if mode == "160000":
                if ((path / filename) / ".git").exists():
                    raise FixtureError(
                        f"populated local submodule needs separate handling: {path}/{filename}; no fetch attempted"
                    )
                # Mirror the seed's intentionally empty gitlinks. Builds needing
                # those assets must fail rather than download them.
                unpopulated_submodules.append(dict(path=filename, commit=oid))
            if kind == "blob":
                size += int(length)
            if mode == "120000":
                target = git(path, "cat-file", "blob", oid)
                if Path(target).is_absolute():
                    raise FixtureError(
                        f"absolute source symlink refused: {path}/{filename}"
                    )
        projects.append(
            dict(
                name=name,
                source=str(path),
                destination=destination,
                commit=state["head"],
                bytes=size,
                original=state,
                unpopulated_submodules=unpopulated_submodules,
            )
        )
    return dict(
        sdk=str(sdk),
        ncs_version=(nrf / "VERSION").read_text().strip(),
        allowlist=allowlist,
        projects=projects,
        config_sha256=digest(sdk / ".west/config"),
        estimated_bytes=sum(project["bytes"] for project in projects),
        excluded_projects=list(excluded_projects),
    )


def seed_repo(path):
    git(path, "init", "-q")
    git(path, "add", ".")
    git(
        path,
        "-c",
        "user.name=SDK source fixture",
        "-c",
        "user.email=fixture@example.invalid",
        "commit",
        "-qm",
        "test-owned fixture",
    )
    return git(path, "rev-parse", "HEAD")


def prepare(
    sdk,
    destination,
    fixture,
    max_bytes=8 * 1024**3,
    reserve_bytes=1024**3,
    excluded_projects=(),
):
    destination = Path(destination).absolute()
    if destination.exists() or destination.is_symlink():
        raise FixtureError(f"destination must not exist: {destination}")
    if not destination.parent.is_dir():
        raise FixtureError("destination parent must already exist")
    plan = inspect_sdk(sdk, excluded_projects)
    if plan["estimated_bytes"] > max_bytes:
        raise FixtureError(
            f"SDK working trees exceed configured copy budget: {plan['estimated_bytes']} > {max_bytes}"
        )
    if (
        shutil.disk_usage(destination.parent).free
        < plan["estimated_bytes"] + reserve_bytes
    ):
        raise FixtureError(
            "insufficient free space for independent working files plus reserve"
        )
    destination.mkdir(mode=0o700)
    for project in plan["projects"]:
        target = destination / project["destination"]
        target.parent.mkdir(parents=True, exist_ok=True)
        # Only local paths are accepted. Disable user hooks/filters and recursion;
        # refs/index/worktree are independent while Git objects are borrowed.
        git(
            destination,
            "clone",
            "--shared",
            "--no-checkout",
            "--no-recurse-submodules",
            "--",
            project["source"],
            str(target),
        )
        git(target, "update-ref", "refs/heads/manifest-rev", project["commit"])
        git(target, "checkout", "--detach", project["commit"])
        for link in target.rglob("*"):
            if link.is_symlink() and not link.resolve().is_relative_to(destination):
                raise FixtureError(f"fixture source symlink escapes workspace: {link}")
        # Ordinary files are new working files, not hardlinks to seed sources.
        probe = "west.yml" if project["name"] in ("nrf", "zephyr") else None
        if (
            probe
            and (target / probe).is_file()
            and os.path.samefile(target / probe, Path(project["source"]) / probe)
        ):
            raise FixtureError(f"borrowed source working file: {target / probe}")
    application = destination / "application"
    module = destination / "modules/source_import_probe"
    shutil.copytree(Path(fixture) / "app", application)
    shutil.copytree(Path(fixture) / "module", module)
    # Nix-store templates are read-only. Only these newly owned copies become
    # writable so test Git metadata/manifests can be created safely.
    for copied in (application, module):
        copied.chmod(copied.stat().st_mode | 0o700)
        for entry in copied.rglob("*"):
            if not entry.is_symlink():
                entry.chmod(entry.stat().st_mode | (0o700 if entry.is_dir() else 0o600))
    module_sha = seed_repo(module)
    nrf_project = next(
        project for project in plan["projects"] if project["name"] == "nrf"
    )
    zephyr_project = next(
        project for project in plan["projects"] if project["name"] == "zephyr"
    )
    data = {
        "manifest": {
            "version": "0.13",
            "projects": [
                {
                    "name": "nrf",
                    "url": nrf_project["source"],
                    "revision": nrf_project["commit"],
                    "path": "nrf",
                    "import": {
                        "path-prefix": "sdk",
                        "name-blocklist": list(excluded_projects),
                    },
                },
                {
                    "name": "zephyr",
                    "url": zephyr_project["source"],
                    "revision": zephyr_project["commit"],
                    "path": "rtos",
                    "import": {
                        "path-prefix": "sdk",
                        "name-allowlist": plan["allowlist"],
                    },
                },
                {
                    "name": "source_import_probe",
                    "url": str(module),
                    "revision": module_sha,
                    "path": "modules/source_import_probe",
                },
            ],
            "self": {"path": "application"},
        }
    }
    (application / "west.yml").write_text(yaml.safe_dump(data, sort_keys=False))
    seed_repo(application)
    (destination / ".west").mkdir()
    (destination / ".west/config").write_text(
        "[manifest]\npath = application\nfile = west.yml\n"
    )
    config = Configuration(topdir=destination)
    resolved = Manifest.from_topdir(topdir=destination, config=config)
    for project in plan["projects"]:
        actual = resolved.get_projects([project["name"]], allow_paths=False)[0]
        if actual.path != project["destination"]:
            raise FixtureError(
                f"import precedence/path-prefix changed {project['name']}: {actual.path}"
            )
        if git(Path(actual.abspath), "rev-parse", "HEAD") != project["commit"]:
            raise FixtureError(f"relocated source revision differs: {project['name']}")
    plan["destination"] = str(destination)
    plan["manifest_sha256"] = digest(application / "west.yml")
    plan["destination_config_sha256"] = digest(destination / ".west/config")
    plan["module_commit"] = module_sha
    return plan


def verify_original(plan):
    if digest(Path(plan["sdk"]) / ".west/config") != plan["config_sha256"]:
        raise FixtureError("original SDK workspace config changed")
    for project in plan["projects"]:
        if snapshot(Path(project["source"])) != project["original"]:
            raise FixtureError(
                f"original source/Git metadata changed: {project['name']}"
            )
