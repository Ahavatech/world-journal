<?php
// Create editorial accounts with a random temporary password that must be changed at the first login. Run ON THE HOST (or the sandbox)
// from the OJS root, the script on php's standard input and the options as one base64 JSON argument (scripts/create-accounts-shared.sh builds it):
//   {"journal":"worj","apply":false,"accounts":[{"username":"..","email":"..","given":"..","family":"..","group":"Journal editor"}],"drop_admin_roles":["Author","Reviewer"],"admin":"administrator"}
// Without "apply": true nothing is written. Output lines: `WOULD:`/`DONE:` text, and `PASSWORD|username|value` ONLY with apply (the value is
// printed once and stored nowhere: the wrapper shows it on the operator's screen only). A user that exists is never touched.
$_SERVER['SCRIPT_NAME'] = '/index.php';
$_SERVER['PATH_INFO'] = '/' . (json_decode(base64_decode($argv[1] ?? ''), true)['journal'] ?? '');
$_SERVER['REQUEST_URI'] = '/index.php' . $_SERVER['PATH_INFO'];
$_SERVER['HTTP_HOST'] = $_SERVER['HTTP_HOST'] ?? 'localhost';
require 'tools/bootstrap.php';
ini_set('display_errors', 'stderr');
error_reporting(E_ALL & ~E_WARNING & ~E_NOTICE & ~E_DEPRECATED);

use APP\core\Application;
use APP\facades\Repo;
use Illuminate\Support\Facades\DB;
use PKP\core\Core;
use PKP\security\Validation;

$o = json_decode(base64_decode($argv[1] ?? ''), true);
if (!is_array($o) || empty($o['journal']) || empty($o['accounts'])) {
    fwrite(STDERR, "usage: php -- BASE64JSON < create-accounts.php\n");
    exit(2);
}
$apply = !empty($o['apply']);
$journal = DB::table('journals')->where('path', $o['journal'])->first();
if (!$journal) {
    echo "FAILED: no journal '{$o['journal']}' exists\n";
    exit(1);
}
$jid = (int) $journal->journal_id;
$groupId = function (string $name) use ($jid): ?int {
    $id = DB::table('user_groups as g')->join('user_group_settings as s', 's.user_group_id', '=', 'g.user_group_id')
        ->where('g.context_id', $jid)->where('s.setting_name', 'name')->where('s.locale', 'en')->where('s.setting_value', $name)->value('g.user_group_id');
    return $id ? (int) $id : null;
};
function tempPassword(): string
{
    $a = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789';
    $p = '';
    for ($i = 0; $i < 16; $i++) {
        $p .= $a[random_int(0, strlen($a) - 1)];
    }
    return $p . '-' . random_int(10, 99);
}
$bad = 0;
// refuse everything first: one bad entry stops the run before anything is written
foreach ($o['accounts'] as $a) {
    foreach (['username', 'email', 'given', 'family', 'group'] as $k) {
        if (empty($a[$k])) {
            echo "FAILED: an account entry has no '$k'\n";
            exit(1);
        }
    }
    if (!preg_match('/^[a-z0-9_.-]{3,32}$/', $a['username']) || !filter_var($a['email'], FILTER_VALIDATE_EMAIL)) {
        echo "FAILED: {$a['username']}: bad username or email\n";
        $bad++;
    } elseif (DB::table('users')->where('username', $a['username'])->orWhere('email', $a['email'])->exists()) {
        echo "FAILED: {$a['username']}: that username or email already has an account (nothing was changed for it)\n";
        $bad++;
    } elseif ($groupId($a['group']) === null) {
        echo "FAILED: {$a['username']}: no role named '{$a['group']}' in this journal\n";
        $bad++;
    }
}
if ($bad) {
    echo "REFUSED: fix the above first; nothing was written\n";
    exit(1);
}
$sections = DB::table('sections')->where('journal_id', $jid)->pluck('section_id')->all();
foreach ($o['accounts'] as $a) {
    $gid = $groupId($a['group']);
    $isSection = DB::table('user_groups')->where('user_group_id', $gid)->value('role_id') == 17;
    if (!$apply) {
        echo "WOULD: create {$a['username']} <{$a['email']}> as {$a['group']}, temporary password, must change it at first login" . ($isSection ? ', assigned to ' . count($sections) . ' section(s)' : '') . "\n";
        continue;
    }
    $pw = tempPassword();
    $u = Repo::user()->newDataObject();
    $u->setUsername($a['username']);
    foreach (['en'] as $loc) {
        $u->setGivenName($a['given'], $loc);
        $u->setFamilyName($a['family'], $loc);
    }
    $u->setEmail($a['email']);
    $u->setDateRegistered(Core::getCurrentDate());
    $u->setInlineHelp(1);
    $u->setPassword(Validation::encryptCredentials($a['username'], $pw));
    $u->setMustChangePassword(1);
    $u->setDisabled(false);
    $uid = Repo::user()->add($u);
    if (!$uid) {
        echo "FAILED: {$a['username']}: could not be created\n";
        exit(1);
    }
    Repo::userGroup()->assignUserToGroup((int) $uid, $gid);
    if ($isSection) {
        foreach ($sections as $sid) {
            DB::table('subeditor_submission_group')->insert(['context_id' => $jid, 'assoc_id' => $sid, 'assoc_type' => \PKP\core\PKPApplication::ASSOC_TYPE_SECTION, 'user_id' => $uid, 'user_group_id' => $gid]);
        }
    }
    echo "DONE: created {$a['username']} as {$a['group']}\n";
    echo "PASSWORD|{$a['username']}|$pw\n";
}
// the merge of the test accounts left extra roles on the administrator
foreach ($o['drop_admin_roles'] ?? [] as $name) {
    $admin = DB::table('users')->where('username', $o['admin'] ?? 'administrator')->value('user_id');
    $gid = $groupId($name);
    if (!$admin || !$gid) {
        continue;
    }
    $has = DB::table('user_user_groups')->where(['user_id' => $admin, 'user_group_id' => $gid])->exists();
    if (!$has) {
        continue;
    }
    if ($apply) {
        DB::table('user_user_groups')->where(['user_id' => $admin, 'user_group_id' => $gid])->delete();
        echo "DONE: removed the $name role from " . ($o['admin'] ?? 'administrator') . "\n";
    } else {
        echo "WOULD: remove the $name role from " . ($o['admin'] ?? 'administrator') . "\n";
    }
}
