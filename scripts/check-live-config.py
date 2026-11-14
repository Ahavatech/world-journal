#!/usr/bin/env python3
"""Check a LIVE OJS config.inc.php for the settings the installer leaves unsafe or unset.

  python3 -I scripts/check-live-config.py CONFIG [--host journal.example.com] [--web-root DIR] [--owner root:www-data] [--launch]

Prints one line per check, `ok   key` or `FAIL key (reason)`, and NEVER a value. Exit 1 if anything fails.
It is the production gate behind Phase 5.1b and Phase 8.3. It fails on:
  - `installed` not On, `app_key` empty
  - `salt` the shipped public default `YouMustSetASecretKeyHere!!`, empty, a leftover @@TOKEN@@, or under 32 chars
  - `api_key_secret` empty, a leftover token, or under 32 chars
  - `allowed_hosts` empty or `[""]` (the installer's value, which rejects every request), or missing --host
  - `time_zone` blank
  - `[oai] repository_id` empty, the shipped `ojs.pkp.sfu.ca`, a leftover token, or (with --host) not the production host
  - `task_runner` On or `process_jobs_at_task_scheduler` Off (scheduled tasks run from cron, see infra/cron.d/worj.template)
  - `base_url` not https, or still the shipped PKP URL or a token
  - `force_ssl` / `force_login_ssl` not On, `restful_urls` not On
  - `show_stacktrace` or `display_errors` On
  - `files_dir` not an absolute path, or inside the web root (private submission files must not be web-reachable)
  - the shipped database credentials (`ojs`/`ojs`), an empty or token database password
  - any @@TOKEN@@ left in an active line
  - with --launch (the Phase 8.3 gate): a placeholder host (example, localhost, 127.0.0.1, .invalid, sandbox, sample, placeholder) in `repository_id`, `--host`, `base_url` or `allowed_hosts`
  - the file readable by others (mode & 007), and, with --owner, a different owner or group
"""
import argparse
import json
import os
import re
import stat
import sys

SECTION = re.compile(r"^\[(\w+)\]\s*$")
ACTIVE = re.compile(r"^([A-Za-z_][\w.\[\]]*)\s*=\s*(.*)$")
DEFAULT_SALT = "YouMustSetASecretKeyHere!!"
TOKEN = re.compile(r"@@[A-Z][A-Z0-9_]*@@")


def bare(v):
    return v.strip().strip("\"'")


def load(path):
    cfg, section = {}, ""
    for line in open(path, encoding="utf-8").read().splitlines():
        m = SECTION.match(line)
        if m:
            section = m.group(1)
            continue
        a = ACTIVE.match(line)
        if a:
            cfg[f"{section}.{a.group(1)}"] = a.group(2).strip()
    return cfg


