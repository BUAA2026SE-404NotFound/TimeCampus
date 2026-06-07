#!/usr/bin/env python3
"""Deploy TimeCampus compose stack over password SSH.

The script reads DEPLOY_HOST, DEPLOY_USER and DEPLOY_PASSWORD from
TimeCampus-Portal/.env, uploads a git-clean archive of this workspace, and runs
docker compose on the server. It intentionally does not print secrets.
"""

from __future__ import annotations

import argparse
import io
from pathlib import Path
import posixpath
import subprocess
import sys
import tarfile
import time

try:
    import paramiko
except ImportError as exc:  # pragma: no cover
    raise SystemExit("paramiko is required. Install with: python -m pip install paramiko") from exc


ROOT = Path(__file__).resolve().parents[1]
PORTAL_ENV = ROOT / "TimeCampus-Portal" / ".env"
REMOTE_DIR = "~/TimeCampus"


def read_dotenv(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        values[key.strip()] = value.strip().strip('"').strip("'")
    return values


def run_git(args: list[str], cwd: Path) -> list[str]:
    output = subprocess.check_output(["git", *args], cwd=cwd, text=True, encoding="utf-8")
    return [line for line in output.splitlines() if line.strip()]


def git_tree_paths(repo: Path) -> list[str]:
    output = subprocess.check_output(
        ["git", "-c", "core.quotePath=false", "ls-tree", "-r", "-z", "--name-only", "HEAD"],
        cwd=repo,
    )
    return [item.decode("utf-8") for item in output.split(b"\0") if item]


def head_files(repo: Path, prefix: str = "") -> list[tuple[str, bytes]]:
    files: list[tuple[str, bytes]] = []
    for line in git_tree_paths(repo):
        if not prefix and line in {"TimeCampus-Backend", "TimeCampus-Portal", "TimeCampus-Agent"}:
            continue
        data = subprocess.check_output(["git", "show", f"HEAD:{line}"], cwd=repo)
        arcname = f"{prefix}{line}" if prefix else line
        files.append((arcname, data))
    return files


def archive_files() -> list[tuple[str, bytes]]:
    files = head_files(ROOT)
    for submodule in ("TimeCampus-Backend", "TimeCampus-Portal", "TimeCampus-Agent"):
        files.extend(head_files(ROOT / submodule, f"{submodule}/"))
    root_env = ROOT / ".env"
    if root_env.exists():
        files.append((".env", root_env.read_bytes()))
    return files


def build_archive() -> bytes:
    buffer = io.BytesIO()
    with tarfile.open(fileobj=buffer, mode="w:gz") as tar:
        for arcname, data in archive_files():
            info = tarfile.TarInfo(arcname)
            info.size = len(data)
            info.mtime = int(time.time())
            tar.addfile(info, io.BytesIO(data))
    buffer.seek(0)
    return buffer.getvalue()


def remote_run(client: paramiko.SSHClient, command: str, input_text: str | None = None) -> None:
    print(f"$ {command}")
    stdin, stdout, stderr = client.exec_command(command, get_pty=False)
    if input_text is not None:
        stdin.write(input_text)
        stdin.flush()
    stdin.channel.shutdown_write()
    while not stdout.channel.exit_status_ready():
        if stdout.channel.recv_ready():
            sys.stdout.write(stdout.channel.recv(4096).decode("utf-8", errors="replace"))
            sys.stdout.flush()
        if stderr.channel.recv_stderr_ready():
            sys.stderr.write(stderr.channel.recv_stderr(4096).decode("utf-8", errors="replace"))
            sys.stderr.flush()
        time.sleep(0.1)
    remaining = stdout.read().decode("utf-8", errors="replace")
    errors = stderr.read().decode("utf-8", errors="replace")
    if remaining:
        sys.stdout.write(remaining)
    if errors:
        sys.stderr.write(errors)
    status = stdout.channel.recv_exit_status()
    if status != 0:
        raise RuntimeError(f"Remote command failed with exit status {status}: {command}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--remote-dir", default=REMOTE_DIR)
    parser.add_argument("--skip-up", action="store_true", help="Upload files but do not run docker compose up.")
    args = parser.parse_args()

    env = read_dotenv(PORTAL_ENV)
    host = env.get("DEPLOY_HOST")
    user = env.get("DEPLOY_USER")
    password = env.get("DEPLOY_PASSWORD")
    if not host or not user or not password:
        raise SystemExit("DEPLOY_HOST, DEPLOY_USER and DEPLOY_PASSWORD must be set in TimeCampus-Portal/.env")

    archive = build_archive()
    print(f"Built deployment archive: {len(archive) / 1024 / 1024:.1f} MiB")

    client = paramiko.SSHClient()
    client.load_system_host_keys()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    client.connect(hostname=host, username=user, password=password, timeout=20, banner_timeout=20)
    try:
        remote_dir = args.remote_dir
        remote_run(client, f"mkdir -p {remote_dir} {remote_dir}/data/storage")
        sftp = client.open_sftp()
        remote_sftp_dir = remote_dir
        if remote_dir.startswith("~"):
            remote_sftp_dir = remote_dir.replace("~", sftp.normalize("."), 1)
        remote_archive = posixpath.join(remote_sftp_dir, "timecampus-upload.tar.gz")
        with sftp.file(remote_archive, "wb") as remote_file:
            remote_file.write(archive)
        sftp.close()
        remote_run(client, f"tar -xzf {remote_archive} -C {remote_dir}")
        remote_run(client, f"rm -f {remote_archive}")
        sudo_prefix = "sudo -S -p ''"
        sudo_input = f"{password}\n"
        remote_run(client, f"{sudo_prefix} docker --version && {sudo_prefix} docker compose version", sudo_input * 2)
        remote_run(
            client,
            f"cd {remote_dir} && {sudo_prefix} docker compose --env-file .env -f compose.yaml config >/tmp/timecampus-compose.config",
            sudo_input,
        )
        if not args.skip_up:
            remote_run(
                client,
                f"cd {remote_dir} && {sudo_prefix} docker compose --env-file .env -f compose.yaml up -d --build",
                sudo_input,
            )
            remote_run(
                client,
                f"cd {remote_dir} && {sudo_prefix} docker compose --env-file .env -f compose.yaml ps",
                sudo_input,
            )
    finally:
        client.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
