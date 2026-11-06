import Foundation

public enum RemoteControlPage {
    public static let html = """
    <!doctype html>
    <html lang="en"><head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
    <meta name="theme-color" content="#101019">
    <title>Chorus Pastor Remote</title>
    <style>
    :root {
      color-scheme: dark;
      font: 16px/1.45 -apple-system, BlinkMacSystemFont, system-ui, sans-serif;
      --panel: rgba(31, 31, 45, .86);
      --line: rgba(255, 255, 255, .09);
      --muted: #a4a4b8;
      --accent: #8b7bff;
    }
    * { box-sizing: border-box; }
    body {
      margin: 0; min-height: 100vh; min-height: 100dvh; color: #fbfaff;
      background: radial-gradient(ellipse at 50% -10%, #332c62 0, #181725 42%, #101019 82%);
      padding: max(20px, env(safe-area-inset-top)) 18px max(22px, env(safe-area-inset-bottom));
    }
    main {
      width: min(100%, 560px); min-height: calc(100dvh - 42px);
      margin: 0 auto; display: flex; flex-direction: column; gap: 18px;
    }
    header { display: flex; align-items: center; justify-content: space-between; gap: 12px; }
    .brand { display: flex; align-items: center; gap: 11px; }
    .mark {
      width: 40px; height: 40px; display: grid; place-items: center; border-radius: 14px;
      background: linear-gradient(145deg, #a397ff, #6653e9); box-shadow: 0 8px 26px #6756e955;
      font-size: 22px; font-weight: 750;
    }
    h1 { margin: 0; font-size: 17px; letter-spacing: -.02em; }
    #serviceName { color: var(--muted); font-size: 12px; margin-top: 2px; }
    .connection {
      display: flex; align-items: center; gap: 7px; color: var(--muted); font-size: 12px;
      background: rgba(255,255,255,.055); border: 1px solid var(--line); border-radius: 99px;
      padding: 7px 10px;
    }
    .dot { width: 7px; height: 7px; border-radius: 50%; background: #e8ad5a; }
    .connection.ok .dot { background: #67d9a0; box-shadow: 0 0 10px #67d9a088; }
    .connection.error .dot { background: #ff7777; }
    .live-card {
      flex: 1; min-height: 220px; display: flex; flex-direction: column;
      justify-content: center; gap: 18px; padding: 28px 22px;
      border: 1px solid var(--line); border-radius: 26px;
      background: linear-gradient(155deg, rgba(42,40,61,.96), rgba(26,25,38,.96));
      box-shadow: 0 24px 70px #0005, inset 0 1px rgba(255,255,255,.045);
    }
    .eyebrow {
      color: #b7adff; text-align: center; font-size: 10px; font-weight: 750;
      letter-spacing: .16em; text-transform: uppercase;
    }
    #live {
      min-height: 100px; display: grid; place-items: center; text-align: center;
      white-space: pre-wrap; overflow-wrap: anywhere;
      font-size: clamp(26px, 7.3vw, 42px); line-height: 1.24; font-weight: 720;
      letter-spacing: -.035em;
    }
    #position { color: var(--muted); text-align: center; font-size: 12px; }
    .controls { display: grid; grid-template-columns: 1fr 1fr; gap: 13px; }
    button {
      border: 1px solid var(--line); color: #fbfaff; font: inherit; font-weight: 700;
      touch-action: manipulation; -webkit-tap-highlight-color: transparent;
      transition: transform .12s ease, filter .12s ease, opacity .12s ease;
    }
    button:active { transform: scale(.96); filter: brightness(1.13); }
    button:disabled { opacity: .46; }
    .step {
      min-height: 88px; display: flex; align-items: center; justify-content: center; gap: 12px;
      border-radius: 22px; background: rgba(255,255,255,.09); font-size: 16px;
    }
    .sr-only {
      position: absolute; width: 1px; height: 1px; padding: 0; margin: -1px;
      overflow: hidden; clip: rect(0, 0, 0, 0); white-space: nowrap; border: 0;
    }
    .step.primary {
      border-color: transparent; background: linear-gradient(145deg, #978aff, #705ef0);
      box-shadow: 0 10px 28px #6756e944;
    }
    .arrow { font-size: 31px; font-weight: 400; line-height: 1; }
    #underlying {
      grid-column: 1 / -1; min-height: 58px; border-radius: 18px;
      background: rgba(255,255,255,.055); color: #d7d2ff;
      font-size: 14px; letter-spacing: .005em;
    }
    #underlying .return-icon { margin-right: 9px; font-size: 19px; vertical-align: -1px; }
    #underlying[hidden] { display: none; }
    .footer { margin: 0; color: #77778b; text-align: center; font-size: 11px; }
    @media (max-height: 600px) {
      main { min-height: auto; }
      .live-card { min-height: 150px; padding: 18px; }
      #live { min-height: 70px; font-size: clamp(22px, 6vw, 34px); }
      .step { min-height: 68px; }
    }
    @media (prefers-reduced-motion: reduce) { button { transition: none; } }
    </style></head><body>
    <main>
      <header>
        <div class="brand">
          <div class="mark" aria-hidden="true">C</div>
          <div><h1>Chorus Remote</h1><div id="serviceName">Waiting for service</div></div>
        </div>
        <div id="connection" class="connection"><span class="dot"></span><span id="connectionText">Connecting</span></div>
      </header>
      <section class="live-card" aria-live="polite">
        <div class="eyebrow">On screen now</div>
        <div id="live">Connecting to Chorus…</div>
        <div id="position"></div>
      </section>
      <div class="controls">
        <button id="back" class="step" aria-label="Previous slide">
          <span class="arrow" aria-hidden="true">‹</span><span class="sr-only">Back</span>
        </button>
        <button id="advance" class="step primary" aria-label="Next slide">
          <span class="sr-only">Next</span><span class="arrow" aria-hidden="true">›</span>
        </button>
        <button id="underlying" hidden aria-label="Go back to the slide shown before the verse">
          <span class="return-icon" aria-hidden="true">↩</span>Go back to the slide
        </button>
      </div>
      <p class="footer">Connected to your Chorus show</p>
    </main>
    <script>
    const connection = document.querySelector('#connection');
    const connectionText = document.querySelector('#connectionText');
    const live = document.querySelector('#live');
    const serviceName = document.querySelector('#serviceName');
    const position = document.querySelector('#position');
    const underlying = document.querySelector('#underlying');
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
          ? 'Remote access is not available.'
          : 'Connection problem (' + response.status + '): ' + detail.slice(0, 120));
      }
      return response.status === 204 ? null : response.json().catch(() => null);
    }
    function setStatus(text, error = false) {
      connectionText.textContent = text;
      connection.classList.toggle('error', error);
      connection.classList.toggle('ok', !error && text === 'Connected');
    }
    function updateButtons() {
      document.querySelector('#back').disabled = busy || !connection.classList.contains('ok');
      document.querySelector('#advance').disabled = busy || !connection.classList.contains('ok');
      underlying.hidden = !connection.classList.contains('ok') || !window.canReturnToUnderlying;
      underlying.disabled = busy || !window.canReturnToUnderlying;
    }
    async function refresh() {
      try {
        const status = await request('/v1/status');
        const current = status.liveSlide;
        serviceName.textContent = status.service?.name || status.position?.currentItemName || 'No service selected';
        live.textContent = current?.text || current?.slideName || 'Nothing live';
        const count = current?.slideCount;
        const index = current?.slideIndex;
        const steps = current?.stepCount ? ' · ' + (current.stepIndex || 0) + '/' + current.stepCount + ' cues' : '';
        position.textContent = Number.isInteger(index) && Number.isInteger(count)
          ? 'Slide ' + (index + 1) + ' of ' + count + steps : steps;
        window.canReturnToUnderlying = status.canReturnToUnderlying === true;
        setStatus('Connected');
      } catch (error) {
        setStatus(error.message, true);
      }
      updateButtons();
    }
    async function command(path, body) {
      if (busy) return;
      busy = true;
      updateButtons();
      try {
        await request(path, 'POST', body);
        await refresh();
      } catch (error) {
        setStatus(error.message, true);
        updateButtons();
      } finally {
        busy = false;
        updateButtons();
      }
    }
    document.querySelector('#back').addEventListener('click', () =>
      command('/v1/show/advance', {steps: -1}));
    document.querySelector('#advance').addEventListener('click', () =>
      command('/v1/show/advance', {steps: 1}));
    underlying.addEventListener('click', () =>
      command('/v1/show/return-underlying'));
    updateButtons();
    refresh();
    setInterval(() => { if (!document.hidden && !busy) refresh(); }, 1500);
    </script></body></html>
    """
}
