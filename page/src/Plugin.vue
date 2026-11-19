<template>
  <div>
    <h2 class="mb-4">Yazi</h2>

    <v-skeleton-loader v-if="loading" :loading="true" type="card" />

    <div v-else style="margin-bottom: 80px">
      <v-alert v-if="error" type="error" variant="tonal" closable class="mb-4" @click:close="error = ''">
        {{ error }}
      </v-alert>

      <v-alert v-if="status.storage_mode === 'ram'" type="warning" variant="tonal" class="mb-4">
        <div class="font-weight-medium">Everything is in RAM</div>
        <div class="text-body-2 mt-1">
          No app directory is configured. Config, data, state, and cache will be lost on reboot.
          Set one absolute directory below to persist this app.
        </div>
      </v-alert>

      <v-card class="mb-4 pa-0">
        <v-card-title class="d-flex align-center">
          <v-icon class="mr-2">mdi-file-tree</v-icon>
          <span>Status</span>
          <v-spacer />
          <v-chip :color="status.installed ? 'success' : 'grey'" size="small" variant="tonal">
            {{ status.installed ? 'Installed' : 'Not installed' }}
          </v-chip>
        </v-card-title>
        <v-card-text>
          <v-row>
            <v-col cols="12" md="3">
              <div class="text-caption text-medium-emphasis">Version</div>
              <div class="text-subtitle-1 font-weight-medium">{{ status.version || 'Not installed' }}</div>
            </v-col>
            <v-col cols="12" md="3">
              <div class="text-caption text-medium-emphasis">Commands</div>
              <div class="text-subtitle-1 font-weight-medium"><code>yazi</code> / <code>ya</code></div>
            </v-col>
            <v-col cols="12" md="3">
              <div class="text-caption text-medium-emphasis">Storage</div>
              <v-chip
                size="small"
                :color="status.storage_mode === 'custom' ? 'success' : 'info'"
                variant="tonal"
              >
                {{ status.storage_mode === 'custom' ? 'Configured directory' : 'RAM' }}
              </v-chip>
            </v-col>
            <v-col cols="12" md="3">
              <div class="text-caption text-medium-emphasis">App root</div>
              <div class="text-body-2">{{ status.app_root || '-' }}</div>
            </v-col>
          </v-row>

          <div class="d-flex flex-wrap ga-2 mt-4">
            <v-btn size="small" variant="text" @click="refreshAll">Refresh</v-btn>
          </div>
          <p class="text-caption text-medium-emphasis mt-2">
            Updates come through the MOS Hub plugin release.
          </p>
        </v-card-text>
      </v-card>

      <v-card class="mb-4 pa-0">
        <v-card-title class="d-flex align-center">
          <v-icon class="mr-2">mdi-puzzle-outline</v-icon>
          <span>Dependencies</span>
          <v-spacer />
          <v-chip :color="missingDeps.length ? 'warning' : 'success'" size="small" variant="tonal">
            {{ missingDeps.length ? `${missingDeps.length} missing` : 'Ready' }}
          </v-chip>
        </v-card-title>
        <v-card-text>
          <v-alert v-if="status.deps_failed" type="warning" variant="tonal" class="mb-4">
            The last dependency install did not finish. Log: <code>{{ status.deps_log }}</code>
          </v-alert>

          <v-progress-linear v-if="status.deps_installing" indeterminate color="primary" class="mb-4" />

          <div v-for="group in depGroups" :key="group.key" class="mb-4">
            <div class="d-flex align-center flex-wrap ga-2">
              <div class="text-subtitle-2">{{ group.title }}</div>
              <v-chip
                size="x-small"
                :color="groupMissing(group) ? 'warning' : 'success'"
                variant="tonal"
              >
                {{ groupMissing(group) ? `${groupMissing(group)} missing` : 'Ready' }}
              </v-chip>
              <v-spacer />
              <v-btn
                v-if="groupMissing(group)"
                size="x-small"
                variant="tonal"
                :loading="installingGroup === group.key"
                :disabled="status.deps_installing"
                @click="installGroup(group.key)"
              >
                Install
              </v-btn>
            </div>
            <div class="text-caption text-medium-emphasis mt-1">{{ group.note }}</div>
            <div class="d-flex flex-wrap ga-2 mt-2">
              <v-chip
                v-for="dep in group.deps"
                :key="dep.key"
                size="small"
                variant="tonal"
                :color="status.deps[dep.key] ? 'success' : 'grey'"
              >
                <v-icon start size="14">{{ status.deps[dep.key] ? 'mdi-check' : 'mdi-close' }}</v-icon>
                {{ dep.label }}
              </v-chip>
            </div>
          </div>

          <p class="text-caption text-medium-emphasis mt-2">
            Only <code>file</code> is installed automatically. The media group is a large download
            and is only needed for video, PDF, archive, and AVIF/HEIC/JXL previews.
          </p>
          <p class="text-caption text-medium-emphasis">
            Image preview also requires a terminal that supports Kitty graphics, Sixel, or iTerm2 images.
          </p>
        </v-card-text>
      </v-card>

      <v-card class="mb-4 pa-0">
        <v-card-title class="d-flex align-center">
          <v-icon class="mr-2">mdi-file-cog-outline</v-icon>
          <span>Configuration</span>
        </v-card-title>
        <v-card-text>
          <v-text-field
            v-model="form.data_dir"
            label="App directory (optional)"
            hint="Empty uses RAM (/run/yazi). Set one absolute directory; config, data, state, and cache go under it."
            persistent-hint
            density="compact"
            variant="outlined"
            class="mb-4"
          />

          <v-row class="mb-2">
            <v-col cols="12" md="6">
              <div class="text-caption text-medium-emphasis">Current app root</div>
              <div class="text-body-2">{{ status.app_root || '-' }}</div>
            </v-col>
            <v-col cols="12" md="6">
              <div class="text-caption text-medium-emphasis">Yazi config</div>
              <div class="text-body-2">{{ status.config_root || '-' }}</div>
            </v-col>
          </v-row>

          <p class="text-body-2 text-medium-emphasis mt-2">
            With an app directory, Yazi keeps <code>config/</code>, <code>data/</code>,
            <code>state/</code>, and <code>cache/</code> inside it. With no directory, all four
            are in <code>/run/yazi</code> and are discarded on reboot.
          </p>

          <div class="d-flex flex-wrap ga-2 mt-4">
            <v-btn size="small" color="primary" :loading="saving" @click="saveSettings">
              <v-icon start>mdi-content-save</v-icon>
              Save settings
            </v-btn>
            <v-btn size="small" variant="text" @click="useRam">Use RAM</v-btn>
          </div>
        </v-card-text>
      </v-card>

      <v-card class="mb-4 pa-0">
        <v-card-title class="d-flex align-center">
          <v-icon class="mr-2">mdi-terminal</v-icon>
          <span>Use</span>
        </v-card-title>
        <v-card-text>
          <pre class="yazi-code">yazi
