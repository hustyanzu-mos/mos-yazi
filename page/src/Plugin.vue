<template>
  <div>
    <h2 class="mb-4">Yazi</h2>

    <v-skeleton-loader v-if="loading" :loading="true" type="card" />

    <div v-else style="margin-bottom: 80px">
      <v-alert v-if="error" type="error" variant="tonal" closable class="mb-4" @click:close="error = ''">
        {{ error }}
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
            <v-col cols="12" md="4">
              <div class="text-caption text-medium-emphasis">Version</div>
              <div class="text-subtitle-1 font-weight-medium">{{ status.version || 'Not installed' }}</div>
            </v-col>
            <v-col cols="12" md="4">
              <div class="text-caption text-medium-emphasis">Commands</div>
              <div class="text-subtitle-1 font-weight-medium"><code>yazi</code> / <code>ya</code></div>
            </v-col>
            <v-col cols="12" md="4">
              <div class="text-caption text-medium-emphasis">Config</div>
              <div class="text-body-2 font-weight-medium">{{ status.config || '-' }}</div>
              <v-chip :color="status.config_exists ? 'success' : 'grey'" size="x-small" variant="tonal" class="mt-1">
                {{ status.config_exists ? 'Custom config' : 'Built-in defaults' }}
              </v-chip>
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

          <div v-for="group in depGroups" :key="group.title" class="mb-3">
            <div class="text-caption text-medium-emphasis">{{ group.title }}</div>
            <div class="d-flex flex-wrap ga-2 mt-1">
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

          <div class="d-flex flex-wrap ga-2 mt-4">
            <v-btn
              size="small"
              color="primary"
              :loading="installBusy"
              :disabled="status.deps_installing"
              @click="installDeps"
            >
              Install basic dependencies
            </v-btn>
          </div>

          <p class="text-caption text-medium-emphasis mt-2">
            The list is saved to <code>/boot/optional/plugins/yazi/packages/packages</code> so MOS can restore the packages at boot.
          </p>
          <p class="text-caption text-medium-emphasis">
            Image preview also requires a terminal that supports Kitty graphics, Sixel, or iTerm2 images.
          </p>
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
            Config and data live under <code>/boot/optional/plugins/yazi</code>. State and cache live in <code>/run/yazi</code> and are cleared on reboot.
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
            <code>ya</code> installs plugins into the persistent config directory.
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

const loading = ref(true);
const error = ref('');
const snackbar = ref(false);
const snackbarText = ref('');
const snackbarColor = ref('success');
const installBusy = ref(false);

const status = reactive({
  installed: false,
  version: '',
  config: '',
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
    title: 'Core',
    deps: [
      { key: 'file', label: 'file' },
      { key: 'rg', label: 'ripgrep' },
      { key: 'fd', label: 'fd' },
      { key: 'fzf', label: 'fzf' },
      { key: 'zoxide', label: 'zoxide' },
      { key: 'jq', label: 'jq' },
      { key: 'git', label: 'git' },
    ],
  },
  {
    title: 'Preview',
    deps: [
      { key: 'ffmpeg', label: 'ffmpeg' },
      { key: 'pdftoppm', label: 'poppler' },
      { key: '7z', label: '7-Zip' },
      { key: 'magick', label: 'ImageMagick' },
      { key: 'resvg', label: 'resvg' },
    ],
  },
  {
    title: 'Extras',
    deps: [
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

async function refreshStatus() {
  const data = await query(['status'], true, 10);
  const out = parseOutput(data) || {};
  status.installed = out.installed === true;
  status.version = out.version || '';
  status.config = out.config || '';
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
    await refreshStatus();
  } catch (e) {
    setError(e);
  } finally {
    loading.value = false;
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
        installBusy.value = false;
        if (status.deps_failed) {
          notify('Dependency installation failed. Check the log path on the card.', 'error');
        } else {
          notify('Basic dependencies are ready.');
        }
      }
    } catch (e) {
      stopPolling();
      installBusy.value = false;
      setError(e);
    }
  }, 3000);
}

async function installDeps() {
  error.value = '';
  installBusy.value = true;
  try {
    await query(['install_deps'], false, 30);
    await refreshStatus();
    if (status.deps_installing) {
      notify('Dependency installation started');
      startPolling();
    } else {
      installBusy.value = false;
      if (status.deps_failed) {
        notify('Dependency installation failed. Check the log path on the card.', 'error');
      } else {
        notify('Basic dependencies are ready.');
      }
    }
  } catch (e) {
    installBusy.value = false;
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
    installBusy.value = true;
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