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
