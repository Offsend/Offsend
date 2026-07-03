(function () {
  const form = document.getElementById('scan-form');
  const status = document.getElementById('status');
  const urlInput = document.getElementById('url');
  if (!form || !status || !urlInput) return;
  const submitButton = form.querySelector('button[type="submit"]');

  const syncSubmitState = () => {
    submitButton.disabled = urlInput.value.trim() === '';
  };

  urlInput.addEventListener('input', syncSubmitState);
  syncSubmitState();

  form.addEventListener('submit', async (event) => {
    event.preventDefault();
    status.textContent = 'Starting scan…';
    const url = urlInput.value;
    const response = await fetch('/scan', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ url })
    });
    if (!response.ok) {
      status.textContent = 'Could not start scan.';
      return;
    }
    const payload = await response.json();
    window.location.href = '/scan/' + payload.jobID + '/page';
  });
})();
