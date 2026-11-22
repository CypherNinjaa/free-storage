import gsap from 'gsap';
import { ScrollTrigger } from 'gsap/ScrollTrigger';

gsap.registerPlugin(ScrollTrigger);

const prefersReducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

function initStickyHeader(): void {
  const header = document.querySelector<HTMLElement>('.site-header');
  if (!header) return;

  const update = () => {
    header.classList.toggle('site-header--scrolled', window.scrollY > 18);
  };
  update();
  window.addEventListener('scroll', update, { passive: true });
}

function initMobileMenu(): void {
  const btn = document.querySelector<HTMLButtonElement>('[data-menu-toggle]');
  const drawer = document.querySelector<HTMLElement>('[data-mobile-drawer]');
  if (!btn || !drawer) return;

  const close = () => {
    drawer.classList.remove('is-open');
    btn.setAttribute('aria-expanded', 'false');
  };

  btn.addEventListener('click', () => {
    const next = !drawer.classList.contains('is-open');
    drawer.classList.toggle('is-open', next);
    btn.setAttribute('aria-expanded', String(next));
  });

  drawer.querySelectorAll('a').forEach((link) => {
    link.addEventListener('click', close);
  });

  window.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') close();
  });
}

function initIntroTabs(): void {
  const tabs = document.querySelectorAll<HTMLButtonElement>('[data-device-tab]');
  const views = document.querySelectorAll<HTMLElement>('[data-device-view]');
  if (!tabs.length || !views.length) return;

  tabs.forEach((tab) => {
    tab.addEventListener('click', () => {
      const target = tab.dataset.deviceTab;
      if (!target) return;

      tabs.forEach((t) => {
        const active = t === tab;
        t.classList.toggle('is-active', active);
        t.setAttribute('aria-selected', String(active));
      });

      views.forEach((v) => {
        const active = v.dataset.deviceView === target;
        v.classList.toggle('is-active', active);
        if (active && !prefersReducedMotion) {
          gsap.fromTo(
            v,
            { opacity: 0, y: 10 },
            { opacity: 1, y: 0, duration: 0.34, ease: 'power2.out', clearProps: 'transform' },
          );
        }
      });
    });
  });
}

function initEncryptionToggle(): void {
  const buttons = document.querySelectorAll<HTMLButtonElement>('[data-mode-btn]');
  const panels = document.querySelectorAll<HTMLElement>('[data-mode-panel]');
  if (!buttons.length || !panels.length) return;

  buttons.forEach((btn) => {
    btn.addEventListener('click', () => {
      const target = btn.dataset.modeBtn;
      if (!target) return;

      buttons.forEach((b) => {
        const active = b === btn;
        b.classList.toggle('is-active', active);
        b.setAttribute('aria-selected', String(active));
      });

      panels.forEach((p) => {
        const active = p.dataset.modePanel === target;
        p.classList.toggle('is-active', active);
        if (active && !prefersReducedMotion) {
          gsap.fromTo(
            p,
            { opacity: 0, y: 8 },
            { opacity: 1, y: 0, duration: 0.3, ease: 'power2.out', clearProps: 'transform' },
          );
        }
      });
    });
  });
}

function initAccordions(): void {
  const triggers = document.querySelectorAll<HTMLButtonElement>('[data-accordion-trigger]');
  triggers.forEach((trigger) => {
    trigger.addEventListener('click', () => {
      const item = trigger.closest<HTMLElement>('.accordion-item');
      if (!item) return;

      const list = item.closest<HTMLElement>('[data-accordion-single]');
      const isOpen = item.classList.contains('is-open');

      if (list) {
        list.querySelectorAll<HTMLElement>('.accordion-item.is-open').forEach((openItem) => {
          if (openItem !== item) {
            openItem.classList.remove('is-open');
            openItem.querySelector<HTMLButtonElement>('[data-accordion-trigger]')?.setAttribute(
              'aria-expanded',
              'false',
            );
          }
        });
      }

      item.classList.toggle('is-open', !isOpen);
      trigger.setAttribute('aria-expanded', String(!isOpen));
    });
  });
}

function initMotion(): void {
  if (prefersReducedMotion) return;

  // Non-blocking Hero entrance
  const heroItems = document.querySelectorAll<HTMLElement>('[data-hero-reveal]');
  if (heroItems.length) {
    gsap.from(heroItems, {
      y: 22,
      opacity: 0,
      duration: 0.72,
      stagger: 0.08,
      ease: 'power3.out',
      clearProps: 'transform,opacity',
    });
  }

  const heroDevice = document.querySelector<HTMLElement>('[data-hero-device]');
  if (heroDevice) {
    gsap.from(heroDevice, {
      y: 34,
      scale: 0.96,
      opacity: 0,
      duration: 0.88,
      delay: 0.14,
      ease: 'power3.out',
      clearProps: 'transform,opacity',
    });
  }

  // Subtle scroll-linked parallax for layered photos
  document.querySelectorAll<HTMLElement>('[data-parallax]').forEach((el) => {
    const shift = Number(el.dataset.parallax ?? '24');
    gsap.to(el, {
      y: shift,
      ease: 'none',
      scrollTrigger: {
        trigger: el.closest('section') ?? el,
        start: 'top bottom',
        end: 'bottom top',
        scrub: 0.7,
      },
    });
  });

  // Gentle scroll reveals per section block
  document.querySelectorAll<HTMLElement>('[data-reveal]').forEach((el) => {
    gsap.from(el, {
      y: 26,
      opacity: 0,
      duration: 0.68,
      ease: 'power2.out',
      clearProps: 'transform,opacity',
      scrollTrigger: {
        trigger: el,
        start: 'top 86%',
        once: true,
      },
    });
  });

  // Staggered card grids
  document.querySelectorAll<HTMLElement>('[data-stagger-group]').forEach((group) => {
    const items = group.querySelectorAll<HTMLElement>('[data-stagger-item]');
    if (!items.length) return;
    gsap.from(items, {
      y: 22,
      opacity: 0,
      duration: 0.6,
      stagger: 0.09,
      ease: 'power2.out',
      clearProps: 'transform,opacity',
      scrollTrigger: {
        trigger: group,
        start: 'top 84%',
        once: true,
      },
    });
  });
}

document.addEventListener('DOMContentLoaded', () => {
  initStickyHeader();
  initMobileMenu();
  initIntroTabs();
  initEncryptionToggle();
  initAccordions();
  initMotion();
});
