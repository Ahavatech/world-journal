<?php
// Enable the sidebar block plugin(s) our seeding needs for the journal `worj`, straight in the database.
// A fresh OJS journal does not enable "Make a Submission", and the REST API refuses a sidebar naming a plugin that is not enabled.
// Run ON THE HOST from the web root, the script arriving on php's standard input:  cd WEBROOT && php < enable-block-plugin.php
// Reads the database settings from config.inc.php in the current directory; prints only `enabled`, `already` or `no journal`
// lines, never a credential. Idempotent. The sandbox does the same in scripts/sandbox-ojs.sh.
$plugins = ['makesubmissionblockplugin'];
$journalPath = 'worj';
$c = parse_ini_file('config.inc.php', true, INI_SCANNER_RAW);
$d = $c['database'];
$q = function ($v) { return trim($v, "\""); };
$m = new mysqli($q($d['host']), $q($d['username']), $q($d['password']), $q($d['name']));
$s = $m->prepare('SELECT journal_id FROM journals WHERE path = ?');
$s->bind_param('s', $journalPath);
$s->execute();
$s->bind_result($journalId);
if (!$s->fetch()) {
    echo "no journal\n";
    exit(0);
}
$s->close();
foreach ($plugins as $plugin) {
    foreach ([null, $journalId] as $ctx) {
        $chk = $ctx === null
            ? $m->prepare("SELECT COUNT(*) FROM plugin_settings WHERE plugin_name = ? AND context_id IS NULL AND setting_name = 'enabled'")
            : $m->prepare("SELECT COUNT(*) FROM plugin_settings WHERE plugin_name = ? AND context_id = ? AND setting_name = 'enabled'");
        if ($ctx === null) {
            $chk->bind_param('s', $plugin);
        } else {
            $chk->bind_param('si', $plugin, $ctx);
        }
        $chk->execute();
        $chk->bind_result($n);
        $chk->fetch();
        $chk->close();
        if ($n > 0) {
            echo "already $plugin " . ($ctx === null ? 'site' : "journal $ctx") . "\n";
            continue;
        }
        $ins = $m->prepare("INSERT INTO plugin_settings (plugin_name, context_id, setting_name, setting_value, setting_type) VALUES (?, ?, 'enabled', '1', 'bool')");
        $ins->bind_param('si', $plugin, $ctx);
        $ins->execute();
        $ins->close();
        echo "enabled $plugin " . ($ctx === null ? 'site' : "journal $ctx") . "\n";
    }
}
