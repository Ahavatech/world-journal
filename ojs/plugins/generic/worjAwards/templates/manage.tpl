{include file="frontend/components/header.tpl" pageTitleTranslated=$worjPageTitle}
<div class="page worj-awards">
	<h1>Research Awards: manager</h1>
	{if $msg}<p role="status"><strong>{$msg|escape}</strong></p>{/if}
	<h2>Settings</h2>
	<form method="post" action="{url page="awards-manage"}">
		{csrf}<input type="hidden" name="action" value="settings">
		<p><label><input type="checkbox" name="nominationsOpen" value="1"{if $open} checked{/if}> Nominations are open</label></p>
		<p><label for="categories">Categories (one per line)</label><br><textarea id="categories" name="categories" rows="4" cols="50">{$categoriesText|escape}</textarea></p>
		<p><label for="judges">Judges: usernames, one per line (each must already have an account)</label><br><textarea id="judges" name="judges" rows="4" cols="50">{$judgesText|escape}</textarea></p>
		<p><button type="submit" class="pkp_button">Save settings</button></p>
	</form>
	<h2>Nominations</h2>
	<p><a href="{url page="awards-manage" escape=false}?export=csv">Download all as a spreadsheet (CSV)</a>. It contains email addresses: keep it private.</p>
	{foreach from=$rows item=r}
		<form method="post" action="{url page="awards-manage"}" class="worj-award-item">
			{csrf}<input type="hidden" name="action" value="status"><input type="hidden" name="nomination_id" value="{$r.n->nomination_id|escape}">
			<h3>{$r.n->nominee_name|escape} <small>({$r.n->category|escape})</small></h3>
			<p>Nominated by {$r.n->nominator_name|escape} ({$r.n->nominator_email|escape}) on {$r.n->created_at|escape}.{if $r.n->nominee_email} Nominee: {$r.n->nominee_email|escape}.{/if}{if $r.n->article_ref} Article: {$r.n->article_ref|escape}.{/if}</p>
			<blockquote>{$r.n->statement|escape|nl2br}</blockquote>
			<p>Judges who scored: {$r.judges}, conflicts declared: {$r.conflicts}. Mean total: {if $r.mean !== null}{$r.mean} of 20{else}not scored yet{/if}.</p>
			<p><label for="st-{$r.n->nomination_id}">Status</label>
			<select id="st-{$r.n->nomination_id}" name="status">{foreach from=$statuses key=k item=l}<option value="{$k}"{if $r.n->status == $k} selected{/if}>{$l}</option>{/foreach}</select>
			<label for="ap-{$r.n->nomination_id}">Period (for example Volume 1)</label>
			<input id="ap-{$r.n->nomination_id}" name="award_period" type="text" maxlength="100" value="{$r.n->award_period|escape}">
			<button type="submit" class="pkp_button">Update</button></p>
		</form>
		<form method="post" action="{url page="awards-manage"}">{csrf}<input type="hidden" name="action" value="delete"><input type="hidden" name="nomination_id" value="{$r.n->nomination_id|escape}"><button type="submit" class="pkp_button">Delete this nomination</button></form>
	{foreachelse}
		<p>No nominations yet.</p>
	{/foreach}
</div>
{include file="frontend/components/footer.tpl"}