yazi /mnt/cache
ya pkg add yazi-rs/plugins:smart-enter</pre>
          <p class="text-caption text-medium-emphasis mt-2">
            Yazi config: <code>{{ status.config_root || '-' }}</code><br />
            Data: <code>{{ status.data_root || '-' }}</code>
          </p>
        </v-card-text>
      </v-card>

      <v-card class="pa-0">
        <v-card-title class="d-flex align-center">
          <v-icon class="mr-2">mdi-view-grid-plus-outline</v-icon>
          <span>Recommended plugins</span>
        </v-card-title>
        <v-card-text>
          <p class="text-body-2 mb-3">
            <code>ya</code> installs plugins into the configured app directory.
          </p>
          <pre class="yazi-code">{{ pluginCommands }}</pre>
          <div class="d-flex flex-wrap ga-2 mt-3">
            <v-btn size="small" variant="text" prepend-icon="mdi-content-copy" @click="copyPluginCommands">
              Copy commands
            </v-btn>
          </div>
          <p class="text-caption text-medium-emphasis mt-2">
            Enable each plugin in <code>init.lua</code> as described in its own README.
          </p>
        </v-card-text>
      </v-card>
    </div>

    <v-snackbar v-model="snackbar" :color="snackbarColor" timeout="4000">{{ snackbarText }}</v-snackbar>
  </div>
