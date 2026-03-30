import * as THREE from 'three';
import { OrbitControls } from 'three/addons/controls/OrbitControls.js';

const API = '';
const COLORS = {
  learning: 0x3fb950, review_feedback: 0xd29922, codebase_pattern: 0x58a6ff,
};
const COLORS_CSS = {
  learning: '#3fb950', review_feedback: '#d29922', codebase_pattern: '#58a6ff',
};

// --- Detail panel ---
function showDetail(panelId, splitId, memory, extra = {}) {
  const panel = document.getElementById(panelId);
  const split = document.getElementById(splitId);
  split.classList.remove('no-detail');
  if (splitId === 'viz-split') split.classList.add('has-detail');
  panel.style.display = 'block';
  const similarityHtml = extra.similarity != null
    ? `<div class="detail-meta-row"><span class="detail-meta-label">Match</span><span class="similarity">${(extra.similarity * 100).toFixed(1)}%</span></div>` : '';

  panel.innerHTML = `
    <button class="detail-close" onclick="closeDetail('${panelId}','${splitId}')">&times;</button>
    <h3>${esc(memory.title)}</h3>
    <div class="detail-section">
      <div class="detail-section-label">Content</div>
      <div class="detail-content">${esc(memory.content)}</div>
    </div>
    <div class="detail-section">
      <div class="detail-section-label">Details</div>
      <div class="detail-meta">
        <div class="detail-meta-row">
          <span class="detail-meta-label">Category</span>
          <span class="cat-badge cat-${memory.category}">${memory.category.replace('_', ' ')}</span>
        </div>
        ${memory.repo ? `<div class="detail-meta-row"><span class="detail-meta-label">Repo</span><span>${memory.repo}</span></div>` : ''}
        ${memory.jira_key ? `<div class="detail-meta-row"><span class="detail-meta-label">Ticket</span><a href="https://redhat.atlassian.net/browse/${memory.jira_key}" target="_blank">${memory.jira_key}</a></div>` : ''}
        ${(memory.metadata && memory.metadata.pr_url) ? `<div class="detail-meta-row"><span class="detail-meta-label">PR</span><a href="${memory.metadata.pr_url}" target="_blank">${memory.metadata.pr_url.replace('https://github.com/', '')}</a></div>` : ''}
        ${similarityHtml}
        ${memory.created_at ? `<div class="detail-meta-row"><span class="detail-meta-label">Created</span><span>${new Date(memory.created_at).toLocaleDateString()} (${timeAgo(memory.created_at)})</span></div>` : ''}
        <div class="detail-meta-row"><span class="detail-meta-label">ID</span><span>#${memory.id}</span></div>
      </div>
    </div>
    ${(memory.tags && memory.tags.length) ? `
    <div class="detail-section">
      <div class="detail-section-label">Tags</div>
      <div class="detail-tags">${memory.tags.map(t => `<span class="tag" onclick="filterByTag('${esc(t)}')">${t}</span>`).join('')}</div>
    </div>` : ''}
    <div class="detail-actions">
      <button class="btn-delete" onclick="deleteMemory(${memory.id}, '${panelId}', '${splitId}')">Delete memory</button>
    </div>
  `;
}

window.deleteMemory = async function(id, panelId, splitId) {
  if (!confirm('Delete this memory?')) return;
  const res = await fetch(API + '/api/memories/' + id, { method: 'DELETE' });
  if (res.ok) {
    closeDetail(panelId, splitId);
    loadStats();
    loadMemories();
  } else {
    alert('Failed to delete memory');
  }
};

window.closeDetail = function(panelId, splitId) {
  document.getElementById(panelId).style.display = 'none';
  const split = document.getElementById(splitId);
  split.classList.add('no-detail');
  if (splitId === 'viz-split') split.classList.remove('has-detail');
  // Deselect cards
  document.querySelectorAll('.memory-card.selected').forEach(c => c.classList.remove('selected'));
};

// --- Hash routing ---
// Format: #tab?key=val&key=val  (e.g. #memories?category=learning&repo=insights-chrome&page=2)
let suppressHashUpdate = false;

