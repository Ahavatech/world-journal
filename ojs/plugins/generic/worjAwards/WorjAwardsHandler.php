<?php

namespace APP\plugins\generic\worjAwards;

use APP\core\Application;
use APP\handler\Handler;
use APP\template\TemplateManager;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Mail;
use PKP\mail\Mailable;
use PKP\security\Role;

class WorjAwardsHandler extends Handler
{
    public const CRITERIA = ['originality' => 'Originality', 'quality' => 'Research Quality', 'impact' => 'Scholarly Impact', 'contribution' => 'Outstanding Contribution'];
    public const STATUSES = ['received' => 'Received', 'shortlisted' => 'Shortlisted', 'winner' => 'Winner', 'declined' => 'Not selected'];

    protected WorjAwardsPlugin $plugin;
    protected string $page;

    public function __construct(WorjAwardsPlugin $plugin, string $page)
    {
        $this->plugin = $plugin;
        $this->page = $page;
    }

    public function index($args, $request)
    {
        $context = $request->getContext();
        if (!$context) {
            $request->getDispatcher()->handle404();
        }
        $this->setupTemplate($request);
        return match ($this->page) {
            'awards-nominate' => $this->nominate($request, $context),
            'awards-judge' => $this->judge($request, $context),
            'awards-manage' => $this->manage($request, $context),
            default => $this->recipients($request, $context),
        };
    }

    // ---------- settings (stored as plugin settings) ----------
    protected function cfg($context, string $key, $default)
    {
        $v = $this->plugin->getSetting($context->getId(), $key);
        return $v === null ? $default : $v;
    }

    protected function categories($context): array
    {
        $c = $this->cfg($context, 'categories', ['Best Researcher']);
        return is_array($c) && $c ? array_values($c) : ['Best Researcher'];
    }

    protected function judges($context): array
    {
        $j = $this->cfg($context, 'judges', []);
        return is_array($j) ? array_map('strtolower', $j) : [];
    }

    protected function show($request, string $tpl, array $vars, string $title): void
    {
        $tm = TemplateManager::getManager($request);
        $tm->assign($vars + ['worjPageTitle' => $title]);
        $tm->display($this->plugin->getTemplateResource($tpl));
    }

    protected function csrfOk($request): bool
    {
        return $request->isPost() && $request->checkCSRF();
    }

    /** A journal manager of this journal, or the site administrator. Read from the database, by role number. */
    protected function isManager($request, $context): bool
    {
        $u = $request->getUser();
        if (!$u) {
            return false;
        }
        return DB::table('user_user_groups as x')->join('user_groups as g', 'g.user_group_id', '=', 'x.user_group_id')
            ->where('x.user_id', $u->getId())
            ->where(fn ($q) => $q->whereNull('x.date_end')->orWhere('x.date_end', '>', date('Y-m-d H:i:s')))
            ->where(fn ($q) => $q->where(['g.role_id' => Role::ROLE_ID_MANAGER, 'g.context_id' => $context->getId()])->orWhere('g.role_id', Role::ROLE_ID_SITE_ADMIN))
            ->exists();
    }

    /** OJS's own "you do not have access" page */
    protected function deny($request)
    {
        $request->redirect(null, 'user', 'authorizationDenied', null, ['message' => 'user.authorization.roleBasedAccessDenied']);
    }

    protected function loginFirst($request)
    {
        $request->redirect(null, 'login', null, null, ['source' => $request->getRequestPath()]);
    }

