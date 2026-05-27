<template>
  <div class="space-y-6 max-w-[1400px] mx-auto">
    <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
      <div>
        <h1 class="text-2xl font-bold text-(--label-text) tracking-tight">
          Alert History
        </h1>
        <p class="text-sm text-(--hint-text) mt-1">
          Every triggered gas alert with resolution status and per-device ACK
          coverage.
        </p>
      </div>
      <div class="flex items-center gap-2">
        <Button
          variant="ghost"
          color="primary"
          icon-left="mdi:refresh"
          @click="refreshAll"
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

    <div class="grid grid-cols-1 sm:grid-cols-4 gap-4">
      <StatCard
        icon="mdi:bell-alert"
        label="Total Alerts"
        :value="alertHistory.length"
        glow-color="warning"
        icon-bg="#F59E0B"
      />
      <StatCard
        icon="mdi:check-circle"
        label="Auto-Resolved"
        :value="autoResolved"
        glow-color="success"
        icon-bg="#22C55E"
      />
      <StatCard
        icon="mdi:hand-okay"
        label="Manually Resolved"
        :value="manualResolved"
        glow-color="info"
        icon-bg="#5AC8FA"
      />
      <StatCard
        icon="mdi:fire-alert"
        label="Active"
        :value="activeCount"
        glow-color="danger"
        icon-bg="#EF4444"
      />
    </div>

    <Card class="p-5">
      <div class="flex items-center justify-between mb-3">
        <h2 class="text-lg font-semibold text-(--label-text)">All Alerts</h2>
        <div class="flex items-center gap-2">
          <button
            type="button"
            class="px-2 py-1 text-xs rounded-md border"
            :class="
              filter === 'all'
                ? 'bg-(--btn-primary-bg)/15 border-(--btn-primary-bg)/40 text-(--btn-primary-bg)'
                : 'border-(--border-color) text-(--hint-text)'
            "
            @click="filter = 'all'"
          >
            All
          </button>
          <button
            type="button"
            class="px-2 py-1 text-xs rounded-md border"
            :class="
              filter === 'active'
                ? 'bg-red-500/15 border-red-500/40 text-red-500'
                : 'border-(--border-color) text-(--hint-text)'
            "
            @click="filter = 'active'"
          >
            Active
          </button>
          <button
            type="button"
            class="px-2 py-1 text-xs rounded-md border"
            :class="
              filter === 'resolved'
                ? 'bg-green-500/15 border-green-500/40 text-green-500'
                : 'border-(--border-color) text-(--hint-text)'
            "
            @click="filter = 'resolved'"
          >
            Resolved
          </button>
        </div>
      </div>

      <div
        v-if="filteredAlerts.length === 0"
        class="text-sm text-(--hint-text) py-12 text-center"
      >
        No alerts yet for this filter.
      </div>

      <div v-else class="overflow-x-auto">
        <table class="w-full text-sm">
          <thead>
            <tr
              class="text-left text-[11px] uppercase tracking-wider text-(--hint-text) border-b border-(--border-color)"
            >
              <th class="py-2 pr-3 font-semibold">Triggered</th>
              <th class="py-2 pr-3 font-semibold">Sensor</th>
              <th class="py-2 pr-3 font-semibold">Type</th>
              <th class="py-2 pr-3 font-semibold">Value</th>
              <th class="py-2 pr-3 font-semibold">Location</th>
              <th class="py-2 pr-3 font-semibold">ACKs</th>
              <th class="py-2 pr-3 font-semibold">Resolved</th>
              <th class="py-2 pr-3 font-semibold">By</th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="alert in filteredAlerts"
              :key="alert.id"
              class="border-b border-(--border-color)/60 hover:bg-(--surface-secondary)/40 cursor-pointer"
              @click="loadAcks(alert.id)"
            >
              <td class="py-2.5 pr-3 text-(--hint-text)">
                {{ formatTime(alert.triggeredAt) }}
              </td>
              <td class="py-2.5 pr-3 font-medium text-(--label-text)">
                {{ sensorNameFor(alert.sensorId) || alert.sensorId }}
              </td>
              <td class="py-2.5 pr-3">
                <Badge :variant="badgeVariantFor(alert.sensorType)">
                  {{ alert.sensorType }}
                </Badge>
              </td>
              <td
                class="py-2.5 pr-3 font-semibold"
                :class="
                  alert.valuePpm >=
                  (thresholds[alert.sensorType]?.critical ?? Infinity)
                    ? 'text-red-500'
                    : 'text-amber-500'
                "
              >
                {{ formatPpm(alert.valuePpm) }} ppm
              </td>
              <td class="py-2.5 pr-3 text-(--label-text)">
                {{ alert.location }}
              </td>
              <td class="py-2.5 pr-3 text-(--hint-text)">
                {{ ackCounts[alert.id] ?? 0 }}
              </td>
              <td class="py-2.5 pr-3 text-(--hint-text)">
                {{ alert.resolvedAt ? formatTime(alert.resolvedAt) : "—" }}
              </td>
              <td class="py-2.5 pr-3">
                <Badge
                  v-if="alert.resolvedBy"
                  :variant="
                    alert.resolvedBy === 'manual' ? 'secondary' : 'success'
                  "
                >
                  {{ alert.resolvedBy }}
                </Badge>
                <span v-else class="text-red-500 text-xs font-semibold">
                  active
                </span>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </Card>

    <Card v-if="selectedAlertId !== null" class="p-5">
      <div class="flex items-center justify-between mb-3">
        <div>
          <h2 class="text-lg font-semibold text-(--label-text)">
            ACK Detail — Alert #{{ selectedAlertId }}
          </h2>
          <p class="text-xs text-(--hint-text) mt-0.5">
            Phones that acknowledged this alert and when.
          </p>
        </div>
        <Button
          variant="ghost"
          color="secondary"
          size="sm"
          icon-left="mdi:close"
          @click="selectedAlertId = null"
        >
          Close
        </Button>
      </div>
      <div
        v-if="(acksByAlert[selectedAlertId] ?? []).length === 0"
        class="text-sm text-(--hint-text) py-6 text-center"
      >
        No devices have acknowledged this alert yet.
      </div>
      <ul v-else class="divide-y divide-(--border-color)">
        <li
          v-for="ack in acksByAlert[selectedAlertId]"
          :key="ack.deviceId"
          class="py-2.5 flex items-center justify-between"
        >
          <div>
            <p class="text-sm font-medium text-(--label-text)">
              {{ ack.deviceLabel || ack.deviceId }}
            </p>
            <p class="text-[11px] text-(--hint-text)">
              {{ ack.platform || "Mobile" }} ·
              <span class="font-mono">{{ ack.deviceId }}</span>
            </p>
          </div>
          <span class="text-xs text-(--hint-text)">
            {{ formatTime(ack.acknowledgedAt) }}
          </span>
        </li>
      </ul>
    </Card>
  </div>
