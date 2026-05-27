<template>
  <div class="space-y-6 max-w-[1400px] mx-auto">
    <!-- Screaming full-screen alarm overlay -->
    <ClientOnly>
      <Teleport to="body">
        <div
          v-if="screamingAlert"
          class="fixed inset-0 z-[9999] flex flex-col items-center justify-center bg-red-900/95 backdrop-blur-sm screaming-overlay"
        >
          <div class="absolute inset-0 pointer-events-none scream-stripes" />
          <div
            class="relative z-10 max-w-2xl mx-auto px-8 py-10 rounded-3xl border-4 border-red-300 bg-red-950/80 text-white text-center shadow-2xl scream-pulse"
          >
            <div class="flex justify-center mb-4">
              <div
                class="h-20 w-20 rounded-full bg-red-500 flex items-center justify-center scream-shake"
              >
                <Icon name="mdi:fire-alert" class="h-12 w-12 text-white" />
              </div>
            </div>
            <p
              class="text-[11px] font-bold tracking-[0.4em] uppercase text-red-200 mb-2"
            >
              Gas Detection System
            </p>
            <h2 class="text-4xl font-black uppercase tracking-tight mb-3">
              {{
                screamingAlert.valuePpm >=
                (thresholds[screamingAlert.sensorType]?.critical ?? Infinity)
                  ? "CRITICAL GAS LEAK"
                  : "GAS WARNING"
              }}
            </h2>
            <p class="text-lg font-semibold mb-1">
              {{ screamingAlert.location }}
            </p>
            <p class="text-sm text-red-200 mb-6">
              {{ sensorNameFor(screamingAlert.sensorId) || screamingAlert.sensorId }}
            </p>
            <div class="grid grid-cols-3 gap-3 mb-6">
              <div class="bg-red-950/60 border border-red-500/40 rounded-xl p-3">
                <p class="text-[10px] uppercase tracking-wider text-red-300">
                  Gas
                </p>
                <p class="text-xl font-bold mt-1">
                  {{ screamingAlert.sensorType }}
                </p>
              </div>
              <div class="bg-red-950/60 border border-red-500/40 rounded-xl p-3">
                <p class="text-[10px] uppercase tracking-wider text-red-300">
                  Reading
                </p>
                <p class="text-xl font-bold mt-1">
                  {{ formatPpm(screamingAlert.valuePpm) }}
                </p>
                <p class="text-[10px] text-red-300">ppm</p>
              </div>
              <div class="bg-red-950/60 border border-red-500/40 rounded-xl p-3">
                <p class="text-[10px] uppercase tracking-wider text-red-300">
                  Threshold
                </p>
                <p class="text-xl font-bold mt-1">
                  {{ formatPpm(screamingAlert.threshold) }}
                </p>
                <p class="text-[10px] text-red-300">ppm</p>
              </div>
            </div>
            <p
              class="text-sm font-semibold text-red-100 mb-6 flex items-center justify-center gap-2"
            >
              <Icon name="mdi:run-fast" class="h-5 w-5" />
              Evacuate the area, ventilate, and dispatch response now.
            </p>
            <div class="flex flex-col sm:flex-row items-center justify-center gap-3">
              <Button
                variant="solid"
                color="danger"
                size="lg"
                icon-left="mdi:bell-cancel"
                @click="acknowledgeScreaming"
              >
                Acknowledge & Silence
              </Button>
              <Button
                variant="outline"
                color="secondary"
                size="lg"
                icon-left="mdi:bell-off"
                @click="silenceOnly"
              >
                Silence Siren Only
              </Button>
            </div>
            <p class="text-[10px] text-red-300 mt-4">
              Triggered {{ formatTime(screamingAlert.triggeredAt) }} ·
              {{ pendingScreamQueue.length }} more queued
            </p>
          </div>
        </div>
      </Teleport>
    </ClientOnly>

    <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
      <div class="flex items-center gap-3">
        <div>
          <div class="flex items-center gap-2">
            <h1 class="text-2xl font-bold text-(--label-text) tracking-tight">
              Gas Monitoring
            </h1>
            <span
              v-if="demoMode"
              class="px-2 py-0.5 text-[10px] font-bold uppercase tracking-widest rounded-full bg-yellow-400/10 text-yellow-500 border border-yellow-400/30"
            >
              DEMO
            </span>
            <button
              type="button"
              class="px-2 py-0.5 text-[10px] font-bold uppercase tracking-widest rounded-full border transition-colors"
              :class="
                alarmArmed
                  ? 'bg-red-500/10 text-red-500 border-red-500/40 hover:bg-red-500/20'
                  : 'bg-(--surface-secondary) text-(--hint-text) border-(--border-color) hover:bg-(--surface-secondary)/80'
              "
              :title="
                alarmArmed
                  ? 'Click to disarm the audible alarm'
                  : 'Click to arm the audible alarm (browser requires a user gesture)'
              "
              @click="toggleAlarmArmed"
            >
              <Icon
                :name="alarmArmed ? 'mdi:bell-ring' : 'mdi:bell-off'"
                class="h-3 w-3 inline-block -mt-0.5 mr-1"
              />
              {{ alarmArmed ? "Siren Armed" : "Arm Siren" }}
            </button>
          </div>
          <p class="text-sm text-(--hint-text) mt-1">
            Real-time gas sensor readings across registered buildings.
          </p>
        </div>
      </div>
      <div class="flex items-center gap-2 flex-wrap">
        <div
          class="flex items-center gap-2 px-3 py-1.5 rounded-lg bg-(--surface-primary) border border-(--border-color)"
        >
          <Icon name="mdi:radar" class="h-4 w-4 text-(--icon-color)" />
          <span class="text-xs text-(--label-text) font-semibold">
            {{ summary.total }} sensors
          </span>
        </div>
        <div
          class="flex items-center gap-2 px-3 py-1.5 rounded-lg bg-(--surface-primary) border border-(--border-color)"
        >
          <span class="h-2.5 w-2.5 rounded-full bg-green-500" />
          <span class="text-xs text-(--label-text)">{{ summary.online }} online</span>
        </div>
        <div
          class="flex items-center gap-2 px-3 py-1.5 rounded-lg bg-(--surface-primary) border border-(--border-color)"
        >
          <span class="h-2.5 w-2.5 rounded-full bg-orange-500" />
          <span class="text-xs text-(--label-text)">{{ summary.inAlert }} in alert</span>
        </div>
        <div
          class="flex items-center gap-2 px-3 py-1.5 rounded-lg"
          :class="
            summary.activeAlerts > 0
              ? 'bg-red-500/10 border border-red-500/30 text-red-500'
              : 'bg-(--surface-primary) border border-(--border-color)'
          "
        >
          <Icon
            :name="summary.activeAlerts > 0 ? 'mdi:alert-octagon' : 'mdi:bell-off-outline'"
            class="h-4 w-4"
          />
          <span class="text-xs font-semibold">
            {{ summary.activeAlerts }} active alerts
          </span>
        </div>
      </div>
    </div>

    <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
      <StatCard
        icon="mdi:radar"
        label="Total Sensors"
        :value="summary.total"
        glow-color="primary"
        icon-bg="#007AFF"
      />
      <StatCard
        icon="mdi:check-circle-outline"
        label="Online"
        :value="summary.online"
        glow-color="success"
        icon-bg="#22C55E"
      />
      <StatCard
        icon="mdi:alert-circle-outline"
        label="In Alert"
        :value="summary.inAlert"
        glow-color="warning"
        icon-bg="#F59E0B"
      />
      <StatCard
        icon="mdi:bell-alert"
        label="Active Alerts"
        :value="summary.activeAlerts"
        glow-color="danger"
        icon-bg="#EF4444"
      />
    </div>

    <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
      <StatCard
        icon="mdi:office-building-marker"
        label="Buildings"
        :value="summary.buildings"
        glow-color="info"
        icon-bg="#5AC8FA"
      />
      <StatCard
        icon="mdi:cellphone-link"
        label="Connected Phones"
        :value="summary.devices"
        glow-color="info"
        icon-bg="#0A84FF"
      />
      <StatCard
        icon="mdi:database-clock"
        label="Readings (24h)"
        :value="summary.readings24h"
        glow-color="primary"
        icon-bg="#34C759"
      />
      <StatCard
        icon="mdi:counter"
        label="Resolved Alerts"
        :value="resolvedAlertCount"
        glow-color="success"
        icon-bg="#10B981"
      />
    </div>

    <Card class="p-5 border-amber-300/40 dark:border-amber-300/20">
      <div class="flex items-center justify-between mb-3 flex-wrap gap-3">
        <div>
          <h2 class="text-lg font-semibold text-(--label-text) flex items-center gap-2">
            <Icon name="mdi:test-tube" class="h-5 w-5 text-amber-500" />
            Demo Alarm Trigger
          </h2>
          <p class="text-xs text-(--hint-text) mt-0.5">
            Fire a deterministic alarm on a specific sensor. The same payload reaches
            mobile phones and dashboards via the existing WebSocket flow.
          </p>
        </div>
        <Button
          variant="outline"
          color="warning"
          size="sm"
          icon-left="mdi:stop-circle-outline"
          :loading="demoClearing"
          @click="clearDemoSpike"
        >
          Clear active demo
        </Button>
      </div>
      <div class="grid grid-cols-1 md:grid-cols-3 gap-3">
        <CustomSelect
          v-model="demoSensorId"
          label="Sensor"
          :options="
            sensors.map((s) => ({
              label: `${s.id} · ${s.locationName}`,
              value: s.id,
            }))
          "
        />
        <CustomSelect
          v-model="demoSeverity"
          label="Severity"
          :options="[
            { label: 'Warning (above warning threshold)', value: 'warning' },
            { label: 'Critical (full screaming alarm)', value: 'critical' },
          ]"
        />
        <div class="flex items-end">
          <Button
            color="danger"
            variant="solid"
            size="md"
            class="w-full"
            icon-left="mdi:bell-ring"
            :disabled="!demoSensorId"
            :loading="demoFiring"
            @click="fireDemoSpike"
          >
            Fire demo alarm
          </Button>
        </div>
      </div>
      <p
        v-if="demoLastResult"
        class="text-xs text-(--hint-text) mt-3 flex items-center gap-2"
      >
        <Icon name="mdi:check-circle" class="h-4 w-4 text-emerald-500" />
        {{ demoLastResult }}
      </p>
    </Card>

    <Card class="p-5">
      <div class="flex items-center justify-between mb-4">
        <div>
          <h2 class="text-lg font-semibold text-(--label-text)">Buildings</h2>
          <p class="text-xs text-(--hint-text) mt-0.5">
            Sensor coverage per monitored property.
          </p>
        </div>
        <Badge variant="outline">{{ buildings.length }} sites</Badge>
      </div>
      <div
        v-if="buildings.length === 0"
        class="text-sm text-(--hint-text) py-6 text-center"
      >
        No buildings registered yet.
      </div>
      <div
        v-else
        class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3"
      >
        <div
          v-for="b in buildings"
          :key="b.buildingId"
          class="p-4 rounded-xl border border-(--border-color) bg-(--surface-secondary)/40 hover:bg-(--surface-secondary)/70 transition-colors"
        >
          <div class="flex items-start justify-between gap-2 mb-2">
            <div class="min-w-0">
              <p class="text-sm font-semibold text-(--label-text) truncate">
                {{ buildingLabel(b.buildingId) }}
              </p>
              <p class="text-[11px] text-(--hint-text) truncate">
                {{ b.locationName }}
              </p>
            </div>
            <span
              class="h-2.5 w-2.5 rounded-full shrink-0 mt-1.5"
              :style="{ background: buildingStatusColor(b.status) }"
            />
          </div>
          <div class="grid grid-cols-3 gap-2 text-center text-[11px]">
            <div class="rounded-lg bg-(--surface-primary) py-1.5">
              <p class="text-(--hint-text) uppercase tracking-wider text-[9px]">
                Sensors
              </p>
              <p class="font-bold text-(--label-text) text-sm">
                {{ b.sensorCount }}
              </p>
            </div>
            <div class="rounded-lg bg-(--surface-primary) py-1.5">
              <p class="text-(--hint-text) uppercase tracking-wider text-[9px]">
                Online
              </p>
              <p class="font-bold text-green-500 text-sm">
                {{ b.onlineCount }}
              </p>
            </div>
            <div class="rounded-lg bg-(--surface-primary) py-1.5">
              <p class="text-(--hint-text) uppercase tracking-wider text-[9px]">
                Alerts
              </p>
              <p class="font-bold text-red-500 text-sm">
                {{ b.alertCount }}
              </p>
            </div>
          </div>
        </div>
      </div>
    </Card>

    <Card class="p-5">
      <div class="flex items-center justify-between mb-3">
        <div>
          <h2 class="text-lg font-semibold text-(--label-text)">
            Threshold Reference
          </h2>
          <p class="text-xs text-(--hint-text) mt-0.5">
            Warning and critical concentrations triggering alerts.
          </p>
        </div>
        <Badge variant="outline">ppm</Badge>
      </div>
      <div class="grid grid-cols-2 sm:grid-cols-4 gap-3">
        <div
          v-for="(t, key) in thresholds"
          :key="key"
          class="rounded-xl border border-(--border-color) p-3"
        >
          <div class="flex items-center justify-between mb-1">
            <span class="text-sm font-semibold text-(--label-text)">
              {{ key }}
            </span>
            <span class="text-[10px] text-(--hint-text) uppercase tracking-wider">
              {{ thresholdNote(key) }}
            </span>
          </div>
          <div class="flex items-baseline justify-between text-xs mt-2">
            <span class="text-amber-500">
              Warn: <strong>{{ t.warning.toLocaleString() }}</strong>
            </span>
            <span class="text-red-500">
              Crit: <strong>{{ t.critical.toLocaleString() }}</strong>
            </span>
          </div>
        </div>
      </div>
    </Card>

    <Card class="overflow-hidden">
      <div class="px-5 pt-5 pb-3 flex items-center justify-between">
        <div>
          <h2 class="text-lg font-semibold text-(--label-text)">Sensor Map</h2>
          <p class="text-xs text-(--hint-text) mt-0.5">
            Colors track live reading status. Click a marker for sensor detail.
          </p>
        </div>
      </div>
      <ClientOnly>
        <div class="h-[420px] map-container">
          <LMap
            ref="mapRef"
            :zoom="11"
            :center="mapCenter"
            :use-global-leaflet="false"
            :options="{ zoomControl: true, attributionControl: true }"
          >
            <LTileLayer
              url="https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png"
              layer-type="base"
              name="CartoDB Dark"
              attribution="&copy; CartoDB"
            />
            <LMarker
              v-for="sensor in sensors"
              :key="sensor.id"
              :lat-lng="[sensor.latitude, sensor.longitude]"
            >
              <LIcon :icon-size="[34, 34]" :icon-anchor="[17, 34]" class-name="">
                <div class="flex flex-col items-center">
                  <div
                    class="h-8 w-8 rounded-full flex items-center justify-center shadow-lg border-2 border-white"
                    :style="{ background: colorForSensor(sensor) }"
                  >
                    <Icon
                      :name="sensorIconFor(sensor.sensorType)"
                      class="h-4 w-4 text-white"
                    />
                  </div>
                </div>
              </LIcon>
              <LPopup>
                <div class="p-2 min-w-[220px]">
                  <h3 class="font-bold text-sm text-gray-900 mb-1">
                    {{ sensor.name }}
                  </h3>
                  <p class="text-xs text-gray-600 mb-2">{{ sensor.locationName }}</p>
                  <div class="space-y-1 text-xs">
                    <div class="flex justify-between">
                      <span class="text-gray-500">Type:</span>
                      <span class="font-medium">{{ sensor.sensorType }}</span>
                    </div>
                    <div class="flex justify-between">
                      <span class="text-gray-500">Reading:</span>
                      <span
                        class="font-medium"
                        :style="{ color: colorForSensor(sensor) }"
                      >
                        {{ formatPpm(sensor.lastReading) }} ppm
                      </span>
                    </div>
                    <div class="flex justify-between">
                      <span class="text-gray-500">Status:</span>
                      <span
                        class="font-medium"
                        :style="{ color: colorForSensor(sensor) }"
                      >
                        {{ sensor.status }}
                      </span>
                    </div>
                    <div class="flex justify-between">
                      <span class="text-gray-500">Floor:</span>
                      <span class="font-medium">{{ floorLabel(sensor.floor) }}</span>
                    </div>
                  </div>
                </div>
              </LPopup>
            </LMarker>
          </LMap>
        </div>
        <template #fallback>
          <div
            class="h-[420px] flex items-center justify-center bg-(--surface-secondary)"
          >
            <p class="text-sm text-(--hint-text)">Loading map…</p>
          </div>
        </template>
      </ClientOnly>
    </Card>

    <div>
      <div class="flex items-center justify-between mb-3">
        <h2 class="text-lg font-semibold text-(--label-text)">Sensor Grid</h2>
        <Badge variant="outline">{{ sensors.length }} sensors</Badge>
      </div>
      <div
        v-if="sensors.length === 0"
        class="text-sm text-(--hint-text) py-12 text-center"
      >
        No gas sensors configured yet.
      </div>
      <div v-else class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
        <Card
          v-for="sensor in sensors"
          :key="sensor.id"
          class="p-4 flex flex-col gap-3"
          :class="{ 'sensor-flash': isFlashing(sensor.id) }"
        >
          <div class="flex items-start justify-between gap-2">
            <div class="min-w-0">
              <p class="text-sm font-semibold text-(--label-text) truncate">
                {{ sensor.name }}
              </p>
              <p class="text-xs text-(--hint-text) truncate">
                {{ sensor.locationName }}
              </p>
            </div>
            <Badge :variant="badgeVariantFor(sensor.sensorType)">
              {{ sensor.sensorType }}
            </Badge>
          </div>

          <div class="flex items-end justify-between">
            <div>
              <p
                class="text-2xl font-bold tracking-tight"
                :style="{ color: colorForSensor(sensor) }"
              >
                {{ formatPpm(sensor.lastReading) }}
              </p>
              <p class="text-[10px] text-(--hint-text) uppercase tracking-wider">
                ppm · {{ sensor.sensorType }}
              </p>
            </div>
            <div class="flex flex-col items-end gap-1">
              <span
                class="h-3 w-3 rounded-full"
                :style="{ background: colorForSensor(sensor) }"
              />
              <span class="text-[10px] text-(--hint-text)">
                {{ statusLabel(sensor) }}
              </span>
            </div>
          </div>

          <div class="h-12 -mx-1">
            <ClientOnly>
              <Line
                v-if="sparklineData(sensor.id)"
                :data="sparklineData(sensor.id)"
                :options="sparklineOptions(sensor)"
              />
            </ClientOnly>
          </div>

          <div
            v-if="sensor.status === 'alert'"
            class="rounded-lg bg-red-500/10 border border-red-500/30 px-2.5 py-1.5 text-xs font-semibold text-red-500 flex items-center justify-between"
          >
            <span class="flex items-center gap-1.5">
              <Icon name="mdi:alert" class="h-3.5 w-3.5" /> ALERT
            </span>
            <span class="text-[10px] font-normal">
              {{ elapsedFor(sensor.id) }}
            </span>
          </div>
        </Card>
      </div>
    </div>

    <Card class="p-5">
      <div class="flex items-center justify-between mb-3">
        <h2 class="text-lg font-semibold text-(--label-text)">Active Alerts</h2>
        <Badge :variant="alerts.length > 0 ? 'danger' : 'outline'">
          {{ alerts.length }}
        </Badge>
      </div>
      <div v-if="alerts.length === 0" class="text-sm text-(--hint-text) py-6 text-center">
        No active gas alerts. All sensors nominal.
      </div>
      <div v-else class="overflow-x-auto">
        <table class="w-full text-sm">
          <thead>
            <tr class="text-left text-[11px] uppercase tracking-wider text-(--hint-text) border-b border-(--border-color)">
              <th class="py-2 pr-3 font-semibold">Sensor</th>
              <th class="py-2 pr-3 font-semibold">Type</th>
              <th class="py-2 pr-3 font-semibold">Value</th>
              <th class="py-2 pr-3 font-semibold">Threshold</th>
              <th class="py-2 pr-3 font-semibold">Location</th>
              <th class="py-2 pr-3 font-semibold">Triggered</th>
              <th class="py-2 pr-3 font-semibold">Phones ACK</th>
              <th class="py-2 pr-3 font-semibold text-right">Action</th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="alert in alerts"
              :key="alert.id"
              class="border-b border-(--border-color)/60 hover:bg-(--surface-secondary)/40"
            >
              <td class="py-2.5 pr-3 font-medium text-(--label-text)">
                {{ sensorNameFor(alert.sensorId) || alert.sensorId }}
              </td>
              <td class="py-2.5 pr-3">
                <Badge :variant="badgeVariantFor(alert.sensorType)">
                  {{ alert.sensorType }}
                </Badge>
              </td>
              <td class="py-2.5 pr-3 font-semibold text-red-500">
                {{ formatPpm(alert.valuePpm) }} ppm
              </td>
              <td class="py-2.5 pr-3 text-(--hint-text)">
                {{ formatPpm(alert.threshold) }} ppm
              </td>
              <td class="py-2.5 pr-3 text-(--label-text)">
                {{ alert.location }}
              </td>
              <td class="py-2.5 pr-3 text-(--hint-text)">
                {{ formatTime(alert.triggeredAt) }}
              </td>
              <td class="py-2.5 pr-3">
                <span
                  class="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-[11px] font-semibold"
                  :class="
                    (ackCounts[alert.id] ?? 0) >= devices.length &&
                    devices.length > 0
                      ? 'bg-green-500/10 text-green-500'
                      : 'bg-amber-500/10 text-amber-500'
                  "
                >
                  <Icon name="mdi:cellphone-check" class="h-3.5 w-3.5" />
                  {{ ackCounts[alert.id] ?? 0 }} / {{ devices.length }}
                </span>
              </td>
              <td class="py-2.5 pr-3 text-right">
                <Button
                  variant="outline"
                  color="danger"
                  size="sm"
                  :disabled="resolving === alert.id"
                  @click="onResolve(alert.id)"
                >
                  {{ resolving === alert.id ? "…" : "Resolve" }}
                </Button>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </Card>

    <Card class="p-5">
      <div class="flex items-center justify-between mb-3">
        <div>
          <h2 class="text-lg font-semibold text-(--label-text)">
            Connected Mobile Devices
          </h2>
          <p class="text-xs text-(--hint-text) mt-0.5">
            Phones registered to receive gas alerts on this network.
          </p>
        </div>
        <CustomLink to="/dashboard/gas/devices">
          <Button variant="ghost" color="primary" size="sm">View all</Button>
        </CustomLink>
      </div>
      <div
        v-if="devices.length === 0"
        class="text-sm text-(--hint-text) py-6 text-center"
      >
        No devices registered yet. Open the Hydralis mobile app to auto-register.
      </div>
      <div v-else class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3">
        <div
          v-for="dev in devices.slice(0, 6)"
          :key="dev.deviceId"
          class="p-3 rounded-xl border border-(--border-color) bg-(--surface-secondary)/40 flex items-center gap-3"
        >
          <div
            class="h-9 w-9 rounded-full bg-(--btn-primary-bg)/15 flex items-center justify-center"
          >
            <Icon
              :name="devicePlatformIcon(dev.platform)"
              class="h-5 w-5 text-(--btn-primary-bg)"
            />
          </div>
          <div class="min-w-0 flex-1">
            <p class="text-sm font-semibold text-(--label-text) truncate">
              {{ dev.label }}
            </p>
            <p class="text-[11px] text-(--hint-text) truncate">
              {{ dev.platform || "Mobile" }} ·
              {{ dev.lastSeenAt ? "seen " + formatTime(dev.lastSeenAt) : "never seen" }}
            </p>
          </div>
          <span
            class="h-2 w-2 rounded-full"
            :class="dev.status === 'active' ? 'bg-green-500' : 'bg-gray-400'"
          />
        </div>
      </div>
    </Card>
  </div>
