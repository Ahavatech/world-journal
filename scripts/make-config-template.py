#!/usr/bin/env python3
"""Generate ojs/config/config.inc.php.template and scripts/ojs-config-keys.txt from the
SHIPPED ojs-core/config.TEMPLATE.inc.php plus the deliberate overrides below.

  python3 -I scripts/make-config-template.py           write both files
  python3 -I scripts/make-config-template.py --check   fail if either is out of date
                                                       (skips with a message if ojs-core/ is absent)

Secrets and server-specific values are `@@TOKENS@@`, filled at provisioning from `.env`
(never committed). The salt and API key secret are GENERATED at provisioning. Re-run after
every OJS pin change; scripts/check-config-template.py fails until you do.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SHIPPED = ROOT / "ojs-core/config.TEMPLATE.inc.php"
OUT = ROOT / "ojs/config/config.inc.php.template"
KEYS = ROOT / "scripts/ojs-config-keys.txt"
PIN = ROOT / "scripts/ojs-version.env"

# (section, key): (value as it appears in the file, reason)
OVERRIDES = {
    ("general", "installed"): ("Off", "stays Off until the install has run; the installer sets On"),
    ("general", "base_url"): ('"@@BASE_URL@@"', "the public https URL of the journal site"),
    ("general", "restful_urls"): ("On", "clean URLs (/worj/awards); needs the nginx rewrite (Phase 5)"),
    ("general", "allowed_hosts"): ("'[\"@@HOSTNAME@@\"]'", "host names OJS answers to. The installer rewrites this to [\"\"] (rejects every request): set it again after the install"),
    ("general", "enable_beacon"): ("Off", "the beacon reports the site to PKP; off until the client decides (the sandbox install answered no)"),
    ("database", "username"): ("@@DB_USER@@", "from .env at provisioning"),
    ("database", "password"): ("@@DB_PASSWORD@@", "from .env at provisioning; never committed"),
    ("database", "name"): ("@@DB_NAME@@", "from .env at provisioning"),
    ("files", "files_dir"): ("@@FILES_DIR@@", "an absolute path OUTSIDE the web root, writable by the PHP user"),
    ("security", "force_ssl"): ("On", "the site is HTTPS only (Cloudflare Full (strict) in front)"),
    ("security", "force_login_ssl"): ("On", "login over HTTPS only"),
    ("security", "salt"): ('"@@SALT@@"', "GENERATED at provisioning (the shipped value is a public default and the installer leaves it unchanged)"),
    ("security", "api_key_secret"): ('"@@API_KEY_SECRET@@"', "GENERATED at provisioning"),
    ("email", "default"): ("smtp", "send through the provider (checklist 6.5); a provider-issued app password or API credential, never a personal mailbox password"),
    ("email", "smtp_server"): ("@@SMTP_SERVER@@", "from the mail provider"),
    ("email", "smtp_port"): ("@@SMTP_PORT@@", "from the mail provider"),
    ("email", "smtp_auth"): ("@@SMTP_AUTH@@", "tls or ssl, from the mail provider"),
    ("email", "smtp_username"): ("@@SMTP_USERNAME@@", "from the mail provider"),
    ("email", "smtp_password"): ("@@SMTP_PASSWORD@@", "from the mail provider; never committed"),
    ("oai", "repository_id"): ("@@OAI_REPOSITORY_ID@@", "an identifier built from the journal's own domain (the shipped value names PKP's server)"),
    ("schedule", "task_runner"): ("Off", "scheduled tasks run from cron every minute (/etc/cron.d/worj). The built-in web runner only runs when a request arrives AND a task's cron expression matches that exact minute, so daily and monthly tasks are skipped on a quiet site"),
    ("queues", "job_runner"): ("Off", "queued jobs (emails) are processed by the cron-driven scheduler below, not at the end of web requests"),
    ("queues", "process_jobs_at_task_scheduler"): ("On", "the scheduler (cron, every minute) processes queued jobs, so queued emails do not wait for web traffic"),
    ("captcha", "recaptcha_public_key"): ('""', "bot protection is a client decision (D21); reCAPTCHA loads a remote script"),
    ("captcha", "recaptcha_private_key"): ('""', "see D21"),
    ("captcha", "altcha_hmackey"): ('""', "see D21; set a generated key only if ALTCHA is chosen"),
}
SECTION = re.compile(r"^\[(\w+)\]")
ACTIVE = re.compile(r"^([A-Za-z_][\w.\[\]]*)\s*=\s*(.*)$")
COMMENTED = re.compile(r"^;\s*([a-z][a-z0-9_]*)\s*=\s*(.*)$")


def pin():
    for line in PIN.read_text().splitlines():
        if line.startswith("OJS_VERSION="):
            return line.split("=", 1)[1].strip().strip('"')
    return "unknown"


def build():
    if not SHIPPED.exists():
        return None, None
    section, used = "", set()
    out, keys = [], []
    for line in SHIPPED.read_text().splitlines():
        m = SECTION.match(line)
        if m:
            section = m.group(1)
        a, c = ACTIVE.match(line), COMMENTED.match(line)
        key = a.group(1) if a else (c.group(1) if c else None)
        if a:
            keys.append(f"{section}.{key}\tactive")
        elif c:
            keys.append(f"{section}.{key}\tcommented")
        if key and (section, key) in OVERRIDES and (a or c):
            value, why = OVERRIDES[(section, key)]
            out.append(f"; WORJ: {why}")
            out.append(f"{key} = {value}")
            used.add((section, key))
            continue
        out.append(line)
    missing = set(OVERRIDES) - used
    if missing:
        raise SystemExit(f"override keys not found in the shipped template: {sorted(missing)}")
    header = (f"; World Open Research Journal: config.inc.php template for OJS {pin()}\n"
              "; GENERATED by scripts/make-config-template.py from the shipped config.TEMPLATE.inc.php.\n"
              "; Do not edit by hand: change OVERRIDES in the script and regenerate. Lines marked `; WORJ:` are ours.\n"
              "; Values between double at-signs are filled at provisioning from the operator env file. No secret is stored here; the salt and the API key\n"
              "; secret are generated at provisioning. `installed` stays Off until the install has run.\n"
              "; Use `;` for comments (OJS reads this file with parse_ini_file).\n;\n")
    keyfile = (f"# Keys of the shipped OJS {pin()} config.TEMPLATE.inc.php (section.key, active or commented).\n"
               "# Generated by scripts/make-config-template.py. Do not edit by hand.\n"
               + "\n".join(sorted(set(keys))) + "\n")
    # the shipped first lines (`; <?php exit; // DO NOT DELETE?>`) must stay at the very top of the file
    guard = 0
    while guard < len(out) and "Doing so will expose this configuration file" not in out[guard]:
        guard += 1
    guard += 1
    return "\n".join(out[:guard]) + "\n" + header + "\n".join(out[guard:]) + "\n", keyfile


def main():
    text, keyfile = build()
    if text is None:
        print("ojs-core/ not present: config template not regenerated (run `make setup`)")
        return 0
    if "--check" in sys.argv[1:]:
        ok = OUT.exists() and OUT.read_text() == text and KEYS.exists() and KEYS.read_text() == keyfile
        print("config template and key list are current" if ok else
              "config template or key list is out of date: run python3 -I scripts/make-config-template.py")
        return 0 if ok else 1
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(text)
    KEYS.write_text(keyfile)
    print(f"wrote {OUT.relative_to(ROOT)} ({len(text.splitlines())} lines) and {KEYS.relative_to(ROOT)} ({keyfile.count(chr(10)) - 2} keys)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
