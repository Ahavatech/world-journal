{include file="frontend/components/header.tpl" pageTitleTranslated=$worjPageTitle}
<div class="page worj-awards">
	<h1>Research Awards: recipients</h1>
	{if $winners|@count}
		<ul>
		{foreach from=$winners item=w}
			<li><strong>{$w->nominee_name|escape}</strong>, {$w->category|escape}{if $w->award_period} ({$w->award_period|escape}){/if}{if $w->article_ref}. {$w->article_ref|escape}{/if}</li>
		{/foreach}
		</ul>
	{else}
		<p>No recipients have been announced yet.</p>
	{/if}
</div>
{include file="frontend/components/footer.tpl"}
