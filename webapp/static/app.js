// CAD Training front end. Plain ES modules, no build step.
// three.js is loaded only when the 3D view opens, so scanning still works without the internet.

const $ = (id) => document.getElementById(id);
const reducedMotion = matchMedia("(prefers-reduced-motion: reduce)");
const STEPS = ["scan", "process", "edit"];
let current = null;

// Example edits. The text matches the canned scripts in bench/edit_cases.py, so they work without a Claude key.
// A third item, true, only fills the box so the kid can finish the words (a name, for example).
const IDEAS = [
  ["Taller", "make it 20 percent taller"],
  ["Half the size", "scale it down to half its size"],
  ["Add a base plate", "add a flat base plate 3 mm thick that sticks out 5 mm on every side"],
  ["Flat bottom", "cut the bottom 5 mm off so it sits flat"],
  ["Hole in the middle", "add a 6 mm hole straight down through the centre"],
  ["Peg on top", "add a round peg 10 mm wide and 15 mm tall on top, in the centre"],
  ["Cut in half", "cut it in half and keep only the left half"],
  ["Keyring loop", "add a keyring loop on the right side"],
  ["Name on it", "write this name on the front: ", true],
  ["Number 7 on top", "put the number 7 on top"],
];
// Shown under "More ideas".
const MORE_IDEAS = [
  ["Carve HI", "engrave HI on the front"],
  ["Fit in a box", "make it fit in a box 40 by 30 by 20 mm"],
  ["Bunny ears", "give it bunny ears"],
  ["Eyes", "put two eyes on the front"],
  ["Wings", "give it wings"],
  ["Crown", "give it a crown"],
  ["Donut hat", "put a donut on its head"],
  ["Arm", "give it an arm on the right"],
  ["Star on top", "put a star on top"],
  ["Pyramid on top", "put a pyramid on top"],
  ["Hollow like a cup", "make it hollow inside"],
  ["Lid", "make a lid for it"],
  ["Cup handle", "add a handle on the left like a cup"],
  ["Coin slot", "cut a slot in the top so coins can go in"],
  ["Round stand", "put it on a round stand"],
  ["Little legs", "give it four little legs"],
  ["Wall hanger", "make it so i can hang it on a nail on the wall"],
  ["Carve a heart", "carve a heart into the top"],
  ["Grooves", "put grooves around it"],
  ["Brick studs", "put lego studs on top"],
  ["Spikes", "make the front spiky"],
  ["Row of 3", "make three of them in a row"],
  ["Mirror", "make it symmetrical"],
  ["Twist", "make it twist like a corkscrew"],
  ["Pointy top", "make the top narrower like a cone"],
  ["Chubby", "make it chubby in the middle"],
  ["Smooth edges", "round off the sharp edges"],
  ["Stronger", "make it stronger, the thin bits keep snapping"],
];

function show(step) {
  current = step;
  const at = STEPS.indexOf(step);
  for (const s of document.querySelectorAll(".screen")) s.hidden = s.id !== step;
  for (const li of document.querySelectorAll(".steps li")) {
    const i = STEPS.indexOf(li.dataset.step);
    li.classList.toggle("active", i === at);
    li.classList.toggle("done", i < at);
    if (i === at) li.setAttribute("aria-current", "step");
    else li.removeAttribute("aria-current");
  }
  if (step === "scan") startCamera();
  else stopCamera();
}

// ---------- Talking to the server ----------
class ApiError extends Error {
  constructor(message, detail, status, kind) {
    super(message);
    Object.assign(this, { detail, status, kind });
  }
}

let downTimer = null;
function serverDown() {
  banner("Lost contact with the app. Check that the server window on this Mac is still running.");
  if (downTimer) return;
  downTimer = setInterval(async () => {
    try {
      const r = await fetch("/api/status", { cache: "no-store" });
      if (r.ok) serverUp();
    } catch (e) { /* still down */ }
  }, 3000);
}
function serverUp() {
  if (!downTimer) return;
  clearInterval(downTimer);
  downTimer = null;
  banner("");
  // The server may have restarted. Make sure the edit screen still has a model behind it.
  if (current === "edit") {
    api("/api/status").then((s) => {
      if (s.status === "ready") return refresh();
      modelLost();
    }).catch(() => {});
  }
}
function modelLost() {
  show("scan");
  banner("The app restarted and the model was lost. Scan again or use a sample model.", true);
}
function banner(text, info) {
  $("banner").hidden = !text;
  $("banner").textContent = text;
  $("banner").className = "banner" + (info ? " info" : "");
}

