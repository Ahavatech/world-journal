{**
 * templates/common/formErrors.tpl (worj theme)
 *
 * Overrides lib/pkp/templates/common/formErrors.tpl. Same list of errors with
 * links to the fields, plus role="alert" and tabindex="-1" so forms.js can move
 * focus to it. The inline <script> that only scrolled to the errors is gone: it
 * would need a script-src exception in a strict Content-Security-Policy, and
 * forms.js now does the job (focus also scrolls).
 *}
{if $isError}
	<div id="formErrors" role="alert" tabindex="-1">
		<span class="pkp_form_error">{translate key="form.errorsOccurred"}:</span>
		<ul class="pkp_form_error_list">
		{foreach key=field item=message from=$errors}
			<li><a href="#{$field|escape}">{$message}</a></li>
		{/foreach}
		</ul>
	</div>
{/if}
