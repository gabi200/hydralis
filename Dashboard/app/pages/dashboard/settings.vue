<template>
  <div class="space-y-6 max-w-[800px] mx-auto">
    <div>
      <h1 class="text-2xl font-bold text-(--label-text) tracking-tight">Settings</h1>
      <p class="text-sm text-(--hint-text) mt-1">Configure your dashboard preferences</p>
    </div>

    <Card class="p-6">
      <h2 class="text-lg font-semibold text-(--label-text) mb-4">Appearance</h2>
      <div class="space-y-4">
        <div class="flex items-center justify-between">
          <div>
            <p class="text-sm font-medium text-(--label-text)">Dark Mode</p>
            <p class="text-xs text-(--hint-text)">Toggle dark/light theme</p>
          </div>
          <ClientOnly>
            <Switch v-model="isDarkMode" color="primary" @update:model-value="toggleDark" />
          </ClientOnly>
        </div>
        <div class="flex items-center justify-between">
          <div>
            <p class="text-sm font-medium text-(--label-text)">Language</p>
            <p class="text-xs text-(--hint-text)">Switch between English and Romanian</p>
          </div>
          <div class="flex gap-2">
            <Button v-for="lang in availableLocales" :key="lang.code" :variant="locale === lang.code ? 'solid' : 'outline'" color="primary" size="sm" @click="setLocale(lang.code)">
              {{ lang.name }}
            </Button>
          </div>
        </div>
      </div>
    </Card>

    <Card class="p-6">
      <h2 class="text-lg font-semibold text-(--label-text) mb-4">Role & Access</h2>
      <div class="space-y-4">
        <div class="flex items-center justify-between">
          <div>
            <p class="text-sm font-medium text-(--label-text)">Current Role</p>
            <p class="text-xs text-(--hint-text)">Select your dashboard view</p>
          </div>
          <div class="flex gap-2">
            <Button v-for="role in roles" :key="role.value" :variant="currentRole === role.value ? 'solid' : 'outline'" color="primary" size="sm" :icon-left="role.icon" @click="setRole(role.value as any)">
              {{ role.label }}
            </Button>
          </div>
        </div>
      </div>
    </Card>

    <Card class="p-6">
      <h2 class="text-lg font-semibold text-(--label-text) mb-4">Notifications</h2>
      <div class="space-y-4">
        <Switch v-model="notifSettings.pushAlerts" color="primary" label="Push Notifications for Alerts" />
        <Switch v-model="notifSettings.emailDigest" color="primary" label="Daily Email Digest" />
        <Switch v-model="notifSettings.sensorWarnings" color="primary" label="Sensor Warning Notifications" />
        <Switch v-model="notifSettings.soundAlarm" color="danger" label="Audible Alarm on Critical Events" />
      </div>
    </Card>

    <Card class="p-6">
      <div class="flex items-center justify-between mb-4">
        <div>
          <h2 class="text-lg font-semibold text-(--label-text)">Gas Safety Profile</h2>
          <p class="text-xs text-(--hint-text) mt-1">
            Buildings, sensors, and registered phones receiving live alerts.
          </p>
        </div>
        <Button
          variant="outline"
          color="primary"
          size="sm"
          icon-left="mdi:refresh"
          :loading="gasLoading"
          @click="refreshGasProfile"
        >
          Refresh
        </Button>
      </div>

      <div class="grid grid-cols-2 md:grid-cols-4 gap-3 mb-5">
        <div class="rounded-xl border border-(--card-border) p-3">
          <p class="text-xs text-(--hint-text) uppercase tracking-wide">Total sensors</p>
          <p class="text-2xl font-bold text-(--label-text) mt-1">{{ gasSummary?.total ?? 0 }}</p>
        </div>
        <div class="rounded-xl border border-(--card-border) p-3">
          <p class="text-xs text-(--hint-text) uppercase tracking-wide">Online</p>
          <p class="text-2xl font-bold text-emerald-500 mt-1">{{ gasSummary?.online ?? 0 }}</p>
        </div>
        <div class="rounded-xl border border-(--card-border) p-3">
          <p class="text-xs text-(--hint-text) uppercase tracking-wide">In alert</p>
          <p class="text-2xl font-bold text-red-500 mt-1">{{ gasSummary?.inAlert ?? 0 }}</p>
        </div>
        <div class="rounded-xl border border-(--card-border) p-3">
          <p class="text-xs text-(--hint-text) uppercase tracking-wide">Devices</p>
          <p class="text-2xl font-bold text-(--label-text) mt-1">{{ gasSummary?.devices ?? 0 }}</p>
        </div>
      </div>

      <div class="space-y-4">
        <div>
          <h3 class="text-sm font-semibold text-(--label-text) mb-2">
            Default building for new sensors
          </h3>
          <div class="flex flex-wrap gap-2">
            <Button
              v-for="b in buildings"
              :key="b.buildingId"
              :variant="defaultBuildingId === b.buildingId ? 'solid' : 'outline'"
              :color="b.status === 'alert' ? 'danger' : 'primary'"
              size="sm"
              icon-left="mdi:office-building"
              @click="setDefaultBuilding(b.buildingId)"
            >
              {{ b.locationName || b.buildingId }}
              <span class="ml-1 text-[10px] opacity-70">
                · {{ b.sensorCount }}s
              </span>
            </Button>
            <span
              v-if="!buildings.length"
              class="text-xs text-(--hint-text)"
            >
              No buildings registered yet.
            </span>
          </div>
        </div>

        <div>
          <h3 class="text-sm font-semibold text-(--label-text) mb-2">
            Sensor thresholds (ppm)
          </h3>
          <div class="grid grid-cols-2 md:grid-cols-4 gap-2">
            <div
              v-for="(t, key) in thresholds"
              :key="key"
              class="rounded-lg border border-(--card-border) px-3 py-2"
            >
              <p class="text-[11px] font-bold text-(--hint-text) tracking-wide">
                {{ key }}
              </p>
              <p class="text-xs text-(--label-text) mt-0.5">
                Warn <strong>{{ t.warning.toLocaleString() }}</strong>
              </p>
              <p class="text-xs text-red-500">
                Crit <strong>{{ t.critical.toLocaleString() }}</strong>
              </p>
            </div>
          </div>
        </div>

        <div>
          <h3 class="text-sm font-semibold text-(--label-text) mb-2">
            Registered phones ({{ devices.length }})
          </h3>
          <div
            v-if="!devices.length"
            class="text-xs text-(--hint-text)"
          >
            No phones registered yet. Install the Hydralis mobile app and open
            the Gas Safety screen to register a device.
          </div>
          <ul v-else class="space-y-2">
            <li
              v-for="d in devices"
              :key="d.deviceId"
              class="flex items-center justify-between rounded-lg border border-(--card-border) px-3 py-2"
            >
              <div class="min-w-0">
                <p class="text-sm font-medium text-(--label-text) truncate">
                  {{ d.label || d.deviceId }}
                </p>
                <p class="text-xs text-(--hint-text) truncate">
                  {{ d.platform || "unknown" }} · {{ d.owner || "anonymous" }}
                </p>
              </div>
              <Badge
                :variant="d.status === 'active' ? 'solid' : 'outline'"
                :color="d.status === 'active' ? 'success' : 'neutral'"
              >
                {{ d.status }}
              </Badge>
            </li>
          </ul>
        </div>

        <div class="space-y-3 pt-2 border-t border-(--card-border)">
          <div class="flex items-start justify-between gap-3">
            <div class="min-w-0">
              <p class="text-sm font-medium text-(--label-text)">
                Auto-simulate random spikes
              </p>
              <p class="text-xs text-(--hint-text) mt-0.5">
                When off, only the Demo Alarm Trigger fires alarms — useful for
                deterministic demos. Backend default: <strong>off</strong>.
              </p>
            </div>
            <Switch
              v-model="autoSpikesEnabled"
              color="warning"
              :loading="autoSpikesLoading"
              @update:model-value="onAutoSpikesToggle"
            />
          </div>
          <Switch
            v-model="gasPrefs.autoArmSiren"
            color="danger"
            label="Auto-arm screaming siren on critical gas alerts"
          />
          <Switch
            v-model="gasPrefs.broadcastResidential"
            color="primary"
            label="Broadcast residential gas alerts to mobile users"
          />
          <Switch
            v-model="gasPrefs.flashTitle"
            color="primary"
            label="Flash browser tab title during active alerts"
          />
        </div>
      </div>
    </Card>

    <Card class="p-6">
      <h2 class="text-lg font-semibold text-(--label-text) mb-4">About Hydralis</h2>
      <div class="space-y-2 text-sm text-(--hint-text)">
        <p>Version: 1.0.0-mvp</p>
        <p>Built for the CASSINI Hackathon — Space for Water</p>
        <p>Powered by Copernicus Data Space Ecosystem & EU Galileo GNSS</p>
        <div class="flex items-center gap-2 mt-3">
          <Badge variant="outline">Nuxt 4</Badge>
          <Badge variant="outline">Leaflet</Badge>
          <Badge variant="outline">Copernicus</Badge>
          <Badge variant="outline">Galileo</Badge>
        </div>
      </div>
    </Card>
  </div>
