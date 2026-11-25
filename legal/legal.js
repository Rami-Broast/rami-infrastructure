/**
 * Shared behaviour for the published legal pages.
 *
 * Two jobs, both of them about not shipping something misleading.
 *
 * 1. **Language.** Each page carries English and Arabic in one document, keyed
 *    off `data-en` / `data-ar`. A store listing carries one privacy URL, so a
 *    customer who lands on the wrong language must not have to go looking for
 *    the other. Anything that is not Arabic falls back to English rather than
 *    to an empty page.
 *
 * 2. **Blanks.** Facts that only the restaurant or its lawyer can supply are
 *    written in the source as `[[ LIKE THIS ]]`. This script highlights every
 *    one and puts a count in a banner across the top of the page. A privacy
 *    notice published with an unfilled party name is worse than an unpublished
 *    one: it is a document that looks binding and names nobody.
 */
(function () {
  var BLANK = /\[\[([^\]]+)\]\]/g;

  function escapeHtml(text) {
    return text
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;');
  }

  /**
   * Renders one string into an element, wrapping `[[ blanks ]]` in a chip.
   *
   * `innerHTML` is used only on text this file escaped a line earlier — the
   * source strings live in the same static document and never come from a
   * request — so there is nothing here an outside party can inject into.
   */
  function render(el, text) {
    if (text.indexOf('[[') === -1) {
      el.textContent = text;
      return 0;
    }
    var count = 0;
    el.innerHTML = escapeHtml(text).replace(BLANK, function (_match, inner) {
      count += 1;
      return '<span class="ph">' + inner.trim() + '</span>';
    });
    return count;
  }

  function apply(lang) {
    document.documentElement.lang = lang;
    document.documentElement.dir = lang === 'ar' ? 'rtl' : 'ltr';

    var blanks = 0;
    var nodes = document.querySelectorAll('[data-en]');
    for (var i = 0; i < nodes.length; i++) {
      var el = nodes[i];
      var text = el.getAttribute(lang === 'ar' ? 'data-ar' : 'data-en');
      blanks += render(el, text == null ? '' : text);
    }

    var buttons = document.querySelectorAll('.langs button');
    for (var j = 0; j < buttons.length; j++) {
      buttons[j].setAttribute('aria-pressed', String(buttons[j].dataset.lang === lang));
    }

    banner(blanks, lang);
  }

  function banner(count, lang) {
    var existing = document.querySelector('.blanks');
    if (existing) {
      existing.remove();
    }
    if (count === 0) {
      return;
    }
    var el = document.createElement('div');
    el.className = 'blanks';
    el.setAttribute('role', 'status');
    el.textContent =
      lang === 'ar'
        ? 'مسودة — ' + count + ' حقلًا لم يُملأ بعد. لا تنشر هذه الصفحة قبل استكمالها ومراجعتها قانونيًا.'
        : 'DRAFT — ' +
          count +
          ' field(s) still unfilled. Do not publish this page until they are completed and legally reviewed.';
    // Before `.wrap`, not inside it: full-bleed without negative margins, which
    // is what previously overflowed the page in RTL.
    document.body.insertBefore(el, document.body.firstChild);
  }

  var buttons = document.querySelectorAll('.langs button');
  for (var k = 0; k < buttons.length; k++) {
    buttons[k].addEventListener('click', function (event) {
      apply(event.currentTarget.dataset.lang);
    });
  }

  apply((navigator.language || 'en').slice(0, 2) === 'ar' ? 'ar' : 'en');
})();
