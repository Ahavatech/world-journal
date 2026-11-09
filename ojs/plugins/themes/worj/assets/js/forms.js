/* Registration form behaviour and chart colours. Replaces the parent theme's
   main.js, whose last statement initialises Swiper unconditionally and throws
   when Swiper is not loaded (this theme does not load it). The behaviour is
   the same, in plain JavaScript. The forms still work without this file: the
   fields are only shown or hidden by it. */
(function () {
  'use strict';

  // Chart.js colours used by the UsageStats plugin
  document.addEventListener('usageStatsChartOptions.pkp', function (e) {
    var colour = 'rgba(2, 39, 96, 0.6)';
    e.chartOptions.elements.line.backgroundColor = colour;
    e.chartOptions.elements.bar.backgroundColor = colour;
  });

  // Site-wide registration: show the consent text when a role is ticked
  var optin = document.getElementById('contextOptinGroup');
  if (optin) {
    optin.addEventListener('change', function (event) {
      var roles = event.target.closest ? event.target.closest('.roles') : null;
      if (!roles || !roles.contains(event.target) || event.target.type !== 'checkbox') {
        return;
      }
      var privacy = roles.parentNode.querySelectorAll('.context_privacy');
      var anyChecked = roles.querySelector('input:checked') !== null;
      Array.prototype.forEach.call(privacy, function (el) {
        el.classList.toggle('context_privacy_visible', anyChecked);
      });
    });
  }

  // Show the reviewer interests field when the user opts in as a reviewer
  var reviewerGroup = document.getElementById('reviewerOptinGroup');
  var interests = document.getElementById('reviewerInterests');
  if (reviewerGroup && interests) {
    var toggle = function () {
      interests.classList.toggle('is_visible', reviewerGroup.querySelector('input:checked') !== null);
    };
    reviewerGroup.addEventListener('click', toggle);
    toggle();
  }
}());