    // ---------- public: nomination form ----------
    protected function nominate($request, $context)
    {
        $open = (bool) $this->cfg($context, 'nominationsOpen', false);
        $cats = $this->categories($context);
        $f = ['category' => '', 'nominee_name' => '', 'nominee_email' => '', 'article_ref' => '', 'statement' => '', 'nominator_name' => '', 'nominator_email' => ''];
        $errors = [];
        $done = false;
        if ($request->isPost()) {
            if (!$this->csrfOk($request)) {
                $errors[] = 'The form expired. Please reload the page and try again.';
            } elseif (!$open) {
                $errors[] = 'Nominations are not open.';
            } else {
                foreach ($f as $k => $_) {
                    $f[$k] = trim((string) $request->getUserVar($k));
                }
                if ((string) $request->getUserVar('website') !== '') { // honeypot: a person leaves it empty
                    $done = true; // pretend success so a bot learns nothing
                } else {
                    if (!in_array($f['category'], $cats, true)) $errors[] = 'Choose a category.';
                    if ($f['nominee_name'] === '' || mb_strlen($f['nominee_name']) > 255) $errors[] = 'Enter the nominee\'s name.';
                    if ($f['nominee_email'] !== '' && !filter_var($f['nominee_email'], FILTER_VALIDATE_EMAIL)) $errors[] = 'The nominee\'s email address is not valid (or leave it empty).';
                    if ($f['nominator_name'] === '' || mb_strlen($f['nominator_name']) > 255) $errors[] = 'Enter your name.';
                    if (!filter_var($f['nominator_email'], FILTER_VALIDATE_EMAIL)) $errors[] = 'Enter a valid email address for yourself.';
                    if (mb_strlen($f['article_ref']) > 500) $errors[] = 'The article reference is too long.';
                    $n = mb_strlen($f['statement']);
                    if ($n < 50 || $n > 3000) $errors[] = 'The supporting statement must be between 50 and 3000 characters (now ' . $n . ').';
                    if (!$request->getUserVar('consent')) $errors[] = 'Please confirm you agree to the journal using these details to consider the nomination.';
                    if (!$errors && DB::table('worj_award_nominations')->where(['context_id' => $context->getId(), 'category' => $f['category'], 'nominee_name' => $f['nominee_name'], 'nominator_email' => $f['nominator_email']])->exists()) {
                        $errors[] = 'You have already nominated this person in this category.';
                    }
                    if (!$errors) {
                        DB::table('worj_award_nominations')->insert([
                            'context_id' => $context->getId(), 'category' => $f['category'], 'nominee_name' => $f['nominee_name'],
                            'nominee_email' => $f['nominee_email'] ?: null, 'article_ref' => $f['article_ref'] ?: null, 'statement' => $f['statement'],
                            'nominator_name' => $f['nominator_name'], 'nominator_email' => $f['nominator_email'], 'status' => 'received', 'created_at' => date('Y-m-d H:i:s'),
                        ]);
                        $this->notify($context, $f);
                        $done = true;
                    }
                }
            }
        }
        $this->show($request, 'nominate.tpl', ['open' => $open, 'cats' => $cats, 'f' => $f, 'errors' => $errors, 'done' => $done], 'Nominate for a Research Award');
    }

    protected function notify($context, array $f): void
    {
        $from = $context->getData('contactEmail');
        $name = $context->getLocalizedName();
        try {
            $m = new Mailable();
            $m->from($from, $name)->to($from)->replyTo($f['nominator_email'], $f['nominator_name'])
                ->subject('New Research Award nomination: ' . $f['category'])
                ->body('<p>A nomination was received.</p><p>Category: ' . e($f['category']) . '<br>Nominee: ' . e($f['nominee_name']) . '<br>Nominated by: ' . e($f['nominator_name']) . ' (' . e($f['nominator_email']) . ')</p><p>Open the journal\'s awards manager page to review it.</p>');
            Mail::send($m);
            $c = new Mailable();
            $c->from($from, $name)->to($f['nominator_email'], $f['nominator_name'])
                ->subject('We received your nomination')
                ->body('<p>Dear ' . e($f['nominator_name']) . ',</p><p>Thank you. We received your nomination of ' . e($f['nominee_name']) . ' for ' . e($f['category']) . '. The journal\'s reviewers and editorial team will consider it. You do not need to do anything more.</p><p>' . e($name) . '</p>');
            Mail::send($c);
        } catch (\Throwable $e) {
            // the nomination is saved; a mail problem must not lose it
            error_log('worjAwards: notification not sent: ' . $e->getMessage());
        }
    }

