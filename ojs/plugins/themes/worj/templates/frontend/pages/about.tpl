{**
 * templates/frontend/pages/about.tpl (worj theme)
 *
 * Overrides lib/pkp/templates/frontend/pages/about.tpl. Same output as core,
 * plus a visible placeholder when the journal's About text is not set yet.
 *}
{include file="frontend/components/header.tpl" pageTitle="about.aboutContext"}

<div class="page page_about">
	{include file="frontend/components/breadcrumbs.tpl" currentTitleKey="about.aboutContext"}
	<h1>
		{translate key="about.aboutContext"}
	</h1>
	{include file="frontend/components/editLink.tpl" page="management" op="settings" path="context" anchor="masthead" sectionTitleKey="about.aboutContext"}

	{if $currentContext->getLocalizedData('about')}
		{$currentContext->getLocalizedData('about')}
	{else}
		<p><span class="worj-placeholder">[PLACEHOLDER: About the Journal text, client to supply]</span></p>
	{/if}
</div><!-- .page -->

{include file="frontend/components/footer.tpl"}