</template>

<script setup lang="ts">
definePageMeta({ layout: "dashboard", middleware: "auth" });

const colorMode = useColorMode();
const { locale, locales, setLocale } = useI18n();
const { currentRole, setRole } = useRole();

const availableLocales = computed(() => locales.value.filter((l): l is { code: string; name: string } => typeof l !== "string"));

const isDarkMode = ref(colorMode.preference === "dark");
const toggleDark = (val: boolean) => { colorMode.preference = val ? "dark" : "light"; };

const roles = [
  { value: "dispatcher", label: "Dispatcher", icon: "mdi:shield-alert" },
  { value: "industrial", label: "Industrial", icon: "mdi:factory" },
  { value: "admin", label: "Admin", icon: "mdi:cog" },
];

const notifSettings = reactive({
  pushAlerts: true,
  emailDigest: false,
  sensorWarnings: true,
  soundAlarm: true,
});

const {
  buildings,
  devices,
  thresholds,
  refreshBuildings,
  refreshDevices,
  fetchSummary,
} = useGasSensors();

type GasSummary = NonNullable<Awaited<ReturnType<typeof fetchSummary>>>;
const gasSummary = ref<GasSummary | null>(null);
const gasLoading = ref(false);
const defaultBuildingId = useState<string | null>(
  "gas-default-building",
  () => null,
);

