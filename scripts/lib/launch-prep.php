<?php
// Launch preparation for ONE journal: delete the fake sample content, hide what has no client text, confirm or hold the client's pages.
// Run ON THE HOST (or the sandbox) from the OJS root, the script on php's standard input and the options as one base64 JSON argument:
//   cd OJSROOT && php -- BASE64JSON < launch-prep.php        (scripts/launch-prep-shared.sh builds the argument)
// Without "apply": true nothing is written; every action prints a `WOULD:` line. With it, `DONE:` lines.
// Safe by construction: a page or setting is touched only while it still carries a placeholder (a person's edit is never overwritten);
// sample content is matched by its exact fake titles; nothing is printed that is a credential.
// a CLI run has no URL: give OJS the one it needs to find the journal (the deletion code asks the request for its context)
$_SERVER['SCRIPT_NAME'] = '/index.php';
$_SERVER['PATH_INFO'] = '/' . (json_decode(base64_decode($argv[1] ?? ''), true)['journal'] ?? '');
$_SERVER['REQUEST_URI'] = '/index.php' . $_SERVER['PATH_INFO'];
$_SERVER['HTTP_HOST'] = $_SERVER['HTTP_HOST'] ?? 'localhost';
require 'tools/bootstrap.php';
// warnings from OJS's own deletion code (a null announcement image) are noise; fatal errors stay visible
ini_set('display_errors', 'stderr');
error_reporting(E_ALL & ~E_WARNING & ~E_NOTICE & ~E_DEPRECATED);

use APP\facades\Repo;
use APP\core\Application;
use Illuminate\Support\Facades\DB;
use APP\core\PageRouter;
use APP\template\TemplateManager;
use PKP\core\PKPContainer;
use PKP\announcement\Announcement;

$o = json_decode(base64_decode($argv[1] ?? ''), true);
if (!is_array($o) || empty($o['journal'])) {
    fwrite(STDERR, "usage: php -- BASE64JSON < launch-prep.php\n");
    exit(2);
}
$apply = !empty($o['apply']);
// the router the deletion code needs to read the journal from the request
$request = Application::get()->getRequest();
$router = new PageRouter();
$router->setApplication(Application::get());
$request->setRouter($router);
$journal = DB::table('journals')->where('path', $o['journal'])->first();
if (!$journal) {
    echo "FAILED: no journal '{$o['journal']}' exists\n";
    exit(1);
}
$jid = (int) $journal->journal_id;
$refused = 0;
const PENDING = 'PLACEHOLDER: client text';

function say(string $kind, string $msg): void
{
    echo $kind . ' ' . $msg . "\n";
}
function act(bool $apply, string $msg, callable $fn): void
{
    if ($apply) {
        $fn();
        say('DONE: ', $msg);
    } else {
        say('WOULD:', $msg);
    }
}
function js(int $jid, string $locale, string $name): ?string
{
    $v = DB::table('journal_settings')->where(['journal_id' => $jid, 'locale' => $locale, 'setting_name' => $name])->value('setting_value');
    return $v === null ? null : (string) $v;
}
function setjs(int $jid, string $locale, string $name, string $value): void
{
    DB::table('journal_settings')->updateOrInsert(['journal_id' => $jid, 'locale' => $locale, 'setting_name' => $name], ['setting_value' => $value]);
}
function isPlaceholder(?string $t): bool
{
    return $t !== null && strpos($t, '[PLACEHOLDER') !== false;
}
function navIds(int $jid, string $where, string $val): array
{
    return DB::table('navigation_menu_items')->where('context_id', $jid)->where($where, $val)->pluck('navigation_menu_item_id')->all();
}
function navContent(array $ids): ?string
{
    if (!$ids) {
        return null;
    }
    $v = DB::table('navigation_menu_item_settings')->whereIn('navigation_menu_item_id', $ids)->where('setting_name', 'content')->where('locale', 'en')->value('setting_value');
    return $v === null ? '' : (string) $v;
}
function deleteNav(array $ids): void
{
    DB::table('navigation_menu_item_assignments')->whereIn('navigation_menu_item_id', $ids)->delete();
    DB::table('navigation_menu_item_settings')->whereIn('navigation_menu_item_id', $ids)->delete();
    DB::table('navigation_menu_items')->whereIn('navigation_menu_item_id', $ids)->delete();
}
function stripBanner(string $t): string
{
    return preg_replace('#<p class="worj-placeholder">\[PLACEHOLDER: client text[^<]*</p>\s*#', '', $t, 1);
}
function dropBlankParagraphs(string $t): string
{
    // a paragraph that holds nothing but a marked blank, with the heading right before it
    return preg_replace('#(<h[23]>[^<]*</h[23]>\s*)?<p>\s*<span class="worj-ph">.*?</span>\s*</p>\s*#s', '', $t);
}