</template>

<script setup>
import { ref, reactive, computed, onMounted, onUnmounted } from 'vue';

const PLUGIN_NAME = 'yazi';
const DEFAULT_SETTINGS = { data_dir: '' };

const loading = ref(true);
const saving = ref(false);
const error = ref('');
const snackbar = ref(false);
const snackbarText = ref('');
const snackbarColor = ref('success');
const installingGroup = ref('');

const settings = reactive({ ...DEFAULT_SETTINGS });
const form = reactive({ data_dir: '' });
const status = reactive({
  installed: false,
  version: '',
  app_root: '',
  storage_mode: 'ram',
  config: '',
  config_root: '',
  data: '',
  data_root: '',
  config_exists: false,
  command: 'yazi',
  deps: {},
  missing_deps: [],
  deps_installing: false,
  deps_failed: false,
  deps_log: '',
});

const depGroups = [
  {
    key: 'core',
    title: 'Required',
    note: 'MIME detection. Without this, Yazi cannot preview files.',
    deps: [
      { key: 'file', label: 'file' },
    ],
  },
  {
    key: 'search',
    title: 'Search & navigation',
    note: 'Small packages for content search, file search, and jumps.',
    deps: [
      { key: 'rg', label: 'ripgrep' },
      { key: 'fd', label: 'fd' },
      { key: 'fzf', label: 'fzf' },
      { key: 'zoxide', label: 'zoxide' },
      { key: 'jq', label: 'jq' },
    ],
  },
  {
    key: 'media',
    title: 'Media previews',
    note: 'Large download. Only needed for video, PDF, archives, and AVIF/HEIC/JXL.',
    deps: [
      { key: 'ffmpeg', label: 'ffmpeg' },
      { key: 'pdftoppm', label: 'poppler' },
      { key: '7z', label: '7-Zip' },
      { key: 'magick', label: 'ImageMagick' },
    ],
  },
  {
    key: 'extras',
    title: 'Extras',
    note: 'Git status, disk mount, SVG, and zip support.',
    deps: [
      { key: 'resvg', label: 'resvg' },
      { key: 'git', label: 'git' },
      { key: 'udisksctl', label: 'udisks2' },
      { key: 'zip', label: 'zip' },
      { key: 'unzip', label: 'unzip' },
    ],
  },
];

const pluginCommands = [
  'ya pkg add yazi-rs/plugins:smart-enter',
  'ya pkg add yazi-rs/plugins:full-border',
  'ya pkg add yazi-rs/plugins:git',
  'ya pkg add yazi-rs/plugins:chmod',
  'ya pkg add yazi-rs/plugins:compress',
  'ya pkg add yazi-rs/plugins:max-preview',
  'ya pkg add yazi-rs/plugins:mount',
].join('\n');

const missingDeps = computed(() => status.missing_deps || []);

function groupMissing(group) {
  return group.deps.filter((dep) => !status.deps[dep.key]).length;
}

let pollTimer = null;

const authHeaders = () => ({ Authorization: 'Bearer ' + (localStorage.getItem('authToken') || '') });
const jsonHeaders = () => ({ ...authHeaders(), 'Content-Type': 'application/json' });

function notify(text, color = 'success') {
  snackbarText.value = text;
  snackbarColor.value = color;
  snackbar.value = true;
}

function setError(e) {
  error.value = e instanceof Error ? e.message : String(e);
  notify(error.value, 'error');
}

function parseOutput(data) {
  let output = data?.output;
  if (typeof output === 'string') {
    try { output = JSON.parse(output); } catch { /* keep string */ }
  }
  return output;
}

async function query(args, parseJson = false, timeout = 60) {
  const res = await fetch('/api/v1/mos/plugins/query', {
    method: 'POST',
    headers: jsonHeaders(),
    body: JSON.stringify({ command: PLUGIN_NAME, args, timeout, parse_json: parseJson }),
  });
  if (!res.ok) throw new Error(`Plugin query failed: HTTP ${res.status}`);
  const data = await res.json();
  if (data && data.success === false) throw new Error(data.error || data.message || 'Plugin query failed');
  return data;
}

