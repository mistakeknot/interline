"""Regression: the statusline renders bead+phase from a KERNEL-authored
interband envelope alone — no legacy /tmp sideband present (Sylveste-rfs).

interphase's `_gate_update_statusline` writer was retired 2026-07-20;
clavain-cli sprint-advance (`writeBeadSideband`) is the sole sideband
author. This test feeds the reader exactly what the kernel writes and
asserts the bead layer renders from it. Also covers the macOS stat
portability fix (BSD `stat -f %m` fallback) — before it, the age gate
silently discarded the envelope on Darwin.
"""

import json
import subprocess
import time

STATUSLINE = "scripts/statusline.sh"
SESSION_ID = "sess-rfs-regress"


def _kernel_envelope(bead_id: str, phase: str) -> dict:
    # Mirrors os/Clavain/cmd/clavain-cli/sideband.go writeBeadSideband.
    now = int(time.time())
    return {
        "version": "1.0.0",
        "namespace": "interphase",
        "type": "bead_phase",
        "session_id": SESSION_ID,
        "timestamp": now,
        "payload": {
            "id": bead_id,
            "phase": phase,
            "reason": "regression",
            "ts": now,
        },
    }


def test_statusline_renders_from_kernel_envelope_only(project_root, tmp_path):
    home = tmp_path / "home"
    (home / ".claude").mkdir(parents=True)
    # Hermetic config: only the bead layer (and its age tag) active.
    (home / ".claude" / "interline.json").write_text(json.dumps({
        "layers": {
            "dispatch": False, "coordination": False, "bead_query": False,
            "phase": False, "session_id": False, "dirty": False,
            "ahead": False, "context": False,
        }
    }))

    interband = tmp_path / "interband"
    bead_dir = interband / "interphase" / "bead"
    bead_dir.mkdir(parents=True)
    (bead_dir / f"{SESSION_ID}.json").write_text(
        json.dumps(_kernel_envelope("Test-042", "executing"))
    )

    stdin_payload = json.dumps({
        "session_id": SESSION_ID,
        "model": {"display_name": "Test"},
        "workspace": {"current_dir": str(tmp_path)},
        "transcript_path": "",
    })
    result = subprocess.run(
        ["bash", str(project_root / STATUSLINE)],
        input=stdin_payload,
        capture_output=True,
        text=True,
        cwd=str(tmp_path),
        env={
            "HOME": str(home),
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin",
            "INTERBAND_ROOT": str(interband),
        },
        timeout=30,
    )

    assert result.returncode == 0, result.stderr
    assert "Test-042" in result.stdout, (
        f"bead id not rendered from kernel envelope; output: {result.stdout!r} "
        f"stderr: {result.stderr!r}"
    )
    assert "executing" in result.stdout, (
        f"phase not rendered from kernel envelope; output: {result.stdout!r}"
    )


def test_stale_kernel_envelope_is_ignored(project_root, tmp_path):
    """The 24h age gate still applies to kernel-authored envelopes."""
    import os

    home = tmp_path / "home"
    (home / ".claude").mkdir(parents=True)
    (home / ".claude" / "interline.json").write_text(json.dumps({
        "layers": {
            "dispatch": False, "coordination": False, "bead_query": False,
            "phase": False, "session_id": False, "dirty": False,
            "ahead": False, "context": False,
        }
    }))
    interband = tmp_path / "interband"
    bead_dir = interband / "interphase" / "bead"
    bead_dir.mkdir(parents=True)
    envelope_path = bead_dir / f"{SESSION_ID}.json"
    envelope_path.write_text(json.dumps(_kernel_envelope("Test-042", "executing")))
    stale = time.time() - 90000  # > 24h
    os.utime(envelope_path, (stale, stale))

    result = subprocess.run(
        ["bash", str(project_root / STATUSLINE)],
        input=json.dumps({"session_id": SESSION_ID,
                          "workspace": {"current_dir": str(tmp_path)}}),
        capture_output=True, text=True, cwd=str(tmp_path),
        env={"HOME": str(home),
             "PATH": "/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin",
             "INTERBAND_ROOT": str(interband)},
        timeout=30,
    )
    assert result.returncode == 0, result.stderr
    assert "Test-042" not in result.stdout

def test_legacy_tmp_sideband_is_not_read(project_root, tmp_path):
    """Sylveste-zlc: the legacy /tmp/clavain-bead path is retired — a file
    there must never influence the statusline, even with no kernel envelope."""
    home = tmp_path / "home"
    (home / ".claude").mkdir(parents=True)
    (home / ".claude" / "interline.json").write_text(json.dumps({
        "layers": {
            "dispatch": False, "coordination": False, "bead_query": False,
            "phase": False, "session_id": False, "dirty": False,
            "ahead": False, "context": False,
        }
    }))
    interband = tmp_path / "interband"
    (interband / "interphase" / "bead").mkdir(parents=True)  # empty: no envelope

    legacy = f"/tmp/clavain-bead-{SESSION_ID}.json"
    with open(legacy, "w") as f:
        json.dump({"id": "Test-999", "phase": "executing", "ts": int(time.time())}, f)
    try:
        result = subprocess.run(
            ["bash", str(project_root / STATUSLINE)],
            input=json.dumps({"session_id": SESSION_ID,
                              "workspace": {"current_dir": str(tmp_path)}}),
            capture_output=True, text=True, cwd=str(tmp_path),
            env={"HOME": str(home),
                 "PATH": "/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin",
                 "INTERBAND_ROOT": str(interband)},
            timeout=30,
        )
    finally:
        subprocess.run(["rm", "-f", legacy], check=True)
    assert result.returncode == 0, result.stderr
    assert "Test-999" not in result.stdout, (
        f"legacy /tmp sideband was read after retirement: {result.stdout!r}"
    )
