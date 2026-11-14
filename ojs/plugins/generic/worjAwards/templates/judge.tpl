{include file="frontend/components/header.tpl" pageTitleTranslated=$worjPageTitle}
<div class="page worj-awards">
	<h1>Judging</h1>
	<p>Score each nomination from 1 (lowest) to 5 (highest) on the four criteria. Tick the conflict box if you know the nominee or have an interest: your score for it is then left out. You can come back and change a score until the manager decides.</p>
	{if $msg}<p role="status"><strong>{$msg|escape}</strong></p>{/if}
	{foreach from=$items item=it}
		<form method="post" action="{url page="awards-judge"}" class="worj-award-item">
			{csrf}
			<input type="hidden" name="nomination_id" value="{$it.n->nomination_id|escape}">
			<h2>{$it.n->nominee_name|escape} <small>({$it.n->category|escape})</small></h2>
			{if $it.n->article_ref}<p>Article: {$it.n->article_ref|escape}</p>{/if}
			<blockquote>{$it.n->statement|escape|nl2br}</blockquote>
			<fieldset><legend>Your scores{if $it.s} (saved){/if}</legend>
			{foreach from=$criteria key=k item=label}
				<p><label for="{$k}-{$it.n->nomination_id}">{$label}</label>
				<select id="{$k}-{$it.n->nomination_id}" name="{$k}">
					<option value="">-</option>
					{section name=i start=1 loop=6}<option value="{$smarty.section.i.index}"{if $it.s && $it.s->$k == $smarty.section.i.index} selected{/if}>{$smarty.section.i.index}</option>{/section}
				</select></p>
			{/foreach}
			<p><label for="comment-{$it.n->nomination_id}">Comment (only the manager sees it)</label><br><textarea id="comment-{$it.n->nomination_id}" name="comment" rows="3" cols="60" maxlength="2000">{if $it.s}{$it.s->comment|escape}{/if}</textarea></p>
			<p><label><input type="checkbox" name="conflict" value="1"{if $it.s && $it.s->conflict} checked{/if}> I have a conflict of interest with this nominee</label></p>
			<p><button type="submit" class="pkp_button">Save scores</button></p>
			</fieldset>
		</form>
	{foreachelse}
		<p>There is nothing to score at the moment.</p>
	{/foreach}
</div>
{include file="frontend/components/footer.tpl"}