</template>

<script setup lang="ts">
import { Line } from "vue-chartjs";
import {
  Chart as ChartJS,
  CategoryScale,
  LinearScale,
  LineElement,
  PointElement,
  Filler,
  Tooltip,
} from "chart.js";
import {
  LIcon,
  LMap,
  LMarker,
  LPopup,
  LTileLayer,
} from "@vue-leaflet/vue-leaflet";
import type { GasSensor, GasSensorType } from "~/composables/useGasSensors";

definePageMeta({ layout: "dashboard", middleware: "auth" });

if (import.meta.client) {
  ChartJS.register(
    CategoryScale,
    LinearScale,
    LineElement,
    PointElement,
    Filler,
    Tooltip,
  );
}

const {
  sensors,
  alerts,
  alertHistory,
  buildings,
  devices,
  history,
  flashStates,
  ackCounts,
  summary,
  colorForSensor,
  classifyReading,
  thresholds,
  refreshAll,
  fetchHistory,
  fetchSummary,
  fetchAcks,
  refreshAlertHistory,
  resolveAlert,
} = useGasSensors();

const resolvedAlertCount = computed(
  () => alertHistory.value.filter((a) => a.resolvedAt != null).length,
);

// ----- Demo alarm trigger -----
const { post: apiPost } = useApi();
const demoSensorId = ref<string>("");
const demoSeverity = ref<"warning" | "critical">("critical");
const demoFiring = ref(false);
const demoClearing = ref(false);
const demoLastResult = ref<string>("");

