"use strict";

const query = new URLSearchParams(location.search);
const token = query.get("token") || "";
const tokenQuery = `token=${encodeURIComponent(token)}`;
const canvas = document.getElementById("stage");
const context = canvas.getContext("2d", { alpha: false });
const badge = document.getElementById("recordingBadge");
const headline = document.getElementById("headline");
const timeline = document.getElementById("timeline");
const evidence = document.getElementById("evidence");
const stopButton = document.getElementById("stopRecording");
const previewSelect = document.getElementById("previewState");
const previewNotice = document.getElementById("previewNotice");
const FRAME_STALE_MS = 5000;
const CANVAS_FOOTER_HEIGHT = 100;
let frameSource = "Waiting for Android device";
let devices = [];
const deviceFrames = new Map();
const frameRequestSequences = new Map();
const frameErrors = new Map();
let previewCatalog = [];
let previewPair = null;
let previewLoadGeneration = 0;
let previewCatalogSequence = 0;
let statusSnapshot = { headline: "Loading verified progress…", events: [] };
let recording = null;
let recordingSession = null;
let chunkSequence = 0;
let uploadChain = Promise.resolve();
let recordingHealthy = true;
let finishing = false;
let gracefulFinished = false;

function endpoint(path) { return `${path}?${tokenQuery}`; }
function mutationHeaders(extra = {}) {
  return { "X-Showcase-Token": token, ...extra };
}

async function loadStatus() {
  try {
    const response = await fetch(endpoint("/api/status"), { cache: "no-store" });
    const result = await response.json();
    statusSnapshot = result.status;
    headline.textContent = statusSnapshot.headline || "Development in progress";
    timeline.replaceChildren(...(statusSnapshot.events || []).map((event) => {
      const item = document.createElement("li");
      item.className = event.state || "pending";
      item.append(document.createTextNode(event.label));
      const eventTime = event.at || statusSnapshot.updatedAt;
      if (event.detail || eventTime) {
        const detail = document.createElement("small");
        detail.textContent = [event.detail, eventTime].filter(Boolean).join(" · ");
        item.append(detail);
      }
      return item;
    }));
  } catch (error) {
    headline.textContent = `Status unavailable: ${error.message}`;
  }
}

async function loadDevices() {
  try {
    const response = await fetch(endpoint("/api/devices"), { cache: "no-store" });
    const result = await response.json();
    devices = result.items || [];
    frameSource = result.message || (devices.length ? "Connected Android sources" : "Waiting for Android device");
  } catch (error) {
    devices = [];
    frameSource = `Frame source unavailable: ${error.message}`;
  }
}

async function loadPreviewCatalog() {
  const requestSequence = ++previewCatalogSequence;
  try {
    const response = await fetch(endpoint("/api/previews"), { cache: "no-store" });
    if (!response.ok) throw new Error(`preview index failed (${response.status})`);
    const result = await response.json();
    if (requestSequence !== previewCatalogSequence) return;
    previewCatalog = result.states || [];
    for (const option of previewSelect.options) {
      if (option.value === "off") continue;
      const state = previewCatalog.find((item) => item.state === option.value);
      option.disabled = !state?.complete;
    }
    const selected = previewCatalog.find((item) => item.state === previewSelect.value && item.complete);
    if (previewSelect.value !== "off" && !selected) {
      const fallback = [...previewCatalog].reverse().find((item) => item.complete);
      previewSelect.value = fallback?.state || "off";
    }
    await loadSelectedPreview();
  } catch (error) {
    previewNotice.textContent = `Flutter preview unavailable: ${error.message}`;
  }
}

async function loadSelectedPreview() {
  const stateName = previewSelect.value;
  if (stateName === "off") {
    releasePreviewPair();
    previewNotice.textContent = "Flutter preview disabled; canvas will show the truthful waiting state without adb.";
    return;
  }
  const state = previewCatalog.find((item) => item.state === stateName && item.complete);
  if (!state) {
    previewNotice.textContent = `No complete phone + tablet ${stateName} render pair is available.`;
    return;
  }
  const unchanged = previewPair?.state === stateName
    && previewPair.phone.modifiedAt === state.phone.modifiedAt
    && previewPair.tablet.modifiedAt === state.tablet.modifiedAt;
  if (unchanged) return;

  const generation = ++previewLoadGeneration;
  try {
    const loaded = await Promise.all(["phone", "tablet"].map(async (variant) => {
      const metadata = state[variant];
      const url = `${endpoint(`/preview/${encodeURIComponent(metadata.name)}`)}&version=${encodeURIComponent(metadata.modifiedAt)}`;
      const response = await fetch(url, { cache: "no-store" });
      if (!response.ok) throw new Error(`${metadata.name} failed (${response.status})`);
      return { ...metadata, bitmap: await createImageBitmap(await response.blob()) };
    }));
    if (generation !== previewLoadGeneration || previewSelect.value !== stateName) {
      loaded.forEach((entry) => entry.bitmap.close());
      return;
    }
    releasePreviewPair();
    previewPair = { state: stateName, phone: loaded[0], tablet: loaded[1] };
    const newest = [loaded[0].modifiedAt, loaded[1].modifiedAt].sort().at(-1);
    previewNotice.textContent = `Flutter UI preview · test renderer · ${stateName} · refreshed ${newest}`;
  } catch (error) {
    previewNotice.textContent = `Flutter preview load failed: ${error.message}`;
  }
}

