/* Progressive enhancement for the site menu. The menu works without this file:
   it is always visible and its dropdowns open with CSS (hover and focus-within).
   This adds a toggle button on small screens and Escape to close menus. */
(function () {
  'use strict';

  var toggle = document.querySelector('.worj-nav-toggle');
  var panel = document.getElementById('worj-nav-panel');
  if (!toggle || !panel) {
    return;
  }

  document.documentElement.classList.add('worj-js');
  toggle.hidden = false;

  function setOpen(open) {
    toggle.setAttribute('aria-expanded', open ? 'true' : 'false');
    panel.classList.toggle('is-open', open);
  }

  toggle.addEventListener('click', function () {
    setOpen(toggle.getAttribute('aria-expanded') !== 'true');
  });

  // Escape closes an open dropdown (focus-within alone would keep it open) or
  // the small-screen menu.
  document.addEventListener('keydown', function (event) {
    if (event.key !== 'Escape') {
      return;
    }
    var active = document.activeElement;
    var item = active && active.closest ? active.closest('.worj-nav > ul > li') : null;
    if (item && item.querySelector('ul')) {
      var link = item.querySelector(':scope > a');
      item.classList.add('worj-dismissed');
      if (link) {
        link.focus();
      }
      var reopen = function () {
        item.classList.remove('worj-dismissed');
        item.removeEventListener('focusout', reopen);
        item.removeEventListener('mouseleave', reopen);
      };
      item.addEventListener('focusout', reopen);
      item.addEventListener('mouseleave', reopen);
    } else if (toggle.getAttribute('aria-expanded') === 'true') {
      setOpen(false);
      toggle.focus();
    }
  });
}());
