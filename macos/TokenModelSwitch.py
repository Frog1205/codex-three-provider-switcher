#!/usr/bin/env python3
"""Token · Model Switch — Apple Silicon GUI companion for Codex Desktop.

This file intentionally has no third-party dependencies. It only edits the
top-level routing fields in ~/.codex/config.toml and keeps a timestamped backup
before every switch.
"""

from __future__ import annotations

import json
import os
import platform
import re
import shutil
import select
import subprocess
import sys
import tempfile
import tkinter as tk
import threading
import queue
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime
from pathlib import Path
from tkinter import messagebox

APP_VERSION = "V_1.3_260829.02"
APP_TITLE = "Token · Model Switch"
SUPPORTED_ARCH = {"arm64", "aarch64"}

ROOT = Path(__file__).resolve().parent
PROVIDERS_PATH = ROOT.parent / "src" / "providers.json"
if not PROVIDERS_PATH.exists():
    PROVIDERS_PATH = ROOT / "providers.json"
CONFIG_PATH = Path.home() / ".codex" / "config.toml"

COLORS = {
    "canvas": "#f5f7fb",
    "surface": "#ffffff",
    "ink": "#18212f",
    "muted": "#6b7280",
    "border": "#e2e8f0",
    "green": "#16a34a",
    "blue": "#2563eb",
    "official": {"accent": "#0f9f86", "soft": "#ecfdf8"},
    "honknet": {"accent": "#2563eb", "soft": "#eff6ff"},
    "deepseek": {"accent": "#7c3aed", "soft": "#faf5ff"},
}


class UnsupportedPlatformError(RuntimeError):
    pass


def ensure_apple_silicon() -> None:
    if sys.platform != "darwin":
        raise UnsupportedPlatformError("This GUI is for macOS Apple Silicon only.")
    machine = platform.machine().lower()
    hardware_arm = machine in SUPPORTED_ARCH
    if not hardware_arm:
        # A Python process launched through Rosetta may report x86_64 even on an M-series Mac.
        try:
            hardware_arm = subprocess.check_output(
                ["sysctl", "-in", "hw.optional.arm64"], text=True, stderr=subprocess.DEVNULL
            ).strip() == "1"
        except (OSError, subprocess.SubprocessError):
            hardware_arm = False
    if not hardware_arm:
        raise UnsupportedPlatformError("Intel Mac is not supported. Apple Silicon (M-series) is required.")


def load_providers(path: Path = PROVIDERS_PATH) -> dict:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def top_level_value(text: str, key: str) -> str | None:
    head = re.split(r"(?m)^\s*\[", text, maxsplit=1)[0]
    match = re.search(rf"(?m)^\s*{re.escape(key)}\s*=\s*['\"]([^'\"]+)['\"]\s*$", head)
    return match.group(1) if match else None


def current_state(config_path: Path = CONFIG_PATH, providers_path: Path = PROVIDERS_PATH) -> dict:
    if not config_path.exists():
        return {"provider": "unknown", "model": "unknown", "display": "Unknown"}
    text = config_path.read_text(encoding="utf-8")
    provider = top_level_value(text, "model_provider") or "openai"
    model = top_level_value(text, "model") or "unknown"
    providers = load_providers(providers_path)
    display_map = {
        "openai": providers["official"]["display_name"],
        "honknet": providers["honknet"]["display_name"],
        "deepseek": providers["deepseek"]["display_name"],
    }
    display = display_map.get(provider.lower(), provider)
    return {"provider": provider, "model": model, "display": display}


def key_present(name: str) -> bool:
    return bool(os.environ.get(name, "").strip())