function releasePreviewPair() {
  if (!previewPair) return;
  previewPair.phone.bitmap.close();
  previewPair.tablet.bitmap.close();
  previewPair = null;
}

async function loadFrames() {
  const deviceSnapshot = [...devices];
  await Promise.all(deviceSnapshot.map(async (device) => {
    const requestSequence = (frameRequestSequences.get(device.serial) || 0) + 1;
    frameRequestSequences.set(device.serial, requestSequence);
    try {
      const response = await fetch(`${endpoint("/api/frame")}&serial=${encodeURIComponent(device.serial)}&nonce=${Date.now()}`, { cache: "no-store" });
      if (!response.ok) {
        const result = await response.json().catch(() => ({}));
        if (frameRequestSequences.get(device.serial) === requestSequence) {
          frameErrors.set(device.serial, result.message || `capture failed (${response.status})`);
        }
        return;
      }
      const bitmap = await createImageBitmap(await response.blob());
      if (frameRequestSequences.get(device.serial) !== requestSequence) {
        bitmap.close();
        return;
      }
      const previous = deviceFrames.get(device.serial);
      if (previous) previous.bitmap.close();
      deviceFrames.set(device.serial, { bitmap, capturedAt: Date.now(), requestSequence });
      frameErrors.delete(device.serial);
    } catch (error) {
      if (frameRequestSequences.get(device.serial) === requestSequence) {
        frameErrors.set(device.serial, error.message || "capture failed");
      }
    }
  }));
  for (const [serial, entry] of deviceFrames) {
    if (!devices.some((device) => device.serial === serial)) {
      entry.bitmap.close();
      deviceFrames.delete(serial);
      frameRequestSequences.delete(serial);
      frameErrors.delete(serial);
    }
  }
}

function drawStage() {
  const width = canvas.width;
  const height = canvas.height;
  context.fillStyle = "#09090b";
  context.fillRect(0, 0, width, height);
  const now = Date.now();
  const sources = devices.map((device) => ({ device, entry: deviceFrames.get(device.serial) })).filter((source) => source.entry);
  let sourceSummary;
  if (sources.length) {
    const columns = sources.length === 1 ? 1 : Math.min(2, sources.length);
    const rows = Math.ceil(sources.length / columns);
    const gap = 24;
    const cellWidth = (width - gap * (columns + 1)) / columns;
    const cellHeight = (height - CANVAS_FOOTER_HEIGHT - gap * (rows + 1)) / rows;
    sources.forEach(({ device, entry }, index) => {
      const column = index % columns;
      const row = Math.floor(index / columns);
      const cellX = gap + column * (cellWidth + gap);
      const cellY = gap + row * (cellHeight + gap);
      drawDeviceFrame(entry, device.label, frameErrors.get(device.serial), cellX, cellY, cellWidth, cellHeight, now);
    });
    const liveCount = sources.filter(({ entry }) => now - entry.capturedAt <= FRAME_STALE_MS).length;
    const staleCount = sources.length - liveCount;
    sourceSummary = `${liveCount} live${staleCount ? ` · ${staleCount} stale` : ""} Android source${sources.length === 1 ? "" : "s"}`;
  } else if (devices.length === 0 && previewPair) {
    drawPreviewComposite(previewPair);
    sourceSummary = `Flutter UI preview · test renderer · ${previewPair.state} · not Android runtime evidence`;
  } else {
    const contentHeight = height - CANVAS_FOOTER_HEIGHT;
    context.fillStyle = "#19171b";
    context.fillRect(32, 32, width - 64, contentHeight - 64);
    context.fillStyle = "#d8aa80";
    context.font = "700 17px system-ui";
    context.fillText("MEOWWATCH MOBILE", 70, contentHeight / 2 - 58);
    context.fillStyle = "#f5f2ed";
    context.font = "700 36px system-ui";
    wrapText(frameSource, 70, contentHeight / 2, width - 140, 48);
    context.fillStyle = "#9a959b";
    context.font = "18px system-ui";
    context.fillText("No simulated product UI is shown.", 70, contentHeight / 2 + 115);
    sourceSummary = "Truthful waiting state";
  }
  drawCanvasFooter(sourceSummary);
}