function updateHash() {
  if (suppressHashUpdate) return;
  const tab = document.querySelector('.tab.active')?.dataset.tab || 'tasks';
  const params = new URLSearchParams();

  if (tab === 'tasks') {
    const s = document.getElementById('task-status-filter').value;
    if (s) params.set('status', s);
    if (tasksOffset > 0) params.set('page', Math.floor(tasksOffset / TASKS_PER_PAGE) + 1);
  } else if (tab === 'memories') {
    const c = document.getElementById('mem-category-filter').value;
    const r = document.getElementById('mem-repo-filter').value;
    const t = document.getElementById('mem-tag-filter').value;
    if (c) params.set('category', c);
    if (r) params.set('repo', r);
    if (t) params.set('tag', t);
    if (memoriesOffset > 0) params.set('page', Math.floor(memoriesOffset / MEMORIES_PER_PAGE) + 1);
  } else if (tab === 'search') {
    const q = document.getElementById('search-input').value.trim();
    if (q) params.set('q', q);
  }

  const str = params.toString();
  const hash = '#' + tab + (str ? '?' + str : '');
  if (location.hash !== hash) history.replaceState(null, '', hash);
}

function applyHash() {
  const raw = location.hash.slice(1) || 'tasks';
  const [tab, qs] = raw.split('?');
  const params = new URLSearchParams(qs || '');

  suppressHashUpdate = true;

  // Activate tab
  document.querySelectorAll('.tab').forEach(t => t.classList.remove('active'));
  document.querySelectorAll('.panel').forEach(p => p.classList.remove('active'));
  const tabEl = document.querySelector(`.tab[data-tab="${tab}"]`);
  if (tabEl) {
    tabEl.classList.add('active');
    document.getElementById('panel-' + tab)?.classList.add('active');
  }

  // Apply filters for the active tab, load defaults for others
  if (tab === 'tasks') {
    document.getElementById('task-status-filter').value = params.get('status') || '';
    tasksOffset = params.has('page') ? (parseInt(params.get('page')) - 1) * TASKS_PER_PAGE : 0;
  } else if (tab === 'memories') {
    document.getElementById('mem-category-filter').value = params.get('category') || '';
    document.getElementById('mem-repo-filter').value = params.get('repo') || '';
    document.getElementById('mem-tag-filter').value = params.get('tag') || '';
    memoriesOffset = params.has('page') ? (parseInt(params.get('page')) - 1) * MEMORIES_PER_PAGE : 0;
  } else if (tab === 'search') {
    const q = params.get('q') || '';
    document.getElementById('search-input').value = q;
    if (q) doSearch();
  } else if (tab === 'viz') {
    loadViz();
  }
  loadTasks();
  loadMemories();

  suppressHashUpdate = false;
}

window.addEventListener('hashchange', applyHash);

// Tabs
document.querySelectorAll('.tab').forEach(tab => {
  tab.addEventListener('click', () => {
    document.querySelectorAll('.tab').forEach(t => t.classList.remove('active'));
    document.querySelectorAll('.panel').forEach(p => p.classList.remove('active'));
    tab.classList.add('active');
    document.getElementById('panel-' + tab.dataset.tab).classList.add('active');
    if (tab.dataset.tab === 'viz') loadViz();
    updateHash();
  });
});

// Load stats
async function loadStats() {
  const res = await fetch(API + '/api/stats');
  const data = await res.json();
  const bar = document.getElementById('stats-bar');
  const taskTotal = Object.values(data.tasks).reduce((a, b) => a + b, 0);
  bar.innerHTML = `
    <span class="stat"><span class="dot" style="background:var(--accent)"></span>${taskTotal} tasks</span>
    <span class="stat"><span class="dot" style="background:var(--purple)"></span>${data.memories.total} memories</span>
  `;
}

// Pagination helper
function renderPagination(containerId, total, limit, offset, loadFn) {
  const pag = document.getElementById(containerId + '-pag');
  const page = Math.floor(offset / limit) + 1;
  const pages = Math.ceil(total / limit);
  if (pages <= 1) { pag.innerHTML = ''; return; }
  const key = containerId.replace(/-/g, '_');
  pag.innerHTML = `
    <button ${page <= 1 ? 'disabled' : ''} onclick="window._pag_${key}(${offset - limit})">Prev</button>
    <span>Page ${page} of ${pages} (${total} total)</span>
    <button ${page >= pages ? 'disabled' : ''} onclick="window._pag_${key}(${offset + limit})">Next</button>
  `;
  window['_pag_' + key] = (newOffset) => { loadFn(newOffset); updateHash(); };
}

