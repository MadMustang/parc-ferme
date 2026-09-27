<script setup lang="ts">
import { computed } from "vue";
import { useRoute } from "vue-router";
import AuthLayout from "~/layouts/auth.vue";
import DefaultLayout from "~/layouts/default.vue";

// Stands in for Nuxt's <NuxtLayout>: pages pick a layout through route meta.
const route = useRoute();
const layout = computed(() => (route.meta.layout === "auth" ? AuthLayout : DefaultLayout));
</script>

<template>
  <component :is="layout"><RouterView /></component>
</template>