    // ---------- judges ----------
    protected function judge($request, $context)
    {
        $u = $request->getUser();
        if (!$u) {
            return $this->loginFirst($request);
        }
        if (!in_array(strtolower($u->getUsername()), $this->judges($context), true)) {
            return $this->deny($request);
        }
        $cid = $context->getId();
        $msg = '';
        if ($request->isPost()) {
            $nid = (int) $request->getUserVar('nomination_id');
            $nom = DB::table('worj_award_nominations')->where(['nomination_id' => $nid, 'context_id' => $cid])->first();
            if (!$this->csrfOk($request)) {
                $msg = 'The form expired. Please try again.';
            } elseif (!$nom || !in_array($nom->status, ['received', 'shortlisted'], true)) {
                $msg = 'That nomination is not open for scoring.';
            } else {
                $conflict = $request->getUserVar('conflict') ? 1 : 0;
                $row = ['conflict' => $conflict, 'comment' => mb_substr(trim((string) $request->getUserVar('comment')), 0, 2000), 'updated_at' => date('Y-m-d H:i:s')];
                $ok = true;
                foreach (array_keys(self::CRITERIA) as $k) {
                    $v = (int) $request->getUserVar($k);
                    if ($conflict) {
                        $row[$k] = null;
                    } elseif ($v < 1 || $v > 5) {
                        $ok = false;
                    } else {
                        $row[$k] = $v;
                    }
                }
                if (!$ok) {
                    $msg = 'Give each criterion a score from 1 to 5, or tick the conflict box.';
                } else {
                    DB::table('worj_award_scores')->updateOrInsert(['nomination_id' => $nid, 'judge_user_id' => $u->getId()], $row);
                    $msg = 'Saved.';
                }
            }
        }
        $noms = DB::table('worj_award_nominations')->where('context_id', $cid)->whereIn('status', ['received', 'shortlisted'])->orderBy('category')->orderBy('nomination_id')->get();
        $mine = DB::table('worj_award_scores')->where('judge_user_id', $u->getId())->get()->keyBy('nomination_id');
        $items = [];
        foreach ($noms as $n) {
            $items[] = ['n' => $n, 's' => $mine->get($n->nomination_id)];
        }
        $this->show($request, 'judge.tpl', ['items' => $items, 'criteria' => self::CRITERIA, 'msg' => $msg], 'Judging');
    }

