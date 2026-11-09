{**
 * templates/frontend/components/footer.tpl (worj theme)
 *
 * Overrides lib/pkp/templates/frontend/components/footer.tpl.
 * Closes <main> (opened in the worj header.tpl) and renders the footer from
 * journal settings. Anything the journal has not configured yet shows a
 * visible [PLACEHOLDER: ...] marker, so check-placeholders can find it and it
 * disappears once the real value is saved in OJS. Never invents a value.
 *
 * @hook Templates::Common::Sidebar []
 * @hook Templates::Common::Footer::PageFooter []
 *}

			</main><!-- pkp_structure_main -->

	{* Sidebars *}
	{if empty($isFullWidth)}
		{capture assign="sidebarCode"}{call_hook name="Templates::Common::Sidebar"}{/capture}
		{if $sidebarCode}
			<aside class="pkp_structure_sidebar left" aria-label="{translate|escape key="plugins.themes.worj.sidebar"}">
				{$sidebarCode}
			</aside><!-- pkp_sidebar.left -->
		{/if}
	{/if}
</div><!-- pkp_structure_content -->

<footer class="worj-footer" id="pkp_content_footer">
	<div class="worj-footer__inner">
		<div class="worj-footer__about">
			{if $currentContext}
				<p class="worj-footer__title">{$currentContext->getLocalizedData('name')|escape}</p>
				<p>
					{if $currentContext->getData('publisherInstitution')}
						{$currentContext->getData('publisherInstitution')|escape}
					{else}
						<span class="worj-placeholder">[PLACEHOLDER: publisher name]</span>
					{/if}
				</p>
				<p>
					{if $currentContext->getData('onlineIssn') || $currentContext->getData('printIssn')}
						{if $currentContext->getData('onlineIssn')}eISSN {$currentContext->getData('onlineIssn')|escape}{/if}
						{if $currentContext->getData('printIssn')}ISSN {$currentContext->getData('printIssn')|escape}{/if}
					{else}
						<span class="worj-placeholder">[PLACEHOLDER: ISSN, pending]</span>
					{/if}
				</p>
				<p>
					{if $currentContext->getData('licenseUrl')}
						<a href="{$currentContext->getData('licenseUrl')|escape}" rel="license">{translate key="submission.license"}</a>
					{else}
						<span class="worj-placeholder">[PLACEHOLDER: licence, e.g. CC BY 4.0, client to confirm]</span>
					{/if}
				</p>
			{/if}
		</div>

		<nav class="worj-footer__links" aria-label="{translate|escape key="plugins.themes.worj.footerNav"}">
			<ul>
				{if $currentContext}
					<li><a href="{url router=PKP\core\PKPApplication::ROUTE_PAGE page="about" op="contact"}">{translate key="about.contact"}</a></li>
					<li><a href="{url router=PKP\core\PKPApplication::ROUTE_PAGE page="about" op="privacy"}">{translate key="manager.setup.privacyStatement"}</a></li>
				{/if}
				<li><a href="{url router=PKP\core\PKPApplication::ROUTE_PAGE page="about" op="aboutThisPublishingSystem"}">{translate key="plugins.themes.worj.publishedWith"}</a></li>
			</ul>
		</nav>

		{if $pageFooter}
			<div class="pkp_footer_content worj-footer__custom">
				{$pageFooter}
			</div>
		{/if}
	</div>
</footer><!-- .worj-footer -->

</div><!-- pkp_structure_page -->

{load_script context="frontend"}

{call_hook name="Templates::Common::Footer::PageFooter"}
</body>
</html>
