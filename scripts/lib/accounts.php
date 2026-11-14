<?php
// Read the accounts, submissions and issues of the site, and check a planned removal. Read-only.
// Run ON THE HOST from the web root, the script on php's standard input:
//   cd WEBROOT && php -- list < accounts.php
//   cd WEBROOT && php -- check-remove KEEP_USERNAME USER1 [USER2 ...] < accounts.php
//   cd WEBROOT && php -- submissions ID [ID ...] < accounts.php
// Output lines are `kind|...`; no credential is ever printed.
if (PHP_SAPI !== 'cli') {
    exit(2);
}
$mode = $argv[1] ?? '';
$cfg = parse_ini_file('config.inc.php', true, INI_SCANNER_RAW);
$q = function ($v) { return trim((string) $v, "\" "); };
$d = $cfg['database'];
$m = new mysqli($q($d['host']), $q($d['username']), $q($d['password']), $q($d['name']));
$m->set_charset('utf8mb4');
$roleLabel = [1 => 'Site administrator', 16 => 'Manager', 17 => 'Editor/assistant', 4097 => 'Production', 4096 => 'Reviewer', 65536 => 'Author', 1048576 => 'Reader', 2097152 => 'Subscription'];

function roles(mysqli $m, array $roleLabel, int $uid): array
{
    $out = [];
    $s = $m->prepare("SELECT g.role_id, COALESCE(MAX(gs.setting_value), '') FROM user_user_groups uug JOIN user_groups g ON g.user_group_id = uug.user_group_id LEFT JOIN user_group_settings gs ON gs.user_group_id = g.user_group_id AND gs.setting_name = 'name' AND gs.locale = 'en' WHERE uug.user_id = ? GROUP BY g.user_group_id, g.role_id");
    $s->bind_param('i', $uid);
    $s->execute();
    $s->bind_result($role, $name);
    while ($s->fetch()) {
        $out[] = ['role_id' => (int) $role, 'name' => $name !== '' ? $name : ($roleLabel[(int) $role] ?? "role $role")];
    }
    $s->close();
    return $out;
}

if ($mode === 'list') {
    $r = $m->query('SELECT user_id, username, email, date_registered, date_last_login, disabled FROM users ORDER BY user_id');
    while ($row = $r->fetch_row()) {
        $names = array_map(function ($x) { return $x['name'] . ($x['role_id'] === 1 ? ' [SITE ADMIN]' : ''); }, roles($m, $roleLabel, (int) $row[0]));
        echo 'user|' . implode('|', [$row[0], $row[1], $row[2], substr((string) $row[3], 0, 10), $row[4] ? substr((string) $row[4], 0, 10) : 'never', $row[5] ? 'disabled' : 'active', implode(', ', $names) ?: '(no role)']) . "\n";
    }
    $r = $m->query("SELECT s.submission_id, s.status, COALESCE(MAX(ps.setting_value), '(no title)') FROM submissions s LEFT JOIN publication_settings ps ON ps.publication_id = s.current_publication_id AND ps.setting_name = 'title' GROUP BY s.submission_id, s.status ORDER BY s.submission_id");
    while ($row = $r->fetch_row()) {
        echo 'submission|' . $row[0] . '|status ' . $row[1] . '|' . mb_substr((string) $row[2], 0, 70) . "\n";
    }
    $r = $m->query("SELECT i.issue_id, i.volume, i.number, i.year, i.published, COALESCE(MAX(s.setting_value), '') FROM issues i LEFT JOIN issue_settings s ON s.issue_id = i.issue_id AND s.setting_name = 'title' GROUP BY i.issue_id ORDER BY i.issue_id");
    while ($row = $r->fetch_row()) {
        echo 'issue|' . $row[0] . '|vol ' . $row[1] . ' no ' . $row[2] . ' ' . $row[3] . '|' . ($row[4] ? 'published' : 'not published') . '|' . mb_substr((string) $row[5], 0, 50) . "\n";
    }
    exit(0);
}

if ($mode === 'check-remove') {
    $keep = $argv[2] ?? '';
    $remove = array_slice($argv, 3);
    $bad = 0;
    $one = function (string $name) use ($m) {
        $s = $m->prepare('SELECT user_id FROM users WHERE username = ?');
        $s->bind_param('s', $name);
        $s->execute();
        $s->bind_result($id);
        $found = $s->fetch() ? (int) $id : null;
        $s->close();
        return $found;
    };
    if ($one($keep) === null) {
        echo "FAIL|the user to keep does not exist: $keep\n";
        exit(1);
    }
    if (!$remove) {
        echo "FAIL|no user to remove\n";
        exit(1);
    }
    foreach ($remove as $u) {
        $id = $one($u);
        if ($id === null) {
            echo "FAIL|$u does not exist\n";
            $bad++;
        } elseif ($u === $keep) {
            echo "FAIL|$u is the account to keep\n";
            $bad++;
        } elseif (array_filter(roles($m, $roleLabel, $id), function ($x) { return $x['role_id'] === 1; })) {
            echo "FAIL|$u is a SITE ADMINISTRATOR: this tool never removes one (take the role off first, on purpose)\n";
            $bad++;
        } else {
            echo "OK|$u (" . implode(', ', array_column(roles($m, $roleLabel, $id), 'name')) . ")\n";
        }
    }
    exit($bad ? 1 : 0);
}

if ($mode === 'submissions') {
    $bad = 0;
    foreach (array_slice($argv, 2) as $sid) {
        $sid = (int) $sid;
        $s = $m->prepare("SELECT COALESCE(MAX(ps.setting_value), '(no title)') FROM submissions s LEFT JOIN publication_settings ps ON ps.publication_id = s.current_publication_id AND ps.setting_name = 'title' WHERE s.submission_id = ? GROUP BY s.submission_id");
        $s->bind_param('i', $sid);
        $s->execute();
        $s->bind_result($title);
        if ($s->fetch()) {
            echo "OK|$sid|" . mb_substr((string) $title, 0, 70) . "\n";
        } else {
            echo "FAIL|submission $sid does not exist\n";
            $bad++;
        }
        $s->close();
    }
    exit($bad ? 1 : 0);
}
fwrite(STDERR, "usage: php -- list | check-remove KEEP USER... | submissions ID...\n");
exit(2);
