<script setup lang="ts">
// Gas monitoring is the main dashboard view — send the dashboard root there.
definePageMeta({
  layout: "dashboard",
  middleware: "auth",
  redirect: "/dashboard/gas",
});
</script>

<template>
  <div />
</template>
