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

  // Server-side form errors: put focus on the message so it is announced, and
  // tie it to the fields it is about (aria-invalid + aria-describedby). Without
  // JavaScript the message is still on the page, in reading order, as text.
  var box = document.getElementById('formErrors') || document.querySelector('form .pkp_form_error');
  if (box) {
    if (!box.id) { box.id = 'worj-form-error'; }
    box.setAttribute('role', 'alert');
    box.setAttribute('tabindex', '-1');
    var describe = function (field) {
      if (!field) { return; }
      field.setAttribute('aria-invalid', 'true');
      var ids = (field.getAttribute('aria-describedby') || '').split(' ').filter(Boolean);
      if (ids.indexOf(box.id) === -1) { ids.push(box.id); }
      field.setAttribute('aria-describedby', ids.join(' '));
    };
    var links = box.querySelectorAll('a[href^="#"]');
    if (links.length) {
      // list of errors: each link points at its field
      Array.prototype.forEach.call(links, function (link) {
        var name = link.getAttribute('href').slice(1);
        describe(document.getElementById(name) || document.querySelector('[name="' + name + '"]'));
      });
    } else {
      // a single message (for example a failed login) is about the credential fields
      var form = box.closest('form');
      if (form) {
        Array.prototype.forEach.call(form.querySelectorAll('input[name=username], input[name=password]'), describe);
      }
    }
    box.focus();
  }
}());
