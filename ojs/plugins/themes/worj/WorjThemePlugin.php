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
        foreach (['fonts', 'tokens', 'base', 'layout', 'components', 'pages', 'article'] as $name) {
            $this->addStyle('worj-' . $name, 'assets/css/' . $name . '.css');
        }

        // The parent's slider and Bootstrap dropdown scripts only serve its
        // JavaScript menu and the homepage highlights slider, which this theme
        // does not use. main.js stays: it also drives the registration form.
        foreach (['popper', 'bsUtil', 'bsDropdown', 'swiper', 'swiper-i18n'] as $name) {
            $this->removeScript($name);
        }
        $this->removeStyle('swiper');

        $this->addScript('worj-nav', 'assets/js/nav.js');

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
