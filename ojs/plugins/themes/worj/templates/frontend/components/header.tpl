{**
 * templates/frontend/components/header.tpl (worj theme)
 *
 * Overrides lib/pkp/templates/frontend/components/header.tpl.
 * Only the visible banner and navigation markup differs from core. The
 * <head> include (headerHead.tpl, which emits the citation_* metadata) and
 * the content wrapper are unchanged.
 *
 * @uses $isFullWidth bool Should this page be displayed without sidebars?
 *}
{strip}
	{assign var="showingLogo" value=true}
	{if !$displayPageHeaderLogo}
		{assign var="showingLogo" value=false}
	{/if}
{/strip}
<!DOCTYPE html>
<html lang="{$currentLocale|replace:"_":"-"}" xml:lang="{$currentLocale|replace:"_":"-"}">
{if !$pageTitleTranslated}{capture assign="pageTitleTranslated"}{translate key=$pageTitle}{/capture}{/if}
{include file="frontend/components/headerHead.tpl"}
<body class="pkp_page_{$requestedPage|escape|default:"index"} pkp_op_{$requestedOp|escape|default:"index"}{if $showingLogo} has_site_logo{/if}" dir="{$currentLocaleLangDir|escape|default:"ltr"}">

	<div class="pkp_structure_page">

		{* Header *}
		<header class="worj-header" id="headerNavigationContainer">
			{include file="frontend/components/skipLinks.tpl"}

			<div class="worj-header__brand">
				<div class="worj-header__inner">
					{if !$requestedPage || $requestedPage === 'index'}
						<h1 class="pkp_screen_reader">
							{if $currentContext}{$displayPageHeaderTitle|escape}{else}{$siteTitle|escape}{/if}
						</h1>
					{/if}
					{capture assign="homeUrl"}{url page="index" router=PKP\core\PKPApplication::ROUTE_PAGE}{/capture}
					{if $displayPageHeaderLogo}
						<a href="{$homeUrl}" class="worj-logo">
							<img src="{$publicFilesDir}/{$displayPageHeaderLogo.uploadName|escape:"url"}" width="{$displayPageHeaderLogo.width|escape}" height="{$displayPageHeaderLogo.height|escape}" alt="{if $displayPageHeaderLogo.altText != ''}{$displayPageHeaderLogo.altText|escape}{else}{$displayPageHeaderTitle|escape}{/if}">
						</a>
					{else}
						<a href="{$homeUrl}" class="worj-logo">
							<img src="{$baseUrl}/plugins/themes/worj/assets/img/logo-header.jpg" width="760" height="318" alt="{if $displayPageHeaderTitle}{$displayPageHeaderTitle|escape}{else}{$siteTitle|escape}{/if}">
						</a>
					{/if}

					{* Account links (Register, Login, or the user menu) *}
					<nav class="worj-user" aria-label="{translate|escape key="common.navigation.user"}">
						{load_menu name="user" id="navigationUser" ulClass="worj-user-list" liClass="profile"}
					</nav>
				</div>
			</div>

			<div class="worj-header__navbar">
				<div class="worj-header__inner">
					{* The toggle is hidden until nav.js runs: without JavaScript the
					   menu is simply always visible. *}
					<button type="button" class="worj-nav-toggle" aria-expanded="false" aria-controls="worj-nav-panel" hidden>
						<span class="worj-nav-toggle__label">{translate key="plugins.themes.worj.menu"}</span>
					</button>

					<nav class="worj-nav" id="worj-nav-panel" aria-label="{translate|escape key="common.navigation.site"}">
						<a id="siteNav"></a>
						{load_menu name="primary" id="navigationPrimary" ulClass="worj-primary-list"}
						{if $currentContext && $requestedPage !== 'search'}
							<a href="{url page="search"}" class="worj-search-link">
								<span class="fa fa-search" aria-hidden="true"></span>
								{translate key="common.search"}
							</a>
						{/if}
					</nav>
				</div>
			</div>
		</header><!-- .worj-header -->

		{* Wrapper for page content and sidebars *}
		{if $isFullWidth}
			{assign var=hasSidebar value=0}
		{/if}
		<div class="pkp_structure_content{if $hasSidebar} has_sidebar{/if}">
			<main class="pkp_structure_main">
				<a id="pkp_content_main"></a>
