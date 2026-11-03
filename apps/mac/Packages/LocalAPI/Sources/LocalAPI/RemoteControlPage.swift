import Foundation

public enum RemoteControlPage {
    public static let html = """
    <!doctype html>
    <html lang="en"><head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
    <meta name="theme-color" content="#111827">
    <title>Chorus Remote</title>
    <style>
    :root { color-scheme: dark; font: 16px/1.45 -apple-system, system-ui, sans-serif; }
    * { box-sizing: border-box; }
    body { margin: 0; min-height: 100vh; background: #111827; color: #f9fafb;
      padding: max(16px, env(safe-area-inset-top)) 16px max(20px, env(safe-area-inset-bottom)); }
    main { width: min(100%, 620px); margin: 0 auto; display: grid; gap: 14px; }
    header, section { background: #1f2937; border: 1px solid #374151; border-radius: 16px; padding: 16px; }
    header { display: flex; justify-content: space-between; align-items: center; gap: 12px; }
    h1 { margin: 0; font-size: 19px; } h2 { margin: 0 0 8px; font-size: 14px; color: #9ca3af; }
    .status { color: #9ca3af; font-size: 12px; } .status.error { color: #fca5a5; }
    .field { display: grid; gap: 6px; margin-top: 12px; color: #9ca3af; font-size: 12px; }
    input, select { width: 100%; min-height: 46px; border: 1px solid #4b5563; border-radius: 10px;
      padding: 10px 12px; background: #111827; color: #f9fafb; font: inherit; }
    .live { min-height: 170px; display: flex; flex-direction: column; justify-content: center;
      text-align: center; white-space: pre-wrap; font-size: clamp(24px, 7vw, 42px); font-weight: 650; }
    .meta { text-align: center; color: #9ca3af; font-size: 13px; }
    .nextText { margin-top: 10px; text-align: center; color: #9ca3af; white-space: pre-wrap; }
    .controls { display: grid; grid-template-columns: 1fr 1fr; gap: 12px; }
    button { min-height: 58px; border: 0; border-radius: 13px; padding: 12px;
      color: #fff; background: #374151; font: inherit; font-weight: 650; touch-action: manipulation; }
    button:active { transform: scale(.98); } button.primary { background: #4f46e5; }
    button.danger { background: #991b1b; } button:disabled { opacity: .5; }
    .hint { margin: 10px 0 0; color: #9ca3af; font-size: 12px; }
    a { color: #a5b4fc; }
    </style></head><body>
    <main>
      <header><h1>Chorus Remote</h1><span id="connection" class="status">Not connected</span></header>
      <section>
        <button id="connect" class="primary" style="width:100%;margin-top:10px">Connect</button>
        <p class="hint">This remote is available to devices on the same local network.</p>
      </section>
      <section>
        <div id="serviceName" class="meta">No service selected</div>
        <div id="live" class="live">Nothing live</div>
        <div id="position" class="meta"></div>
        <div id="next" class="nextText"></div>
      </section>
      <div class="controls">
        <button id="back" aria-label="Previous slide">← Back</button>
        <button id="advance" class="primary" aria-label="Next slide">Next →</button>
        <button id="underlying">Back to slide</button>
        <button id="blank">Clear slides</button>
        <button id="clearAll" class="danger">Clear all</button>
      </div>
      <p class="hint">Keep this page on a trusted network. Anyone on the LAN can operate the current show.</p>
    </main>
    <script>
    const connection = document.querySelector('#connection');
    const live = document.querySelector('#live');
    const next = document.querySelector('#next');
    const serviceName = document.querySelector('#serviceName');
    const position = document.querySelector('#position');
    let busy = false;
    async function request(path, method = 'GET', body) {
      const response = await fetch(path, {
        method,
        headers: { ...(body ? {'Content-Type': 'application/json'} : {}) },
        body: body ? JSON.stringify(body) : undefined
      });
      if (!response.ok) {
        const detail = await response.text();
        throw new Error(response.status === 401 || response.status === 403
          ? 'Key is invalid or does not have Operate access.'
          : 'Request failed (' + response.status + '): ' + detail.slice(0, 180));
      }
      return response.status === 204 ? null : response.json().catch(() => null);
    }
    function setStatus(text, error = false) {
      connection.textContent = text;
      connection.classList.toggle('error', error);
    }
    async function refresh() {
      try {
        const status = await request('/v1/status');
        const current = status.liveSlide;
        serviceName.textContent = status.service?.name || status.position?.currentItemName || 'No service selected';
        live.textContent = current?.text || current?.slideName || 'Nothing live';
        const count = current?.slideCount;
        const index = current?.slideIndex;
        const steps = current?.stepCount ? ' · click ' + (current.stepIndex || 0) + '/' + current.stepCount : '';
        position.textContent = Number.isInteger(index) && Number.isInteger(count)
          ? 'Slide ' + (index + 1) + ' of ' + count + steps : steps;
        next.textContent = status.nextSlideText ? 'Next: ' + status.nextSlideText : '';
        setStatus('Connected');
      } catch (error) {
        setStatus(error.message, true);
      }
    }
    async function command(path, body, confirmText) {
      if (busy) return;
      if (confirmText && !confirm(confirmText)) return;
      busy = true;
      document.querySelectorAll('button').forEach(button => button.disabled = true);
      try {
        await request(path, 'POST', body);
        await refresh();
      } catch (error) {
        setStatus(error.message, true);
      } finally {
        busy = false;
        document.querySelectorAll('button').forEach(button => button.disabled = false);
      }
    }
    document.querySelector('#back').addEventListener('click', () =>
      command('/v1/show/advance', {steps: -1}));
    document.querySelector('#advance').addEventListener('click', () =>
      command('/v1/show/advance', {steps: 1}));
    document.querySelector('#underlying').addEventListener('click', () =>
      command('/v1/show/return-underlying'));
    document.querySelector('#blank').addEventListener('click', () =>
      command('/v1/show/clear', {function: 'slides'}));
    document.querySelector('#clearAll').addEventListener('click', () =>
      command('/v1/show/clear-all', null, 'Clear all live layers?'));
    document.querySelector('#connect').addEventListener('click', () => {
      refresh();
    });
    refresh();
    setInterval(() => { if (!document.hidden) refresh(); }, 2000);
    </script></body></html>
    """
}