// ---- 1. the fake sample content
if (!empty($o['delete_sample'])) {
    foreach (DB::table('announcement_settings')->where('setting_name', 'title')->where('setting_value', 'like', '[PLACEHOLDER] Sample announcement%')->pluck('announcement_id')->all() as $aid) {
        act($apply, "delete the placeholder announcement $aid", function () use ($aid) {
            $a = Announcement::find((int) $aid);
            if ($a) {
                $a->delete();
            }
        });
    }
    $subs = DB::table('submissions as s')
        ->join('publication_settings as ps', 'ps.publication_id', '=', 's.current_publication_id')
        ->where('s.context_id', $jid)->where('ps.setting_name', 'title')->where('ps.setting_value', 'like', 'Sample Article %')
        ->pluck('s.submission_id')->unique()->all();
    foreach ($subs as $sid) {
        act($apply, "delete the sample submission $sid", function () use ($sid) {
            $s = Repo::submission()->get((int) $sid);
            if ($s) {
                Repo::submission()->delete($s);
            }
        });
    }
    $issues = DB::table('issues as i')->join('issue_settings as s', 's.issue_id', '=', 'i.issue_id')
        ->where('i.journal_id', $jid)->where('s.setting_name', 'title')->where('s.setting_value', 'like', '%not a real publication%')
        ->pluck('i.issue_id')->unique()->all();
    foreach ($issues as $iid) {
        act($apply, "delete the sample issue $iid", function () use ($iid) {
            $i = Repo::issue()->get((int) $iid);
            if ($i) {
                Repo::issue()->delete($i);
            }
        });
    }
    if (!$subs && !$issues && !DB::table('announcement_settings')->where('setting_name', 'title')->where('setting_value', 'like', '[PLACEHOLDER] Sample announcement%')->exists()) {
        say('skip ', 'no sample content found');
    }
}

// ---- 2. pages with no client text: hidden (the item and its menu entry are deleted) while they are still placeholders
foreach ($o['hide_pages'] ?? [] as $path) {
    $ids = navIds($jid, 'path', $path);
    if (!$ids) {
        say('skip ', "/$path is not there");
        continue;
    }
    if (!isPlaceholder(navContent($ids))) {
        say('skip ', "/$path was written by a person: left alone");
        continue;
    }
    act($apply, "hide /$path (delete the page and its menu entry)", function () use ($ids) {
        deleteNav($ids);
    });
}
if (!empty($o['hide_masthead'])) {
    $ids = DB::table('navigation_menu_items')->where('context_id', $jid)->where('type', 'NMI_TYPE_MASTHEAD')->pluck('navigation_menu_item_id')->all();
    if ($ids) {
        act($apply, 'remove the Editorial Team from the menus', function () use ($ids) {
            deleteNav($ids);
        });
    }
    if (isPlaceholder(js($jid, 'en', 'editorialHistory'))) {
        act($apply, 'empty the placeholder editorial team text', function () use ($jid) {
            setjs($jid, 'en', 'editorialHistory', '');
        });
    }
}
if (!empty($o['hide_info'])) {
    foreach (['readerInformation', 'authorInformation', 'librarianInformation'] as $name) {
        if (isPlaceholder(js($jid, 'en', $name))) {
            act($apply, "empty the placeholder text $name", function () use ($jid, $name) {
                setjs($jid, 'en', $name, '');
            });
        }
    }
    $sb = json_decode((string) js($jid, '', 'sidebar'), true);
    if (is_array($sb) && in_array('informationblockplugin', $sb, true)) {
        act($apply, 'take the Information block out of the sidebar', function () use ($jid, $sb) {
            setjs($jid, '', 'sidebar', json_encode(array_values(array_diff($sb, ['informationblockplugin']))));
        });
    }
}