const gasPrefs = reactive({
  autoArmSiren: true,
  broadcastResidential: true,
  flashTitle: true,
});

const setDefaultBuilding = (id: string) => {
  defaultBuildingId.value = defaultBuildingId.value === id ? null : id;
  if (typeof window !== "undefined") {
    if (defaultBuildingId.value) {
      window.localStorage.setItem("hydralis_default_building", id);
    } else {
      window.localStorage.removeItem("hydralis_default_building");
    }
  }
};

const refreshGasProfile = async () => {
  gasLoading.value = true;
  try {
    await Promise.all([
      refreshBuildings(),
      refreshDevices(),
      fetchAutoSpikes(),
    ]);
    gasSummary.value = await fetchSummary();
  } finally {
    gasLoading.value = false;
  }
};

const { get: apiGet, post: apiPost } = useApi();
const autoSpikesEnabled = ref(false);
const autoSpikesLoading = ref(false);

const fetchAutoSpikes = async () => {
  try {
    const res = await apiGet<{ enabled: boolean }>(
      "/api/v1/gas/demo/auto-spikes",
    );
    autoSpikesEnabled.value = res.enabled;
  } catch (err) {
    console.error("Failed to fetch auto-spike state", err);
  }
};

const onAutoSpikesToggle = async (val: boolean) => {
  autoSpikesLoading.value = true;
  try {
    const res = await apiPost<{ enabled: boolean }>(
      "/api/v1/gas/demo/auto-spikes",
      { enabled: val },
    );
    autoSpikesEnabled.value = res.enabled;
  } catch (err) {
    console.error("Failed to toggle auto spikes", err);
    autoSpikesEnabled.value = !val;
  } finally {
    autoSpikesLoading.value = false;
  }
};

onMounted(() => {
  if (typeof window !== "undefined") {
    const stored = window.localStorage.getItem("hydralis_default_building");
    if (stored) defaultBuildingId.value = stored;
    const prefs = window.localStorage.getItem("hydralis_gas_prefs");
    if (prefs) {
      try {
        Object.assign(gasPrefs, JSON.parse(prefs));
      } catch {
        /* ignore */
      }
    }
  }
  refreshGasProfile();
});

watch(
  gasPrefs,
  (value) => {
    if (typeof window === "undefined") return;
    window.localStorage.setItem(
      "hydralis_gas_prefs",
      JSON.stringify(value),
    );
  },
  { deep: true },
);
</script>