    // ---------- manager ----------
    protected function manage($request, $context)
    {
        if (!$request->getUser()) {
            return $this->loginFirst($request);
        }
        if (!$this->isManager($request, $context)) {
            return $this->deny($request);
        }
        $cid = $context->getId();
        $msg = '';
        if ($request->isPost()) {
            if (!$this->csrfOk($request)) {
                $msg = 'The form expired. Please try again.';
            } else {
                $act = (string) $request->getUserVar('action');
                if ($act === 'settings') {
                    $lines = fn (string $k) => array_values(array_filter(array_map('trim', preg_split('/\R/', (string) $request->getUserVar($k)))));
                    $this->plugin->updateSetting($cid, 'nominationsOpen', (bool) $request->getUserVar('nominationsOpen'), 'bool');
                    $cats = array_slice($lines('categories'), 0, 20);
                    $this->plugin->updateSetting($cid, 'categories', $cats ?: ['Best Researcher'], 'object');
                    $this->plugin->updateSetting($cid, 'judges', array_slice(array_map('strtolower', $lines('judges')), 0, 50), 'object');
                    $msg = 'Settings saved.';
                } elseif ($act === 'status') {
                    $st = (string) $request->getUserVar('status');
                    $nid = (int) $request->getUserVar('nomination_id');
                    if (isset(self::STATUSES[$st]) && DB::table('worj_award_nominations')->where(['nomination_id' => $nid, 'context_id' => $cid])->exists()) {
                        DB::table('worj_award_nominations')->where('nomination_id', $nid)->update([
                            'status' => $st, 'award_period' => mb_substr(trim((string) $request->getUserVar('award_period')), 0, 100) ?: null,
                            'decided_at' => in_array($st, ['winner', 'declined'], true) ? date('Y-m-d H:i:s') : null]);
                        $msg = 'Updated.';
                    }
                } elseif ($act === 'delete') {
                    $nid = (int) $request->getUserVar('nomination_id');
                    if (DB::table('worj_award_nominations')->where(['nomination_id' => $nid, 'context_id' => $cid])->delete()) {
                        DB::table('worj_award_scores')->where('nomination_id', $nid)->delete();
                    }
                    $msg = 'Deleted.';
                }
            }
        }
        $rows = $this->ranked($cid);
        if ($request->getUserVar('export') === 'csv' && !$request->isPost()) {
            return $this->csv($rows);
        }
        $this->show($request, 'manage.tpl', [
            'rows' => $rows, 'statuses' => self::STATUSES, 'msg' => $msg,
            'open' => (bool) $this->cfg($context, 'nominationsOpen', false),
            'categoriesText' => implode("\n", $this->categories($context)), 'judgesText' => implode("\n", $this->judges($context)),
        ], 'Awards manager');
    }

    /** Nominations with the judges' mean total (the four criteria, 4 to 20), most scored first within each category. */
    protected function ranked(int $cid): array
    {
        $out = [];
        foreach (DB::table('worj_award_nominations')->where('context_id', $cid)->orderBy('category')->orderBy('nomination_id')->get() as $n) {
            $sc = DB::table('worj_award_scores')->where('nomination_id', $n->nomination_id)->get();
            $real = $sc->where('conflict', 0);
            $tot = $real->map(fn ($s) => $s->originality + $s->quality + $s->impact + $s->contribution);
            $out[] = ['n' => $n, 'judges' => $real->count(), 'conflicts' => $sc->where('conflict', 1)->count(), 'mean' => $tot->count() ? round($tot->avg(), 2) : null];
        }
        usort($out, fn ($a, $b) => [$a['n']->category, -($a['mean'] ?? -1)] <=> [$b['n']->category, -($b['mean'] ?? -1)]);
        return $out;
    }

    protected function csv(array $rows)
    {
        $safe = fn ($v) => (is_string($v) && $v !== '' && strpbrk($v[0], "=+-@\t\r") !== false) ? "'" . $v : $v;
        header('Content-Type: text/csv; charset=UTF-8');
        header('Content-Disposition: attachment; filename="research-award-nominations.csv"');
        $f = fopen('php://output', 'w');
        fputcsv($f, ['id', 'category', 'nominee', 'nominee_email', 'article', 'nominator', 'nominator_email', 'status', 'period', 'judges', 'conflicts', 'mean_total_of_20', 'received', 'statement']);
        foreach ($rows as $r) {
            $n = $r['n'];
            fputcsv($f, array_map($safe, [$n->nomination_id, $n->category, $n->nominee_name, $n->nominee_email, $n->article_ref, $n->nominator_name, $n->nominator_email, $n->status, $n->award_period, $r['judges'], $r['conflicts'], $r['mean'], $n->created_at, $n->statement]));
        }
        fclose($f);
        exit;
    }

    // ---------- public: recipients ----------
    protected function recipients($request, $context)
    {
        $w = DB::table('worj_award_nominations')->where(['context_id' => $context->getId(), 'status' => 'winner'])->orderByDesc('decided_at')->get(['category', 'nominee_name', 'article_ref', 'award_period']);
        $this->show($request, 'recipients.tpl', ['winners' => $w], 'Award recipients');
    }
}