function drawCanvasFooter(sourceSummary) {
  const width = canvas.width;
  const height = canvas.height;
  const stamp = new Date().toISOString();
  context.fillStyle = "#09090bcc";
  context.fillRect(0, height - CANVAS_FOOTER_HEIGHT, width, CANVAS_FOOTER_HEIGHT);
  context.fillStyle = "#f5f2ed";
  context.font = "700 18px system-ui";
  context.fillText(fitCanvasText(statusSnapshot.headline || "Development status unavailable", width - 44), 22, height - 68);
  context.fillStyle = "#b5afb5";
  context.font = "600 15px ui-monospace, monospace";
  context.fillText(stamp, 22, height - 42);
  context.font = "14px system-ui";
  context.fillText(sourceSummary, 22, height - 18);
}

function fitCanvasText(text, maxWidth) {
  const value = String(text);
  if (context.measureText(value).width <= maxWidth) return value;
  let shortened = value;
  while (shortened.length && context.measureText(`${shortened}…`).width > maxWidth) shortened = shortened.slice(0, -1);
  return `${shortened}…`;
}

function drawPreviewComposite(pair) {
  const width = canvas.width;
  const contentHeight = canvas.height - CANVAS_FOOTER_HEIGHT;
  context.fillStyle = "#211b18";
  context.fillRect(0, 0, width, 58);
  context.fillStyle = "#f1c79e";
  context.font = "800 17px system-ui";
  context.textAlign = "center";
  context.fillText("FLUTTER UI PREVIEW · TEST RENDERER · INJECTED UNIT STATE · NOT ANDROID PLUGIN/RUNTIME EVIDENCE", width / 2, 36);
  context.textAlign = "left";
  const gap = 26;
  const cellWidth = (width - gap * 3) / 2;
  const cellHeight = contentHeight - 78;
  drawPreviewFrame(pair.phone, "PHONE", gap, 68, cellWidth, cellHeight);
  drawPreviewFrame(pair.tablet, "TABLET", gap * 2 + cellWidth, 68, cellWidth, cellHeight);
}

function drawPreviewFrame(entry, variant, x, y, width, height) {
  const labelHeight = 44;
  const bezel = 9;
  const availableWidth = width - bezel * 2;
  const availableHeight = height - labelHeight - bezel * 2;
  const scale = Math.min(availableWidth / entry.bitmap.width, availableHeight / entry.bitmap.height);
  const drawWidth = entry.bitmap.width * scale;
  const drawHeight = entry.bitmap.height * scale;
  const frameWidth = drawWidth + bezel * 2;
  const frameHeight = drawHeight + bezel * 2;
  const frameX = x + (width - frameWidth) / 2;
  const frameY = y + labelHeight + (height - labelHeight - frameHeight) / 2;
  context.fillStyle = "#302d31";
  context.beginPath();
  context.roundRect(frameX, frameY, frameWidth, frameHeight, 16);
  context.fill();
  context.drawImage(entry.bitmap, frameX + bezel, frameY + bezel, drawWidth, drawHeight);
  context.fillStyle = "#f5f2ed";
  context.font = "700 15px system-ui";
  context.textAlign = "center";
  context.fillText(`${variant} · ${entry.name}`, x + width / 2, y + 17);
  context.fillStyle = "#aaa5aa";
  context.font = "12px ui-monospace, monospace";
  context.fillText(entry.modifiedAt, x + width / 2, y + 36);
  context.textAlign = "left";
}