// ---- 3. theme options
foreach (['awards_card_off' => ['showAwardsCard', 0, 'hide the Awards card on the home page'], 'omit_issn' => ['omitIssnLine', 1, 'leave the ISSN line out of the footer while there is no ISSN'], 'omit_publisher' => ['omitPublisherLine', 1, 'leave the publisher line out of the footer while there is no publisher name']] as $key => [$opt, $val, $what]) {
    $current = DB::table('plugin_settings')->where(['plugin_name' => 'worjthemeplugin', 'context_id' => $jid, 'setting_name' => $opt])->value('setting_value');
    if (!empty($o[$key]) && (string) $current === (string) $val) {
        say('skip ', "theme option $opt is already $val");
    } elseif (!empty($o[$key])) {
        act($apply, $what, function () use ($jid, $opt, $val) {
            DB::table('plugin_settings')->updateOrInsert(['plugin_name' => 'worjthemeplugin', 'context_id' => $jid, 'setting_name' => $opt], ['setting_value' => (string) $val, 'setting_type' => 'bool']);
        });
    }
}

// ---- 3b. the licence, where the document leaves its name blank (the addendum records the licence its own terms describe)
if (!empty($o['licence_url'])) {
    $cur = js($jid, '', 'licenseUrl');
    if ($cur === null || $cur === '') {
        $url = (string) $o['licence_url'];
        act($apply, "set the journal licence to $url (the footer links to it)", function () use ($jid, $url) {
            setjs($jid, '', 'licenseUrl', $url);
        });
    } else {
        say('skip ', 'the journal already has a licence set: left alone');
    }
}

// ---- 3c. OJS's own default submission checklist (not the client's text): emptied while it is still the shipped wording
if (!empty($o['drop_default_checklist'])) {
    $list = js($jid, 'en', 'submissionChecklist');
    if ($list !== null && $list !== '') {
        $plain = strtolower(html_entity_decode(strip_tags($list)));
        $hits = 0;
        foreach ($o['default_wording'] ?? [] as $frag) {
            if ($frag !== '' && strpos($plain, $frag) !== false) {
                $hits++;
            }
        }
        if ($hits >= 3) {
            act($apply, "empty OJS's default submission checklist ($hits shipped phrases found; the client has not supplied one)", function () use ($jid) {
                setjs($jid, 'en', 'submissionChecklist', '');
            });
        } else {
            say('skip ', 'the submission checklist is not the shipped one: left alone');
        }
    }
}

// ---- 4. the home page summary and the contact name
if (!empty($o['summary']) && isPlaceholder(js($jid, 'en', 'description'))) {
    $text = (string) $o['summary'];
    act($apply, 'set the home page summary to the first paragraph of the client\'s About text', function () use ($jid, $text) {
        setjs($jid, 'en', 'description', $text);
    });
}
if (!empty($o['contact_office'])) {
    if (isPlaceholder(js($jid, '', 'contactName'))) {
        act($apply, 'set the contact name to "Editorial Office" (a role, not a person)', function () use ($jid) {
            setjs($jid, '', 'contactName', 'Editorial Office');
        });
    }
    if (isPlaceholder(js($jid, '', 'mailingAddress'))) {
        act($apply, 'leave the mailing address empty until the client sends one', function () use ($jid) {
            setjs($jid, '', 'mailingAddress', '');
        });
    }
}

