const http = require("node:http");
const fs = require("node:fs");
const path = require("node:path");

const host = process.env.HOST || "0.0.0.0";
const port = Number(process.env.PORT || 8080);
const publicDirectory = path.join(__dirname, "public");
const clients = new Set();

const state = {
  moisture: { A: 58, B: 43 },
  threshold: 35,
  mode: "automatic",
  pumpOn: false,
  valveOpen: { A: false, B: false },
  pumpCommand: false,
  valveCommand: { A: false, B: false },
  waterToday: 18.4,
  baselineWater: 42,
  automatedWater: 27.3,
  updatedAt: new Date().toISOString(),
  history: [],
  events: [],
};

function recordEvent(title, details, type = "normal") {
  state.events.unshift({
    title,
    details,
    type,
    occurredAt: new Date().toISOString(),
  });
  state.events = state.events.slice(0, 40);
}

function snapshot() {
  return {
    moisture: { ...state.moisture },
    threshold: state.threshold,
    mode: state.mode,
    pumpOn: state.pumpOn,
    valveOpen: { ...state.valveOpen },
    waterToday: Number(state.waterToday.toFixed(1)),
    baselineWater: state.baselineWater,
    automatedWater: state.automatedWater,
    updatedAt: state.updatedAt,
    history: state.history.slice(-48),
    events: state.events.slice(0, 20),
    demo: true,
  };
}

function publish() {
  const data = `data: ${JSON.stringify(snapshot())}\n\n`;
  for (const client of clients) client.write(data);
}

for (let index = 0; index < 24; index += 1) {
  const timestamp = Date.now() - (23 - index) * 30 * 60 * 1000;
  state.history.push({
    time: new Date(timestamp).toISOString(),
    A: Math.round(54 + Math.sin(index / 3) * 7),
    B: Math.round(45 + Math.cos(index / 4) * 6),
  });
}
recordEvent("System ready", "Demo sensor and pump simulation started.", "normal");

setInterval(() => {
  let watered = false;
  if (state.mode === "automatic") {
    for (const field of ["A", "B"]) {
      state.valveOpen[field] = state.moisture[field] < state.threshold;
    }
    state.pumpOn = state.valveOpen.A || state.valveOpen.B;
  } else {
    state.valveOpen = { ...state.valveCommand };
    state.pumpOn =
      state.pumpCommand || state.valveOpen.A || state.valveOpen.B;
  }

  for (const field of ["A", "B"]) {
    if (state.valveOpen[field]) {
      state.moisture[field] = Math.min(88, state.moisture[field] + 0.9);
      watered = true;
    } else {
      state.moisture[field] = Math.max(12, state.moisture[field] - 0.16);
    }
  }
  if (watered && state.pumpOn) state.waterToday += 0.06;

  state.updatedAt = new Date().toISOString();
  if (Date.now() % 12000 < 2800) {
    state.history.push({
      time: state.updatedAt,
      A: Math.round(state.moisture.A),
      B: Math.round(state.moisture.B),
    });
    state.history = state.history.slice(-48);
  }
  publish();
}, 2500);

function sendJson(response, status, body) {
  response.writeHead(status, {
    "content-type": "application/json; charset=utf-8",
    "cache-control": "no-store",
  });
  response.end(JSON.stringify(body));
}

function contentType(filePath) {
  const extension = path.extname(filePath).toLowerCase();
  return ({
    ".html": "text/html; charset=utf-8",
    ".css": "text/css; charset=utf-8",
    ".js": "text/javascript; charset=utf-8",
    ".svg": "image/svg+xml",
    ".png": "image/png",
    ".ico": "image/x-icon",
  })[extension] || "application/octet-stream";
}

