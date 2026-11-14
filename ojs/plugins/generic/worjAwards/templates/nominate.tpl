{include file="frontend/components/header.tpl" pageTitleTranslated=$worjPageTitle}
<div class="page worj-awards">
	<h1>Nominate for a Research Award</h1>
	{if $done}
		<p role="status"><strong>Thank you.</strong> Your nomination was received. A confirmation has been emailed to you; please check your spam folder if it does not arrive.</p>
	{elseif !$open}
		<p>Nominations are not open at the moment.</p>
	{else}
		{if $errors|@count}
			<div role="alert" class="worj-register-note"><p>Please fix the following:</p><ul>{foreach from=$errors item=e}<li>{$e|escape}</li>{/foreach}</ul></div>
		{/if}
		<form method="post" action="{url page="awards-nominate"}">
			{csrf}
			<p><label for="category">Category (required)</label><br>
			<select id="category" name="category" required>
				<option value="">Choose</option>
				{foreach from=$cats item=c}<option value="{$c|escape}"{if $f.category == $c} selected{/if}>{$c|escape}</option>{/foreach}
			</select></p>
			<p><label for="nominee_name">Nominee's full name (required)</label><br><input id="nominee_name" name="nominee_name" type="text" maxlength="255" required value="{$f.nominee_name|escape}"></p>
			<p><label for="nominee_email">Nominee's email address (optional)</label><br><input id="nominee_email" name="nominee_email" type="email" maxlength="255" value="{$f.nominee_email|escape}"></p>
			<p><label for="article_ref">The article, with its web address or DOI (optional)</label><br><input id="article_ref" name="article_ref" type="text" maxlength="500" value="{$f.article_ref|escape}"></p>
			<p><label for="statement">Why this person? (required, 50 to 3000 characters)</label><br><textarea id="statement" name="statement" rows="8" cols="60" minlength="50" maxlength="3000" required>{$f.statement|escape}</textarea></p>
			<p><label for="nominator_name">Your name (required)</label><br><input id="nominator_name" name="nominator_name" type="text" maxlength="255" required value="{$f.nominator_name|escape}"></p>
			<p><label for="nominator_email">Your email address (required)</label><br><input id="nominator_email" name="nominator_email" type="email" maxlength="255" required value="{$f.nominator_email|escape}"></p>
			<p style="position:absolute;left:-9999px" aria-hidden="true"><label for="website">Leave this empty</label><input id="website" name="website" type="text" tabindex="-1" autocomplete="off"></p>
			<p><label><input type="checkbox" name="consent" value="1" required> I agree that the journal may use these details to consider the nomination and to email me about it.</label></p>
			<p><button type="submit" class="pkp_button">Send nomination</button></p>
		</form>
	{/if}
</div>
{include file="frontend/components/footer.tpl"}
