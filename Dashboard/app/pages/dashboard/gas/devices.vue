<template>
  <div class="space-y-6 max-w-[1400px] mx-auto">
    <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
      <div>
        <h1 class="text-2xl font-bold text-(--label-text) tracking-tight">
          Connected Devices
        </h1>
        <p class="text-sm text-(--hint-text) mt-1">
          Mobile phones registered to receive gas alert broadcasts.
        </p>
      </div>
      <div class="flex items-center gap-2">
        <Button
          variant="ghost"
          color="primary"
          icon-left="mdi:refresh"
          @click="refreshDevices"
        >
          Refresh
        </Button>
        <CustomLink to="/dashboard/gas">
          <Button variant="outline" color="secondary">
            Back to monitoring
          </Button>
        </CustomLink>
      </div>
    </div>

    <div class="grid grid-cols-1 sm:grid-cols-3 gap-4">
      <StatCard
        icon="mdi:cellphone-link"
        label="Total Devices"
        :value="devices.length"
        glow-color="primary"
        icon-bg="#007AFF"
      />
      <StatCard
        icon="mdi:check-circle-outline"
        label="Active"
        :value="activeCount"
        glow-color="success"
        icon-bg="#22C55E"
      />
      <StatCard
        icon="mdi:clock-alert"
        label="Stale (>5 min)"
        :value="staleCount"
        glow-color="warning"
        icon-bg="#F59E0B"
      />
    </div>

    <Card class="p-5">
      <div class="flex items-center justify-between mb-3">
        <h2 class="text-lg font-semibold text-(--label-text)">Devices</h2>
        <Badge variant="outline">{{ devices.length }}</Badge>
      </div>
      <div
        v-if="devices.length === 0"
        class="text-sm text-(--hint-text) py-12 text-center"
      >
        No devices registered. Launching the Hydralis mobile app auto-registers
        a device using its persistent device ID.
      </div>
      <div v-else class="overflow-x-auto">
        <table class="w-full text-sm">
          <thead>
            <tr
              class="text-left text-[11px] uppercase tracking-wider text-(--hint-text) border-b border-(--border-color)"
            >
              <th class="py-2 pr-3 font-semibold">Label</th>
              <th class="py-2 pr-3 font-semibold">Platform</th>
              <th class="py-2 pr-3 font-semibold">Device ID</th>
              <th class="py-2 pr-3 font-semibold">Owner</th>
              <th class="py-2 pr-3 font-semibold">Registered</th>
              <th class="py-2 pr-3 font-semibold">Last Seen</th>
              <th class="py-2 pr-3 font-semibold">Status</th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="dev in devices"
              :key="dev.deviceId"
              class="border-b border-(--border-color)/60 hover:bg-(--surface-secondary)/40"
            >
              <td class="py-2.5 pr-3 font-medium text-(--label-text)">
                <div class="flex items-center gap-2">
                  <Icon
                    :name="platformIcon(dev.platform)"
                    class="h-4 w-4 text-(--icon-color)"
                  />
                  {{ dev.label }}
                </div>
              </td>
              <td class="py-2.5 pr-3 text-(--hint-text)">
                {{ dev.platform || "—" }}
              </td>
              <td class="py-2.5 pr-3 font-mono text-[11px] text-(--hint-text)">
                {{ dev.deviceId }}
              </td>
              <td class="py-2.5 pr-3 text-(--label-text)">
                {{ dev.owner || "—" }}
              </td>
              <td class="py-2.5 pr-3 text-(--hint-text)">
                {{ formatTime(dev.registeredAt) }}
              </td>
              <td class="py-2.5 pr-3 text-(--hint-text)">
                {{ dev.lastSeenAt ? formatTime(dev.lastSeenAt) : "never" }}
              </td>
              <td class="py-2.5 pr-3">
                <Badge
                  :variant="isStale(dev.lastSeenAt) ? 'danger' : 'success'"
                >
                  {{ isStale(dev.lastSeenAt) ? "stale" : "active" }}
                </Badge>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </Card>
  </div>
</template>

<script setup lang="ts">
definePageMeta({ layout: "dashboard", middleware: "auth" });

const { devices, refreshDevices } = useGasSensors();

onMounted(() => {
  refreshDevices();
});

const STALE_MS = 5 * 60 * 1000;

const isStale = (lastSeenAt: string | null): boolean => {
  if (!lastSeenAt) return true;
  const ts = new Date(lastSeenAt).getTime();
  if (Number.isNaN(ts)) return true;
  return Date.now() - ts > STALE_MS;
};

const activeCount = computed(
  () => devices.value.filter((d) => !isStale(d.lastSeenAt)).length,
);

const staleCount = computed(
  () => devices.value.filter((d) => isStale(d.lastSeenAt)).length,
);

const platformIcon = (platform: string | null) => {
  switch ((platform ?? "").toLowerCase()) {
    case "android":
      return "mdi:android";
    case "ios":
      return "mdi:apple-ios";
    case "macos":
      return "mdi:apple";
    case "windows":
      return "mdi:microsoft-windows";
    case "linux":
      return "mdi:linux";
    default:
      return "mdi:cellphone";
  }
};

const formatTime = (iso: string) => {
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return iso;
  return d.toLocaleString();
};
</script>
