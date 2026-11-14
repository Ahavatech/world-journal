<?php

/**
 * @file plugins/generic/worjAwards/WorjAwardsPlugin.php
 *
 * @brief Research Awards for World Open Research Journal: a nomination form, judges' scoring, a manager page and a public list of recipients.
 * Four pages, no JavaScript: /awards-nominate, /awards-judge, /awards-manage, /awards-recipients.
 */

namespace APP\plugins\generic\worjAwards;

use Illuminate\Database\Migrations\Migration;
use PKP\plugins\GenericPlugin;
use PKP\plugins\Hook;

class WorjAwardsPlugin extends GenericPlugin
{
    public const PAGES = ['awards-nominate', 'awards-judge', 'awards-manage', 'awards-recipients'];

    public function register($category, $path, $mainContextId = null)
    {
        $success = parent::register($category, $path, $mainContextId);
        if ($success && $this->getEnabled($mainContextId)) {
            Hook::add('LoadHandler', function ($hookName, $args) {
                $page = &$args[0];
                $handler = &$args[3];
                if (in_array($page, self::PAGES, true)) {
                    $handler = new WorjAwardsHandler($this, $page);
                    return true;
                }
                return false;
            });
        }
        return $success;
    }

    public function getDisplayName()
    {
        return __('plugins.generic.worjAwards.displayName');
    }

    public function getDescription()
    {
        return __('plugins.generic.worjAwards.description');
    }

    public function getInstallMigration(): Migration
    {
        return new WorjAwardsMigration();
    }

}