async function api(path, { method = "GET", body, json, timeout = 10000 } = {}) {
  const ctl = new AbortController();
  const timer = setTimeout(() => ctl.abort(), timeout);
  const opts = { method, signal: ctl.signal, cache: "no-store" };
  if (json !== undefined) {
    opts.headers = { "Content-Type": "application/json" };
    opts.body = JSON.stringify(json);
  } else if (body) opts.body = body;
  let res;
  try {
    res = await fetch(path, opts);
  } catch (e) {
    if (e.name === "AbortError") throw new ApiError("The app is slow to answer.", null, 0, "timeout");
    serverDown();
    throw new ApiError("Lost contact with the app.", String(e), 0, "network");
  } finally {
    clearTimeout(timer);
  }
  serverUp();
  let data = null;
  try { data = await res.json(); } catch (e) { /* empty or not JSON */ }
  if (!res.ok) {
    const d = data && data.detail;
    if (d && typeof d === "object" && !Array.isArray(d)) throw new ApiError(d.message, d.detail, res.status);
    throw new ApiError(typeof d === "string" ? d : "Something went wrong on the server.", null, res.status);
  }
  return data;
}

// ---------- Step 1: scan ----------
let stream = null, recorder = null, chunks = [], frameTimer = null, sending = false, failedFrames = 0;
let recStart = 0, recTimer = null;
const canvas = document.createElement("canvas");

async function startCamera() {
  if (stream) return;
  $("btn-start").disabled = true;
  $("camera-msg").hidden = true;
  $("coach").hidden = false;
  // The permission prompt can sit unanswered. Say so instead of showing a silent black box.
  const waitHint = setTimeout(() => { $("coach-wait").hidden = !!stream; }, 2000);
  try {
    if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) throw { name: "Insecure" };
    stream = await navigator.mediaDevices.getUserMedia({
      video: { width: { ideal: 1280 }, height: { ideal: 720 }, facingMode: { ideal: "environment" } },
      audio: false,
    });
    $("video").srcObject = stream;
    $("camera-msg").hidden = true;
    $("coach").hidden = false;
    $("btn-start").disabled = false;
    $("btn-sample").classList.remove("primary");
    stream.getVideoTracks()[0].onended = () => {
      cancelRecording();
      stopCamera();
      cameraError({ name: "Ended" });
    };
    // Light and focus checks run before Start too, so kids can fix the room first.
    frameTimer = setInterval(sendFrame, 1000);
  } catch (e) {
    stream = null;
    cameraError(e);
  } finally {
    clearTimeout(waitHint);
    $("coach-wait").hidden = true;
  }
}

function cameraError(e) {
  const text = {
    NotAllowedError: ["The camera is blocked",
      "Click the camera icon in the address bar and choose Allow. Then press Try again."],
    NotFoundError: ["No camera found", "Plug in a camera, then press Try again."],
    OverconstrainedError: ["No camera found", "Plug in a camera, then press Try again."],
    NotReadableError: ["Another app is using the camera",
      "Close Zoom, FaceTime or Photo Booth. Then press Try again."],
    Insecure: ["The camera cannot start here",
      "Open the app at http://localhost:8000 on this Mac. Browsers only allow the camera there or on https."],
    Ended: ["The camera stopped", "Check the cable, then press Try again."],
  }[e && e.name] || ["The camera did not start", "Press Try again. You can also use a sample model."];
  $("camera-msg-title").textContent = text[0];
  $("camera-msg-text").textContent = text[1] + " No camera? Use a sample model below.";
  $("camera-msg").hidden = false;
  $("coach").hidden = true;
  $("btn-sample").classList.add("primary");
  $("btn-start").disabled = true;
}
$("btn-camera-retry").onclick = () => startCamera();

