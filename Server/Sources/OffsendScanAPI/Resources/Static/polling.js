(function () {
  const statusEl = document.getElementById('status');
  const spinnerEl = document.getElementById('spinner');
  const progressEl = document.getElementById('scan-progress');
  if (!statusEl || !spinnerEl || !progressEl) return;

  function setIdle(message) {
    spinnerEl.hidden = true;
    progressEl.removeAttribute('aria-busy');
    statusEl.textContent = message;
  }

  // Debug preview mode cycles statuses without a real job.
  if (document.body.dataset.debug === '1') {
    const previewStatuses = ['Starting…', 'Waiting to start…', 'Analyzing repository…'];
    let previewIndex = 0;
    setInterval(() => {
      statusEl.textContent = previewStatuses[previewIndex % previewStatuses.length];
      previewIndex += 1;
    }, 2000);
    return;
  }

  const jobID = document.body.dataset.jobId || '';
  const statusLabels = {
    queued: 'Waiting to start…',
    running: 'Analyzing repository…',
  };

  async function poll() {
    const response = await fetch('/scan/' + encodeURIComponent(jobID));
    if (!response.ok) {
      setIdle('Scan not found.');
      return;
    }
    const payload = await response.json();
    if (payload.status === 'completed') {
      window.location.href = '/r/' + encodeURIComponent(jobID);
      return;
    }
    if (payload.status === 'failed') {
      setIdle('Scan failed: ' + (payload.errorMessage || 'unknown error'));
      return;
    }
    statusEl.textContent = statusLabels[payload.status] || 'Working…';
    setTimeout(poll, 2000);
  }
  poll();
})();
