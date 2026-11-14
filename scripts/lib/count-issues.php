<?php
// Print how many issues the OJS database holds (a number and nothing else). Run ON THE HOST from the web root with the script
// on php's standard input:  cd WEBROOT && php < count-issues.php   (scripts/seed-shared.sh uses it so the fake sample issue
// is never imported twice). Reads the database settings from config.inc.php; prints no credential.
$c = parse_ini_file('config.inc.php', true, INI_SCANNER_RAW);
$d = $c['database'];
$q = function ($v) { return trim($v, "\""); };
$m = new mysqli($q($d['host']), $q($d['username']), $q($d['password']), $q($d['name']));
$r = $m->query('SELECT COUNT(*) FROM issues');
echo (int) $r->fetch_row()[0], "\n";
