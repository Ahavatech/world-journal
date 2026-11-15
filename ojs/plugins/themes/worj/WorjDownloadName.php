<?php

/**
 * @file plugins/themes/worj/WorjDownloadName.php
 *
 * @brief Names a downloaded article file from the article's own details, whatever the uploaded file was called:
 *   WORJ_Vol{volume}_No{number}_{year}_{first author's surname}_{short title}.{extension}
 * (without an issue: WORJ_{year}_{surname}_{short title}). Only a reader's download of a published article's own galley file is renamed;
 * dependent files and everything in the editorial workflow keep OJS's own naming. Built from real fields only; nothing is invented.
 */

namespace APP\plugins\themes\worj;

use APP\facades\Repo;
use PKP\plugins\Hook;

class WorjDownloadName
{
    /** @var array|null the article download in progress: [article, galley] */
    protected static ?array $pending = null;

    public static function register(): void
    {
        // ArticleHandler::download fires just before OJS builds the file name; we only note which article this is and let OJS go on
        Hook::add('ArticleHandler::download', function ($hookName, $args) {
            [$article, $galley, $fileId] = [$args[0], $args[1], $args[2]];
            self::$pending = ($galley && $fileId && (int) $galley->getData('submissionFileId') === (int) $fileId) ? ['article' => $article, 'galley' => $galley, 'fileId' => (int) $fileId] : null;
            return Hook::CONTINUE;
        });
        Hook::add('File::formatFilename', function ($hookName, $args) {
            $name = &$args[0];
            $path = (string) $args[1];
            if (self::$pending === null) {
                return Hook::CONTINUE;
            }
            $ctx = self::$pending;
            self::$pending = null;
            try {
                $file = Repo::submissionFile()->get($ctx['fileId']);
                if (!$file || (string) $file->getData('path') !== $path) {
                    return Hook::CONTINUE;
                }
                $new = self::build($ctx['article'], $path);
                if ($new !== '') {
                    $name = $new;
                }
            } catch (\Throwable $e) {
            }
            return Hook::CONTINUE;
        });
    }

    public static function build($article, string $path): string
    {
        $pub = $article->getCurrentPublication();
        if (!$pub) {
            return '';
        }
        $ext = preg_match('/\.[A-Za-z0-9]{1,8}$/', $path, $m) ? strtolower($m[0]) : '';
        $parts = ['WORJ'];
        $issue = $pub->getData('issueId') ? Repo::issue()->get((int) $pub->getData('issueId')) : null;
        if ($issue && $issue->getVolume() !== null && $issue->getVolume() !== '') {
            $parts[] = 'Vol' . self::clean((string) $issue->getVolume(), 12);
        }
        if ($issue && $issue->getNumber() !== null && $issue->getNumber() !== '') {
            $parts[] = 'No' . self::clean((string) $issue->getNumber(), 12);
        }
        $date = $pub->getData('datePublished') ?: ($issue ? $issue->getDatePublished() : null);
        $year = $issue && $issue->getYear() ? (string) $issue->getYear() : ($date ? date('Y', strtotime($date)) : '');
        if ($year !== '') {
            $parts[] = self::clean($year, 4);
        }
        $authors = $pub->getData('authors');
        $first = is_array($authors) ? (reset($authors) ?: null) : ($authors ? $authors->first() : null);
        if ($first) {
            $sur = (string) ($first->getLocalizedFamilyName() ?: $first->getLocalizedGivenName());
            $s = self::clean($sur, 30);
            if ($s !== '') {
                $parts[] = $s;
            }
        }
        $title = self::slug((string) $pub->getLocalizedFullTitle(), 60);
        if ($title !== '') {
            $parts[] = $title;
        }
        return count($parts) > 1 ? implode('_', $parts) . $ext : '';
    }

    /** letters and digits only (accents folded to plain letters), at most $max characters */
    protected static function clean(string $s, int $max): string
    {
        $s = self::ascii($s);
        $s = preg_replace('/[^A-Za-z0-9]+/', '', $s);
        return substr($s, 0, $max);
    }

    /** Words joined by hyphens, cut at a word boundary */
    protected static function slug(string $s, int $max): string
    {
        $s = self::ascii(strip_tags(html_entity_decode($s, ENT_QUOTES | ENT_HTML5, 'UTF-8')));
        $s = trim(preg_replace('/[^A-Za-z0-9]+/', '-', $s), '-');
        if (strlen($s) <= $max) {
            return $s;
        }
        $cut = substr($s, 0, $max);
        $p = strrpos($cut, '-');
        return rtrim($p !== false && $p > $max * 0.5 ? substr($cut, 0, $p) : $cut, '-');
    }

    protected static function ascii(string $s): string
    {
        $t = function_exists('transliterator_transliterate') ? @transliterator_transliterate('Any-Latin; Latin-ASCII', $s) : false;
        if ($t === false || $t === null) {
            $t = @iconv('UTF-8', 'ASCII//TRANSLIT//IGNORE', $s);
        }
        return $t === false ? preg_replace('/[^\x20-\x7E]/', '', $s) : $t;
    }
}
