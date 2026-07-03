(function () {
  const nav = document.getElementById('topnav');
  const menu = document.getElementById('topnav-menu');
  const burger = document.getElementById('topnav-burger');
  const backdrop = document.getElementById('topnav-backdrop');
  if (!nav || !menu || !burger || !backdrop) return;

  const closeMenu = () => {
    nav.classList.remove('is-menu-open');
    document.body.classList.remove('is-menu-open');
    menu.classList.remove('is-open');
    burger.classList.remove('is-open');
    burger.setAttribute('aria-expanded', 'false');
    burger.setAttribute('aria-label', 'Open menu');
    backdrop.hidden = true;
  };

  const openMenu = () => {
    nav.classList.add('is-menu-open');
    document.body.classList.add('is-menu-open');
    menu.classList.add('is-open');
    burger.classList.add('is-open');
    burger.setAttribute('aria-expanded', 'true');
    burger.setAttribute('aria-label', 'Close menu');
    backdrop.hidden = false;
  };

  const onScroll = () => {
    nav.classList.toggle('scrolled', window.scrollY > 8);
  };

  onScroll();
  window.addEventListener('scroll', onScroll, { passive: true });

  burger.addEventListener('click', () => {
    if (nav.classList.contains('is-menu-open')) closeMenu();
    else openMenu();
  });

  backdrop.addEventListener('click', closeMenu);

  menu.querySelectorAll('a').forEach((link) => {
    link.addEventListener('click', closeMenu);
  });

  window.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') closeMenu();
  });

  window.addEventListener('resize', () => {
    if (window.matchMedia('(min-width: 769px)').matches) closeMenu();
  });
})();
