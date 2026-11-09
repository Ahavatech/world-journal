{**
 * templates/frontend/pages/indexJournal.tpl (worj theme)
 *
 * Overrides templates/frontend/pages/indexJournal.tpl.
 * Homepage per docs/01-SPEC.md section 5: hero, About block, latest
 * announcements, Research Awards call-out, current issue preview. Anything
 * the journal has not configured shows a visible [PLACEHOLDER: ...] marker.
 * Homepage highlights (the parent's slider) are not rendered by this theme.
 *
 * @uses $currentJournal Journal This journal
 * @uses $announcements array List of announcements
 * @uses $numAnnouncementsHomepage int Number of announcements to display
 * @uses $issue Issue Current issue
 *
 * @hook Templates::Index::journal []
 *}
{include file="frontend/components/header.tpl" pageTitleTranslated=$currentJournal->getLocalizedName()}

<div class="page_index_journal worj-home">

	{call_hook name="Templates::Index::journal"}

	{* Hero *}
	<section class="worj-hero" aria-labelledby="worj-hero-title">
		<img class="worj-hero__logo" src="{$baseUrl}/plugins/themes/worj/assets/img/logo-lockup.jpg" width="900" height="415" alt="">
		<div class="worj-hero__text">
			<p class="worj-hero__name" id="worj-hero-title">{$currentJournal->getLocalizedName()|escape}</p>
			<p class="worj-hero__tagline"><span class="worj-placeholder">[PLACEHOLDER: tagline]</span></p>
			<p class="worj-hero__actions">
				<a class="worj-button worj-button--primary" href="{url router=PKP\core\PKPApplication::ROUTE_PAGE page="about" op="submissions"}">{translate key="plugins.themes.worj.makeSubmission"}</a>
				<a class="worj-button" href="{url router=PKP\core\PKPApplication::ROUTE_PAGE page="issue" op="current"}">{translate key="plugins.themes.worj.currentIssue"}</a>
			</p>
		</div>
	</section>

	{* About *}
	<section class="worj-home__about" id="homepageAbout">
		<h2>{translate key="about.aboutContext"}</h2>
		{if $currentContext->getLocalizedData('description')}
			{$currentContext->getLocalizedData('description')}
		{else}
			<p><span class="worj-placeholder">[PLACEHOLDER: short description of the journal, aims and scope]</span></p>
		{/if}
		<p><a class="read_more" href="{url router=PKP\core\PKPApplication::ROUTE_PAGE page="about"}">{translate key="plugins.themes.worj.aboutMore"}</a></p>
	</section>

	{* Latest announcements (the count is a journal setting; the spec asks for 3).
	   Own markup instead of the parent's announcements_list.tpl, which carries a
	   float layout. #homepageAnnouncements is the skip-link target. *}
	{if $numAnnouncementsHomepage && $announcements|@count}
		<section class="worj-announcements" id="homepageAnnouncements" aria-labelledby="worj-announcements-title">
			<h2 id="worj-announcements-title">{translate key="announcement.announcements"}</h2>
			<ul class="worj-announcements__list">
				{foreach name=announcements from=$announcements item=announcement}
					{if $smarty.foreach.announcements.iteration > $numAnnouncementsHomepage}
						{break}
					{/if}
					<li class="worj-announcement">
						<h3><a href="{url router=PKP\core\PKPApplication::ROUTE_PAGE page="announcement" op="view" path=$announcement->id}">{$announcement->getLocalizedData('title')|escape}</a></h3>
						<p class="worj-announcement__date">{$announcement->datePosted->format($dateFormatShort)}</p>
						<div class="worj-announcement__summary">{$announcement->getLocalizedData('descriptionShort')|strip_unsafe_html}</div>
					</li>
				{/foreach}
			</ul>
		</section>
	{/if}

	{* Research Awards call-out. Theme option showAwardsCard, off by default: the
	   Awards page is Phase 3.4 content and the card must not link to a 404. *}
	{if $activeTheme && $activeTheme->getOption('showAwardsCard')}
		<aside class="worj-card worj-awards" aria-labelledby="worj-awards-title">
			<h2 id="worj-awards-title">{translate key="plugins.themes.worj.awardsTitle"}</h2>
			<p><span class="worj-placeholder">[PLACEHOLDER: awards call-out text]</span></p>
			<p><a class="worj-button" href="{url router=PKP\core\PKPApplication::ROUTE_PAGE page="awards"}">{translate key="plugins.themes.worj.awardsLink"}</a></p>
		</aside>
	{/if}

	{* Current issue preview *}
	{if $issue}
		<section class="current_issue worj-issue-preview">
			<a id="homepageIssue"></a>
			<h2>{translate key="journal.currentIssue"}</h2>
			<div class="worj-issue-preview__grid">
				<div class="worj-issue-preview__cover">
					{assign var=issueCover value=$issue->getLocalizedCoverImageUrl()}
					{if $issueCover}
						<img src="{$issueCover|escape}" alt="{$issue->getLocalizedCoverImageAltText()|escape|default:''}">
					{else}
						<div class="worj-cover-placeholder"><span class="worj-placeholder">[PLACEHOLDER: issue cover]</span></div>
					{/if}
				</div>
				<div class="worj-issue-preview__body">
					<p class="current_issue_title">{$issue->getIssueIdentification()|escape}</p>
					{include file="frontend/objects/issue_toc.tpl" heading="h3"}
					<p><a href="{url router=PKP\core\PKPApplication::ROUTE_PAGE page="issue" op="archive"}" class="read_more">{translate key="journal.viewAllIssues"}</a></p>
				</div>
			</div>
		</section>
	{/if}

	{* Additional homepage content from the journal settings *}
	{if $additionalHomeContent}
		<div class="additional_content">
			{$additionalHomeContent}
		</div>
	{/if}
</div><!-- .page -->

{include file="frontend/components/footer.tpl"}