// ---- 5. the client's pages: approve (take the pending banner off) or hold (hide until confirmed)
$pages = $o['pages'] ?? [];
$get = function (array $p) use ($jid): array {
    if ($p['kind'] === 'setting') {
        return [js($jid, 'en', $p['key']), null];
    }
    if ($p['kind'] === 'custom') {
        $ids = navIds($jid, 'path', $p['path']);
        return [navContent($ids), $ids];
    }
    $aid = DB::table('announcement_settings')->where('setting_name', 'title')->where('setting_value', $p['title'])->value('announcement_id');
    $desc = $aid ? DB::table('announcement_settings')->where(['announcement_id' => $aid, 'setting_name' => 'description'])->value('setting_value') : null;
    return [$desc === null ? null : (string) $desc, $aid ? [$aid] : []];
};
$put = function (array $p, ?array $ids, string $text) use ($jid): void {
    if ($p['kind'] === 'setting') {
        setjs($jid, 'en', $p['key'], $text);
    } elseif ($p['kind'] === 'custom') {
        DB::table('navigation_menu_item_settings')->where('navigation_menu_item_id', $ids[0])->where('setting_name', 'content')->where('locale', 'en')->update(['setting_value' => $text]);
    } else {
        DB::table('announcement_settings')->where(['announcement_id' => $ids[0], 'setting_name' => 'description'])->update(['setting_value' => $text]);
    }
};
foreach ($o['approve'] ?? [] as $id) {
    $p = $pages[$id] ?? null;
    if (!$p) {
        say('FAIL ', "$id is not one of the client's pages");
        $refused++;
        continue;
    }
    [$text, $ids] = $get($p);
    if ($text === null || ($p['kind'] !== 'setting' && !$ids)) {
        say('skip ', "$id is not on the site");
        continue;
    }
    if (strpos($text, PENDING) === false) {
        say('skip ', "$id has no pending banner (already confirmed, or written by a person)");
        continue;
    }
    $new = stripBanner($text);
    if (!empty($o['drop_blanks'])) {
        $new = dropBlankParagraphs($new);
    }
    if (isPlaceholder($new)) {
        preg_match_all('#\[PLACEHOLDER[^\]]*\]#', $new, $m);
        say('FAIL ', "$id still has a marked blank, so it is NOT confirmed: " . implode(' | ', array_unique($m[0])));
        $refused++;
        continue;
    }
    act($apply, "confirm $id (take the pending banner off)", function () use ($put, $p, $ids, $new) {
        $put($p, $ids, $new);
    });
}
foreach ($o['hold'] ?? [] as $id) {
    $p = $pages[$id] ?? null;
    if (!$p) {
        say('FAIL ', "$id is not one of the client's pages");
        $refused++;
        continue;
    }
    [$text, $ids] = $get($p);
    if ($text === null || ($p['kind'] !== 'setting' && !$ids)) {
        say('skip ', "$id is not on the site");
        continue;
    }
    if (strpos($text, PENDING) === false) {
        say('skip ', "$id has no pending banner: not held");
        continue;
    }
    if ($p['kind'] === 'setting') {
        act($apply, "hold $id (empty the text until the client confirms)", function () use ($put, $p) {
            $put($p, null, '');
        });
    } elseif ($p['kind'] === 'custom') {
        act($apply, "hold $id (hide the page and its menu entry until the client confirms)", function () use ($ids) {
            deleteNav($ids);
        });
    } else {
        act($apply, "hold $id (delete the announcement until the client confirms)", function () use ($ids) {
            $a = Announcement::find((int) $ids[0]);
            if ($a) {
                $a->delete();
            }
        });
    }
}
// the menus last: whether Announcements has anything depends on what was deleted or held above
$tidyMenus = function () use ($o, $jid, $apply): void {
    if (empty($o['tidy_menus'])) {
        return;
    }
    {
    $menu = DB::table('navigation_menus')->where('context_id', $jid)->where('area_name', 'primary')->first();
    if (!$menu) {
        say('skip ', 'no primary menu');
    } else {
        $mid = (int) $menu->navigation_menu_id;
        $items = DB::table('navigation_menu_items')->where('context_id', $jid)->get(['navigation_menu_item_id', 'type', 'path']);
        $find = function (string $type, ?string $path = null) use ($items) {
            foreach ($items as $it) {
                if ($it->type === $type && ($path === null || $it->path === $path)) {
                    return (int) $it->navigation_menu_item_id;
                }
            }
            return null;
        };
        $aboutTop = DB::table('navigation_menu_item_assignments as a')->join('navigation_menu_items as i', 'i.navigation_menu_item_id', '=', 'a.navigation_menu_item_id')
            ->where('a.navigation_menu_id', $mid)->where('i.type', 'NMI_TYPE_ABOUT')->whereNull('a.parent_id')->value('a.navigation_menu_item_id');
        if (!$aboutTop) {
            say('skip ', 'no About entry in the primary menu: menus left alone');
        } else {
            $aboutTop = (int) $aboutTop;
            $wanted = [
                ['NMI_TYPE_ABOUT', null], ['NMI_TYPE_CUSTOM', 'aims-and-scope'], ['NMI_TYPE_MASTHEAD', null], ['NMI_TYPE_SUBMISSIONS', null],
                ['NMI_TYPE_CUSTOM', 'peer-review'], ['NMI_TYPE_CUSTOM', 'publication-ethics'], ['NMI_TYPE_CUSTOM', 'open-access'],
                ['NMI_TYPE_CUSTOM', 'copyright-licensing'], ['NMI_TYPE_PRIVACY', null], ['NMI_TYPE_CUSTOM', 'disclaimer'], ['NMI_TYPE_CONTACT', null],
            ];
            $seq = 0;
            foreach ($wanted as [$type, $path]) {
                // the top About entry has the same type as the first child: the child is the one with a parent
                $id = null;
                if ($type === 'NMI_TYPE_ABOUT') {
                    $id = DB::table('navigation_menu_item_assignments')->where('navigation_menu_id', $mid)->where('parent_id', $aboutTop)->whereIn('navigation_menu_item_id', DB::table('navigation_menu_items')->where('type', 'NMI_TYPE_ABOUT')->pluck('navigation_menu_item_id'))->value('navigation_menu_item_id');
                } else {
                    $id = $find($type, $path);
                }
                if (!$id) {
                    continue;
                }
                $here = DB::table('navigation_menu_item_assignments')->where(['navigation_menu_id' => $mid, 'navigation_menu_item_id' => $id])->first();
                $at = $seq++;
                if ($here && (int) $here->parent_id === $aboutTop && (int) $here->seq === $at) {
                    continue;
                }
                $label = $path ?? $type;
                act($apply, "menu: $label under About, position " . ($at + 1), function () use ($mid, $id, $aboutTop, $at) {
                    DB::table('navigation_menu_item_assignments')->updateOrInsert(['navigation_menu_id' => $mid, 'navigation_menu_item_id' => $id], ['parent_id' => $aboutTop, 'seq' => $at]);
                });
            }
        }
        $mast = $find('NMI_TYPE_MASTHEAD');
        if ($mast) {
            $title = DB::table('navigation_menu_item_settings')->where(['navigation_menu_item_id' => $mast, 'setting_name' => 'title', 'locale' => 'en'])->value('setting_value');
            if ($title !== 'Editorial Team') {
                act($apply, 'menu: label the editorial masthead "Editorial Team"', function () use ($mast) {
                    DB::table('navigation_menu_item_settings')->updateOrInsert(['navigation_menu_item_id' => $mast, 'setting_name' => 'title', 'locale' => 'en'], ['setting_value' => 'Editorial Team', 'setting_type' => 'string']);
                });
            }
        }
        $ann = $find('NMI_TYPE_ANNOUNCEMENTS');
        if ($ann && !DB::table('announcements')->where('assoc_id', $jid)->exists()
            && DB::table('navigation_menu_item_assignments')->where(['navigation_menu_id' => $mid, 'navigation_menu_item_id' => $ann])->exists()) {
            act($apply, 'menu: take the empty Announcements entry out (add it back when the first announcement exists)', function () use ($mid, $ann) {
                DB::table('navigation_menu_item_assignments')->where(['navigation_menu_id' => $mid, 'navigation_menu_item_id' => $ann])->delete();
            });
        }
    }
    }
};

$tidyMenus();

// what was written must show up at once: OJS caches rendered menus and templates
if ($apply) {
    PKPContainer::getInstance()['cache']->store()->flush();
    $templateMgr = TemplateManager::getManager($request);
    $templateMgr->clearTemplateCache();
    $templateMgr->clearCssCache();
}
exit($refused ? 1 : 0);
