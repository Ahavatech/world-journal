<?php
// Set the publication date of published articles. Run from the OJS root, script on stdin, options as base64 JSON:
//   {"journal":"worj","apply":false,"dates":{"8":"2025-02-13","9":"2022-08-20"}}
// Only a PUBLISHED article is changed, and only its publication date. Prints WOULD:/DONE: lines. Nothing else is touched.
$_SERVER['SCRIPT_NAME'] = '/index.php';
$_SERVER['PATH_INFO'] = '/' . (json_decode(base64_decode($argv[1] ?? ''), true)['journal'] ?? '');
$_SERVER['REQUEST_URI'] = '/index.php' . $_SERVER['PATH_INFO'];
$_SERVER['HTTP_HOST'] = $_SERVER['HTTP_HOST'] ?? 'localhost';
require 'tools/bootstrap.php';
ini_set('display_errors', 'stderr');
error_reporting(E_ALL & ~E_WARNING & ~E_NOTICE & ~E_DEPRECATED);
use Illuminate\Support\Facades\DB;
use PKP\core\PKPContainer;

$o = json_decode(base64_decode($argv[1] ?? ''), true);
$apply = !empty($o['apply']);
$bad = 0;
$todo = [];
foreach (($o['dates'] ?? []) as $sid => $date) {
    $sid = (int) $sid;
    $row = DB::table('submissions as s')->join('publications as p', 'p.publication_id', '=', 's.current_publication_id')
        ->where('s.submission_id', $sid)->first(['p.publication_id', 'p.status', 'p.date_published']);
    if (!preg_match('/^\d{4}-\d{2}-\d{2}$/', (string) $date) || !checkdate((int) substr($date, 5, 2), (int) substr($date, 8, 2), (int) substr($date, 0, 4))) {
        echo "FAIL  submission $sid: '$date' is not a real date (use YYYY-MM-DD)\n";
        $bad++;
    } elseif (!$row) {
        echo "FAIL  submission $sid does not exist\n";
        $bad++;
    } elseif ((int) $row->status !== 3) {
        echo "FAIL  submission $sid is not published (status {$row->status}): its date is not changed here\n";
        $bad++;
    } else {
        $todo[] = [$sid, (int) $row->publication_id, substr((string) $row->date_published, 0, 10), $date];
    }
}
if ($bad) {
    echo "REFUSED: fix the above first; nothing was written\n";
    exit(1);
}
foreach ($todo as [$sid, $pid, $old, $new]) {
    if ($old === $new) {
        echo "skip   submission $sid already has $new\n";
    } elseif ($apply) {
        DB::table('publications')->where('publication_id', $pid)->update(['date_published' => $new . ' 00:00:00']);
        echo "DONE:  submission $sid: $old -> $new\n";
    } else {
        echo "WOULD: submission $sid: $old -> $new\n";
    }
}
if ($apply) {
    try {
        PKPContainer::getInstance()['cache']->store()->flush();
    } catch (\Throwable $e) {
        echo "NOTE:  the dates are saved; clear the caches in Administration > Clear Data Caches and Clear Template Cache\n";
    }
}
