/* Lyveira site — tiny vanilla interactions, no dependencies. */
(function () {
  'use strict';

  // ── Scroll reveal ──────────────────────────────────────────────────────────
  var revealEls = document.querySelectorAll('.reveal');
  if ('IntersectionObserver' in window && revealEls.length) {
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (e) {
        if (e.isIntersecting) { e.target.classList.add('in'); io.unobserve(e.target); }
      });
    }, { threshold: 0.12, rootMargin: '0px 0px -8% 0px' });
    revealEls.forEach(function (el) { io.observe(el); });
  } else {
    revealEls.forEach(function (el) { el.classList.add('in'); });
  }

  // ── Mobile nav toggle ──────────────────────────────────────────────────────
  var toggle = document.querySelector('.nav-toggle');
  var links = document.querySelector('.nav-links');
  if (toggle && links) {
    toggle.addEventListener('click', function () {
      links.classList.toggle('open');
      toggle.setAttribute('aria-expanded', links.classList.contains('open'));
    });
    links.querySelectorAll('a').forEach(function (a) {
      a.addEventListener('click', function () { links.classList.remove('open'); });
    });
  }

  // ── Phone screen carousel ──────────────────────────────────────────────────
  var slides = document.querySelectorAll('.screen .slide');
  var dots = document.querySelectorAll('.dots b');
  if (slides.length > 1) {
    var i = 0;
    setInterval(function () {
      slides[i].classList.remove('on');
      if (dots[i]) dots[i].classList.remove('on');
      i = (i + 1) % slides.length;
      slides[i].classList.add('on');
      if (dots[i]) dots[i].classList.add('on');
    }, 3200);
  }

  // ── Breathing cue text ─────────────────────────────────────────────────────
  var breath = document.querySelector('.breath-circle');
  if (breath) {
    var phases = ['Breathe in', 'Hold', 'Breathe out', 'Hold'];
    var p = 0;
    breath.textContent = phases[0];
    setInterval(function () { p = (p + 1) % phases.length; breath.textContent = phases[p]; }, 2000);
  }

  // ── Start page: pass a known choice through to the app ──────────────────
  // /start/?c=<choice>. Only a choice from this closed set is passed on, and the
  // app holds the same set (dwasi-app src/utils/startLink.ts) and the words for
  // each: a link carries no text. Anything else opens the app with no choice.
  var openApp = document.querySelector('[data-open-app]');
  if (openApp) {
    var CHOICES = ['habit', 'sleep', 'friend'];
    var choice = new URLSearchParams(window.location.search).get('c');
    if (CHOICES.indexOf(choice) !== -1) {
      openApp.setAttribute('href', 'lyveira:///start?c=' + choice);
    }
  }

  // ── Footer year ────────────────────────────────────────────────────────────
  var y = document.querySelector('[data-year]');
  if (y) y.textContent = '2026';
})();