function stopCamera() {
  clearInterval(frameTimer);
  frameTimer = null;
  cancelRecording();
  if (stream) stream.getTracks().forEach((t) => t.stop());
  stream = null;
  $("video").srcObject = null;
}

function drawRing(sectors) {
  const n = sectors.length, rOut = 100, rIn = 64, gap = 0.04;
  let svg = "";
  sectors.forEach((v, i) => {
    const a0 = (i / n) * 2 * Math.PI - Math.PI / 2 + gap, a1 = ((i + 1) / n) * 2 * Math.PI - Math.PI / 2 - gap;
    const p = (r, a) => `${(r * Math.cos(a)).toFixed(1)} ${(r * Math.sin(a)).toFixed(1)}`;
    const d = `M${p(rOut, a0)} A${rOut} ${rOut} 0 0 1 ${p(rOut, a1)} L${p(rIn, a1)} A${rIn} ${rIn} 0 0 0 ${p(rIn, a0)}Z`;
    const fill = v >= 1 ? "#48c774" : v > 0 ? "#f0a020" : "#000";
    const op = v >= 1 ? 1 : v > 0 ? 0.6 + 0.35 * v : 0.5;
    svg += `<path d="${d}" fill="${fill}" fill-opacity="${op}" stroke="#fff" stroke-width="4"/>`;
  });
  $("ring").innerHTML = svg;
}

function setChip(id, label, ok) {
  const el = $(id);
  el.textContent = label;
  el.className = "chip" + (ok === undefined ? "" : ok ? " ok" : " bad");
}
function resetChips() {
  setChip("chip-speed", "Speed");
  setChip("chip-light", "Light");
  setChip("chip-focus", "Focus");
}

function setWarning(text, good) {
  $("warning").hidden = !text;
  $("warning").textContent = text || "";
  $("warning").classList.toggle("good", !!good);
}

function renderGuidance(g) {
  const lightWords = { dark: "Too dark", bright: "Too bright", glare: "Glare" };
  setChip("chip-light", g.light.ok ? "Light good" : lightWords[g.light.issue] || "Light", g.light.ok);
  setChip("chip-focus", g.blur.ok ? "Sharp" : "Blurry", g.blur.ok);
  if (!recording()) {
    setChip("chip-speed", "Speed");
    const fix = !g.light.ok ? "Fix the light before you start" : !g.blur.ok ? "Hold still so the picture is sharp" : "";
    setWarning(fix);
    return;
  }
  setChip("chip-speed", g.speed.ok ? "Speed good" : "Slow down", g.speed.ok);
  drawRing(g.coverage.sectors);
  const pct = Math.round(g.coverage.pct);
  $("coverage-pct").textContent = pct + "%";
  if (g.warnings.length) setWarning(g.warnings[0]);
  else if (pct >= 95) setWarning("All the way round. Press Finish scan.", true);
  else setWarning("Good. Keep walking slowly.", true);
}

async function sendFrame() {
  const v = $("video");
  if (sending || !v.videoWidth) return;
  sending = true;
  try {
    canvas.width = 640;
    canvas.height = Math.round((640 * v.videoHeight) / v.videoWidth);
    canvas.getContext("2d").drawImage(v, 0, 0, canvas.width, canvas.height);
    const blob = await new Promise((r) => canvas.toBlob(r, "image/jpeg", 0.7));
    const g = await api("/api/guidance/frame", { method: "POST", body: blob, timeout: 4000 });
    failedFrames = 0;
    if (frameTimer) renderGuidance(g);
  } catch (e) {
    // Do not leave old green chips up when the checks have stopped.
    if (++failedFrames >= 3) {
      resetChips();
      setWarning("The checks are not answering. Keep going slowly.");
    }
  } finally {
    sending = false;
  }
}

const recording = () => recorder && recorder.state === "recording";

