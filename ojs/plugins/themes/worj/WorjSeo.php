<?php

/**
 * @file plugins/themes/worj/WorjSeo.php
 *
 * @brief Search engine and social metadata for the public pages: a canonical link, a description, Open Graph and Twitter card tags, the
 * article's own keywords as meta keywords, and schema.org JSON-LD (Periodical, PublicationIssue, ScholarlyArticle). Google Scholar's
 * citation_* tags and the Dublin Core tags already come from OJS's own plugins and are not repeated here.
 * Nothing is invented: a field is written only when the journal has a value for it (no ISSN or DOI is printed until one exists).
 */

namespace APP\plugins\themes\worj;

use APP\core\Application;
use APP\template\TemplateManager;

class WorjSeo
{
    public static function inject(TemplateManager $tm, $request): void
    {
        $context = $request->getContext();
        if (!$context) {
            return;
        }
        $page = (string) $request->getRequestedPage();
        $op = (string) $request->getRequestedOp();
        $article = $tm->getTemplateVars('article');
        $publication = $tm->getTemplateVars('publication');
        $issue = $tm->getTemplateVars('issue');
        $name = self::plain((string) $context->getLocalizedName());
        $base = rtrim((string) $request->getBaseUrl(), '/');
        $logo = $base . '/plugins/themes/worj/assets/img/logo-lockup.jpg';
        $locale = str_replace('_', '-', (string) $context->getPrimaryLocale());
        $siteDescription = self::trim(self::plain((string) ($context->getLocalizedData('searchDescription') ?: $context->getLocalizedData('description'))), 300);
        if (stripos($siteDescription, 'PLACEHOLDER') !== false) {
            $siteDescription = '';
        }
        $home = $request->getDispatcher()->url($request, Application::ROUTE_PAGE, $context->getPath());
        $issn = self::issn($context);

        $url = self::canonical($request);
        $title = $name;
        $desc = '';
        $type = 'website';
        $image = $logo;
        $ld = [];
        $keywords = [];
        $extra = '';

        if ($page === 'article' && $op === 'view' && $article && $publication) {
            $title = self::plain((string) $publication->getLocalizedFullTitle());
            $abstract = self::plain((string) $publication->getLocalizedData('abstract'));
            $desc = self::trim($abstract !== '' ? $abstract : $title, 300);
            $type = 'article';
            $url = $request->getDispatcher()->url($request, Application::ROUTE_PAGE, $context->getPath(), 'article', 'view', [$article->getBestId()]);
            foreach ((array) $publication->getLocalizedData('keywords') as $k) {
                $k = self::plain(is_array($k) ? (string) ($k['name'] ?? '') : (string) $k);
                if ($k !== '') {
                    $keywords[] = $k;
                }
            }
            $published = $publication->getData('datePublished');
            $authors = [];
            foreach ($publication->getData('authors') ?? [] as $a) {
                $p = ['@type' => 'Person', 'name' => self::plain((string) $a->getFullName(false))];
                $aff = self::plain((string) $a->getLocalizedData('affiliation'));
                if ($aff !== '') {
                    $p['affiliation'] = ['@type' => 'Organization', 'name' => $aff];
                }
                $authors[] = $p;
            }
            $periodical = ['@type' => 'Periodical', 'name' => $name, 'url' => $home];
            if ($issn) {
                $periodical['issn'] = $issn;
            }
            $part = $periodical;
            if ($issue) {
                $part = ['@type' => 'PublicationIssue', 'issueNumber' => (string) $issue->getNumber(), 'isPartOf' => ['@type' => 'PublicationVolume', 'volumeNumber' => (string) $issue->getVolume(), 'isPartOf' => $periodical]];
                if ($issue->getDatePublished()) {
                    $part['datePublished'] = date('Y-m-d', strtotime($issue->getDatePublished()));
                }
                if (!$issue->getNumber()) {
                    $part = ['@type' => 'PublicationVolume', 'volumeNumber' => (string) $issue->getVolume(), 'isPartOf' => $periodical];
                }
            }
            $ld = [
                '@context' => 'https://schema.org', '@type' => 'ScholarlyArticle',
                'headline' => $title, 'name' => $title, 'url' => $url, 'mainEntityOfPage' => $url,
                'inLanguage' => str_replace('_', '-', (string) $publication->getData('locale')),
                'isAccessibleForFree' => true, 'isPartOf' => $part,
            ];
            if ($abstract !== '') {
                $ld['description'] = $abstract;
                $ld['abstract'] = $abstract;
            }
            if ($published) {
                $ld['datePublished'] = date('Y-m-d', strtotime($published));
            }
            if ($publication->getData('lastModified')) {
                $ld['dateModified'] = date('Y-m-d', strtotime($publication->getData('lastModified')));
            }
            if ($authors) {
                $ld['author'] = $authors;
            }
            if ($keywords) {
                $ld['keywords'] = implode(', ', $keywords);
            }
            $licence = (string) $publication->getData('licenseUrl') ?: (string) $context->getData('licenseUrl');
            if ($licence !== '') {
                $ld['license'] = $licence;
            }
            $doi = method_exists($publication, 'getDoi') ? (string) $publication->getDoi() : '';
            if ($doi !== '') {
                $ld['identifier'] = ['@type' => 'PropertyValue', 'propertyID' => 'DOI', 'value' => $doi];
            }
            if ($publication->getData('pages')) {
                $ld['pagination'] = self::plain((string) $publication->getData('pages'));
            }
            foreach ($publication->getData('galleys') ?? [] as $g) {
                if ($g->isPdfGalley()) {
                    $ld['encoding'] = ['@type' => 'MediaObject', 'encodingFormat' => 'application/pdf', 'contentUrl' => $request->getDispatcher()->url($request, Application::ROUTE_PAGE, $context->getPath(), 'article', 'download', [$article->getBestId(), $g->getBestGalleyId()])];
                    break;
                }
            }
            $extra .= self::meta('article:published_time', $published ? date('c', strtotime($published)) : '', 'property');
            foreach ($keywords as $k) {
                $extra .= self::meta('article:tag', $k, 'property');
            }
            foreach ($authors as $a) {
                $extra .= self::meta('article:author', $a['name'], 'property');
            }
        } elseif ($page === 'issue' && $op === 'view' && $issue) {
            $label = self::plain((string) $issue->getIssueIdentification());
            $title = $label !== '' ? $label . ' | ' . $name : $name;
            $desc = self::trim(self::plain((string) $issue->getLocalizedDescription()) ?: ($label . ' of ' . $name . '.'), 300);
            $url = $request->getDispatcher()->url($request, Application::ROUTE_PAGE, $context->getPath(), 'issue', 'view', [$issue->getBestIssueId()]);
            $ld = ['@context' => 'https://schema.org', '@type' => 'PublicationIssue', 'name' => $label, 'url' => $url, 'isPartOf' => ['@type' => 'Periodical', 'name' => $name, 'url' => $home]];
            if ($issue->getNumber()) {
                $ld['issueNumber'] = (string) $issue->getNumber();
            }
            if ($issue->getDatePublished()) {
                $ld['datePublished'] = date('Y-m-d', strtotime($issue->getDatePublished()));
            }
            if ($issn) {
                $ld['isPartOf']['issn'] = $issn;
            }
        } elseif ($page === 'index' || $page === '' || $page === $context->getPath()) {
            $desc = $siteDescription;
            $ld = ['@context' => 'https://schema.org', '@graph' => [
                array_filter(['@type' => 'Periodical', '@id' => $home . '#journal', 'name' => $name, 'url' => $home, 'description' => $siteDescription ?: null, 'issn' => $issn ?: null, 'inLanguage' => $locale, 'isAccessibleForFree' => true, 'logo' => $logo]),
                ['@type' => 'WebSite', 'name' => $name, 'url' => $home, 'inLanguage' => $locale, 'potentialAction' => ['@type' => 'SearchAction', 'target' => $request->getDispatcher()->url($request, Application::ROUTE_PAGE, $context->getPath(), 'search', 'search') . '?query={search_term_string}', 'query-input' => 'required name=search_term_string']],
            ]];
        }

        $h = '<link rel="canonical" href="' . self::e($url) . '"/>' . "\n";
        if ($desc !== '') {
            $h .= self::meta('description', $desc);
        }
        if ($keywords) {
            $h .= self::meta('keywords', implode(', ', $keywords));
        }
        $h .= self::meta('og:site_name', $name, 'property') . self::meta('og:type', $type, 'property') . self::meta('og:title', $title, 'property')
            . self::meta('og:url', $url, 'property') . self::meta('og:locale', str_replace('-', '_', $locale), 'property')
            . self::meta('og:image', $image, 'property');
        if ($desc !== '') {
            $h .= self::meta('og:description', $desc, 'property');
        }
        $h .= self::meta('twitter:card', 'summary') . self::meta('twitter:title', $title) . self::meta('twitter:image', $image);
        if ($desc !== '') {
            $h .= self::meta('twitter:description', $desc);
        }
        $h .= $extra;
        if ($ld) {
            // JSON_HEX_* keeps a "</script>" or "&" inside a title from ending the tag or being read as markup
            $h .= '<script type="application/ld+json">' . json_encode($ld, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE | JSON_HEX_TAG | JSON_HEX_AMP | JSON_HEX_APOS | JSON_HEX_QUOT) . "</script>\n";
        }
        $tm->addHeader('worjSeo', $h, ['contexts' => ['frontend']]);
    }

