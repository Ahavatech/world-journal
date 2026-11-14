<?php
// Switch the WORJ Research Awards plugin on for the journal (its tables are made by lib/pkp/tools/installPluginVersion.php first).
// Run from the OJS root, script on stdin, options as base64 JSON: {"journal":"worj","apply":false}. Prints WOULD:/DONE: lines.
require 'tools/bootstrap.php';
use Illuminate\Support\Facades\DB;
$o = json_decode(base64_decode($argv[1] ?? ''), true);
$j = DB::table('journals')->where('path', $o['journal'] ?? '')->value('journal_id');
if (!$j) {
    echo "FAILED: no such journal\n";
    exit(1);
}
$tables = DB::select("SHOW TABLES LIKE 'worj_award_nominations'");
if (!$tables) {
    echo "FAILED: the plugin's tables do not exist yet (installPluginVersion has not run)\n";
    exit(1);
}
$on = DB::table('plugin_settings')->where(['plugin_name' => 'worjawardsplugin', 'context_id' => $j, 'setting_name' => 'enabled'])->value('setting_value');
if ($on === '1' || $on === 1) {
    echo "skip  the Awards plugin is already on\n";
    exit(0);
}
if (empty($o['apply'])) {
    echo "WOULD: enable the Awards plugin for the journal\n";
    exit(0);
}
DB::table('plugin_settings')->updateOrInsert(['plugin_name' => 'worjawardsplugin', 'context_id' => $j, 'setting_name' => 'enabled'], ['setting_value' => '1', 'setting_type' => 'bool']);
echo "DONE: enabled the Awards plugin for the journal\n";