</template>

<script setup lang="ts">
definePageMeta({ layout: "dashboard", middleware: "auth" });

const {
  sensors,
  alertHistory,
  ackCounts,
  acksByAlert,
  thresholds,
  refreshAll,
  refreshAlertHistory,
  fetchAcks,
} = useGasSensors();

const filter = ref<"all" | "active" | "resolved">("all");
const selectedAlertId = ref<number | null>(null);

onMounted(async () => {
  await refreshAlertHistory();
  for (const a of alertHistory.value) {
    fetchAcks(a.id);
  }
});

const filteredAlerts = computed(() => {
  if (filter.value === "all") return alertHistory.value;
  if (filter.value === "active")
    return alertHistory.value.filter((a) => a.resolvedAt == null);
  return alertHistory.value.filter((a) => a.resolvedAt != null);
});

const autoResolved = computed(
  () => alertHistory.value.filter((a) => a.resolvedBy === "auto").length,
);
const manualResolved = computed(
  () => alertHistory.value.filter((a) => a.resolvedBy === "manual").length,
);
const activeCount = computed(
  () => alertHistory.value.filter((a) => a.resolvedAt == null).length,
);

const sensorNameFor = (sensorId: string) =>
  sensors.value.find((s) => s.id === sensorId)?.name;

const badgeVariantFor = (type: string) => {
  switch (type) {
    case "CH4":
      return "secondary" as const;
    case "CO":
      return "danger" as const;
    case "LPG":
      return "outline" as const;
    case "MULTI":
    default:
      return "default" as const;
  }
};

const formatPpm = (value: number | null | undefined) => {
  if (value == null) return "—";
  return value.toLocaleString(undefined, { maximumFractionDigits: 1 });
};

const formatTime = (iso: string) => {
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return iso;
  return d.toLocaleString();
};

const loadAcks = (alertId: number) => {
  selectedAlertId.value = alertId;
  fetchAcks(alertId);
};
</script>