async function fetchSettings() {
  const res = await fetch(`/api/v1/mos/plugins/settings/${PLUGIN_NAME}`, { headers: authHeaders() });
  if (!res.ok) throw new Error(`Settings request failed: HTTP ${res.status}`);
  const raw = await res.json();
  const data = raw && raw.data && typeof raw.data === 'object' ? raw.data : raw;
  settings.data_dir = data.data_dir || '';
  form.data_dir = settings.data_dir;
}

async function refreshStatus() {
  const data = await query(['status'], true, 10);
  const out = parseOutput(data) || {};
  status.installed = out.installed === true;
  status.version = out.version || '';
  status.app_root = out.app_root || '';
  status.storage_mode = out.storage_mode || 'ram';
  status.config = out.config || '';
  status.config_root = out.config_root || '';
  status.data = out.data || '';
  status.data_root = out.data_root || '';
  status.config_exists = out.config_exists === true;
  status.command = out.command || 'yazi';
  status.deps = out.deps || {};
  status.missing_deps = Array.isArray(out.missing_deps) ? out.missing_deps : [];
  status.deps_installing = out.deps_installing === true;
  status.deps_failed = out.deps_failed === true;
  status.deps_log = out.deps_log || '';
}

async function refreshAll() {
  loading.value = true;
  try {
    await fetchSettings();
    await refreshStatus();
  } catch (e) {
    setError(e);
  } finally {
    loading.value = false;
  }
}

function useRam() {
  form.data_dir = '';
  notify('RAM selected; click Save settings');
}

function validatePath(value) {
  if (!value) return;
  if (!value.startsWith('/')) {
    throw new Error('App directory must be an absolute path');
  }
  if (value === '/boot' || value.startsWith('/boot/')) {
    throw new Error('App directory must not be on /boot');
  }
}

async function saveSettings() {
  saving.value = true;
  try {
    const dataDir = form.data_dir.trim();
    validatePath(dataDir);

    const res = await fetch(`/api/v1/mos/plugins/settings/${PLUGIN_NAME}`, {
      method: 'POST',
      headers: jsonHeaders(),
      body: JSON.stringify({ data_dir: dataDir }),
    });
    if (!res.ok) throw new Error(`Save failed: HTTP ${res.status}`);
    settings.data_dir = dataDir;
    await refreshStatus();
    notify('Settings saved');
  } catch (e) {
    setError(e);
  } finally {
    saving.value = false;
  }
}

function stopPolling() {
  if (pollTimer) {
    clearInterval(pollTimer);
    pollTimer = null;
  }
}

function startPolling() {
  if (pollTimer) return;
  pollTimer = setInterval(async () => {
    try {
      await refreshStatus();
      if (!status.deps_installing) {
        stopPolling();
        installingGroup.value = '';
        if (status.deps_failed) {
          notify('Dependency installation failed. Check the log path on the card.', 'error');
        } else {
          notify('Dependencies updated.');
        }
      }
    } catch (e) {
      stopPolling();
      installingGroup.value = '';
      setError(e);
    }
  }, 3000);
}

async function installGroup(key) {
  error.value = '';
  installingGroup.value = key;
  try {
    await query(['install_group', key], false, 30);
    await refreshStatus();
    if (status.deps_installing) {
      notify(`Installing ${key} dependencies`);
      startPolling();
    } else {
      installingGroup.value = '';
      if (status.deps_failed) {
        notify('Dependency installation failed. Check the log path on the card.', 'error');
      } else {
        notify('Dependencies updated.');
      }
    }
  } catch (e) {
    installingGroup.value = '';
    setError(e);
  }
}

async function copyPluginCommands() {
  try {
    await navigator.clipboard.writeText(pluginCommands);
    notify('Commands copied');
  } catch {
    notify('Copy failed', 'error');
  }
}

onMounted(async () => {
  await refreshAll();
  if (status.deps_installing) {
    startPolling();
  }
});

onUnmounted(stopPolling);
</script>

<style scoped>
.yazi-code {
  background: rgba(0, 0, 0, 0.25);
  padding: 12px;
  border-radius: 8px;
  font-size: 12px;
  line-height: 1.5;
  overflow-x: auto;
}
</style>