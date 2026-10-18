(() => {
  const content = document.querySelector("#page-content");
  const connectionBanner = document.querySelector("#connection-banner");
  const breadcrumb = document.querySelector("#breadcrumb-page");
  const lastSynced = document.querySelector("#last-synced");
  const toastElement = document.querySelector("#toast");
  const pageNames = {
    dashboard: "Overview",
    fields: "Fields",
    usage: "Water usage",
    activity: "Activity",
    settings: "Settings",
  };
  let state = null;
  let activePage = "dashboard";
  let toastTimeout;

  const escapeHtml = (value) =>
    String(value).replace(/[&<>"']/g, (character) => ({
      "&": "&amp;",
      "<": "&lt;",
      ">": "&gt;",
      '"': "&quot;",
      "'": "&#39;",
    })[character]);

  function timeAgo(value) {
    const seconds = Math.max(0, Math.floor((Date.now() - new Date(value).getTime()) / 1000));
    if (seconds < 60) return "just now";
    if (seconds < 3600) return `${Math.floor(seconds / 60)} min ago`;
    if (seconds < 86400) return `${Math.floor(seconds / 3600)} hr ago`;
    return `${Math.floor(seconds / 86400)} d ago`;
  }

  function showToast(message) {
    toastElement.textContent = message;
    toastElement.classList.add("show");
    clearTimeout(toastTimeout);
    toastTimeout = setTimeout(() => toastElement.classList.remove("show"), 2400);
  }

  function statusFor(field) {
    if (state.moisture[field] < state.threshold) {
      return state.valveOpen[field] ? "Watering now" : "Needs water";
    }
    return "Healthy";
  }

  function renderMoistureCard(value, caption, target = state.threshold, blue = false) {
    const healthy = value >= target;
    return `
      <div class="card moisture-card">
        <div class="moisture-top">
          <span class="moisture-caption">${escapeHtml(caption)}</span>
          <span class="status-white">${healthy ? "● Healthy" : "● Needs water"}</span>
        </div>
        <div class="moisture-value-row">
          <span class="moisture-number">${Math.round(value)}</span><span class="moisture-unit">%</span>
          <span class="moisture-target">Target ${Math.round(target)}%</span>
        </div>
        <div class="progress-track"><div class="progress-fill ${blue ? "blue" : ""}" style="width:${Math.min(100, Math.max(0, value))}%"></div></div>
        <div class="scale-labels"><span>Dry</span><span>Ideal moisture</span><span>Wet</span></div>
      </div>`;
  }

  function metricCard(icon, label, value, note, blue = false) {
    return `
      <div class="card metric">
        <div class="metric-icon ${blue ? "blue" : ""}">${icon}</div>
        <div><div class="metric-label">${escapeHtml(label)}</div>
          <div class="metric-value">${escapeHtml(value)}</div>
          <div class="metric-note">${escapeHtml(note)}</div>
        </div>
      </div>`;
  }

  function fieldRows() {
    return ["A", "B"].map((field) => {
      const moisture = state.moisture[field];
      const dry = moisture < state.threshold;
      return `
        <div class="field-row">
          <div class="field-plant">♧</div>
          <div class="field-details">
            <div class="field-name">Field ${field}</div>
            <div class="field-info">${state.valveOpen[field] ? "Water valve open" : "Moisture sensor connected"}</div>
          </div>
          <div><div class="field-value">${Math.round(moisture)}%</div>
            <div class="field-status ${dry ? "dry" : ""}">${escapeHtml(statusFor(field))}</div>
          </div>
        </div>`;
    }).join("");
  }

  function chartSvg() {
    const history = state.history.length > 2 ? state.history : [];
    const values = history.length ? history : [{ A: state.moisture.A, B: state.moisture.B }];
    const width = 620;
    const height = 150;
    const left = 32;
    const right = 7;
    const top = 8;
    const bottom = 22;
    const plotWidth = width - left - right;
    const plotHeight = height - top - bottom;
    const maxValue = 100;
    const point = (value, index) => ({
      x: left + (values.length < 2 ? 0 : index * plotWidth / (values.length - 1)),
      y: top + plotHeight - Math.max(0, Math.min(maxValue, value)) / maxValue * plotHeight,
    });
    const points = (field) => values.map((entry, index) => point(entry[field], index));
    const makePath = (field) => points(field)
      .map((item, index) => `${index ? "L" : "M"} ${item.x.toFixed(1)} ${item.y.toFixed(1)}`)
      .join(" ");
    const gridValues = [0, 25, 50, 75, 100];
    const grid = gridValues.map((value) => {
      const y = top + plotHeight - value / maxValue * plotHeight;
      return `<line class="chart-grid" x1="${left}" y1="${y}" x2="${width}" y2="${y}"/><text class="chart-label" x="0" y="${y + 3}">${value}%</text>`;
    }).join("");
    const times = [0, 1, 2, 3].map((position) => {
      const index = Math.round((values.length - 1) * position / 3);
      const date = new Date(values[index]?.time || Date.now());
      const label = date.toLocaleTimeString([], { hour: "numeric", minute: "2-digit" });
      const x = left + plotWidth * position / 3;
      return `<text class="chart-label" x="${x}" y="${height - 3}" text-anchor="${position === 0 ? "start" : position === 3 ? "end" : "middle"}">${escapeHtml(label)}</text>`;
    }).join("");
    return `<svg viewBox="0 0 ${width} ${height}" role="img" aria-label="Soil moisture chart showing the last sensor readings">
      ${grid}${times}
      <path d="${makePath("A")}" class="chart-line-a"/>
      <path d="${makePath("B")}" class="chart-line-b"/>
    </svg>`;
  }

  function eventRows(limit = 20) {
    if (!state.events.length) {
      return `<div class="event-row"><div class="event-icon">✓</div><div><div class="event-title">All caught up</div><div class="event-details">New system activity will appear here.</div></div></div>`;
    }
    return state.events.slice(0, limit).map((event) => {
      const iconClass = event.type === "warning" ? "warning" : event.type === "watering" ? "" : "blue";
      const symbol = event.type === "warning" ? "!" : event.type === "watering" ? "↓" : "✓";
      return `
        <div class="event-row">
          <div class="event-icon ${iconClass}">${symbol}</div>
          <div><div class="event-title">${escapeHtml(event.title)}</div><div class="event-details">${escapeHtml(event.details)}</div></div>
          <span class="event-time">${escapeHtml(timeAgo(event.occurredAt))}</span>
        </div>`;
    }).join("");
  }

  function savingsPercent() {
    if (!state.baselineWater) return 0;
    return Math.round((state.baselineWater - state.automatedWater) / state.baselineWater * 100);
  }

  function savingsCard() {
    const saved = state.baselineWater - state.automatedWater;
    const percent = savingsPercent();
    const positive = saved >= 0;
    return `
      <div class="card water-savings">
        <div class="saving-icon">↘</div>
        <div class="saving-copy"><div class="saving-title">${positive ? "You're saving water" : "Water use increased"}</div>
          <div class="saving-subtitle">Compared with your pre-automation average</div>
        </div>
        <div class="saving-number">${Math.abs(saved).toFixed(1)} <small>L/day ${positive ? "saved" : "more"}</small></div>
      </div>
      <div class="comparison-callout">
        <span class="callout-symbol">${positive ? "✦" : "!"}</span>
        <div class="callout-text">Your automated system uses <strong>${Math.abs(percent)}% ${positive ? "less" : "more"} water</strong> than the ${state.baselineWater.toFixed(0)} L/day baseline.</div>
      </div>`;
  }

  function renderDashboard() {
    const average = (state.moisture.A + state.moisture.B) / 2;
    const running = state.pumpOn;
    return `
      <div class="page-heading">
        <div><p class="eyebrow">THURSDAY, OCTOBER 16</p><h1>Good evening, gardener <span aria-hidden="true">🌱</span></h1>
          <p class="heading-copy">Here's what's happening in your greenhouse today.</p>
        </div>
        <span class="date-label">System updated ${escapeHtml(timeAgo(state.updatedAt))}</span>
      </div>
      <div class="layout-grid">
        <div class="stack overview-primary">
          ${renderMoistureCard(average, "AVERAGE SOIL MOISTURE")}
          <div class="metric-grid">
            ${metricCard("◉", "WATER TODAY", `${state.waterToday.toFixed(1)} L`, "Measured today", true)}
            ${metricCard("ϟ", "PUMP STATUS", running ? "Running" : "Standby", state.mode === "automatic" ? "Automatic mode" : "Manual mode")}
          </div>
          <section class="card card-pad">
            <div class="card-head"><div><h2 class="card-title">Moisture trends</h2><p class="card-subtitle">Soil levels from both fields</p></div>
              <button class="text-link" data-page="fields">View fields →</button>
            </div>
            <div class="chart-wrap">${chartSvg()}</div>
            <div class="legend"><span class="legend-item"><i class="legend-dot"></i>Field A</span><span class="legend-item"><i class="legend-dot blue"></i>Field B</span></div>
          </section>
          <section class="card card-pad">
            <div class="card-head"><div><h2 class="card-title">Recent activity</h2><p class="card-subtitle">Latest updates from your system</p></div>
              <button class="text-link" data-page="activity">View all →</button>
            </div>
            <div class="event-list">${eventRows(3)}</div>
          </section>
        </div>
        <div class="stack overview-secondary">
          <section class="card control-card">
            <div class="card-head"><div><h2 class="card-title">Irrigation control</h2><p class="card-subtitle">Manage your pump and watering</p></div></div>
            <div class="mode-switch">
              <button class="mode-button ${state.mode === "automatic" ? "active" : ""}" data-action="mode" data-value="automatic">✳ &nbsp;Automatic</button>
              <button class="mode-button ${state.mode === "manual" ? "active" : ""}" data-action="mode" data-value="manual">☷ &nbsp;Manual</button>
            </div>
            <div class="control-row"><span class="control-label">Watering threshold</span><span class="control-value" id="threshold-value">${state.threshold}%</span></div>
            <input class="threshold-slider" id="threshold-slider" type="range" min="10" max="80" step="1" value="${state.threshold}" aria-label="Moisture threshold">
            <div class="slider-range"><span>10%</span><span>80%</span></div>
            <div class="control-divider"></div>
            <div class="button-row"><span class="control-label">Pump override</span>
              <button class="pump-button ${running ? "on" : ""}" data-action="pump" data-value="${!running}" ${state.mode === "automatic" ? "disabled title=\"Switch to manual mode first\"" : ""}>${running ? "Ⅱ  Stop pump" : "▶  Start pump"}</button>
            </div>
            <div class="control-divider"></div>
            <div class="card-head" style="margin-bottom:10px"><div><h3 class="card-title">Field valves</h3></div><span class="card-subtitle">${state.mode === "manual" ? "Manual" : "Auto"}</span></div>
            ${["A", "B"].map((field) => `<div class="button-row" style="margin-top:9px"><span class="control-label">Field ${field} · ${Math.round(state.moisture[field])}%</span><button class="valve-button ${state.valveOpen[field] ? "on" : ""}" data-action="valve" data-field="${field}" data-value="${!state.valveOpen[field]}" ${state.mode === "automatic" ? "disabled title=\"Switch to manual mode first\"" : ""}>${state.valveOpen[field] ? "Close valve" : "Open valve"}</button></div>`).join("")}
          </section>
          <section class="card card-pad">
            <div class="card-head"><div><h2 class="card-title">Your fields</h2><p class="card-subtitle">Current growing conditions</p></div>
              <button class="text-link" data-page="fields">Manage</button>
            </div>
            <div class="field-list">${fieldRows()}</div>
          </section>
          <div class="card">${savingsCard()}</div>
        </div>
      </div>`;
  }

  function renderFields() {
    return `
      <div class="page-heading"><div><p class="eyebrow">YOUR GARDEN</p><h1>Fields</h1><p class="heading-copy">Monitor soil conditions and irrigation for each growing area.</p></div><span class="date-label">2 active fields</span></div>
      <div class="layout-grid">
        <div class="stack">
          ${["A", "B"].map((field) => `
            <section class="card card-pad">
              <div class="card-head"><div><h2 class="card-title">Field ${field}</h2><p class="card-subtitle">${field === "A" ? "North garden · Moisture sensor 01" : "South garden · Moisture sensor 02"}</p></div><span class="field-status ${state.moisture[field] < state.threshold ? "dry" : ""}">${escapeHtml(statusFor(field))}</span></div>
              ${renderMoistureCard(state.moisture[field], `FIELD ${field} SOIL MOISTURE`)}
              <div class="control-row"><span class="control-label">Watering valve</span><span class="control-value">${state.valveOpen[field] ? "Open" : "Closed"}</span></div>
              <div class="button-row" style="margin-top:12px"><span class="card-subtitle">${state.mode === "automatic" ? "Valve is managed automatically" : "Manual valve control is enabled"}</span>
                <button class="valve-button ${state.valveOpen[field] ? "on" : ""}" data-action="valve" data-field="${field}" data-value="${!state.valveOpen[field]}" ${state.mode === "automatic" ? "disabled" : ""}>${state.valveOpen[field] ? "Close valve" : "Open valve"}</button>
              </div>
            </section>`).join("")}
        </div>
        <div class="stack">
          <section class="card control-card">
            <div class="card-head"><div><h2 class="card-title">System mode</h2><p class="card-subtitle">Choose how your fields are watered</p></div></div>
            <div class="mode-switch"><button class="mode-button ${state.mode === "automatic" ? "active" : ""}" data-action="mode" data-value="automatic">✳ &nbsp;Automatic</button><button class="mode-button ${state.mode === "manual" ? "active" : ""}" data-action="mode" data-value="manual">☷ &nbsp;Manual</button></div>
            <p class="card-subtitle" style="line-height:1.6;margin-top:12px">${state.mode === "automatic" ? "Your system waters a field when soil moisture drops below your target." : "You control each valve and the pump yourself."}</p>
            <div class="control-row"><span class="control-label">Watering threshold</span><span class="control-value" id="threshold-value">${state.threshold}%</span></div>
            <input class="threshold-slider" id="threshold-slider" type="range" min="10" max="80" value="${state.threshold}" aria-label="Moisture threshold">
            <div class="slider-range"><span>10%</span><span>80%</span></div>
          </section>
          <section class="card card-pad"><div class="card-head"><div><h2 class="card-title">At a glance</h2><p class="card-subtitle">Current greenhouse readings</p></div></div>${fieldRows()}</section>
        </div>
      </div>`;
  }

  function renderUsage() {
    const before = state.baselineWater;
    const after = state.automatedWater;
    const max = Math.max(before, after, 1);
    const percent = savingsPercent();
    return `
      <div class="page-heading"><div><p class="eyebrow">SMARTER WATERING</p><h1>Water usage</h1><p class="heading-copy">See how automation helps your garden use water efficiently.</p></div><span class="date-label">Daily averages</span></div>
      <div class="layout-grid">
        <div class="stack">
          <section class="card card-pad"><div class="card-head"><div><h2 class="card-title">Before and after automation</h2><p class="card-subtitle">Average water use per day</p></div></div>
            <div class="compare-grid">
              <div class="card compare-card"><div class="metric-label">BEFORE AUTOMATION</div><div class="compare-value">${before.toFixed(1)} <small>L / day</small></div><div class="bar-track"><div class="bar-fill" style="width:${before / max * 100}%"></div></div><div class="compare-caption">Your recorded baseline</div></div>
              <div class="card compare-card"><div class="metric-label">WITH AUTOMATION</div><div class="compare-value">${after.toFixed(1)} <small>L / day</small></div><div class="bar-track"><div class="bar-fill green" style="width:${after / max * 100}%"></div></div><div class="compare-caption">Current measured average</div></div>
            </div>
            ${savingsCard()}
          </section>
          <section class="card card-pad"><div class="card-head"><div><h2 class="card-title">Moisture trends</h2><p class="card-subtitle">Sensor readings guide automatic watering</p></div></div><div class="chart-wrap">${chartSvg()}</div><div class="legend"><span class="legend-item"><i class="legend-dot"></i>Field A</span><span class="legend-item"><i class="legend-dot blue"></i>Field B</span></div></section>
        </div>
        <div class="stack">
          ${metricCard("◉", "WATER USED TODAY", `${state.waterToday.toFixed(1)} L`, "Across both fields", true)}
          ${metricCard("↘", "DAILY WATER SAVED", `${Math.abs(before - after).toFixed(1)} L`, `${Math.abs(percent)}% ${percent >= 0 ? "less" : "more"} than baseline`)}
          <section class="card card-pad"><div class="card-head"><div><h2 class="card-title">How we compare</h2></div></div><p class="card-subtitle" style="line-height:1.7">Water savings use measured average daily consumption before and after automation. Comparable tracking periods give the clearest results.</p></section>
        </div>
      </div>`;
  }

  function renderActivity() {
    return `
      <div class="page-heading"><div><p class="eyebrow">SYSTEM LOG</p><h1>Activity</h1><p class="heading-copy">Recent events and changes from your irrigation system.</p></div><span class="date-label">${state.events.length} recent events</span></div>
      <div class="layout-grid">
        <section class="card card-pad"><div class="card-head"><div><h2 class="card-title">Recent events</h2><p class="card-subtitle">Updates appear as the system runs</p></div><i class="live-dot" aria-label="Live updates"></i></div>
          <div class="event-list">${eventRows(20)}</div>
        </section>
        <div class="stack">
          ${metricCard("ϟ", "PUMP STATUS", state.pumpOn ? "Running" : "Standby", state.mode === "automatic" ? "Automatic mode" : "Manual mode")}
          ${metricCard("◉", "WATER TODAY", `${state.waterToday.toFixed(1)} L`, "Measured today", true)}
          <section class="card card-pad"><div class="card-head"><div><h2 class="card-title">Connection</h2></div></div><div class="field-status">● Demo server connected</div><p class="card-subtitle" style="line-height:1.6;margin-top:8px">This is a simulation. It does not connect to real soil sensors, a pump, or Firebase.</p></section>
        </div>
      </div>`;
  }

  function renderSettings() {
    return `
      <div class="page-heading"><div><p class="eyebrow">PREFERENCES</p><h1>Settings</h1><p class="heading-copy">Configure the way your irrigation system behaves.</p></div></div>
      <div class="layout-grid">
        <div class="stack">
          <section class="card card-pad"><div class="card-head"><div><h2 class="card-title">Watering preferences</h2><p class="card-subtitle">Set when your garden needs water</p></div></div>
            <div class="settings-row"><div><div class="settings-name">Automatic watering</div><div class="settings-description">Let soil moisture trigger irrigation</div></div><button class="switch" role="switch" aria-checked="${state.mode === "automatic"}" data-action="mode" data-value="${state.mode === "automatic" ? "manual" : "automatic"}" aria-label="Toggle automatic watering"></button></div>
            <div class="settings-row"><div><div class="settings-name">Moisture threshold</div><div class="settings-description">Start watering when moisture falls below target</div></div><span class="control-value" id="threshold-value">${state.threshold}%</span></div>
            <input class="threshold-slider" id="threshold-slider" type="range" min="10" max="80" value="${state.threshold}" aria-label="Moisture threshold"><div class="slider-range"><span>10%</span><span>80%</span></div>
          </section>
          <section class="card card-pad"><div class="card-head"><div><h2 class="card-title">Manual controls</h2><p class="card-subtitle">Switch to manual mode to operate hardware controls</p></div></div>
            <div class="button-row"><span class="control-label">Water pump</span><button class="pump-button ${state.pumpOn ? "on" : ""}" data-action="pump" data-value="${!state.pumpOn}" ${state.mode === "automatic" ? "disabled" : ""}>${state.pumpOn ? "Ⅱ  Stop pump" : "▶  Start pump"}</button></div>
            ${["A", "B"].map((field) => `<div class="button-row" style="margin-top:12px"><span class="control-label">Field ${field} valve</span><button class="valve-button ${state.valveOpen[field] ? "on" : ""}" data-action="valve" data-field="${field}" data-value="${!state.valveOpen[field]}" ${state.mode === "automatic" ? "disabled" : ""}>${state.valveOpen[field] ? "Close valve" : "Open valve"}</button></div>`).join("")}
          </section>
        </div>
        <div class="stack">
          <section class="card card-pad"><div class="card-head"><div><h2 class="card-title">System information</h2><p class="card-subtitle">Greenhouse 01</p></div></div>
            <div class="settings-row"><span class="settings-name">Connection</span><span class="field-status">● Demo simulation</span></div>
            <div class="settings-row"><span class="settings-name">Fields monitored</span><span class="date-label">2</span></div>
            <div class="settings-row"><span class="settings-name">Last sensor update</span><span class="date-label">${escapeHtml(timeAgo(state.updatedAt))}</span></div>
          </section>
          <section class="card card-pad"><div class="card-head"><div><h2 class="card-title">About this demo</h2></div></div><p class="card-subtitle" style="line-height:1.7">This browser app simulates sensors, irrigation valves, and pump controls. All devices connected to this computer's local demo server see the same simulated state. No real equipment is controlled.</p></section>
        </div>
      </div>`;
  }

  function render() {
    if (!state) return;
    const renderers = {
      dashboard: renderDashboard,
      fields: renderFields,
      usage: renderUsage,
      activity: renderActivity,
      settings: renderSettings,
    };
    breadcrumb.textContent = pageNames[activePage] || "Overview";
    document.querySelectorAll("[data-page]").forEach((button) => {
      button.classList.toggle("active", button.dataset.page === activePage);
    });
    content.innerHTML = (renderers[activePage] || renderDashboard)();
    lastSynced.textContent = timeAgo(state.updatedAt);
  }

  async function updateControl(update, successMessage) {
    try {
      const response = await fetch("/api/control", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify(update),
      });
      const result = await response.json();
      if (!response.ok) throw new Error(result.error || "Unable to update controls.");
      state = result;
      render();
      showToast(successMessage);
    } catch (error) {
      showToast(error.message);
    }
  }

  document.addEventListener("click", (event) => {
    const pageButton = event.target.closest("[data-page]");
    if (pageButton) {
      activePage = pageButton.dataset.page;
      render();
      return;
    }
    const actionButton = event.target.closest("[data-action]");
    if (!actionButton || actionButton.disabled) return;
    if (actionButton.dataset.action === "mode") {
      const value = actionButton.dataset.value;
      updateControl({ mode: value }, `${value === "automatic" ? "Automatic" : "Manual"} mode enabled.`);
    } else if (actionButton.dataset.action === "pump") {
      const pump = actionButton.dataset.value === "true";
      updateControl({ pump }, `Pump ${pump ? "started" : "stopped"} in the simulation.`);
    } else if (actionButton.dataset.action === "valve") {
      const open = actionButton.dataset.value === "true";
      updateControl({ field: actionButton.dataset.field, open }, `Field ${actionButton.dataset.field} valve ${open ? "opened" : "closed"}.`);
    }
  });

  document.addEventListener("input", (event) => {
    if (event.target.id === "threshold-slider") {
      const label = document.querySelector("#threshold-value");
      if (label) label.textContent = `${event.target.value}%`;
    }
  });

  document.addEventListener("change", (event) => {
    if (event.target.id === "threshold-slider") {
      updateControl({ threshold: Number(event.target.value) }, `Watering target set to ${event.target.value}%.`);
    }
  });

  const alertsButton = document.querySelector("#alerts-button");
  alertsButton.addEventListener("click", () => {
    activePage = "activity";
    render();
  });

  const connection = new EventSource("/api/stream");
  connection.onmessage = (event) => {
    try {
      state = JSON.parse(event.data);
      connectionBanner.hidden = true;
      render();
    } catch {
      connectionBanner.hidden = false;
    }
  };
  connection.onerror = () => {
    connectionBanner.hidden = false;
  };
})();