async function startRecording() {
  if (!stream || recording()) return;
  if (typeof MediaRecorder === "undefined") {
    return setWarning("This browser cannot record video. Use Chrome or Safari, or open a scan file.");
  }
  try { await api("/api/guidance/reset", { method: "POST", timeout: 4000 }); } catch (e) { /* the scan still records */ }
  chunks = [];
  recorder = new MediaRecorder(stream);
  recorder.ondataavailable = (e) => e.data.size && chunks.push(e.data);
  recorder.start(1000);
  drawRing(Array(12).fill(0));
  $("coverage-pct").textContent = "0%";
  $("coach").hidden = true;
  $("camera").classList.add("recording");
  $("btn-start").hidden = true;
  $("btn-stop").hidden = false;
  $("btn-stop").focus();
  recStart = Date.now();
  $("rec").hidden = false;
  $("rec-time").textContent = "0:00";
  recTimer = setInterval(() => {
    const s = Math.floor((Date.now() - recStart) / 1000);
    $("rec-time").textContent = `${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`;
  }, 500);
  setWarning("Good. Walk slowly around the object.", true);
}

function resetRecordingUi() {
  clearInterval(recTimer);
  $("camera").classList.remove("recording");
  $("rec").hidden = true;
  $("btn-start").hidden = false;
  $("btn-stop").hidden = true;
}

function cancelRecording() {
  if (recording()) {
    recorder.onstop = null;
    recorder.stop();
  }
  recorder = null;
  resetRecordingUi();
}

function finishRecording() {
  if (!recording()) return;
  const r = recorder;
  r.onstop = () => {
    const type = r.mimeType || "video/webm";
    if (!chunks.length) return setWarning("The recording was empty. Press Start scan and try again.");
    uploadScan(new Blob(chunks, { type }), "scan." + (type.includes("mp4") ? "mp4" : "webm"));
  };
  r.stop();
  recorder = null;
  resetRecordingUi();
}

$("btn-start").onclick = startRecording;
$("btn-stop").onclick = finishRecording;
$("btn-sample").onclick = useSample;
$("file-input").onchange = (e) => {
  const f = e.target.files[0];
  e.target.value = "";
  if (f) uploadScan(f, f.name);
};

function useSample() {
  uploadScan(new Blob([], { type: "video/webm" }), "sample.webm", true);
}

// ---------- Step 2: clean up ----------
let elapsedTimer = null;

function stage(id, st) {
  $(id).className = st || "";
}

function startElapsed(since) {
  clearInterval(elapsedTimer);
  const tick = () => {
    const s = Math.max(0, Math.floor((Date.now() - since) / 1000));
    $("elapsed").textContent = s;
    $("slow-msg").hidden = s < 60;
    $("btn-retry").hidden = s < 60;
  };
  tick();
  elapsedTimer = setInterval(tick, 1000);
}

function processStart(isSample, since = Date.now()) {
  show("process");
  banner("");
  $("process-busy").hidden = false;
  $("process-fail").hidden = true;
  $("btn-retry").hidden = true;
  $("btn-retry-sample").hidden = true;
  $("upload-pct").textContent = "";
  $("stage-upload").firstChild.textContent = isSample ? "Loading the sample " : "Sending the video ";
  stage("stage-upload", "active");
  stage("stage-build");
  stage("stage-ready");
  startElapsed(since);
}

function uploadScan(blob, name, isSample) {
  processStart(isSample);
  const form = new FormData();
  form.append("video", blob, name);
  // XHR because fetch cannot report upload progress.
  const xhr = new XMLHttpRequest();
  xhr.open("POST", "/api/scan");
  xhr.upload.onprogress = (e) => {
    if (e.lengthComputable && e.total > 0) $("upload-pct").textContent = Math.round((100 * e.loaded) / e.total) + "%";
  };
  xhr.onload = () => {
    let d = null;
    try { d = JSON.parse(xhr.responseText).detail; } catch (e) { /* not JSON */ }
    if (xhr.status === 409) return pollStatus(); // already processing, follow it
    if (xhr.status >= 400) return processFail((d && d.message) || "The server would not take the scan.");
    stage("stage-upload", "done");
    stage("stage-build", "active");
    pollStatus();
  };
  xhr.onerror = () => {
    serverDown();
    processFail("Lost contact with the app while sending the video.");
  };
  xhr.send(form);
}

