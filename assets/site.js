document.documentElement.classList.add('js');

// Mobile menu
const toggle = document.querySelector('.menu-toggle');
const nav = document.getElementById('nav');
if (toggle && nav) {
  toggle.addEventListener('click', () => {
    const open = nav.classList.toggle('is-open');
    toggle.setAttribute('aria-expanded', String(open));
    toggle.textContent = open ? toggle.dataset.close : toggle.dataset.open;
  });
}

// Fade sections in as they enter the viewport
const reveals = document.querySelectorAll('.reveal');
if ('IntersectionObserver' in window) {
  const io = new IntersectionObserver((entries) => {
    for (const e of entries) {
      if (e.isIntersecting) { e.target.classList.add('is-visible'); io.unobserve(e.target); }
    }
  }, { rootMargin: '0px 0px -10% 0px' });
  reveals.forEach((el) => io.observe(el));
} else {
  reveals.forEach((el) => el.classList.add('is-visible'));
}

// Google Maps loads only after the visitor asks for it (no third-party request before that)
document.querySelectorAll('[data-map-load]').forEach((btn) => {
  btn.addEventListener('click', () => {
    const box = btn.closest('.map');
    const iframe = document.createElement('iframe');
    iframe.src = box.dataset.src;
    iframe.title = box.dataset.title;
    iframe.loading = 'lazy';
    iframe.referrerPolicy = 'no-referrer-when-downgrade';
    box.replaceChildren(iframe);
  });
});

// Contact form via Web3Forms. Until an access key is set, the form is replaced by the fallback text.
document.querySelectorAll('form[data-web3forms]').forEach((form) => {
  const key = form.querySelector('[name="access_key"]').value;
  const fallback = form.nextElementSibling;
  if (!key || key.startsWith('YOUR_')) {
    form.hidden = true;
    if (fallback) fallback.hidden = false;
    return;
  }
  const status = form.querySelector('.form-status');
  const button = form.querySelector('button[type="submit"]');
  form.addEventListener('submit', async (ev) => {
    ev.preventDefault();
    if (!form.reportValidity()) return;
    button.disabled = true;
    status.dataset.state = '';
    status.textContent = form.dataset.sending;
    try {
      const res = await fetch('https://api.web3forms.com/submit', {
        method: 'POST',
        headers: { Accept: 'application/json' },
        body: new FormData(form),
      });
      const data = await res.json();
      if (!data.success) throw new Error(data.message);
      form.reset();
      status.dataset.state = 'ok';
      status.textContent = form.dataset.success;
    } catch {
      status.dataset.state = 'error';
      status.textContent = form.dataset.failure;
    } finally {
      button.disabled = false;
    }
  });
});

// Home page quotes take turns every 6 seconds. They pause while the mouse or keyboard
// focus is on them and the dots jump to a quote. With "reduce motion" (common on Windows
// with animation effects off) they still take turns, but switch without the fade (site.css).
document.querySelectorAll('[data-quotes]').forEach((box) => {
  const items = [...box.querySelectorAll('.quote')];
  const dots = box.querySelector('.quote-dots');
  if (items.length < 2 || !dots) return;
  let current = 0;
  let timer = null;
  const buttons = items.map((_, n) => {
    const b = document.createElement('button');
    b.type = 'button';
    b.setAttribute('aria-label', `${box.dataset.label} ${n + 1}`);
    if (n === 0) b.setAttribute('aria-current', 'true');
    // the pointer or focus is on the quotes while clicking, so rotation stays paused until it leaves
    b.addEventListener('click', () => show(n));
    dots.appendChild(b);
    return b;
  });
  function show(n) {
    items[current].classList.remove('is-active');
    buttons[current].removeAttribute('aria-current');
    current = (n + items.length) % items.length;
    items[current].classList.add('is-active');
    buttons[current].setAttribute('aria-current', 'true');
  }
  const stop = () => { clearInterval(timer); timer = null; };
  const start = () => { if (!timer) timer = setInterval(() => show(current + 1), 6000); };
  box.addEventListener('mouseenter', stop);
  box.addEventListener('mouseleave', start);
  box.addEventListener('focusin', stop);
  box.addEventListener('focusout', start);
  document.addEventListener('visibilitychange', () => (document.hidden ? stop() : start()));
  start();
});
// Article "copy link" button: copies the address and says so for two seconds
document.querySelectorAll('[data-copy]').forEach((btn) => {
  const label = btn.textContent;
  btn.addEventListener('click', async () => {
    try {
      await navigator.clipboard.writeText(btn.dataset.copy);
      btn.textContent = btn.dataset.done;
      setTimeout(() => { btn.textContent = label; }, 2000);
    } catch (e) { /* clipboard blocked: the address is still in the browser bar */ }
  });
});