def catalog_ready(definition: dict, providers_path: Path = PROVIDERS_PATH) -> bool:
    catalog_file = definition.get("catalog_file")
    if not catalog_file:
        return True
    catalog_path = providers_path.parent / catalog_file
    if not catalog_path.exists():
        return False
    try:
        data = json.loads(catalog_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return False
    return any(item.get("slug") == definition.get("model") for item in data.get("models", []))


def toml_string(value: str) -> str:
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


def provider_block(definition: dict) -> str:
    lines = [f"[model_providers.{definition['provider_id']}]\n"]
    for key in ("name", "base_url", "env_key", "wire_api"):
        value = definition.get(key)
        if value:
            lines.append(f"{key} = {toml_string(str(value))}\n")
    lines.append(f"requires_openai_auth = {str(bool(definition.get('requires_openai_auth'))).lower()}\n")
    for key in ("request_max_retries", "stream_max_retries", "stream_idle_timeout_ms"):
        if key in definition:
            lines.append(f"{key} = {definition[key]}\n")
    return "".join(lines).rstrip()


def switched_config(provider: str, config_path: Path = CONFIG_PATH, providers_path: Path = PROVIDERS_PATH) -> str:
    if not config_path.exists():
        raise FileNotFoundError("Codex config.toml was not found. Start Codex Desktop once first.")
    providers = load_providers(providers_path)
    definition = providers[provider]
    if definition.get("requires_openai_auth") and not (config_path.parent / "auth.json").exists():
        raise RuntimeError("Official Codex login was not found. Sign in to Codex first.")
    env_key = definition.get("env_key")
    if env_key and not key_present(env_key):
        raise RuntimeError(f"{env_key} is missing. Configure it in the shell environment first.")
    if not catalog_ready(definition, providers_path):
        raise RuntimeError(f"The model catalog is missing or does not contain {definition['model']}.")

    text = config_path.read_text(encoding="utf-8")
    first_table = re.search(r"(?m)^\s*\[", text)
    if first_table:
        head, tail = text[: first_table.start()], text[first_table.start() :]
    else:
        head, tail = text, ""
    switch_keys = r"model|model_provider|model_catalog_json|model_reasoning_effort|disable_response_storage"
    head = re.sub(rf"(?m)^\s*(?:{switch_keys})\s*=.*(?:\n|$)", "", head)
    settings = [
        f"model_provider = {toml_string(definition['provider_id'])}",
        f"model = {toml_string(definition['model'])}",
        f"model_reasoning_effort = {toml_string(definition['reasoning_effort'])}",
    ]
    if definition.get("disable_response_storage"):
        settings.append("disable_response_storage = true")
    catalog_file = definition.get("catalog_file")
    if catalog_file:
        catalog_path = (providers_path.parent / catalog_file).resolve()
        settings.append(f"model_catalog_json = {toml_string(str(catalog_path))}")
    if definition["provider_id"] != "openai":
        block_pattern = rf"(?ms)^\s*\[model_providers\.{re.escape(definition['provider_id'])}\]\s*\n.*?(?=^\s*\[|\Z)"
        tail = re.sub(block_pattern, "", tail).rstrip()
        tail += "\n\n" + provider_block(definition) + "\n"
    parts = ["\n".join(settings).strip(), head.strip(), tail.strip()]
    return "\n\n".join(part for part in parts if part) + "\n"


def write_config_atomically(content: str, config_path: Path = CONFIG_PATH) -> Path:
    backup_dir = config_path.parent / "provider-switch-backups"
    backup_dir.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now().strftime("%Y%m%d-%H%M%S-%f")[:-3]
    backup_path = backup_dir / f"config-{stamp}.toml"
    shutil.copy2(config_path, backup_path)
    with tempfile.NamedTemporaryFile("w", encoding="utf-8", dir=config_path.parent, delete=False) as handle:
        handle.write(content)
        temp_path = Path(handle.name)
    os.replace(temp_path, config_path)
    return backup_path


def switch_provider(provider: str, config_path: Path = CONFIG_PATH, providers_path: Path = PROVIDERS_PATH) -> Path:
    content = switched_config(provider, config_path, providers_path)
    return write_config_atomically(content, config_path)


def _json_request(url: str, api_key: str, timeout: int = 10) -> dict:
    request = urllib.request.Request(url, headers={"Authorization": f"Bearer {api_key}", "Accept": "application/json"})
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        raise RuntimeError(f"HTTP {exc.code}") from exc
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as exc:
        raise RuntimeError(str(exc)) from exc


def query_honknet_usage(timeout: int = 10) -> dict:
    api_key = os.environ.get("HONKNET_API_KEY", "").strip() or os.environ.get("HONKAI_API_KEY", "").strip()
    if not api_key:
        raise RuntimeError("HONKNET_API_KEY is not configured")
    now = datetime.now()
    start = now.strftime("%Y-%m-01")
    end = now.strftime("%Y-%m-%d")
    query = urllib.parse.urlencode({"start_date": start, "end_date": end, "timezone": "Asia/Shanghai"})
    data = _json_request(f"https://ai.honknet.io/api/v1/usage?{query}", api_key, timeout)
    quota = (data.get("quota") or {})
    usage = (data.get("usage") or {})
    today = usage.get("today") or {}
    remaining = float(quota.get("remaining_usd") or 0)
    currency = str(quota.get("unit") or "USD")
    return {
        "value": f"{remaining:.2f} {currency}",
        "detail": f"Today  {int(today.get('requests') or 0):,} requests · {int(today.get('total_tokens') or 0):,} tokens",
        "status": "Available" if bool(data.get("valid", True)) and remaining > 0 else "Low or unavailable",
        "checked": datetime.now().strftime("%H:%M:%S"),
    }


def query_deepseek_balance(timeout: int = 10) -> dict:
    api_key = os.environ.get("DEEPSEEK_API_KEY", "").strip()
    if not api_key:
        raise RuntimeError("DEEPSEEK_API_KEY is not configured")
    data = _json_request("https://api.deepseek.com/user/balance", api_key, timeout)
    entries = data.get("balance_infos") or []
    if not entries:
        raise RuntimeError("No balance data returned")
    entry = next((item for item in entries if item.get("currency") == "CNY"), None)
    entry = entry or next((item for item in entries if item.get("currency") == "USD"), None) or entries[0]
    total = float(entry.get("total_balance") or 0)
    currency = str(entry.get("currency") or "USD")
    return {
        "value": f"{total:.2f} {currency}",
        "detail": f"Topped up  {float(entry.get('topped_up_balance') or 0):.2f} {currency} · Granted  {float(entry.get('granted_balance') or 0):.2f} {currency}",
        "status": "Available" if bool(data.get("is_available", True)) and total > 0 else "Low or unavailable",
        "checked": datetime.now().strftime("%H:%M:%S"),
    }


def query_official_quota(timeout: int = 12) -> dict:
    """Read the official Codex bucket through the locally installed app-server."""
    command = shutil.which("codex")
    if not command:
        node = shutil.which("node")
        npm_root = os.environ.get("CODEX_NPM_ROOT", "")
        candidates = [
            Path(npm_root) / "@openai" / "codex" / "bin" / "codex.js" if npm_root else None,
            Path.home() / ".npm-global" / "lib" / "node_modules" / "@openai" / "codex" / "bin" / "codex.js",
            Path("/opt/homebrew/lib/node_modules/@openai/codex/bin/codex.js"),
            Path("/usr/local/lib/node_modules/@openai/codex/bin/codex.js"),
        ]
        codex_js = next((path for path in candidates if path and path.exists()), None)
        if not node or not codex_js:
            raise RuntimeError("Codex CLI not found; install @openai/codex first")
        command = node
        args = [command, str(codex_js), "app-server", "--stdio", "-c", "model_provider=openai"]
    else:
        args = [command, "app-server", "--stdio", "-c", "model_provider=openai"]
    process = subprocess.Popen(args, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, bufsize=1)
    try:
        messages = [
            {"method": "initialize", "id": 0, "params": {"clientInfo": {"name": "token_model_switch", "title": APP_TITLE, "version": APP_VERSION}}},
            {"method": "initialized"},
            {"method": "account/rateLimits/read", "id": 6},
        ]
        for message in messages:
            process.stdin.write(json.dumps(message) + "\n")
            process.stdin.flush()
        responses = {}
        deadline = datetime.now().timestamp() + timeout
        while datetime.now().timestamp() < deadline:
            remaining = max(0.1, deadline - datetime.now().timestamp())
            ready, _, _ = select.select([process.stdout], [], [], remaining)
            if not ready:
                break
            line = process.stdout.readline()
            if not line:
                break
            try:
                payload = json.loads(line)
            except json.JSONDecodeError:
                continue
            if "id" in payload:
                responses[payload["id"]] = payload
            if 6 in responses:
                break
        response = responses.get(6) or {}
        result = response.get("result") or {}
        snapshot = (result.get("rateLimitsByLimitId") or {}).get("codex")
        if not snapshot and (result.get("rateLimits") or {}).get("limitId") == "codex":
            snapshot = result.get("rateLimits")
        if not snapshot:
            raise RuntimeError("Codex rate-limit bucket was not returned")
        windows = []
        for name in ("primary", "secondary"):
            window = snapshot.get(name) or {}
            if window.get("usedPercent") is not None:
                reset = window.get("resetsAt")
                reset_text = datetime.fromtimestamp(reset).strftime("%Y-%m-%d %H:%M") if reset else "unknown"
                windows.append((100 - float(window["usedPercent"]), reset_text))
        if not windows:
            raise RuntimeError("Codex rate-limit window was not returned")
        remaining, reset_text = min(windows, key=lambda item: item[0])
        return {"value": f"{max(0, remaining):.0f}% remaining", "detail": f"Resets  {reset_text}", "status": "Available" if remaining > 0 else "Exhausted", "checked": datetime.now().strftime("%H:%M:%S")}
    finally:
        try:
            process.kill()
        except OSError:
            pass
        try:
            process.wait(timeout=2)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()


class TokenModelSwitchApp:
    def __init__(self, root: tk.Tk):
        self.root = root
        self.providers = load_providers()
        self.cards: dict[str, dict[str, tk.Widget]] = {}
        self.quota_cards: dict[str, dict[str, tk.Widget]] = {}
        self.quota_queue: queue.Queue = queue.Queue()
        self.quota_thread: threading.Thread | None = None
        self._configure_window()
        self._build_ui()
        self.refresh_all()

    def _configure_window(self) -> None:
        self.root.title(f"{APP_TITLE}  {APP_VERSION}")
        self.root.geometry("1040x900")
        self.root.minsize(900, 820)
        self.root.configure(bg=COLORS["canvas"])
        self.root.option_add("*Font", "SF Pro Text 11")

    def _label(self, parent, text="", size=11, weight="normal", color=None, bg=None, **kwargs):
        return tk.Label(parent, text=text, font=("SF Pro Text", size, weight),
                        fg=color or COLORS["ink"], bg=bg or COLORS["surface"], **kwargs)

    def _button(self, parent, text, command, accent=None, bg=None):
        button = tk.Button(parent, text=text, command=command, relief="flat", bd=0,
                           padx=14, pady=8, cursor="hand2", font=("SF Pro Text", 10),
                           fg=accent or COLORS["ink"], bg=bg or COLORS["surface"],
                           activeforeground=accent or COLORS["ink"], activebackground=bg or COLORS["surface"])
        return button

    def _card(self, parent, color=None):
        frame = tk.Frame(parent, bg=color or COLORS["surface"], highlightthickness=1,
                         highlightbackground=COLORS["border"], padx=18, pady=16)
        return frame

    def _build_ui(self) -> None:
        outer = tk.Frame(self.root, bg=COLORS["canvas"], padx=34, pady=24)
        outer.pack(fill="both", expand=True)
        header = tk.Frame(outer, bg=COLORS["canvas"])
        header.pack(fill="x")
        left = tk.Frame(header, bg=COLORS["canvas"])
        left.pack(side="left")
        self._label(left, "Token · Model Switch", 23, "bold", bg=COLORS["canvas"]).pack(anchor="w")
        self._label(left, "Codex Desktop · Apple Silicon", 11, color=COLORS["muted"], bg=COLORS["canvas"]).pack(anchor="w", pady=(5, 0))
        right = tk.Frame(header, bg=COLORS["canvas"])
        right.pack(side="right", anchor="n")
        self.version_label = self._label(right, APP_VERSION, 10, color=COLORS["muted"], bg=COLORS["canvas"])
        self.version_label.pack(side="left", padx=(0, 16), pady=8)
        self.refresh_button = self._button(right, "Refresh", self.refresh_all, COLORS["blue"], COLORS["canvas"])
        self.refresh_button.pack(side="left")

        self._label(outer, "ACTIVE ROUTE", 10, "bold", COLORS["muted"], COLORS["canvas"]).pack(anchor="w", pady=(26, 8))
        active = self._card(outer)
        active.pack(fill="x")
        tk.Frame(active, bg=COLORS["blue"], width=4).pack(side="left", fill="y", padx=(0, 16))
        current = tk.Frame(active, bg=COLORS["surface"])
        current.pack(side="left", fill="both", expand=True)
        self.current_provider = self._label(current, "", 15, "bold")
        self.current_provider.pack(anchor="w")
        self.current_hint = self._label(current, "", 10, color=COLORS["muted"])
        self.current_hint.pack(anchor="w", pady=(6, 0))
        self.current_model = self._label(active, "", 14, "bold", COLORS["green"])
        self.current_model.pack(side="left", padx=18)
        self.health = self._label(active, "", 10, color=COLORS["muted"], justify="right")
        self.health.pack(side="right", padx=(10, 0))

        self._label(outer, "AVAILABLE ROUTES", 10, "bold", COLORS["muted"], COLORS["canvas"]).pack(anchor="w", pady=(24, 8))
        routes = tk.Frame(outer, bg=COLORS["canvas"])
        routes.pack(fill="x")
        for provider in ("official", "honknet", "deepseek"):
            self._build_provider_card(routes, provider)

        self._label(outer, "QUOTA & USAGE", 10, "bold", COLORS["muted"], COLORS["canvas"]).pack(anchor="w", pady=(24, 8))
        quotas = tk.Frame(outer, bg=COLORS["canvas"])
        quotas.pack(fill="x")
        for provider in ("official", "honknet", "deepseek"):
            self._build_quota_card(quotas, provider)

        self._label(outer, "CONFIGURATION STATUS", 10, "bold", COLORS["muted"], COLORS["canvas"]).pack(anchor="w", pady=(24, 8))
        status = self._card(outer)
        status.pack(fill="x")
        self.status_text = self._label(status, "", 10, color=COLORS["muted"], justify="left")
        self.status_text.pack(side="left", fill="x", expand=True)
        self._label(status, "macOS  ·  M-series only", 10, color=COLORS["muted"]).pack(side="right")

        self._label(outer, "Keys are read from the macOS shell environment. Every switch creates a backup in ~/.codex/provider-switch-backups.", 9, color=COLORS["muted"], bg=COLORS["canvas"]).pack(anchor="w", pady=(18, 0))

    def _build_provider_card(self, parent, provider: str) -> None:
        palette = COLORS[provider]
        card = self._card(parent, palette["soft"])
        card.pack(side="left", fill="both", expand=True, padx=(0, 10) if provider != "deepseek" else (0, 0))
        top = tk.Frame(card, bg=palette["soft"])
        top.pack(fill="x")
        name = self._label(top, self.providers[provider]["display_name"], 13, "bold", bg=palette["soft"])
        name.pack(side="left")
        state = self._label(top, "", 10, color=palette["accent"], bg=palette["soft"])
        state.pack(side="right")
        model = self._label(card, "", 10, color=COLORS["muted"], bg=palette["soft"])
        model.pack(anchor="w", pady=(18, 3))
        key = self._label(card, "", 10, color=COLORS["muted"], bg=palette["soft"])
        key.pack(anchor="w")
        action = self._button(card, "Use this route", lambda p=provider: self._switch(p), palette["accent"], palette["soft"])
        action.pack(fill="x", pady=(18, 0))
        self.cards[provider] = {"card": card, "name": name, "state": state, "model": model, "key": key, "action": action}

    def _build_quota_card(self, parent, provider: str) -> None:
        palette = COLORS[provider]
        card = self._card(parent, palette["soft"])
        card.pack(side="left", fill="both", expand=True, padx=(0, 10) if provider != "deepseek" else (0, 0))
        top = tk.Frame(card, bg=palette["soft"])
        top.pack(fill="x")
        title = self._label(top, self.providers[provider]["display_name"], 11, "bold", bg=palette["soft"])
        title.pack(side="left")
        status = self._label(top, "Waiting", 9, color=COLORS["muted"], bg=palette["soft"])
        status.pack(side="right")
        value = self._label(card, "—", 16, "bold", color=palette["accent"], bg=palette["soft"])
        value.pack(anchor="w", pady=(14, 4))
        detail = self._label(card, "Click Refresh to query", 9, color=COLORS["muted"], bg=palette["soft"])
        detail.pack(anchor="w")
        self.quota_cards[provider] = {"card": card, "value": value, "detail": detail, "status": status}

    def _switch(self, provider: str) -> None:
        definition = self.providers[provider]
        if not messagebox.askokcancel("Confirm route switch", f"Switch to {definition['display_name']}?\n\nSave your current task first. Codex Desktop must be restarted after the change."):
            return
        try:
            backup = switch_provider(provider)
        except Exception as exc:  # noqa: BLE001 - convert to a concise user message
            messagebox.showerror("Switch failed", str(exc))
            return
        self.refresh_all()
        messagebox.showinfo("Switch complete", f"Route changed to {definition['display_name']}.\n\nBackup created at:\n{backup}\n\nRestart Codex Desktop and create a new task.")

    def refresh(self) -> None:
        state = current_state()
        self.current_provider.configure(text=f"Current route  ·  {state['display']}")
        self.current_model.configure(text=f"Model  ·  {state['model']}")
        self.current_hint.configure(text="Save the current task before switching. Restart Codex Desktop after the change.")
        provider = state["provider"].lower()
        active_id = {"openai": "official", "honknet": "honknet", "deepseek": "deepseek"}.get(provider)
        key_states = {
            "official": (Path.home() / ".codex" / "auth.json").exists(),
            "honknet": key_present("HONKNET_API_KEY") or key_present("HONKAI_API_KEY"),
            "deepseek": key_present("DEEPSEEK_API_KEY"),
        }
        for name, card in self.cards.items():
            definition = self.providers[name]
            ready = key_states[name] and catalog_ready(definition)
            active = name == active_id
            palette = COLORS[name]
            card["state"].configure(text="● Active route" if active else ("● Ready" if ready else "● Setup required"), fg=COLORS["blue"] if active else (COLORS["green"] if ready else "#b45309"))
            card["model"].configure(text=f"Model  {definition['model']}")
            card["key"].configure(text="Credentials ready" if ready else "Credentials not configured", fg=COLORS["muted"] if ready else "#b45309")
            card["action"].configure(text="Active route" if active else "Use this route", state="disabled" if active else "normal", fg=COLORS["blue"] if active else palette["accent"], bg="#e8f1ff" if active else palette["soft"])
        configured = sum(1 for value in key_states.values() if value)
        catalog = "ready" if catalog_ready(self.providers["deepseek"]) else "missing"
        self.health.configure(text=f"Credentials {configured}/3  ·  Catalog {catalog}", fg=COLORS["green"] if configured == 3 and catalog == "ready" else COLORS["muted"])
        self.status_text.configure(text=f"Config: {CONFIG_PATH}\nProvider changes are backed up automatically before writing.")

    def refresh_all(self) -> None:
        self.refresh()
        self.start_quota_refresh()

    def start_quota_refresh(self) -> None:
        if self.quota_thread and self.quota_thread.is_alive():
            return
        self.quota_queue = queue.Queue()
        for provider, card in self.quota_cards.items():
            palette = COLORS[provider]
            card["value"].configure(text="Checking…", fg=palette["accent"])
            card["detail"].configure(text="Querying provider…")
            card["status"].configure(text="Checking", fg=COLORS["muted"])
        self.refresh_button.configure(state="disabled")
        self.quota_thread = threading.Thread(target=self._query_quota_worker, name="quota-refresh", daemon=True)
        self.quota_thread.start()
        self.root.after(100, self._drain_quota_results)

    def _query_quota_worker(self) -> None:
        functions = {
            "official": query_official_quota,
            "honknet": query_honknet_usage,
            "deepseek": query_deepseek_balance,
        }

        def run(provider: str, function) -> None:
            try:
                self.quota_queue.put((provider, "ok", function()))
            except Exception as exc:  # noqa: BLE001 - surface provider-specific failures in the card
                self.quota_queue.put((provider, "error", str(exc)))

        workers = [threading.Thread(target=run, args=(provider, function), daemon=True) for provider, function in functions.items()]
        for worker in workers:
            worker.start()
        for worker in workers:
            worker.join()
        self.quota_queue.put(("__done__", "done", None))

    def _drain_quota_results(self) -> None:
        finished = False
        while True:
            try:
                provider, outcome, payload = self.quota_queue.get_nowait()
            except queue.Empty:
                break
            if provider == "__done__":
                finished = True
                break
            card = self.quota_cards.get(provider)
            if not card:
                continue
            palette = COLORS[provider]
            if outcome == "ok":
                card["value"].configure(text=payload["value"], fg=palette["accent"])
                card["detail"].configure(text=f"{payload['detail']}  ·  {payload['checked']}")
                status = payload.get("status", "Available")
                status_color = COLORS["green"] if status == "Available" else "#b45309"
                card["status"].configure(text=status, fg=status_color)
            else:
                card["value"].configure(text="Unavailable", fg="#b45309")
                card["detail"].configure(text=payload)
                card["status"].configure(text="Unavailable", fg="#b45309")
        if finished:
            self.refresh_button.configure(state="normal")
            return
        self.root.after(100, self._drain_quota_results)


def run_self_test() -> int:
    """Small cross-platform smoke test used by CI and Windows development hosts."""
    providers = load_providers(PROVIDERS_PATH)
    assert set(providers) >= {"official", "honknet", "deepseek"}
    sample = 'model_provider = "honknet"\nmodel = "gpt-5.6-sol"\n\n[other]\nkeep = true\n'
    assert top_level_value(sample, "model_provider") == "honknet"
    assert top_level_value(sample, "keep") is None
    assert toml_string(r"C:\tmp\catalog.json") == r'"C:\\tmp\\catalog.json"'
    print("PASS: macOS Token · Model Switch config helpers and provider catalog.")
    return 0


def main() -> int:
    if "--self-test" in sys.argv:
        return run_self_test()
    try:
        ensure_apple_silicon()
    except UnsupportedPlatformError as exc:
        root = tk.Tk()
        root.withdraw()
        messagebox.showerror("Apple Silicon required", str(exc))
        root.destroy()
        return 2
    root = tk.Tk()
    TokenModelSwitchApp(root)
    root.mainloop()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