async function pollStatus() {
  if (current !== "process") return;
  let s;
  try {
    s = await api("/api/status", { timeout: 5000 });
  } catch (e) {
    return setTimeout(pollStatus, 2000); // the banner explains, keep trying
  }
  if (s.status === "processing") {
    stage("stage-upload", "done");
    stage("stage-build", "active");
    return setTimeout(pollStatus, 1000);
  }
  if (s.status === "error") return processFail(s.error, s.detail);
  if (s.status === "ready") {
    stage("stage-build", "done");
    stage("stage-ready", "done");
    clearInterval(elapsedTimer);
    setTimeout(() => openEditor(s), reducedMotion.matches ? 0 : 500);
  }
}

function processFail(msg, detail) {
  clearInterval(elapsedTimer);
  $("process-busy").hidden = true;
  $("process-fail").hidden = false;
  $("process-error").textContent = (msg || "Something went wrong.") + " Try the scan again, or use the sample model.";
  $("process-detail").textContent = detail || "No more details.";
  $("process-detail").parentElement.hidden = !detail;
  $("btn-retry").hidden = false;
  $("btn-retry-sample").hidden = false;
  $("btn-retry").focus();
}
$("btn-retry").onclick = () => show("scan");
$("btn-retry-sample").onclick = useSample;

// ---------- Step 3: view, change, print ----------
let viewerPromise = null;
function getViewer() {
  viewerPromise ||= makeViewer().catch((e) => {
    viewerPromise = null;
    throw e;
  });
  return viewerPromise;
}

async function makeViewer() {
  const THREE = await import("three");
  const { STLLoader } = await import("three/addons/loaders/STLLoader.js");
  const { OrbitControls } = await import("three/addons/controls/OrbitControls.js");
  const el = $("viewer");
  const renderer = new THREE.WebGLRenderer({ antialias: true });
  renderer.setPixelRatio(Math.min(2, window.devicePixelRatio));
  el.appendChild(renderer.domElement);
  const scene = new THREE.Scene();
  const camera = new THREE.PerspectiveCamera(40, 1, 0.1, 5000);
  camera.up.set(0, 0, 1);
  const controls = new OrbitControls(camera, renderer.domElement);
  controls.enableDamping = true;
  controls.autoRotateSpeed = 1.5;
  controls.addEventListener("start", () => { controls.autoRotate = false; });
  scene.add(new THREE.HemisphereLight(0xffffff, 0x8899aa, 1.2));
  const sun = new THREE.DirectionalLight(0xffffff, 1.5);
  sun.position.set(1, -1, 2);
  scene.add(sun);
  const material = new THREE.MeshStandardMaterial({ color: 0x3f9a92, roughness: 0.55 });
  const grid = new THREE.GridHelper(200, 20, 0x888888, 0xbbbbbb);
  grid.rotation.x = Math.PI / 2;
  grid.material.transparent = true;
  grid.material.opacity = 0.35;
  scene.add(grid);
  let mesh = null, home = null;

  function setBackground() {
    scene.background = new THREE.Color(getComputedStyle(el).backgroundColor);
  }
  setBackground();

  function resize() {
    const w = el.clientWidth, h = el.clientHeight;
    if (!w || !h) return;
    renderer.setSize(w, h);
    camera.aspect = w / h;
    camera.updateProjectionMatrix();
  }
  new ResizeObserver(resize).observe(el);
  renderer.setAnimationLoop(() => { controls.update(); renderer.render(scene, camera); });

  function resetView() {
    if (!home) return;
    controls.target.copy(home.target);
    camera.position.copy(home.position);
    controls.update();
  }

  // Arrow keys turn the model, plus and minus zoom. Kids on a keyboard and the teacher on a remote both get this.
  el.addEventListener("keydown", (e) => {
    const off = camera.position.clone().sub(controls.target);
    const turns = { ArrowLeft: -0.2, ArrowRight: 0.2 };
    if (e.key in turns) off.applyAxisAngle(camera.up, turns[e.key]);
    else if (e.key === "+" || e.key === "=") off.multiplyScalar(0.9);
    else if (e.key === "-") off.multiplyScalar(1.1);
    else return;
    e.preventDefault();
    controls.autoRotate = false;
    camera.position.copy(controls.target).add(off);
  });

  async function load(url, reframe) {
    const res = await fetch(url, { cache: "no-store" });
    if (!res.ok) throw new Error("model " + res.status);
    const geo = new STLLoader().parse(await res.arrayBuffer());
    geo.computeVertexNormals();
    geo.computeBoundingBox();
    if (mesh) { scene.remove(mesh); mesh.geometry.dispose(); }
    mesh = new THREE.Mesh(geo, material);
    scene.add(mesh);
    const size = geo.boundingBox.getSize(new THREE.Vector3());
    const r = (n) => Math.round(n);
    $("size").textContent = `${r(size.x)} × ${r(size.y)} × ${r(size.z)} mm`;
    $("size").title = "Width by depth by height";
    grid.position.z = geo.boundingBox.min.z;
    if (reframe || !home) {
      geo.computeBoundingSphere();
      const { center, radius } = geo.boundingSphere;
      home = {
        target: center.clone(),
        position: new THREE.Vector3(center.x + radius * 2, center.y - radius * 2.2, center.z + radius * 1.6),
      };
      resetView();
      // A slow turn on first view shows the shape is real 3D. It stops at the first touch.
      controls.autoRotate = !reducedMotion.matches;
    }
  }
  return { load, resetView, setBackground };
}

