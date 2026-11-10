WORJ Day-0 kit: temporary test files for the shared-hosting plan. Delete the whole folder when done.

HOW TO USE
1. Upload this folder, named exactly  worj-day0  , to the WEB ROOT of the STAGING subdomain
   (so that  https://STAGING_HOST/worj-day0/probe.php  exists). Never upload it to the production site.
2. The staging site must be password-protected. Tell the developer when it is uploaded.
3. The developer runs scripts/probe-day0-kit.sh against it and reports what worked.
4. DELETE the folder afterwards, and delete the staging login if it was created only for this.

WHAT IT CONTAINS
probe.php           prints PHP facts as JSON (version, extensions, limits, open_basedir, whether PHP can write
                    one level above the web root). No passwords, no environment variables, no phpinfo().
                    It creates and immediately deletes one empty file above the web root as a write test.
t01 .. t13          one small folder per .htaccess feature, each with its own .htaccess, so that an
                    unsupported directive breaks only its own folder (HTTP 500) and not the other tests.
All files are harmless text. Nothing here connects to a database or sends mail.