function drawDeviceFrame(entry, label, captureError, x, y, width, height, now) {
  const { bitmap, capturedAt } = entry;
  const ageMs = now - capturedAt;
  const stale = ageMs > FRAME_STALE_MS;
  const labelHeight = 34;
  const bezel = 10;
  const availableWidth = width - bezel * 2;
  const availableHeight = height - labelHeight - bezel * 2;
  const scale = Math.min(availableWidth / bitmap.width, availableHeight / bitmap.height);
  const drawWidth = bitmap.width * scale;
  const drawHeight = bitmap.height * scale;
  const frameWidth = drawWidth + bezel * 2;
  const frameHeight = drawHeight + bezel * 2;
  const frameX = x + (width - frameWidth) / 2;
  const frameY = y + labelHeight + (height - labelHeight - frameHeight) / 2;
  context.fillStyle = "#29262b";
  context.beginPath();
  context.roundRect(frameX, frameY, frameWidth, frameHeight, 18);
  context.fill();
  context.drawImage(bitmap, frameX + bezel, frameY + bezel, drawWidth, drawHeight);
  if (stale) {
    context.fillStyle = "#351b1bd9";
    context.fillRect(frameX + bezel, frameY + bezel + drawHeight - 42, drawWidth, 42);
    context.fillStyle = "#ffc0b8";
    context.font = "700 15px system-ui";
    context.textAlign = "center";
    const age = Math.max(1, Math.floor(ageMs / 1000));
    context.fillText(`STALE · last frame ${age}s ago${captureError ? " · capture failed" : ""}`, frameX + frameWidth / 2, frameY + bezel + drawHeight - 16);
  }
  context.fillStyle = stale ? "#ffc0b8" : "#f5f2ed";
  context.font = "600 16px system-ui";
  context.textAlign = "center";
  context.fillText(`${label} · ${stale ? "STALE" : "LIVE"}`, x + width / 2, y + 22);
  context.textAlign = "left";
}

function wrapText(text, x, y, maxWidth, lineHeight) {
  const words = String(text).split(/\s+/);
  let line = "";
  let offset = 0;
  for (const word of words) {
    const candidate = `${line}${word} `;
    if (context.measureText(candidate).width > maxWidth && line) {
      context.fillText(line.trim(), x, y + offset);
      line = `${word} `;
      offset += lineHeight;
    } else line = candidate;
  }
  context.fillText(line.trim(), x, y + offset);
}

async function loadEvidence() {
  try {
    const response = await fetch(endpoint("/api/evidence"), { cache: "no-store" });
    const result = await response.json();
    if (!result.items.length) {
      evidence.className = "evidence-empty";
      evidence.textContent = "No CI screenshots or video downloaded yet.";
      return;
    }
    evidence.className = "";
    evidence.replaceChildren(...result.items.map((item) => {
      const wrapper = document.createElement("div");
      wrapper.className = "evidence-item";
      const media = document.createElement(item.kind === "video" ? "video" : "img");
      media.src = endpoint(`/evidence/${item.name.split("/").map(encodeURIComponent).join("/")}`);
      if (item.kind === "video") media.controls = true;
      else media.alt = `Native CI screenshot: ${item.name}`;
      const label = document.createElement("p");
      label.textContent = `${item.name} · ${(item.size / 1024).toFixed(1)} KiB · ${item.modifiedAt}`;
      wrapper.append(media, label);
      return wrapper;
    }));
  } catch (error) {
    evidence.textContent = `Evidence index unavailable: ${error.message}`;
  }
}

async function uploadChunk(blob, sequence) {
  if (!recordingSession || !blob.size) return;
  let lastError;
  for (let attempt = 1; attempt <= 3; attempt += 1) {
    try {
      const response = await fetch(endpoint(`/api/recordings/${recordingSession.sessionId}/chunk`), {
        method: "POST",
        headers: mutationHeaders({
          "Authorization": `Bearer ${recordingSession.sessionSecret}`,
          "Content-Type": blob.type || "application/octet-stream",
          "X-Chunk-Sequence": String(sequence),
        }),
        body: blob,
      });
      if (!response.ok) throw new Error(`chunk ${sequence} rejected (${response.status})`);
      return;
    } catch (error) {
      lastError = error;
      if (attempt < 3) await new Promise((resolve) => setTimeout(resolve, attempt * 1000));
    }
  }
  throw lastError;
}

function enqueueChunk(blob) {
  if (!recordingHealthy || !blob.size) return;
  const sequence = chunkSequence++;
  uploadChain = uploadChain.then(() => uploadChunk(blob, sequence)).catch((error) => {
    recordingHealthy = false;
    stopButton.disabled = true;
    badge.className = "badge error";
    badge.textContent = `Recording upload stopped: ${error.message}`;
    if (recording?.state === "recording") recording.stop();
    sendInterrupt("recording upload retries exhausted");
  });
}

