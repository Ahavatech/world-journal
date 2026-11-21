<?php
// Small journal features, each on its own switch, each safe to repeat. Run from the OJS root, script on stdin, options as base64 JSON:
//   {"journal":"worj","apply":false,"ops":["citations","coauthor","awards-menu"]}
// Prints WOULD:/DONE:/skip lines. Nothing here writes a credential or removes anything.
// a CLI run has no URL: give OJS the one it needs to find the journal (the template cache clearing asks the request for it)
$_SERVER['SCRIPT_NAME'] = '/index.php';
$_SERVER['PATH_INFO'] = '/' . (json_decode(base64_decode($argv[1] ?? ''), true)['journal'] ?? '');
$_SERVER['REQUEST_URI'] = '/index.php' . $_SERVER['PATH_INFO'];
$_SERVER['HTTP_HOST'] = $_SERVER['HTTP_HOST'] ?? 'localhost';
require 'tools/bootstrap.php';
ini_set('display_errors', 'stderr');
error_reporting(E_ALL & ~E_WARNING & ~E_NOTICE & ~E_DEPRECATED);
use Illuminate\Support\Facades\DB;
use APP\core\Application;
use APP\core\PageRouter;
use APP\template\TemplateManager;
use PKP\core\PKPContainer;

$o = json_decode(base64_decode($argv[1] ?? ''), true);
$request = Application::get()->getRequest();
$router = new PageRouter();
$router->setApplication(Application::get());
$request->setRouter($router);
$apply = !empty($o['apply']);
$jid = (int) DB::table('journals')->where('path', $o['journal'] ?? '')->value('journal_id');
if (!$jid) {
    echo "FAILED: no such journal\n";
    exit(1);
}
$changed = false;
function act(bool $apply, string $msg, callable $fn): void
{
    global $changed;
    if ($apply) {
        $fn();
        $changed = true;
        echo "DONE:  $msg\n";
    } else {
        echo "WOULD: $msg\n";
    }
}
function setting(int $jid, string $plugin, string $name): ?string
{
    $v = DB::table('plugin_settings')->where(['plugin_name' => $plugin, 'context_id' => $jid, 'setting_name' => $name])->value('setting_value');
    return $v === null ? null : (string) $v;
}
function setPlugin(int $jid, string $plugin, string $name, $value, string $type): void
{
    DB::table('plugin_settings')->updateOrInsert(['plugin_name' => $plugin, 'context_id' => $jid, 'setting_name' => $name], ['setting_value' => is_array($value) ? json_encode($value) : (string) $value, 'setting_type' => $type]);
}