watchEffect(() => {
  if (!demoSensorId.value && sensors.value.length) {
    demoSensorId.value = sensors.value[0].id;
  }
});

const fireDemoSpike = async () => {
  if (!demoSensorId.value) return;
  demoFiring.value = true;
  try {
    const res = await apiPost<{ sensorId: string; sensorType: string }>(
      "/api/v1/gas/demo/spike",
      {
        sensor_id: demoSensorId.value,
        severity: demoSeverity.value,
      },
    );
    demoLastResult.value =
      `Spike scheduled for ${res.sensorId} (${res.sensorType}, ${demoSeverity.value}). ` +
      `Alarm will fire on the next simulator tick (~15s).`;
  } catch (err) {
    demoLastResult.value = `Failed to fire demo: ${err}`;
  } finally {
    demoFiring.value = false;
  }
};

const clearDemoSpike = async () => {
  demoClearing.value = true;
  try {
    await apiPost("/api/v1/gas/demo/clear", {});
    demoLastResult.value = "Active demo spike cleared.";
  } catch (err) {
    demoLastResult.value = `Failed to clear demo: ${err}`;
  } finally {
    demoClearing.value = false;
  }
};

const buildingLabel = (buildingId: string) =>
  buildingId
    .replace(/^BLD-/i, "")
    .toLowerCase()
    .replace(/\b\w/g, (c) => c.toUpperCase());

