WORJ Day-0 kit: temporary test files for the shared-hosting plan. Delete the whole folder when done.

HOW TO USE
1. Upload this folder, named exactly  worj-day0  , to the WEB ROOT of the site
   (so that  https://worldopenresearchjournal.com/worj-day0/probe.php  exists).
   Only BEFORE the site is public, while it is closed to search engines. Never on a live journal.
2. If the site is password-protected, tell the developer; the login goes on the secure credential card,
   never in chat. Tell the developer when the folder is uploaded.
3. The developer runs scripts/probe-day0-kit.sh against it and reports what worked.
4. DELETE the folder afterwards (the probe says so at the end).

WHAT IT CONTAINS
probe.php           prints PHP facts as JSON (version, extensions, limits, open_basedir, whether PHP can write
                    one level above the web root). No passwords, no environment variables, no phpinfo().
                    It creates and immediately deletes one empty file above the web root as a write test.
t01 .. t13          one small folder per .htaccess feature, each with its own .htaccess, so that an
                    unsupported directive breaks only its own folder (HTTP 500) and not the other tests.
All files are harmless text. Nothing here connects to a database or sends mail.
