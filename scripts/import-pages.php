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
 *   php scripts/import-pages.php --journal=worj [--check] [--force-sandbox] [--ojs=ojs-core]
 *   --check  print what would happen and change nothing
 *
 * Journal settings texts (about, privacy, ...) are handled by
 * scripts/sandbox-content.js; this script covers custom pages only.
 */

$opts = getopt('', ['journal:', 'check', 'force-sandbox', 'ojs::']);
$root = dirname(__DIR__);
$ojsDir = $opts['ojs'] ?? ($root . '/ojs-core');
$journalPath = $opts['journal'] ?? null;
$dryRun = array_key_exists('check', $opts);
$force = array_key_exists('force-sandbox', $opts);

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
$banner = '[PLACEHOLDER: replace with client-approved text]';

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
    if ($page['mechanism'] !== 'custom-page') {
        continue;
    }
    $path = $page['path'];
    $content = file_get_contents($root . '/ojs/content/' . $page['file']);
    if (strpos($content, $banner) === false) {
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
    if (strpos($stored, $banner) === false) {
        echo "leave   /$path  (edited by a human: the placeholder banner is gone)\n";
        $counts['edited']++;
        continue;
    }
    if (!$force) {
        echo "skip    /$path  (exists; create-only)\n";
        $counts['skipped']++;
        continue;
    }
    echo ($dryRun ? 'would update' : 'update') . "  /$path  (still a placeholder, --force-sandbox)\n";
    if (!$dryRun) {
        $existing->setTitle($page['title'], $locale);
        $existing->setContent($content, $locale);
        $dao->updateObject($existing);
    }
    $counts['updated']++;
}
echo sprintf("%s: %d created, %d updated, %d skipped, %d left alone (edited)\n", $dryRun ? 'dry run' : 'done', $counts['created'], $counts['updated'], $counts['skipped'], $counts['edited']);