const server = http.createServer((request, response) => {
  const requestUrl = new URL(request.url, `http://${request.headers.host || "localhost"}`);

  if (request.method === "GET" && requestUrl.pathname === "/api/state") {
    return sendJson(response, 200, snapshot());
  }

  if (request.method === "GET" && requestUrl.pathname === "/api/stream") {
    response.writeHead(200, {
      "content-type": "text/event-stream; charset=utf-8",
      "cache-control": "no-cache, no-transform",
      connection: "keep-alive",
      "access-control-allow-origin": "*",
    });
    response.write(`data: ${JSON.stringify(snapshot())}\n\n`);
    clients.add(response);
    request.on("close", () => clients.delete(response));
    return;
  }

  if (request.method === "POST" && requestUrl.pathname === "/api/control") {
    let body = "";
    request.on("data", (chunk) => {
      body += chunk;
      if (body.length > 4096) request.destroy();
    });
    request.on("end", () => {
      try {
        const update = JSON.parse(body || "{}");
        if (update.threshold !== undefined) {
          if (!Number.isFinite(update.threshold) || update.threshold < 10 || update.threshold > 80) {
            return sendJson(response, 400, { error: "Threshold must be 10–80%." });
          }
          state.threshold = Math.round(update.threshold);
        }
        if (update.mode !== undefined) {
          if (update.mode !== "automatic" && update.mode !== "manual") {
            return sendJson(response, 400, { error: "Mode must be automatic or manual." });
          }
          state.mode = update.mode;
          if (update.mode === "automatic") {
            state.pumpCommand = false;
            state.valveCommand = { A: false, B: false };
          } else {
            state.pumpCommand = false;
            state.valveCommand = { A: false, B: false };
          }
        }
        if (update.field && ["A", "B"].includes(update.field) && typeof update.open === "boolean") {
          state.mode = "manual";
          state.valveCommand[update.field] = update.open;
          state.pumpCommand = false;
        }
        if (update.pump !== undefined) {
          if (typeof update.pump !== "boolean") {
            return sendJson(response, 400, { error: "Pump command must be on or off." });
          }
          state.mode = "manual";
          state.pumpCommand = update.pump;
        }
        state.updatedAt = new Date().toISOString();
        recordEvent(
          update.mode === "automatic" ? "Automatic mode enabled"
            : update.mode === "manual" ? "Manual mode enabled"
              : update.field ? `Field ${update.field} valve updated`
                : update.pump !== undefined ? `Pump ${update.pump ? "started" : "stopped"} manually`
                  : update.threshold !== undefined ? "Watering threshold updated" : "System updated",
          update.threshold !== undefined ? `Target moisture set to ${state.threshold}%.`
            : update.field ? `Field ${update.field} valve ${update.open ? "opened" : "closed"}.`
              : update.pump !== undefined ? `Pump ${update.pump ? "started" : "stopped"} using manual control.`
                : `System is now in ${state.mode} mode.`,
          update.field || update.pump !== undefined ? "watering" : "normal",
        );
        publish();
        return sendJson(response, 200, snapshot());
      } catch {
        return sendJson(response, 400, { error: "Invalid JSON request." });
      }
    });
    return;
  }

  const pathname = decodeURIComponent(requestUrl.pathname);
  const relativePath = pathname === "/" ? "index.html" : pathname.slice(1);
  const filePath = path.resolve(publicDirectory, relativePath);
  if (!filePath.startsWith(`${publicDirectory}${path.sep}`) && filePath !== path.join(publicDirectory, "index.html")) {
    return sendJson(response, 403, { error: "Forbidden." });
  }
  fs.readFile(filePath, (error, contents) => {
    if (error) {
      response.writeHead(404, { "content-type": "text/plain; charset=utf-8" });
      return response.end("Not found");
    }
    response.writeHead(200, {
      "content-type": contentType(filePath),
      "cache-control": "no-cache",
    });
    response.end(contents);
  });
});

server.listen(port, host, () => {
  console.log(`Irrigation demo ready: http://localhost:${port}`);
  console.log("For phone access on the same Wi-Fi, open this computer's LAN IP at the same port.");
  console.log("Demo only: readings and pump controls are simulated; no hardware is connected.");
});

function shutdown() {
  for (const client of clients) client.end();
  server.close(() => process.exit(0));
  setTimeout(() => process.exit(0), 1000).unref();
}
process.on("SIGINT", shutdown);
process.on("SIGTERM", shutdown);
