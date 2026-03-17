const baseUrlInput = document.getElementById("baseUrl");
const showHiddenInput = document.getElementById("showHidden");
const refreshBtn = document.getElementById("refreshBtn");
const statusText = document.getElementById("statusText");
const fileTbody = document.getElementById("fileTbody");

function getApiUrl() {
  const base = (baseUrlInput.value || "").trim().replace(/\/+$/, "");
  const hidden = showHiddenInput.checked ? "?hidden=1" : "";
  if (!base) return `/api/files${hidden}`;
  return `${base}/api/files${hidden}`;
}

function setStatus(text) {
  statusText.textContent = text;
}

function formatBytes(bytes) {
  if (bytes === 0) return "0 B";
  const units = ["B", "KB", "MB", "GB", "TB"];
  const exponent = Math.min(Math.floor(Math.log(bytes) / Math.log(1024)), units.length - 1);
  const value = bytes / Math.pow(1024, exponent);
  return `${value.toFixed(value < 10 && exponent > 0 ? 1 : 0)} ${units[exponent]}`;
}

function render(files) {
  fileTbody.innerHTML = "";

  for (const file of files) {
    const tr = document.createElement("tr");

    const nameTd = document.createElement("td");
    nameTd.className = "name";
    nameTd.textContent = file.isDir ? `${file.name}/` : file.name;
    tr.appendChild(nameTd);

    const typeTd = document.createElement("td");
    const badge = document.createElement("span");
    badge.className = "badge";
    badge.textContent = file.isDir ? "dir" : "file";
    typeTd.appendChild(badge);
    tr.appendChild(typeTd);

    const sizeTd = document.createElement("td");
    sizeTd.className = "right";
    sizeTd.textContent = file.isDir ? "-" : formatBytes(file.size || 0);
    tr.appendChild(sizeTd);

    const modTd = document.createElement("td");
    modTd.textContent = file.modTime ? new Date(file.modTime).toLocaleString() : "-";
    tr.appendChild(modTd);

    fileTbody.appendChild(tr);
  }

  if (files.length === 0) {
    const tr = document.createElement("tr");
    const td = document.createElement("td");
    td.colSpan = 4;
    td.style.color = "rgba(127, 127, 127, 0.9)";
    td.textContent = "No files found.";
    tr.appendChild(td);
    fileTbody.appendChild(tr);
  }
}

async function loadFiles() {
  const url = getApiUrl();
  setStatus(`Loading ${url} ...`);
  refreshBtn.disabled = true;

  try {
    const res = await fetch(url, { headers: { Accept: "application/json" } });
    if (!res.ok) {
      const text = await res.text();
      throw new Error(`HTTP ${res.status}: ${text}`);
    }
    const files = await res.json();
    render(Array.isArray(files) ? files : []);
    setStatus(`Loaded ${Array.isArray(files) ? files.length : 0} entries`);
  } catch (err) {
    render([]);
    setStatus(`Error: ${err?.message || String(err)}`);
  } finally {
    refreshBtn.disabled = false;
  }
}

refreshBtn.addEventListener("click", loadFiles);
showHiddenInput.addEventListener("change", loadFiles);

loadFiles();

