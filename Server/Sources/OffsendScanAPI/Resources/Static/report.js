(function () {
  const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  // Save to PDF via the browser print dialog.
  const printBtn = document.getElementById('report-print');
  if (printBtn) {
    printBtn.addEventListener('click', () => window.print());
  }

  // Animated privacy score + meter fill, colored by result.
  const scoreEl = document.querySelector('.score');
  const meterFill = document.querySelector('.score-meter-fill');
  const match = scoreEl && scoreEl.textContent.trim().match(/^(\d+)\s*\/\s*(\d+)/);
  if (scoreEl && match) {
    const target = parseInt(match[1], 10);
    const max = parseInt(match[2], 10) || 100;
    const suffix = '/' + max;
    const pct = Math.max(0, Math.min(100, (target / max) * 100));
    const tone = pct >= 80 ? 'is-good' : pct >= 50 ? 'is-mid' : 'is-bad';
    scoreEl.classList.add(tone);
    if (meterFill) meterFill.classList.add(tone);

    const setValue = (v) => { scoreEl.textContent = v + suffix; };

    if (reduceMotion) {
      setValue(target);
      if (meterFill) meterFill.style.width = pct + '%';
    } else {
      setValue(0);
      requestAnimationFrame(() => { if (meterFill) meterFill.style.width = pct + '%'; });
      const duration = 1100;
      const start = performance.now();
      const ease = (t) => 1 - Math.pow(1 - t, 3);
      const tick = (now) => {
        const t = Math.min(1, (now - start) / duration);
        setValue(Math.round(ease(t) * target));
        if (t < 1) requestAnimationFrame(tick);
        else setValue(target);
      };
      requestAnimationFrame(tick);
    }
  } else if (meterFill) {
    meterFill.parentElement.hidden = true;
  }

  // Countdown until the report is purged and stops being reachable.
  const expiryEl = document.querySelector('.report-expiry');
  const textEl = expiryEl && expiryEl.querySelector('.report-expiry-text');
  const iso = expiryEl && expiryEl.getAttribute('data-expires-at');
  const expiresAt = iso ? Date.parse(iso) : NaN;
  if (expiryEl && textEl && !isNaN(expiresAt)) {
    const fmt = (ms) => {
      const s = Math.floor(ms / 1000);
      const d = Math.floor(s / 86400);
      const h = Math.floor((s % 86400) / 3600);
      const m = Math.floor((s % 3600) / 60);
      const sec = s % 60;
      const parts = [];
      if (d) parts.push(d + 'd');
      if (d || h) parts.push(h + 'h');
      parts.push(m + 'm');
      parts.push(sec + 's');
      return parts.join(' ');
    };
    let timer;
    const update = () => {
      const remaining = expiresAt - Date.now();
      if (remaining <= 0) {
        expiryEl.classList.add('is-expired');
        textEl.innerHTML = 'This report is no longer available — <a class="link" href="/">run a new scan</a>.';
        if (timer) clearInterval(timer);
        return;
      }
      textEl.innerHTML = 'Available for <strong>' + fmt(remaining) + '</strong>';
    };
    update();
    timer = setInterval(update, 1000);
  } else if (expiryEl) {
    expiryEl.hidden = true;
  }

  // "Fix it": show a per-platform command that recreates the missing/incomplete
  // AI ignore files locally, built from the fix files embedded in the page.
  const fixOpen = document.getElementById('fix-open');
  const fixModal = document.getElementById('fix-modal');
  const fixDataEl = document.getElementById('fix-files-data');
  if (fixOpen && fixModal && fixDataEl) {
    let files = [];
    try { files = JSON.parse(fixDataEl.textContent || '[]'); } catch (e) { files = []; }

    const codeEl = document.getElementById('fix-command-code');
    const hintEl = document.getElementById('fix-shell-hint');
    const copyBtn = document.getElementById('fix-copy');
    const copyLabel = copyBtn && copyBtn.querySelector('.fix-copy-label');
    const platformBtns = Array.from(fixModal.querySelectorAll('.fix-platform'));

    const hints = {
      macos: 'Run in Terminal (bash or zsh).',
      linux: 'Run in your shell (bash or sh).',
      windows: 'Run in PowerShell.',
    };

    // POSIX heredoc: quoted delimiter keeps contents literal (no expansion).
    const posixCommand = (list) =>
      list
        .map((f) => {
          const dir = f.path.includes('/') ? f.path.replace(/\/[^/]*$/, '') : '';
          const mkdir = dir ? "mkdir -p '" + dir + "'\n" : '';
          const body = (f.contents || '').replace(/\n$/, '');
          return mkdir + "cat > '" + f.path + "' <<'OFFSEND_EOF'\n" + body + "\nOFFSEND_EOF";
        })
        .join('\n\n');

    // PowerShell here-string: literal @' ... '@ block, closing marker at column 0.
    const powershellCommand = (list) =>
      list
        .map((f) => {
          const dir = f.path.includes('/') ? f.path.replace(/\/[^/]*$/, '') : '';
          const mkdir = dir
            ? 'New-Item -ItemType Directory -Force -Path "' + dir + '" | Out-Null\n'
            : '';
          const body = (f.contents || '').replace(/\n$/, '');
          return (
            mkdir +
            "Set-Content -NoNewline -Path '" +
            f.path +
            "' -Value @'\n" +
            body +
            "\n'@"
          );
        })
        .join('\n\n');

    const commandFor = (platform) =>
      platform === 'windows' ? powershellCommand(files) : posixCommand(files);

    let current = 'macos';
    const selectPlatform = (platform) => {
      current = platform;
      platformBtns.forEach((btn) => {
        const active = btn.dataset.platform === platform;
        btn.setAttribute('aria-selected', active ? 'true' : 'false');
        btn.classList.toggle('is-active', active);
      });
      if (codeEl) codeEl.textContent = commandFor(platform);
      if (hintEl) hintEl.textContent = hints[platform] || '';
      if (copyLabel) copyLabel.textContent = 'Copy';
    };

    platformBtns.forEach((btn) => {
      btn.addEventListener('click', () => selectPlatform(btn.dataset.platform));
    });

    const openModal = () => {
      selectPlatform(current);
      fixModal.hidden = false;
      document.body.style.overflow = 'hidden';
    };
    const closeModal = () => {
      fixModal.hidden = true;
      document.body.style.overflow = '';
      fixOpen.focus();
    };

    fixOpen.addEventListener('click', openModal);
    document.getElementById('fix-modal-close').addEventListener('click', closeModal);
    document.getElementById('fix-modal-backdrop').addEventListener('click', closeModal);
    document.addEventListener('keydown', (e) => {
      if (e.key === 'Escape' && !fixModal.hidden) closeModal();
    });

    if (copyBtn) {
      copyBtn.addEventListener('click', async () => {
        const text = codeEl ? codeEl.textContent : '';
        try {
          await navigator.clipboard.writeText(text);
        } catch (e) {
          const range = document.createRange();
          range.selectNodeContents(codeEl);
          const sel = window.getSelection();
          sel.removeAllRanges();
          sel.addRange(range);
          document.execCommand('copy');
          sel.removeAllRanges();
        }
        if (copyLabel) {
          copyLabel.textContent = 'Copied';
          setTimeout(() => { copyLabel.textContent = 'Copy'; }, 1600);
        }
      });
    }
  }
})();