async function startRecording() {
  if (!window.MediaRecorder || !canvas.captureStream) {
    badge.className = "badge error";
    badge.textContent = "Canvas recording unsupported";
    return;
  }
  const preferred = ["video/webm;codecs=vp9", "video/webm;codecs=vp8", "video/webm"];
  const mimeType = preferred.find((type) => MediaRecorder.isTypeSupported(type)) || "";
  try {
    const response = await fetch(endpoint("/api/recordings/start"), {
      method: "POST",
      headers: mutationHeaders({ "Content-Type": "application/json" }),
      body: JSON.stringify({ mimeType: mimeType || "browser-default", canvasFps: 2, requestedBitsPerSecond: 900000 }),
    });
    if (!response.ok) throw new Error(`session start rejected (${response.status})`);
    recordingSession = await response.json();
    recording = new MediaRecorder(canvas.captureStream(2), { ...(mimeType ? { mimeType } : {}), videoBitsPerSecond: 900000 });
    recording.addEventListener("dataavailable", (event) => {
      enqueueChunk(event.data);
    });
    recording.addEventListener("error", (event) => {
      recordingHealthy = false;
      stopButton.disabled = true;
      badge.className = "badge error";
      badge.textContent = `Recorder error: ${event.error?.message || "unknown"}`;
      sendInterrupt("browser MediaRecorder error");
    });
    recording.start(30000);
    stopButton.disabled = false;
    badge.className = "badge live";
    badge.textContent = "Recording showcase canvas · 2 fps";
  } catch (error) {
    badge.className = "badge error";
    badge.textContent = `Recording did not start: ${error.message}`;
  }
}

function sendInterrupt(reason) {
  if (!recordingSession || gracefulFinished) return;
  fetch(endpoint(`/api/recordings/${recordingSession.sessionId}/interrupt`), {
    method: "POST",
    headers: mutationHeaders({ "Authorization": `Bearer ${recordingSession.sessionSecret}`, "Content-Type": "application/json" }),
    body: JSON.stringify({ reason }),
    keepalive: true,
  }).catch(() => {});
}

async function stopRecordingGracefully() {
  if (finishing || gracefulFinished || !recordingSession) return;
  finishing = true;
  stopButton.disabled = true;
  badge.className = "badge waiting";
  badge.textContent = "Flushing final recording data…";
  try {
    if (recording?.state === "recording") {
      await new Promise((resolve) => {
        recording.addEventListener("stop", resolve, { once: true });
        recording.stop();
      });
    }
    await uploadChain;
    if (!recordingHealthy) throw new Error("a recording upload did not complete");
    const response = await fetch(endpoint(`/api/recordings/${recordingSession.sessionId}/end`), {
      method: "POST",
      headers: mutationHeaders({ "Authorization": `Bearer ${recordingSession.sessionSecret}`, "Content-Type": "application/json" }),
      body: JSON.stringify({ reason: "user requested graceful stop after final upload" }),
    });
    if (!response.ok) throw new Error(`server finalization failed (${response.status})`);
    gracefulFinished = true;
    recordingSession = null;
    badge.className = "badge";
    badge.textContent = "Recording saved completely";
  } catch (error) {
    badge.className = "badge error";
    badge.textContent = `Recording interrupted: ${error.message}`;
    sendInterrupt("graceful stop could not confirm final upload");
  } finally {
    finishing = false;
  }
}

async function heartbeat() {
  if (!recordingSession || !recordingHealthy) return;
  try {
    await fetch(endpoint(`/api/recordings/${recordingSession.sessionId}/heartbeat`), {
      method: "POST",
      headers: mutationHeaders({ "Authorization": `Bearer ${recordingSession.sessionSecret}` }),
      body: "",
      keepalive: true,
    });
  } catch (_) { /* server records the missing heartbeat as a gap */ }
}

function markPageInterruption() {
  if (gracefulFinished || !recordingSession) return;
  sendInterrupt("page unloaded before final MediaRecorder flush could be confirmed");
}

document.getElementById("refreshEvidence").addEventListener("click", loadEvidence);
stopButton.addEventListener("click", stopRecordingGracefully);
previewSelect.addEventListener("change", loadSelectedPreview);
window.addEventListener("pagehide", markPageInterruption);
drawStage();
loadStatus();
loadDevices().then(loadFrames);
loadPreviewCatalog();
loadEvidence();
setInterval(drawStage, 500);
setInterval(loadFrames, 1500);
setInterval(loadDevices, 5000);
setInterval(loadPreviewCatalog, 5000);
setInterval(loadStatus, 5000);
setInterval(loadEvidence, 15000);
setInterval(heartbeat, 5000);
startRecording();
