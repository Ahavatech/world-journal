{**
 * templates/frontend/components/breadcrumbs_announcement.tpl (worj theme)
 *
 * Overrides lib/pkp/templates/frontend/components/breadcrumbs_announcement.tpl
 * to add an accessible name to the nav (translated core key
 * navigation.breadcrumbLabel) and aria-current on the current item.
 *
 * @uses $currentTitle string The title to use for the current page.
 *}
<nav class="cmp_breadcrumbs cmp_breadcrumbs_announcement" aria-label="{translate|escape key="navigation.breadcrumbLabel"}">
	<ol>
		<li>
			<a href="{url page="index" router=PKP\core\PKPApplication::ROUTE_PAGE}">
				{translate key="common.homepageNavigationLabel"}
			</a>
			<span class="separator">{translate key="navigation.breadcrumbSeparator"}</span>
		</li>
		<li>
			<a href="{url page="announcement" router=PKP\core\PKPApplication::ROUTE_PAGE}">
				{translate key="announcement.announcements"}
			</a>
			<span class="separator">{translate key="navigation.breadcrumbSeparator"}</span>
		</li>
		<li class="current" aria-current="page">
			<span aria-current="page">{$currentTitle|escape}</span>
		</li>
	</ol>
</nav>
