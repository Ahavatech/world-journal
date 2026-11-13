<?php
// Audit or set the email addresses the site itself uses (journal contact and support, site contact, the administrator's own address).
// Run ON THE HOST from the web root, the script on php's standard input:
//   cd WEBROOT && php -- audit < email-addresses.php
//   cd WEBROOT && php -- apply PRINCIPAL SUPPORT SITE ADMIN_USERNAME ADMIN_EMAIL < email-addresses.php
// Output lines are `kind|name|value`; no credential is ever printed (the database password is read, never shown).
if (PHP_SAPI !== 'cli') {
    exit(2);
}
$mode = $argv[1] ?? '';
$cfg = parse_ini_file('config.inc.php', true, INI_SCANNER_RAW);
$q = function ($v) { return trim((string) $v, "\" "); };
$d = $cfg['database'];
$m = new mysqli($q($d['host']), $q($d['username']), $q($d['password']), $q($d['name']));
$m->set_charset('utf8mb4');
$e = $cfg['email'] ?? [];

if ($mode === 'audit') {
    foreach (['default', 'smtp_username', 'default_envelope_sender', 'force_default_envelope_sender', 'force_dmarc_compliant_from'] as $k) {
        echo "config|$k|" . $q($e[$k] ?? '') . "\n";
    }
    $r = $m->query("SELECT j.path, s.setting_name, s.setting_value FROM journal_settings s JOIN journals j ON j.journal_id = s.journal_id WHERE s.setting_name IN ('contactEmail', 'supportEmail', 'envelopeSender') ORDER BY j.path, s.setting_name");
    while ($row = $r->fetch_row()) {
        echo "journal|{$row[0]}.{$row[1]}|{$row[2]}\n";
    }
    $r = $m->query("SELECT setting_name, locale, setting_value FROM site_settings WHERE setting_name IN ('contactEmail', 'supportEmail') ORDER BY setting_name, locale");
    while ($row = $r->fetch_row()) {
        echo "site|{$row[0]}.{$row[1]}|{$row[2]}\n";
    }
    $r = $m->query('SELECT username, email FROM users ORDER BY user_id LIMIT 200');
    while ($row = $r->fetch_row()) {
        echo "user|{$row[0]}|{$row[1]}\n";
    }
    // where the other aliases belong: the privacy statement (privacy@) and the Crossref depositor email (doi@)
    $r = $m->query("SELECT j.path, s.setting_value FROM journal_settings s JOIN journals j ON j.journal_id = s.journal_id WHERE s.setting_name = 'privacyStatement'");
    while ($row = $r->fetch_row()) {
        preg_match_all('/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/', (string) $row[1], $found);
        echo "text|{$row[0]}.privacyStatement|" . implode(',', array_unique($found[0])) . "\n";
    }
    $r = $m->query("SELECT plugin_name, setting_value FROM plugin_settings WHERE plugin_name LIKE 'crossref%' AND setting_name = 'depositorEmail'");
    while ($row = $r->fetch_row()) {
        echo "plugin|{$row[0]}.depositorEmail|{$row[1]}\n";
    }
    $r = $m->query("SELECT COUNT(DISTINCT email) FROM authors WHERE email <> ''");
    echo 'authors|distinct addresses|' . (int) $r->fetch_row()[0] . "\n";
    exit(0);
}

if ($mode === 'apply') {
    [$principal, $support, $site, $adminUser, $adminEmail] = array_slice($argv, 2, 5) + [null, null, null, null, null];
    foreach ([$principal, $support, $site, $adminEmail] as $addr) {
        if (!filter_var($addr, FILTER_VALIDATE_EMAIL)) {
            echo "FAILED: not an email address: " . var_export($addr, true) . "\n";
            exit(1);
        }
    }
    if (!$adminUser) {
        echo "FAILED: no administrator username\n";
        exit(1);
    }
    // journal contact and support (non-localized settings: locale '')
    $r = $m->query('SELECT journal_id, path FROM journals');
    $journals = $r->fetch_all(MYSQLI_NUM);
    if (!$journals) {
        echo "FAILED: no journal exists yet (run scripts/seed-shared.sh first)\n";
        exit(1);
    }
    foreach ($journals as [$jid, $path]) {
        foreach (['contactEmail' => $principal, 'supportEmail' => $support] as $name => $val) {
            $s = $m->prepare("SELECT setting_value FROM journal_settings WHERE journal_id = ? AND locale = '' AND setting_name = ?");
            $s->bind_param('is', $jid, $name);
            $s->execute();
            $s->bind_result($old);
            $had = $s->fetch();
            $s->close();
            $w = $m->prepare("INSERT INTO journal_settings (journal_id, locale, setting_name, setting_value) VALUES (?, '', ?, ?) ON DUPLICATE KEY UPDATE setting_value = VALUES(setting_value)");
            $w->bind_param('iss', $jid, $name, $val);
            $w->execute();
            $w->close();
            echo "set|journal $path $name|" . ($had ? $old : '(unset)') . " -> $val\n";
        }
    }
    // OJS shows the technical support contact on the contact page only when it has a name: leave a marked blank where there is none
    foreach ($journals as [$jid, $path]) {
        $s = $m->prepare("SELECT COUNT(*) FROM journal_settings WHERE journal_id = ? AND locale = '' AND setting_name = 'supportName'");
        $s->bind_param('i', $jid);
        $s->execute();
        $s->bind_result($has);
        $s->fetch();
        $s->close();
        if (!$has) {
            $blank = '[PLACEHOLDER: technical support contact name]';
            $w = $m->prepare("INSERT INTO journal_settings (journal_id, locale, setting_name, setting_value) VALUES (?, '', 'supportName', ?)");
            $w->bind_param('is', $jid, $blank);
            $w->execute();
            $w->close();
            echo "set|journal $path supportName|$blank\n";
        }
    }
    // site contact (localized: change every existing row, or add an English one)
    $s = $m->prepare("SELECT COUNT(*) FROM site_settings WHERE setting_name = 'contactEmail'");
    $s->execute();
    $s->bind_result($n);
    $s->fetch();
    $s->close();
    if ($n > 0) {
        $w = $m->prepare("UPDATE site_settings SET setting_value = ? WHERE setting_name = 'contactEmail'");
        $w->bind_param('s', $site);
    } else {
        $w = $m->prepare("INSERT INTO site_settings (setting_name, locale, setting_value) VALUES ('contactEmail', 'en', ?)");
        $w->bind_param('s', $site);
    }
    $w->execute();
    $w->close();
    echo "set|site contactEmail|$site\n";
    // the administrator's own address (OJS needs every user's address to be unique)
    $s = $m->prepare('SELECT username FROM users WHERE email = ? AND username <> ?');
    $s->bind_param('ss', $adminEmail, $adminUser);
    $s->execute();
    $s->bind_result($other);
    if ($s->fetch()) {
        echo "FAILED: the address $adminEmail already belongs to the user $other\n";
        exit(1);
    }
    $s->close();
    $w = $m->prepare('UPDATE users SET email = ? WHERE username = ?');
    $w->bind_param('ss', $adminEmail, $adminUser);
    $w->execute();
    echo "set|user $adminUser|" . ($w->affected_rows > 0 ? $adminEmail : "$adminEmail (unchanged or no such user)") . "\n";
    exit(0);
}
fwrite(STDERR, "usage: php -- audit | apply PRINCIPAL SUPPORT SITE ADMIN_USERNAME ADMIN_EMAIL\n");
exit(2);