const buildingStatusColor = (status: string) => {
  if (status === "alert") return "#EF4444";
  if (status === "offline") return "#6B7280";
  return "#22C55E";
};

const thresholdNote = (type: string) => {
  switch (type) {
    case "CH4":
      return "Methane";
    case "CO":
      return "Carbon Monoxide";
    case "LPG":
      return "Propane / Butane";
    case "MULTI":
    default:
      return "Multi-Gas";
  }
};

const devicePlatformIcon = (platform: string | null) => {
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

const demoMode = true;
const resolving = ref<number | null>(null);
const now = ref(Date.now());
let nowTimer: ReturnType<typeof setInterval> | null = null;

// ----- Screaming alarm state -----
const alarmArmed = ref(true);
const screamingAlert = ref<GasAlert | null>(null);
const pendingScreamQueue = ref<GasAlert[]>([]);
const seenAlertIds = new Set<number>();

let audioContext: AudioContext | null = null;
let alarmOsc: OscillatorNode | null = null;
let alarmGain: GainNode | null = null;
let alarmSweepTimer: ReturnType<typeof setInterval> | null = null;
let titleFlashTimer: ReturnType<typeof setInterval> | null = null;
let originalDocTitle = "";

const ensureAudioContext = () => {
  if (typeof window === "undefined") return null;
  if (!audioContext) {
    const Ctor =
      (window as any).AudioContext || (window as any).webkitAudioContext;
    if (!Ctor) return null;
    audioContext = new Ctor();
  }
  if (audioContext && audioContext.state === "suspended") {
    audioContext.resume().catch(() => {});
  }
  return audioContext;
};

const startSiren = () => {
  const ctx = ensureAudioContext();
  if (!ctx) return;
  stopSiren();
  alarmGain = ctx.createGain();
  alarmGain.gain.value = 0.35;
  alarmGain.connect(ctx.destination);

  alarmOsc = ctx.createOscillator();
  alarmOsc.type = "sawtooth";
  alarmOsc.frequency.value = 700;
  alarmOsc.connect(alarmGain);
  alarmOsc.start();

  let high = true;
  alarmSweepTimer = setInterval(() => {
    if (!alarmOsc || !audioContext) return;
    alarmOsc.frequency.setValueAtTime(
      high ? 1100 : 600,
      audioContext.currentTime,
    );
    high = !high;
  }, 380);
};

const stopSiren = () => {
  if (alarmSweepTimer !== null) {
    clearInterval(alarmSweepTimer);
    alarmSweepTimer = null;
  }
  if (alarmOsc) {
    try {
      alarmOsc.stop();
    } catch {}
    try {
      alarmOsc.disconnect();
    } catch {}
    alarmOsc = null;
  }
  if (alarmGain) {
    try {
      alarmGain.disconnect();
    } catch {}
    alarmGain = null;
  }
};

const startTitleFlash = () => {
  if (typeof document === "undefined" || titleFlashTimer) return;
  originalDocTitle = document.title;
  let toggle = true;
  titleFlashTimer = setInterval(() => {
    document.title = toggle
      ? `⚠ GAS ALERT — ${originalDocTitle}`
      : originalDocTitle;
    toggle = !toggle;
  }, 700);
};

const stopTitleFlash = () => {
  if (titleFlashTimer !== null) {
    clearInterval(titleFlashTimer);
    titleFlashTimer = null;
  }
  if (typeof document !== "undefined" && originalDocTitle) {
    document.title = originalDocTitle;
  }
};

const requestBrowserNotification = () => {
  if (typeof window === "undefined" || !("Notification" in window)) return;
  if (Notification.permission === "default") {
    Notification.requestPermission().catch(() => {});
  }
};

const pushBrowserNotification = (alert: GasAlert) => {
  if (typeof window === "undefined" || !("Notification" in window)) return;
  if (Notification.permission !== "granted") return;
  try {
    new Notification("⚠ Gas Alert", {
      body: `${alert.sensorType} at ${formatPpm(alert.valuePpm)} ppm — ${alert.location}`,
      icon: "/icon.png",
      tag: `gas-${alert.id}`,
      requireInteraction: true,
    });
  } catch {
    // ignore
  }
};

const triggerScreamForAlert = (alert: GasAlert) => {
  if (screamingAlert.value) {
    if (!pendingScreamQueue.value.some((a) => a.id === alert.id)) {
      pendingScreamQueue.value.push(alert);
    }
    return;
  }
  screamingAlert.value = alert;
  pushBrowserNotification(alert);
  startTitleFlash();
  if (alarmArmed.value) startSiren();
};

const toggleAlarmArmed = () => {
  alarmArmed.value = !alarmArmed.value;
  if (alarmArmed.value) {
    ensureAudioContext();
    requestBrowserNotification();
    if (screamingAlert.value) startSiren();
  } else {
    stopSiren();
  }
};

const acknowledgeScreaming = () => {
  stopSiren();
  screamingAlert.value = null;
  if (pendingScreamQueue.value.length > 0) {
    const next = pendingScreamQueue.value.shift()!;
    triggerScreamForAlert(next);
  } else {
    stopTitleFlash();
  }
};

const silenceOnly = () => {
  stopSiren();
};

const oneShotResume = () => {
  ensureAudioContext();
  if (typeof window !== "undefined") {
    window.removeEventListener("pointerdown", oneShotResume);
    window.removeEventListener("keydown", oneShotResume);
  }
};

onMounted(async () => {
  await refreshAll();
  await Promise.all([refreshAlertHistory(), fetchSummary()]);
  for (const sensor of sensors.value) {
    fetchHistory(sensor.id, 10);
  }
  for (const alert of alerts.value) {
    fetchAcks(alert.id);
  }
  nowTimer = setInterval(() => {
    now.value = Date.now();
  }, 1000);

  // Seed seenAlertIds with existing alerts so the first refresh does not scream.
  for (const a of alerts.value) seenAlertIds.add(a.id);

  if (import.meta.client) {
    requestBrowserNotification();
    window.addEventListener("pointerdown", oneShotResume, { once: true });
    window.addEventListener("keydown", oneShotResume, { once: true });
  }
});

watch(
  () => alerts.value.map((a) => a.id).join(","),
  () => {
    for (const alert of alerts.value) {
      if (!seenAlertIds.has(alert.id)) {
        seenAlertIds.add(alert.id);
        triggerScreamForAlert(alert);
      }
    }
    if (screamingAlert.value && !alerts.value.some((a) => a.id === screamingAlert.value!.id)) {
      acknowledgeScreaming();
    }
    pendingScreamQueue.value = pendingScreamQueue.value.filter((a) =>
      alerts.value.some((b) => b.id === a.id),
    );
  },
);

onBeforeUnmount(() => {
  if (nowTimer) {
    clearInterval(nowTimer);
    nowTimer = null;
  }
  stopSiren();
  stopTitleFlash();
  screamingAlert.value = null;
  pendingScreamQueue.value = [];
  if (typeof window !== "undefined") {
    window.removeEventListener("pointerdown", oneShotResume);
    window.removeEventListener("keydown", oneShotResume);
  }
  if (audioContext) {
    try {
      audioContext.close();
    } catch {}
    audioContext = null;
  }
});

const mapCenter = computed<[number, number]>(() => {
  if (sensors.value.length === 0) return [44.4378, 26.0969];
  const avgLat =
    sensors.value.reduce((acc, s) => acc + s.latitude, 0) / sensors.value.length;
  const avgLng =
    sensors.value.reduce((acc, s) => acc + s.longitude, 0) / sensors.value.length;
  return [avgLat, avgLng];
});

const sensorIconFor = (type: GasSensorType) => {
  switch (type) {
    case "CH4":
      return "mdi:gas-burner";
    case "CO":
      return "mdi:molecule-co";
    case "LPG":
      return "mdi:fire";
    case "MULTI":
    default:
      return "mdi:radar";
  }
};

const badgeVariantFor = (type: GasSensorType) => {
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

const floorLabel = (floor: number) => {
  if (floor === -1) return "Basement";
  if (floor === 0) return "Ground";
  return `Floor ${floor}`;
};

const statusLabel = (sensor: GasSensor) => {
  if (sensor.status === "alert") {
    return classifyReading(
      sensor.sensorType,
      sensor.lastReading ?? 0,
      thresholds.value[sensor.sensorType],
    );
  }
  return sensor.status;
};

const sensorNameFor = (sensorId: string) =>
  sensors.value.find((s) => s.id === sensorId)?.name;

const sparklineData = (sensorId: string) => {
  const data = history.value[sensorId];
  if (!data || data.length === 0) return null;
  const sensor = sensors.value.find((s) => s.id === sensorId);
  const color = sensor ? colorForSensor(sensor) : "#22C55E";
  return {
    labels: data.map((_, i) => `${i}`),
    datasets: [
      {
        data,
        borderColor: color,
        backgroundColor: `${color}33`,
        borderWidth: 1.5,
        pointRadius: 0,
        tension: 0.35,
        fill: true,
      },
    ],
  };
};

const sparklineOptions = (sensor: GasSensor) => ({
  responsive: true,
  maintainAspectRatio: false,
  plugins: {
    legend: { display: false },
    tooltip: { enabled: false },
  },
  scales: {
    x: { display: false },
    y: {
      display: false,
      beginAtZero: false,
      suggestedMin: 0,
      suggestedMax: Math.max(
        ...(history.value[sensor.id] ?? [0]),
        thresholds.value[sensor.sensorType]?.warning ?? 1000,
      ),
    },
  },
  elements: {
    line: { capBezierPoints: false },
  },
});

const isFlashing = (sensorId: string) => {
  const ts = flashStates.value[sensorId];
  if (!ts) return false;
  return now.value - ts < 4000;
};

const elapsedFor = (sensorId: string) => {
  const ts = flashStates.value[sensorId];
  if (!ts) return "";
  const seconds = Math.floor((now.value - ts) / 1000);
  if (seconds < 60) return `${seconds}s ago`;
  const minutes = Math.floor(seconds / 60);
  return `${minutes}m ago`;
};

const formatTime = (iso: string) => {
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return iso;
  return d.toLocaleTimeString(undefined, { hour: "2-digit", minute: "2-digit", second: "2-digit" });
};

const onResolve = async (alertId: number) => {
  resolving.value = alertId;
  try {
    await resolveAlert(alertId);
  } finally {
    resolving.value = null;
  }
};
</script>

<style scoped>
.sensor-flash {
  animation: gas-flash 1s ease-in-out 4;
}

@keyframes gas-flash {
  0%, 100% {
    box-shadow: 0 0 0 0 rgba(239, 68, 68, 0);
  }
  50% {
    box-shadow: 0 0 0 8px rgba(239, 68, 68, 0.35);
  }
}

.map-container :deep(.leaflet-container) {
  width: 100%;
  height: 100%;
}

.screaming-overlay {
  animation: scream-bg 0.6s ease-in-out infinite alternate;
}

@keyframes scream-bg {
  from {
    background-color: rgba(127, 29, 29, 0.92);
  }
  to {
    background-color: rgba(239, 68, 68, 0.92);
  }
}

.scream-pulse {
  animation: scream-pulse 0.9s ease-in-out infinite;
}

@keyframes scream-pulse {
  0%, 100% {
    transform: scale(1);
    box-shadow: 0 0 0 0 rgba(255, 255, 255, 0.0);
  }
  50% {
    transform: scale(1.02);
    box-shadow: 0 0 60px 10px rgba(239, 68, 68, 0.55);
  }
}

.scream-shake {
  animation: scream-shake 0.4s ease-in-out infinite;
}

@keyframes scream-shake {
  0%, 100% { transform: translateX(0) rotate(0deg); }
  25% { transform: translateX(-4px) rotate(-3deg); }
  75% { transform: translateX(4px) rotate(3deg); }
}

.scream-stripes {
  background-image: repeating-linear-gradient(
    45deg,
    rgba(255, 255, 255, 0.08) 0 22px,
    transparent 22px 44px
  );
  animation: scream-stripes 1.4s linear infinite;
}

@keyframes scream-stripes {
  from { background-position: 0 0; }
  to { background-position: 64px 0; }
}
</style>