    protected static function canonical($request): string
    {
        $u = (string) $request->getCompleteUrl();
        $u = preg_replace('/[?#].*$/', '', $u);
        return rtrim($u, '/') === rtrim((string) $request->getBaseUrl(), '/') ? $u : rtrim($u, '/');
    }

    protected static function issn($context): string
    {
        foreach (['onlineIssn', 'printIssn'] as $k) {
            $v = trim((string) $context->getData($k));
            if ($v !== '' && stripos($v, 'PLACEHOLDER') === false) {
                return $v;
            }
        }
        return '';
    }

    protected static function meta(string $name, string $content, string $attr = 'name'): string
    {
        return $content === '' ? '' : '<meta ' . $attr . '="' . self::e($name) . '" content="' . self::e($content) . '"/>' . "\n";
    }

    protected static function e(string $s): string
    {
        return htmlspecialchars($s, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
    }

    protected static function plain(string $s): string
    {
        return trim(preg_replace('/\s+/u', ' ', html_entity_decode(strip_tags($s), ENT_QUOTES | ENT_HTML5, 'UTF-8')));
    }

    protected static function trim(string $s, int $max): string
    {
        if (mb_strlen($s) <= $max) {
            return $s;
        }
        $cut = mb_substr($s, 0, $max);
        $sp = mb_strrpos($cut, ' ');
        return rtrim(mb_substr($cut, 0, $sp !== false && $sp > $max * 0.6 ? $sp : $max), " ,;:.-") . '…';
    }
}