foreach ($o['ops'] ?? [] as $op) {
    if ($op === 'citations') {
        // "How to cite" with a format dropdown and RIS / BibTeX downloads on every article page; references asked for at submission
        if (setting($jid, 'citationstylelanguageplugin', 'enabled') !== '1') {
            act($apply, 'switch on the citation formats plugin (How to cite)', fn () => setPlugin($jid, 'citationstylelanguageplugin', 'enabled', '1', 'bool'));
        } else {
            echo "skip   the citation formats plugin is already on\n";
        }
        if (setting($jid, 'citationstylelanguageplugin', 'enabledCitationStyles') === null) {
            $styles = ['apa', 'harvard-cite-them-right', 'ieee', 'modern-language-association', 'chicago-author-date', 'vancouver'];
            act($apply, 'offer these citation formats: ' . implode(', ', $styles) . ' (APA first)', function () use ($jid, $styles) {
                setPlugin($jid, 'citationstylelanguageplugin', 'enabledCitationStyles', $styles, 'object');
                setPlugin($jid, 'citationstylelanguageplugin', 'primaryCitationStyle', 'apa', 'string');
                setPlugin($jid, 'citationstylelanguageplugin', 'enabledCitationDownloads', ['ris', 'bibtex'], 'object');
            });
        } else {
            echo "skip   the citation formats are already chosen (not changed)\n";
        }
        $cit = DB::table('journal_settings')->where(['journal_id' => $jid, 'setting_name' => 'citations'])->value('setting_value');
        if (!in_array($cit, ['request', 'require'], true)) {
            act($apply, 'ask authors for their references at submission (it was ' . var_export($cit, true) . ')', fn () => DB::table('journal_settings')->updateOrInsert(['journal_id' => $jid, 'locale' => '', 'setting_name' => 'citations'], ['setting_value' => 'request']));
        } else {
            echo "skip   authors are already asked for references ($cit)\n";
        }
    }
    if ($op === 'coauthor') {
        // a "Co-author" choice in the contributor role list (any number of contributors can be added; each takes a role)
        $exists = DB::table('user_group_settings')->where(['setting_name' => 'name', 'locale' => 'en', 'setting_value' => 'Co-author'])->whereIn('user_group_id', DB::table('user_groups')->where('context_id', $jid)->pluck('user_group_id'))->exists();
        $author = DB::table('user_groups')->where(['context_id' => $jid, 'role_id' => 65536, 'is_default' => 1])->orderBy('user_group_id')->first();
        if ($exists) {
            echo "skip   the Co-author role already exists\n";
        } elseif (!$author) {
            echo "FAILED: no Author role to copy from\n";
        } else {
            act($apply, 'add the Co-author contributor role (an author role, same permissions as Author)', function () use ($jid, $author) {
                $row = (array) $author;
                unset($row['user_group_id']);
                $row['is_default'] = 0;
                $row['permit_self_registration'] = 0;
                $id = DB::table('user_groups')->insertGetId($row);
                DB::table('user_group_settings')->insert([
                    ['user_group_id' => $id, 'locale' => 'en', 'setting_name' => 'name', 'setting_value' => 'Co-author'],
                    ['user_group_id' => $id, 'locale' => 'en', 'setting_name' => 'abbrev', 'setting_value' => 'CA'],
                ]);
                foreach (DB::table('user_group_stage')->where('user_group_id', $author->user_group_id)->get() as $st) {
                    DB::table('user_group_stage')->insert(['context_id' => $jid, 'user_group_id' => $id, 'stage_id' => $st->stage_id]);
                }
            });
        }
    }
    if ($op === 'downloads') {
        // the Downloads block (manuscript template, cover letter, copyright agreement) on the Author Guidelines page, which a person may already have approved:
        // append-only and repeatable; a link to the old DRAFT agreement file is repointed to the current one
        $key = ['journal_id' => $jid, 'locale' => 'en', 'setting_name' => 'authorGuidelines'];
        $txt = (string) DB::table('journal_settings')->where($key)->value('setting_value');
        $block = "\n<h3>Downloads for authors</h3>\n<ul>\n<li><a href=\"/downloads/WORJ-Manuscript-Template.docx\" download>Manuscript template (Word)</a></li>\n<li><a href=\"/downloads/WORJ-Cover-Letter-Template.docx\" download>Cover letter template (Word)</a></li>\n<li><a href=\"/downloads/WORJ-Copyright-and-Publication-Agreement.docx\" download>Copyright and publication agreement (Word)</a></li>\n</ul>\n";
        $new = $txt;
        // the links ask the browser to download the file (a Word file served with the wrong type opened as text on the host)
        $new = preg_replace('#<a href="(/downloads/[^"]+\.docx)">#', '<a href="$1" download>', $new);
        if (strpos($new, 'WORJ-Copyright-and-Publication-Agreement-DRAFT.docx') !== false) {
            $new = str_replace('WORJ-Copyright-and-Publication-Agreement-DRAFT.docx">Copyright and publication agreement (Word, draft for review)', 'WORJ-Copyright-and-Publication-Agreement.docx">Copyright and publication agreement (Word)', $new);
        }
        if (strpos($new, 'WORJ-Manuscript-Template.docx') === false) {
            if ($txt === '') {
                echo "skip   the Author Guidelines are empty: nothing to add the Downloads block to\n";
                continue;
            }
            $new = rtrim($new) . $block;
        }
        if ($new === $txt) {
            echo "skip   the Author Guidelines already have the Downloads block\n";
        } else {
            act($apply, 'add the Downloads block to the Author Guidelines (append only)', fn () => DB::table('journal_settings')->where($key)->update(['setting_value' => $new]));
        }
    }
    if ($op === 'awards-menu') {
        // Research Awards in the main menu: the awards page, with the winners page under it
        $mid = DB::table('navigation_menus')->where(['context_id' => $jid, 'area_name' => 'primary'])->value('navigation_menu_id');
        $aw = DB::table('navigation_menu_items')->where(['context_id' => $jid, 'path' => 'awards'])->value('navigation_menu_item_id');
        $win = DB::table('navigation_menu_items')->where(['context_id' => $jid, 'path' => 'awards-winners'])->value('navigation_menu_item_id');
        if (!$mid || !$aw) {
            echo "skip   the awards page or the main menu is missing (scripts/pages-shared.sh --only awards,awards-winners --apply first)\n";
        } else {
            $in = fn ($id) => DB::table('navigation_menu_item_assignments')->where(['navigation_menu_id' => $mid, 'navigation_menu_item_id' => $id])->exists();
            if (!$in($aw)) {
                act($apply, 'put Research Awards in the main menu', function () use ($mid, $aw) {
                    $seq = (int) DB::table('navigation_menu_item_assignments')->where('navigation_menu_id', $mid)->whereNull('parent_id')->max('seq') + 1;
                    DB::table('navigation_menu_item_assignments')->insert(['navigation_menu_id' => $mid, 'navigation_menu_item_id' => $aw, 'parent_id' => null, 'seq' => $seq]);
                });
            } else {
                echo "skip   Research Awards is already in the main menu\n";
            }
            if ($win && !$in($win)) {
                act($apply, 'put the winners page under Research Awards', function () use ($mid, $aw, $win) {
                    DB::table('navigation_menu_item_assignments')->insert(['navigation_menu_id' => $mid, 'navigation_menu_item_id' => $win, 'parent_id' => $aw, 'seq' => 0]);
                });
            }
        }
    }
}
if ($changed) {
    // what was written must show up at once: OJS caches rendered menus and templates. A cache problem must not hide that the writes happened.
    try {
        PKPContainer::getInstance()['cache']->store()->flush();
        $tm = TemplateManager::getManager($request);
        $tm->clearTemplateCache();
        $tm->clearCssCache();
        echo "DONE:  cleared the caches\n";
    } catch (\Throwable $e) {
        echo "NOTE:  the changes are saved, but the caches could not be cleared here (" . $e->getMessage() . "). Clear them in Administration > Clear Data Caches and Clear Template Cache.\n";
    }
}