def main():
    ap = argparse.ArgumentParser(add_help=False)
    ap.add_argument("config")
    ap.add_argument("--host")
    ap.add_argument("--web-root")
    ap.add_argument("--owner")
    ap.add_argument("--launch", action="store_true")
    try:
        a = ap.parse_args()
    except SystemExit:
        return 2
    cfg = load(a.config)
    results = []

    def check(key, ok, why=""):
        results.append((ok, key, why))

    def on(key):
        return bare(cfg.get(key, "")).lower() == "on"

    check("general.installed", on("general.installed"), "must be On (the installer sets it)")
    check("general.app_key", bool(bare(cfg.get("general.app_key", ""))), "empty: the installer generates it")
    salt = bare(cfg.get("security.salt", ""))
    check("security.salt", bool(salt) and salt != DEFAULT_SALT and not TOKEN.search(salt) and len(salt) >= 32,
          "empty, the shipped public default, a leftover token, or under 32 characters")
    api = bare(cfg.get("security.api_key_secret", ""))
    check("security.api_key_secret", bool(api) and not TOKEN.search(api) and len(api) >= 32,
          "empty, a leftover token, or under 32 characters")
    raw_hosts = cfg.get("general.allowed_hosts", "")
    try:
        hosts = [h for h in json.loads(bare(raw_hosts) if raw_hosts.strip()[:1] in "\"'" else raw_hosts) if h]
    except Exception:
        hosts = []
    check("general.allowed_hosts", bool(hosts) and not any(TOKEN.search(h) for h in hosts),
          'empty or [""] (the installer value rejects every request) or a leftover token')
    if a.host:
        check("general.allowed_hosts includes the host", a.host in hosts, "the production host is not listed")
    check("general.time_zone", bool(bare(cfg.get("general.time_zone", ""))), "blank (the installer blanks it)")
    rid = bare(cfg.get("oai.repository_id", ""))
    check("oai.repository_id", bool(rid) and "pkp.sfu.ca" not in rid and not TOKEN.search(rid) and (not a.host or rid == a.host),
          "must be the production host (OAI identifiers must never change after harvesting); the shipped value names PKP's server")
    base = bare(cfg.get("general.base_url", ""))
    check("general.base_url", base.startswith("https://") and "pkp.sfu.ca" not in base and not TOKEN.search(base),
          "must be the real https URL")
    if a.launch:
        # the Phase 8.3 production gate: a placeholder host must not go live (provisioning rehearsals use example hosts on purpose)
        placeholder = re.compile(r"example|localhost|127\.0\.0\.1|\.invalid|\.test$|sandbox|sample|placeholder", re.I)
        check("launch: oai.repository_id is not a placeholder host", bool(rid) and not placeholder.search(rid),
              "contains example, localhost, .invalid, sandbox or placeholder")
        check("launch: --host is not a placeholder host", bool(a.host) and not placeholder.search(a.host),
              "missing, or contains example, localhost, .invalid, sandbox or placeholder")
        check("launch: general.base_url is not a placeholder host", not placeholder.search(base),
              "contains example, localhost, .invalid, sandbox or placeholder")
        check("launch: general.allowed_hosts has no placeholder host", not any(placeholder.search(h) for h in hosts),
              "lists example, localhost, .invalid, sandbox or placeholder")
    check("security.force_ssl", on("security.force_ssl"), "must be On")
    check("security.force_login_ssl", on("security.force_login_ssl"), "must be On")
    check("general.restful_urls", on("general.restful_urls"), "must be On (clean URLs)")
    check("schedule.task_runner", not on("schedule.task_runner"), "must be Off: scheduled tasks run from cron (a quiet site misses tasks otherwise)")
    check("queues.process_jobs_at_task_scheduler", on("queues.process_jobs_at_task_scheduler"), "must be On: queued emails are processed by the cron scheduler")
    if bare(cfg.get("email.default", "")) == "smtp":
        check("email.require_validation", on("email.require_validation"),
              "must be On: new accounts confirm their address (decision of 2026-11-14); only switch it off if mail is broken")
        check("email.force_default_envelope_sender", on("email.force_default_envelope_sender"),
              "must be On: every message leaves from the mailbox, never from an outside address")
        sender = bare(cfg.get("email.default_envelope_sender", ""))
        check("email.default_envelope_sender", bool(sender) and sender == bare(cfg.get("email.smtp_username", "")),
              "must be the mailbox the SMTP login belongs to")
        check("email.force_dmarc_compliant_from", on("email.force_dmarc_compliant_from"),
              "must be On: an editor's own address goes to Reply-To and the From header is the mailbox")
    check("debug.show_stacktrace", not on("debug.show_stacktrace"), "must be Off in production")
    check("debug.display_errors", not on("debug.display_errors"), "must be Off in production")
    files_dir = bare(cfg.get("files.files_dir", ""))
    web_root = os.path.realpath(a.web_root or os.path.dirname(os.path.abspath(a.config)))
    outside = os.path.isabs(files_dir) and not (os.path.realpath(files_dir) + os.sep).startswith(web_root + os.sep)
    check("files.files_dir", outside, "must be an absolute path outside the web root")
    dbpw = bare(cfg.get("database.password", ""))
    check("database.password", bool(dbpw) and dbpw != "ojs" and not TOKEN.search(dbpw), "empty, the shipped default or a leftover token")
    check("database.username", bare(cfg.get("database.username", "")) not in ("", "ojs") and not TOKEN.search(cfg.get("database.username", "")),
          "empty, the shipped default or a leftover token")
    left = sorted(k for k, v in cfg.items() if TOKEN.search(v))
    check("no leftover tokens", not left, "tokens remain in: " + ", ".join(left))
    st = os.stat(a.config)
    check("file mode", stat.S_IMODE(st.st_mode) & 0o007 == 0, f"readable by others (mode {oct(stat.S_IMODE(st.st_mode))[2:]})")
    if a.owner:
        import grp
        import pwd
        owner = f"{pwd.getpwuid(st.st_uid).pw_name}:{grp.getgrgid(st.st_gid).gr_name}"
        check("file owner", owner == a.owner, f"is {owner}, expected {a.owner}")
    bad = 0
    for ok, key, why in results:
        if ok:
            print(f"ok    {key}")
        else:
            bad += 1
            print(f"FAIL  {key} ({why})")
    print(f"live config check: {len(results)} checks, {bad} failed")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
