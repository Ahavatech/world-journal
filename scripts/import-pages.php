<?php

/**
 * Create the placeholder custom pages from ojs/content/pages.json (the pages
 * whose mechanism is "custom-page") as OJS custom navigation-menu pages.
 *
 * SAFE BY DEFAULT. It is create-only:
 *   - a page that already exists is SKIPPED, never overwritten;
 *   - a page whose stored text no longer contains the placeholder banner has been
 *     edited by a human and is ALWAYS left alone, even with --force-sandbox;
 *   - --force-sandbox allows refreshing a page that still has the banner, and the
 *     script refuses to run with it unless the OJS installation's base_url host
 *     is localhost, 127.0.0.1 or ::1.
 *
 * Usage (from the repository root):
 *   php scripts/import-pages.php --journal=worj [--check] [--force-sandbox] [--ojs=ojs-core] [--client-content] [--only=id,id]
 *   --check  print what would happen and change nothing
 *
 * Journal settings texts (about, privacy, ...) are handled by
 * scripts/sandbox-content.js; this script covers custom pages, and with --only also a settings page by id.
 */

$opts = getopt('', ['journal:', 'check', 'force-sandbox', 'client-content', 'ojs::', 'only::']);
$root = dirname(__DIR__);
$ojsDir = $opts['ojs'] ?? ($root . '/ojs-core');
$journalPath = $opts['journal'] ?? null;
$dryRun = array_key_exists('check', $opts);
$force = array_key_exists('force-sandbox', $opts);
$client = array_key_exists('client-content', $opts);
// --only=id,id: touch just these pages (by id in ojs/content/pages.json); without it every page is considered
$only = isset($opts['only']) && $opts['only'] !== '' ? explode(',', (string) $opts['only']) : null;

if (!$journalPath) {
    fwrite(STDERR, "usage: php scripts/import-pages.php --journal=PATH [--check] [--force-sandbox] [--ojs=DIR]\n");
    exit(2);
}
if (!is_file($ojsDir . '/tools/bootstrap.php')) {
    fwrite(STDERR, "ERROR: no OJS found at $ojsDir (run make setup)\n");
    exit(2);
}

require $ojsDir . '/tools/bootstrap.php';

use APP\core\Application;
use PKP\config\Config;
use PKP\db\DAORegistry;
use Illuminate\Support\Facades\DB;
use PKP\core\PKPContainer;
use PKP\navigationMenu\NavigationMenuItem;

// --- guard: overwrite is for a local sandbox only
if ($force) {
    $host = strtolower((string) parse_url((string) Config::getVar('general', 'base_url'), PHP_URL_HOST));
    if (!in_array($host, ['localhost', '127.0.0.1', '::1', '[::1]'], true)) {
        fwrite(STDERR, "REFUSED: --force-sandbox only runs when base_url is localhost (this installation: '$host').\n");
        exit(3);
    }
}

$manifest = json_decode(file_get_contents($root . '/ojs/content/pages.json'), true);
// a page is still a placeholder (safe to replace) while it carries the generic banner or the pending banner of the client's own text
$isPlaceholder = function (string $t): bool {
    return (bool) preg_match('/\[PLACEHOLDER: (replace with client-approved text|client text)/', $t);
};
// with --client-content the client's text (ojs/client-content, received 2026-11-11) replaces the placeholder where the client supplied some
$overlay = [];
if ($client) {
    $cmap = json_decode(file_get_contents($root . '/ojs/client-content/map.json'), true);
    foreach ($cmap['pages'] as $cp) {
        $overlay[$cp['id']] = $cp['file'];
    }
}

$context = Application::getContextDAO()->getByPath($journalPath);
if (!$context) {
    fwrite(STDERR, "ERROR: journal '$journalPath' not found\n");
    exit(2);
}
$contextId = (int) $context->getId();
$locale = $context->getPrimaryLocale();
/** @var \PKP\navigationMenu\NavigationMenuItemDAO $dao */
$dao = DAORegistry::getDAO('NavigationMenuItemDAO');