async function loadModel(reframe) {
  $("viewer-msg").hidden = true;
  try {
    const v = await getViewer();
    await v.load("/api/model.stl", reframe);
  } catch (e) {
    console.warn("viewer", e);
    $("viewer-msg").hidden = false;
    $("viewer-msg").textContent = navigator.onLine === false || String(e).includes("import")
      ? "The 3D view needs the internet to load. Connect, then reload the page. Download STL still works."
      : "The 3D view could not show this model. Download STL still works.";
  }
}

function renderHistory(s) {
  const list = $("history");
  list.innerHTML = "";
  const add = (text, cls) => {
    const li = document.createElement("li");
    li.textContent = text;
    if (cls) li.className = cls;
    list.appendChild(li);
  };
  s.versions.forEach((v, i) => add(v.instruction, i === s.versions.length - 1 ? "current" : ""));
  for (const v of [...(s.redo || [])].reverse()) add(v.instruction, "undone");
  if (s.versions.length < 2 && !(s.redo || []).length) add("No changes yet. Type one above or tap an idea.", "empty");
  $("btn-undo").disabled = editBusy || s.versions.length < 2;
  $("btn-redo").disabled = editBusy || !(s.redo || []).length;
  $("badge-sample").hidden = !s.sample;
  lastState = s;
}
let lastState = null;

async function openEditor(s) {
  show("edit");
  renderHistory(s);
  await loadModel(true);
}

function editMsg(text, kind, detail) {
  const el = $("edit-msg");
  el.hidden = !text;
  el.className = "msg" + (kind ? " " + kind : "");
  el.textContent = text || "";
  if (detail) {
    const d = document.createElement("details");
    d.innerHTML = "<summary>Details for the teacher</summary><pre></pre>";
    d.querySelector("pre").textContent = detail;
    el.appendChild(d);
  }
}

let editBusy = false, editTimer = null;
function setEditBusy(on) {
  editBusy = on;
  for (const b of document.querySelectorAll("#btn-edit, .ideas button")) b.disabled = on;
  $("instruction").readOnly = on;
  $("viewer-busy").hidden = !on;
  clearInterval(editTimer);
  if (on) {
    const t0 = Date.now();
    const tick = () => {
      const sec = Math.floor((Date.now() - t0) / 1000);
      $("edit-elapsed").textContent = sec;
      $("btn-edit").textContent = `Working on it, ${sec} s`;
    };
    tick();
    editTimer = setInterval(tick, 1000);
  } else $("btn-edit").textContent = "Make the change";
  if (lastState) renderHistory(lastState);
}