// Tasks
let allTasks = [];
let tasksOffset = 0;
const TASKS_PER_PAGE = 20;
async function loadTasks(offset) {
  if (offset !== undefined) tasksOffset = offset;
  const status = document.getElementById('task-status-filter').value;
  const params = new URLSearchParams({ limit: TASKS_PER_PAGE, offset: tasksOffset });
  if (status) params.set('status', status);
  const res = await fetch(API + '/api/tasks?' + params);
  const data = await res.json();
  allTasks = data.items;
  const el = document.getElementById('task-list');
  renderPagination('task-list', data.total, data.limit, data.offset, loadTasks);
  if (!allTasks.length) { el.innerHTML = '<div class="empty">No tasks found</div>'; return; }
  el.innerHTML = allTasks.map((t, i) => `
    <div class="task-card status-${t.status}" data-task-idx="${i}">
      <div class="task-header">
        <span class="task-key">${t.jira_key}</span>
        <span class="badge badge-${t.status}">${t.status.replace('_', ' ')}</span>
      </div>
      ${t.title ? `<div class="task-title">${esc(t.title)}</div>` : ''}
      <div class="task-meta">
        ${t.repo ? `<span>repo: ${t.repo}</span>` : ''}
        ${t.pr_url ? `<span>PR #${t.pr_number}</span>` : t.pr_number ? `<span>PR #${t.pr_number}</span>` : ''}
        <span>created: ${new Date(t.created_at).toLocaleDateString()}</span>
        <span>last: ${timeAgo(t.last_addressed)}</span>
      </div>
      ${t.metadata && t.metadata.last_step ? `<div style="margin-top:6px;font-size:12px;color:var(--text-dim)">Step: ${t.metadata.last_step.replace(/_/g, ' ')}${t.metadata.next_step ? ' → ' + t.metadata.next_step.replace(/_/g, ' ') : ''}</div>` : ''}
      ${t.paused_reason ? `<div style="margin-top:8px;font-size:13px;color:var(--yellow)">Paused: ${esc(t.paused_reason)}</div>` : ''}
    </div>
  `).join('');

  el.querySelectorAll('.task-card').forEach(card => {
    card.addEventListener('click', (e) => {
      if (e.target.tagName === 'A') return;
      const idx = parseInt(card.dataset.taskIdx);
      el.querySelectorAll('.task-card').forEach(c => c.classList.remove('selected'));
      card.classList.add('selected');
      showTaskDetail(allTasks[idx]);
    });
  });
}

function showTaskDetail(t) {
  const panel = document.getElementById('task-detail');
  const split = document.getElementById('tasks-split');
  split.classList.remove('no-detail');
  panel.style.display = 'block';

  panel.innerHTML = `
    <button class="detail-close" onclick="closeDetail('task-detail','tasks-split')">&times;</button>
    <h3>${esc(t.title || t.jira_key)}</h3>
    <div class="detail-section">
      <div class="detail-meta">
        <div class="detail-meta-row">
          <span class="detail-meta-label">Ticket</span>
          <a href="https://redhat.atlassian.net/browse/${t.jira_key}" target="_blank">${t.jira_key}</a>
        </div>
        <div class="detail-meta-row">
          <span class="detail-meta-label">Status</span>
          <span class="badge badge-${t.status}">${t.status.replace('_', ' ')}</span>
        </div>
        ${t.repo ? `<div class="detail-meta-row"><span class="detail-meta-label">Repo</span><span>${t.repo}</span></div>` : ''}
        ${t.branch ? `<div class="detail-meta-row"><span class="detail-meta-label">Branch</span><span style="font-family:monospace;font-size:12px">${t.branch}</span></div>` : ''}
        ${t.pr_url ? `<div class="detail-meta-row"><span class="detail-meta-label">PR</span><a href="${t.pr_url}" target="_blank">${t.pr_url.replace('https://github.com/', '')}</a></div>` : t.pr_number ? `<div class="detail-meta-row"><span class="detail-meta-label">PR</span><span>#${t.pr_number}</span></div>` : ''}
        <div class="detail-meta-row"><span class="detail-meta-label">Created</span><span>${new Date(t.created_at).toLocaleDateString()} (${timeAgo(t.created_at)})</span></div>
        <div class="detail-meta-row"><span class="detail-meta-label">Last active</span><span>${new Date(t.last_addressed).toLocaleDateString()} (${timeAgo(t.last_addressed)})</span></div>
      </div>
    </div>
    ${t.summary ? `
    <div class="detail-section">
      <div class="detail-section-label">Summary</div>
      <div class="detail-content">${esc(t.summary)}</div>
    </div>` : ''}
    ${t.paused_reason ? `
    <div class="detail-section">
      <div class="detail-section-label">Paused Reason</div>
      <div class="detail-content" style="color:var(--yellow)">${esc(t.paused_reason)}</div>
    </div>` : ''}
    ${t.metadata && t.metadata.last_step ? `
    <div class="detail-section">
      <div class="detail-section-label">Progress</div>
      <div class="detail-meta">
        <div class="detail-meta-row"><span class="detail-meta-label">Step</span><span class="badge badge-in_progress">${t.metadata.last_step.replace(/_/g, ' ')}</span></div>
        ${t.metadata.next_step ? `<div class="detail-meta-row"><span class="detail-meta-label">Next</span><span>${t.metadata.next_step.replace(/_/g, ' ')}</span></div>` : ''}
        ${t.metadata.files_changed ? `<div class="detail-meta-row"><span class="detail-meta-label">Files</span><span style="font-family:monospace;font-size:11px">${t.metadata.files_changed.join(', ')}</span></div>` : ''}
        ${t.metadata.commits ? `<div class="detail-meta-row"><span class="detail-meta-label">Commits</span><span style="font-family:monospace;font-size:11px">${t.metadata.commits.length} commit(s)</span></div>` : ''}
        ${t.metadata.notes ? `<div class="detail-meta-row"><span class="detail-meta-label">Notes</span><span>${esc(t.metadata.notes)}</span></div>` : ''}
      </div>
    </div>` : ''}
    ${t.metadata && Object.keys(t.metadata).length && !t.metadata.last_step ? `
    <div class="detail-section">
      <div class="detail-section-label">Metadata</div>
      <div class="detail-content" style="font-family:monospace;font-size:12px">${esc(JSON.stringify(t.metadata, null, 2))}</div>
    </div>` : ''}
  `;
}

document.getElementById('task-status-filter').addEventListener('change', () => { loadTasks(0); updateHash(); });

// Memories
let allMemories = [];
let memoriesOffset = 0;
const MEMORIES_PER_PAGE = 20;
async function loadMemories(offset) {
  if (offset !== undefined) memoriesOffset = offset;
  const cat = document.getElementById('mem-category-filter').value;
  const repo = document.getElementById('mem-repo-filter').value;
  const tag = document.getElementById('mem-tag-filter').value;
  const params = new URLSearchParams({ limit: MEMORIES_PER_PAGE, offset: memoriesOffset });
  if (cat) params.set('category', cat);
  if (repo) params.set('repo', repo);
  if (tag) params.set('tag', tag);
  const res = await fetch(API + '/api/memories?' + params);
  const data = await res.json();
  allMemories = data.items;
  renderMemories(document.getElementById('memory-list'), allMemories, false, 'memory-detail', 'memories-split');
  renderPagination('memory-list', data.total, data.limit, data.offset, loadMemories);
}

async function loadFilters() {
  const tagRes = await fetch(API + '/api/tags');
  const tags = await tagRes.json();
  const tagSel = document.getElementById('mem-tag-filter');
  tags.forEach(t => { const o = document.createElement('option'); o.value = t; o.textContent = t; tagSel.appendChild(o); });

  const statsRes = await fetch(API + '/api/stats');
  const stats = await statsRes.json();
  const repoSel = document.getElementById('mem-repo-filter');
  Object.keys(stats.memories.by_repo).forEach(r => {
    if (r === 'unset') return;
    const o = document.createElement('option'); o.value = r; o.textContent = r; repoSel.appendChild(o);
  });
}

document.getElementById('mem-category-filter').addEventListener('change', () => { loadMemories(0); updateHash(); });
document.getElementById('mem-repo-filter').addEventListener('change', () => { loadMemories(0); updateHash(); });
document.getElementById('mem-tag-filter').addEventListener('change', () => { loadMemories(0); updateHash(); });

// Search
let searchResults = [];
async function doSearch() {
  const q = document.getElementById('search-input').value.trim();
  if (!q) return;
  const res = await fetch(API + '/api/memories/search?q=' + encodeURIComponent(q));
  searchResults = await res.json();
  renderMemories(document.getElementById('search-results'), searchResults, true, 'search-detail', 'search-split');
  updateHash();
}

document.getElementById('search-btn').addEventListener('click', doSearch);
document.getElementById('search-input').addEventListener('keydown', e => { if (e.key === 'Enter') doSearch(); });

function renderMemories(container, mems, showSimilarity, detailPanelId, splitId) {
  if (!mems.length) { container.innerHTML = '<div class="empty">No memories found</div>'; return; }
  container.innerHTML = mems.map((m, i) => `
    <div class="memory-card" data-idx="${i}" data-detail="${detailPanelId}" data-split="${splitId}">
      <div class="memory-title">${esc(m.title)}</div>
      <div class="memory-content">${esc(m.content).substring(0, 150)}${m.content.length > 150 ? '...' : ''}</div>
      <div class="memory-footer">
        <span class="cat-badge cat-${m.category}">${m.category.replace('_', ' ')}</span>
        ${m.repo ? `<span>repo: ${m.repo}</span>` : ''}
        ${m.jira_key ? `<a href="https://redhat.atlassian.net/browse/${m.jira_key}" target="_blank">${m.jira_key}</a>` : ''}
        ${(m.tags || []).map(t => `<span class="tag">${t}</span>`).join('')}
        ${showSimilarity && m.similarity != null ? `<span class="similarity">${(m.similarity * 100).toFixed(1)}%</span>` : ''}
      </div>
    </div>
  `).join('');

  // Click handlers
  container.querySelectorAll('.memory-card').forEach(card => {
    card.addEventListener('click', (e) => {
      if (e.target.tagName === 'A' || e.target.classList.contains('tag')) return;
      const idx = parseInt(card.dataset.idx);
      const mem = mems[idx];
      container.querySelectorAll('.memory-card').forEach(c => c.classList.remove('selected'));
      card.classList.add('selected');
      showDetail(card.dataset.detail, card.dataset.split, mem, { similarity: mem.similarity });
    });
  });
}

window.filterByTag = function(tag) {
  document.querySelectorAll('.tab')[1].click();
  document.getElementById('mem-tag-filter').value = tag;
  loadMemories();
};

// ---- 3D Embedding Visualization ----
let vizInitialized = false;
let renderer, scene, camera, controls, pointsGroup;
let vizPoints = [];
let raycaster, mouse;

async function loadViz() {
  const res = await fetch(API + '/api/memories/embeddings');
  vizPoints = await res.json();
  if (!vizPoints.length) return;

  const container = document.getElementById('viz-container');
  const tooltip = document.getElementById('viz-tooltip');

  if (vizInitialized) {
    updatePoints();
    return;
  }
  vizInitialized = true;

  const W = container.clientWidth;
  const H = container.clientHeight;

  scene = new THREE.Scene();
  scene.background = new THREE.Color(0x161b22);

  camera = new THREE.PerspectiveCamera(60, W / H, 0.1, 100);
  camera.position.set(2.5, 1.8, 2.5);

  renderer = new THREE.WebGLRenderer({ antialias: true });
  renderer.setSize(W, H);
  renderer.setPixelRatio(window.devicePixelRatio);
  container.insertBefore(renderer.domElement, tooltip);

  controls = new OrbitControls(camera, renderer.domElement);
  controls.enableDamping = true;
  controls.dampingFactor = 0.08;
  controls.rotateSpeed = 0.8;
  controls.zoomSpeed = 1.2;
  controls.panSpeed = 0.8;
  controls.minDistance = 0.5;
  controls.maxDistance = 20;

  // Subtle grid
  const grid = new THREE.GridHelper(4, 20, 0x30363d, 0x21262d);
  grid.position.y = -1.5;
  scene.add(grid);

  // Axes hint
  const axLen = 0.3;
  const axMat = (c) => new THREE.LineBasicMaterial({ color: c, transparent: true, opacity: 0.4 });
  [[axLen,0,0,0xff4444],[0,axLen,0,0x44ff44],[0,0,axLen,0x4444ff]].forEach(([x,y,z,c]) => {
    const g = new THREE.BufferGeometry().setFromPoints([new THREE.Vector3(0,0,0), new THREE.Vector3(x,y,z)]);
    scene.add(new THREE.Line(g, axMat(c)));
  });

  raycaster = new THREE.Raycaster();
  raycaster.params.Points.threshold = 0.08;
  mouse = new THREE.Vector2();

  pointsGroup = new THREE.Group();
  scene.add(pointsGroup);

  updatePoints();

  // Legend
  const legend = document.getElementById('viz-legend');
  const cats = [...new Set(vizPoints.map(p => p.category))];
  legend.innerHTML = cats.map(c =>
    `<div class="legend-item"><span class="legend-dot" style="background:${COLORS_CSS[c] || '#8b949e'}"></span>${c.replace('_', ' ')}</div>`
  ).join('');

  // Hover tooltip
  let hoveredIdx = -1;
  renderer.domElement.addEventListener('mousemove', (e) => {
    const rect = renderer.domElement.getBoundingClientRect();
    mouse.x = ((e.clientX - rect.left) / rect.width) * 2 - 1;
    mouse.y = -((e.clientY - rect.top) / rect.height) * 2 + 1;

    raycaster.setFromCamera(mouse, camera);
    const meshes = pointsGroup.children.filter(c => c.isMesh);
    const intersects = raycaster.intersectObjects(meshes);

    if (intersects.length > 0) {
      const idx = intersects[0].object.userData.idx;
      if (idx !== hoveredIdx) {
        hoveredIdx = idx;
        const p = vizPoints[idx];
        meshes.forEach((m, i) => {
          m.material.opacity = i === idx ? 1.0 : 0.3;
          m.scale.setScalar(i === idx ? 1.8 : 1.0);
        });
        tooltip.style.display = 'block';
        tooltip.innerHTML = `
          <strong>${esc(p.title)}</strong><br>
          <span style="color:${COLORS_CSS[p.category] || '#8b949e'}">${p.category.replace('_', ' ')}</span>
          ${p.repo ? ' | ' + p.repo : ''}
        `;
      }
      const cRect = container.getBoundingClientRect();
      tooltip.style.left = Math.min(e.clientX - cRect.left + 14, cRect.width - 360) + 'px';
      tooltip.style.top = Math.max(e.clientY - cRect.top - 10, 0) + 'px';
    } else {
      if (hoveredIdx !== -1) {
        hoveredIdx = -1;
        meshes.forEach(m => { m.material.opacity = 0.85; m.scale.setScalar(1.0); });
        tooltip.style.display = 'none';
      }
    }
  });

  // Click to show detail panel
  renderer.domElement.addEventListener('click', (e) => {
    const rect = renderer.domElement.getBoundingClientRect();
    mouse.x = ((e.clientX - rect.left) / rect.width) * 2 - 1;
    mouse.y = -((e.clientY - rect.top) / rect.height) * 2 + 1;

    raycaster.setFromCamera(mouse, camera);
    const meshes = pointsGroup.children.filter(c => c.isMesh);
    const intersects = raycaster.intersectObjects(meshes);

    if (intersects.length > 0) {
      const idx = intersects[0].object.userData.idx;
      const p = vizPoints[idx];
      // Fetch full memory data
      fetch(API + '/api/memories/' + p.id).then(r => r.json()).then(full => {
        if (full) showDetail('viz-detail', 'viz-split', full);
      });
    }
  });

  // Resize
  const onResize = () => {
    const w = container.clientWidth, h = container.clientHeight;
    camera.aspect = w / h;
    camera.updateProjectionMatrix();
    renderer.setSize(w, h);
  };
  window.addEventListener('resize', onResize);

  function animate() {
    requestAnimationFrame(animate);
    controls.update();
    renderer.render(scene, camera);
  }
  animate();
}

function updatePoints() {
  while (pointsGroup.children.length) pointsGroup.remove(pointsGroup.children[0]);

  const SPREAD = 2.5;
  const sphereGeo = new THREE.SphereGeometry(0.06, 16, 12);

  vizPoints.forEach((p, i) => {
    const color = COLORS[p.category] || 0x8b949e;
    const mat = new THREE.MeshBasicMaterial({ color, transparent: true, opacity: 0.85 });
    const mesh = new THREE.Mesh(sphereGeo, mat);
    mesh.position.set(p.x * SPREAD, p.y * SPREAD, p.z * SPREAD);
    mesh.userData = { idx: i };
    pointsGroup.add(mesh);
  });

  // Lines between nearby same-category points
  const lineMat = new THREE.LineBasicMaterial({ color: 0x30363d, transparent: true, opacity: 0.15 });
  for (let i = 0; i < vizPoints.length; i++) {
    for (let j = i + 1; j < vizPoints.length; j++) {
      if (vizPoints[i].category !== vizPoints[j].category) continue;
      const a = vizPoints[i], b = vizPoints[j];
      const dist = Math.sqrt((a.x-b.x)**2 + (a.y-b.y)**2 + (a.z-b.z)**2);
      if (dist < 0.6) {
        const lineGeo = new THREE.BufferGeometry().setFromPoints([
          new THREE.Vector3(a.x * SPREAD, a.y * SPREAD, a.z * SPREAD),
          new THREE.Vector3(b.x * SPREAD, b.y * SPREAD, b.z * SPREAD),
        ]);
        pointsGroup.add(new THREE.Line(lineGeo, lineMat));
      }
    }
  }
}

// Helpers
function esc(s) { const d = document.createElement('div'); d.textContent = s || ''; return d.innerHTML; }
function timeAgo(iso) {
  const d = new Date(iso); const s = Math.floor((Date.now() - d) / 1000);
  if (s < 60) return 'just now';
  if (s < 3600) return Math.floor(s/60) + 'm ago';
  if (s < 86400) return Math.floor(s/3600) + 'h ago';
  return Math.floor(s/86400) + 'd ago';
}

// ---- WebSocket live updates ----
const EVENT_LABELS = {
  task_added: { icon: '+', label: 'Task added' },
  task_updated: { icon: '~', label: 'Task updated' },
  task_removed: { icon: '-', label: 'Task removed' },
  memory_stored: { icon: '+', label: 'Memory stored' },
  memory_deleted: { icon: '-', label: 'Memory deleted' },
};

function showToast(event) {
  const container = document.getElementById('toast-container');
  const meta = EVENT_LABELS[event.type] || { icon: '*', label: event.type };
  const detail = event.data.jira_key || event.data.title || (event.data.id ? `#${event.data.id}` : '');
  const summary = event.data.summary || event.data.status || event.data.category || '';

  const toast = document.createElement('div');
  toast.className = `toast type-${event.type}`;
  toast.innerHTML = `
    <span class="toast-icon">${meta.icon}</span>
    <div class="toast-body">
      <div class="toast-title">${meta.label}${detail ? ': ' + esc(detail) : ''}</div>
      ${summary ? `<div class="toast-message">${esc(summary)}</div>` : ''}
      <div class="toast-time">${new Date(event.timestamp * 1000).toLocaleTimeString()}</div>
    </div>
    <button class="toast-close">&times;</button>
  `;

  const dismiss = () => toast.remove();
  toast.querySelector('.toast-close').addEventListener('click', (e) => { e.stopPropagation(); dismiss(); });
  toast.addEventListener('click', dismiss);

  container.prepend(toast);
}

function connectWS() {
  const wsIndicator = document.getElementById('ws-status');
  const proto = location.protocol === 'https:' ? 'wss:' : 'ws:';
  const ws = new WebSocket(`${proto}//${location.host}/ws`);

  ws.onopen = () => {
    wsIndicator.classList.add('connected');
    wsIndicator.title = 'Live updates connected';
  };

  ws.onclose = () => {
    wsIndicator.classList.remove('connected');
    wsIndicator.title = 'Live updates disconnected — reconnecting...';
    setTimeout(connectWS, 3000);
  };

  ws.onerror = () => ws.close();

  ws.onmessage = (msg) => {
    try {
      const event = JSON.parse(msg.data);
      showToast(event);

      // Auto-refresh relevant data
      if (event.type.startsWith('task_')) {
        loadTasks();
        loadStats();
      } else if (event.type.startsWith('memory_')) {
        loadMemories();
        loadStats();
      }
    } catch (e) {
      console.error('WS parse error:', e);
    }
  };
}

// Init
loadStats();
loadFilters().then(() => applyHash());
connectWS();