$counts = ['created' => 0, 'updated' => 0, 'skipped' => 0, 'edited' => 0];
foreach ($manifest['pages'] as $page) {
    // with --only, a page kept in a journal setting (about, privacy, author guidelines, editorial team) is handled too:
    // written when empty, refreshed while it still carries its pending banner, never when a person has edited or approved it
    if ($only !== null && $page['mechanism'] === 'setting' && in_array($page['id'], $only, true)) {
        $fromClient = isset($overlay[$page['id']]);
        $content = file_get_contents($root . ($fromClient ? '/ojs/client-content/' . $overlay[$page['id']] : '/ojs/content/' . $page['file']));
        $key = ['journal_id' => $contextId, 'locale' => $locale, 'setting_name' => $page['setting']];
        $stored = (string) DB::table('journal_settings')->where($key)->value('setting_value');
        if ($stored === $content) {
            echo "skip    {$page['setting']}  (already this text)\n";
            $counts['skipped']++;
        } elseif ($stored !== '' && !$isPlaceholder($stored)) {
            echo "leave   {$page['setting']}  (edited or approved: the pending banner is gone)\n";
            $counts['edited']++;
        } else {
            echo ($dryRun ? 'would write' : 'write') . "   {$page['setting']}  (" . ($stored === '' ? 'it was empty' : 'still pending') . ")\n";
            if (!$dryRun) {
                DB::table('journal_settings')->updateOrInsert($key, ['setting_value' => $content]);
                PKPContainer::getInstance()['cache']->store()->flush();
            }
            $counts['updated']++;
        }
        continue;
    }
    if ($page['mechanism'] !== 'custom-page' || ($only !== null && !in_array($page['id'], $only, true))) {
        continue;
    }
    $path = $page['path'];
    $fromClient = isset($overlay[$page['id']]);
    $content = file_get_contents($root . ($fromClient ? '/ojs/client-content/' . $overlay[$page['id']] : '/ojs/content/' . $page['file']));
    if (!$isPlaceholder($content)) {
        fwrite(STDERR, "ERROR: {$page['file']} has no placeholder banner; refusing to import it\n");
        exit(2);
    }
    $existing = $dao->getByPath($contextId, $path);
    if (!$existing) {
        echo ($dryRun ? 'would create' : 'create') . "  /$path\n";
        if (!$dryRun) {
            $item = $dao->newDataObject();
            $item->setContextId($contextId);
            $item->setType(NavigationMenuItem::NMI_TYPE_CUSTOM);
            $item->setPath($path);
            $item->setTitle($page['title'], $locale);
            $item->setContent($content, $locale);
            $dao->insertObject($item);
        }
        $counts['created']++;
        continue;
    }
    $stored = (string) $existing->getContent($locale);
    if (!$isPlaceholder($stored)) {
        echo "leave   /$path  (edited by a human: the placeholder banner is gone)\n";
        $counts['edited']++;
        continue;
    }
    // the client's text may replace a page that is still a placeholder, without --force-sandbox (a person's edit is never touched)
    $upgrade = $fromClient && $stored !== $content;
    if (!$force && !$upgrade) {
        echo "skip    /$path  (exists; create-only)\n";
        $counts['skipped']++;
        continue;
    }
    echo ($dryRun ? 'would update' : 'update') . "  /$path  (still a placeholder" . ($fromClient ? ', client text' : ', --force-sandbox') . ")\n";
    if (!$dryRun) {
        $existing->setTitle($page['title'], $locale);
        $existing->setContent($content, $locale);
        $dao->updateObject($existing);
    }
    $counts['updated']++;
}
echo sprintf("%s: %d created, %d updated, %d skipped, %d left alone (edited)\n", $dryRun ? 'dry run' : 'done', $counts['created'], $counts['updated'], $counts['skipped'], $counts['edited']);