async function runEdit(instruction) {
  if (editBusy) return;
  if (!instruction) {
    editMsg("Type what you want to change first. Or tap an idea.");
    return $("instruction").focus();
  }
  setEditBusy(true);
  editMsg("");
  try {
    const s = await api("/api/edit", { method: "POST", json: { instruction }, timeout: 150000 });
    $("instruction").value = "";
    renderHistory(s);
    await loadModel(false);
    editMsg("Done. Turn it around to check, then download.", "good");
  } catch (e) {
    if (e.kind === "timeout") {
      editMsg("Claude is taking too long. Wait a little, then look at the list of changes before you try again.");
      setTimeout(refresh, 15000);
    } else if (e.kind === "network") {
      editMsg("Lost contact with the app. Your last saved shape is still here.");
    } else {
      editMsg(e.message, "", e.detail);
    }
  } finally {
    setEditBusy(false);
  }
}

async function refresh() {
  try {
    const s = await api("/api/status");
    if (s.status === "ready" && current === "edit") {
      renderHistory(s);
      await loadModel(false);
    }
  } catch (e) { /* banner covers it */ }
}

async function step(path) {
  if (editBusy) return;
  try {
    const s = await api(path, { method: "POST" });
    if (!s.versions.length) return modelLost();
    renderHistory(s);
    editMsg("");
    await loadModel(false);
  } catch (e) {
    editMsg(e.message);
  }
}

$("edit-form").onsubmit = (e) => {
  e.preventDefault();
  runEdit($("instruction").value.trim());
};
// Enter sends. Shift and Enter makes a new line.
$("instruction").addEventListener("keydown", (e) => {
  if (e.key === "Enter" && !e.shiftKey && !e.isComposing) {
    e.preventDefault();
    $("edit-form").requestSubmit();
  }
});
for (const [list, box] of [[IDEAS, "ideas"], [MORE_IDEAS, "more-ideas"]]) {
  for (const [label, text, fill] of list) {
    const b = document.createElement("button");
    b.type = "button";
    b.textContent = label;
    b.title = text;
    b.onclick = () => {
      const field = $("instruction");
      field.value = text;
      if (!fill) return runEdit(text);
      field.focus();
      field.setSelectionRange(text.length, text.length);
    };
    $(box).appendChild(b);
  }
}
$("btn-undo").onclick = () => step("/api/undo");
$("btn-redo").onclick = () => step("/api/redo");
$("btn-reset-view").onclick = () => getViewer().then((v) => v.resetView()).catch(() => {});
$("btn-new").onclick = () => {
  editMsg("");
  show("scan");
};

// ---------- Keyboard ----------
document.addEventListener("keydown", (e) => {
  const typing = e.target.closest("input, textarea, select");
  if (current === "edit" && (e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "z" && !typing) {
    e.preventDefault();
    step(e.shiftKey ? "/api/redo" : "/api/undo");
  }
  if (current === "scan" && e.key === " " && !typing && !e.target.closest("button, a, summary, label")) {
    e.preventDefault();
    recording() ? finishRecording() : startRecording();
  }
});

// ---------- Theme ----------
const darkQuery = matchMedia("(prefers-color-scheme: dark)");
const isDark = () => (document.documentElement.dataset.theme || (darkQuery.matches ? "dark" : "light")) === "dark";
function syncTheme() {
  $("btn-theme").textContent = isDark() ? "Light" : "Dark";
  if (viewerPromise) viewerPromise.then((v) => v.setBackground()).catch(() => {});
}
$("btn-theme").onclick = () => {
  const next = isDark() ? "light" : "dark";
  document.documentElement.dataset.theme = next;
  try { localStorage.setItem("theme", next); } catch (e) { /* private window */ }
  syncTheme();
};
darkQuery.addEventListener("change", syncTheme);
syncTheme();

// ---------- Start ----------
drawRing(Array(12).fill(0));
// Start where the server is. A page reload keeps the current model.
(async () => {
  let s;
  try {
    s = await api("/api/status");
  } catch (e) {
    return show("scan");
  }
  $("engine-note").hidden = s.engine !== "stub";
  if (s.status === "ready") openEditor(s);
  else if (s.status === "processing") {
    processStart(false, s.started ? s.started * 1000 : Date.now());
    pollStatus();
  } else show("scan");
})();
