<?php

/**
 * @file plugins/themes/worj/WorjThemePlugin.php
 *
 * @class WorjThemePlugin
 *
 * @brief Child theme of the OJS default theme for World Open Research Journal.
 *        Extends the parent: it adds styles and overrides a few templates and
 *        never edits anything under ojs-core/.
 */

namespace APP\plugins\themes\worj;

class WorjThemePlugin extends \PKP\plugins\ThemePlugin
{
    /**
     * Initialize the theme. Runs on the active theme and is where the parent
     * theme is declared. The parent's init() loads its own styles, scripts
     * and menu areas.
     */
    public function init()
    {
        $this->setParent('defaultthemeplugin');

        // The parent's own typeface stylesheet is replaced by ours (fonts.css).
        $this->removeStyle('font');

        // Plain CSS, added after the parent's styles so it overrides them.
        foreach (['fonts', 'tokens', 'base', 'layout', 'components', 'pages', 'article', 'forms'] as $name) {
            $this->addStyle('worj-' . $name, 'assets/css/' . $name . '.css');
        }

        // The parent's slider, Bootstrap dropdown and main.js only serve its
        // JavaScript menu and the homepage highlights slider, which this theme
        // does not use. main.js also runs `new Swiper()` unconditionally, which
        // throws without Swiper, so it is replaced by forms.js (the registration
        // form behaviour and chart colours, in plain JavaScript).
        foreach (['popper', 'bsUtil', 'bsDropdown', 'swiper', 'swiper-i18n', 'default'] as $name) {
            $this->removeScript($name);
        }
        $this->removeStyle('swiper');

        // The registration page tells people to look in their spam folder when email validation is on.
        \PKP\plugins\Hook::add('TemplateManager::display', function ($hookName, $args) {
            $args[0]->assign('worjRequireValidation', (bool) \PKP\config\Config::getVar('email', 'require_validation'));
            // A welcome box with the first-login steps, for people who signed in within their first 14 days. No state is stored.
            $user = \APP\core\Application::get()->getRequest()->getUser();
            $welcome = '';
            if ($user && $user->getDateRegistered() && strtotime($user->getDateRegistered()) > time() - 14 * 86400) {
                $context = \APP\core\Application::get()->getRequest()->getContext();
                $editorial = $context && $user->hasRole([\PKP\security\Role::ROLE_ID_MANAGER, \PKP\security\Role::ROLE_ID_SUB_EDITOR], $context->getId());
                $welcome = $editorial ? 'editorial' : 'member';
            }
            $args[0]->assign('worjWelcome', $welcome);
            return \PKP\plugins\Hook::CONTINUE;
        });

        $this->addScript('worj-nav', 'assets/js/nav.js');
        $this->addScript('worj-forms', 'assets/js/forms.js');

        // Parent options that do nothing here: this theme replaces the parent's
        // typeface and colour styles and its homepage. Controls that do nothing
        // mislead whoever administers the site. displayStats stays: the parent's
        // article template still reads it.
        foreach (['typography', 'baseColour', 'showDescriptionInJournalIndex', 'useHomepageImageAsHeader'] as $option) {
            $this->removeOption($option);
        }

        // Off by default: the Awards page is built in a later phase, and a card
        // that links to a missing page must not ship. Turn on once /awards exists.
        $this->addOption('showAwardsCard', 'FieldOptions', [
            'label' => __('plugins.themes.worj.option.showAwardsCard.label'),
            'description' => __('plugins.themes.worj.option.showAwardsCard.description'),
            'options' => [
                [
                    'value' => true,
                    'label' => __('plugins.themes.worj.option.showAwardsCard.option'),
                ],
            ],
            'default' => false,
        ]);

        // Off by default: while a journal has no ISSN the footer prints a visible placeholder (the launch gate
        // must stay red). A journal that launches WITHOUT an ISSN turns this on and the ISSN line is left out
        // until one is entered. Never prints an invented number.
        $this->addOption('omitIssnLine', 'FieldOptions', [
            'label' => __('plugins.themes.worj.option.omitIssnLine.label'),
            'description' => __('plugins.themes.worj.option.omitIssnLine.description'),
            'options' => [
                [
                    'value' => true,
                    'label' => __('plugins.themes.worj.option.omitIssnLine.option'),
                ],
            ],
            'default' => false,
        ]);

        // Same idea for the publisher line: off by default; a journal whose publisher is not stated turns it on and the
        // line is left out until a publisher name is entered in the journal settings. Never prints an invented name.
        $this->addOption('omitPublisherLine', 'FieldOptions', [
            'label' => __('plugins.themes.worj.option.omitPublisherLine.label'),
            'description' => __('plugins.themes.worj.option.omitPublisherLine.description'),
            'options' => [
                [
                    'value' => true,
                    'label' => __('plugins.themes.worj.option.omitPublisherLine.option'),
                ],
            ],
            'default' => false,
        ]);
    }

    /**
     * Settings file installed when a journal is created.
     */
    public function getContextSpecificPluginSettingsFile()
    {
        return $this->getPluginPath() . '/settings.xml';
    }

    /**
     * Settings file installed site-wide when OJS is installed.
     */
    public function getInstallSitePluginSettingsFile()
    {
        return $this->getPluginPath() . '/settings.xml';
    }

    /**
     * @copydoc Plugin::getDisplayName()
     */
    public function getDisplayName()
    {
        return __('plugins.themes.worj.name');
    }

    /**
     * @copydoc Plugin::getDescription()
     */
    public function getDescription()
    {
        return __('plugins.themes.worj.description');
    }
}
