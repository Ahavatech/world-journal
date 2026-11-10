{**
 * templates/frontend/components/breadcrumbs.tpl (worj theme)
 *
 * Overrides lib/pkp/templates/frontend/components/breadcrumbs.tpl: the nav
 * gets an accessible name (the translated core key navigation.breadcrumbLabel,
 * which the article and issue breadcrumbs already use) and the current page is
 * marked aria-current="page".
 *
 * @uses $currentTitle string The title to use for the current page.
 * @uses $currentTitleKey string Translation key for title of current page.
 *}
<nav class="cmp_breadcrumbs" aria-label="{translate|escape key="navigation.breadcrumbLabel"}">
	<ol>
		<li>
			<a href="{url page="index" router=PKP\core\PKPApplication::ROUTE_PAGE}">
				{translate key="common.homepageNavigationLabel"}
			</a>
			<span class="separator">{translate key="navigation.breadcrumbSeparator"}</span>
		</li>
		<li class="current" aria-current="page">
			<span aria-current="page">
				{if $currentTitleKey}
					{translate key=$currentTitleKey}
				{else}
					{$currentTitle|escape}
				{/if}
			</span>
		</li>
	</ol>
</nav>
