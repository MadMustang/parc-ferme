import { createRouter, createWebHistory } from "vue-router";

// Mirrors app/pages/ path for path, so this is the only file a move to Nuxt deletes.
export const router = createRouter({
  history: createWebHistory(),
  routes: [
    { path: "/", component: () => import("~/pages/index.vue") },
    { path: "/leaderboard", component: () => import("~/pages/leaderboard.vue") },
    { path: "/profile", component: () => import("~/pages/profile.vue") },
    { path: "/sign-in", component: () => import("~/pages/sign-in.vue"), meta: { layout: "auth" } },
    { path: "/join", component: () => import("~/pages/join.vue"), meta: { layout: "auth" } },
    { path: "/check-email", component: () => import("~/pages/check-email.vue"), meta: { layout: "auth" } },
    { path: "/auth/callback", component: () => import("~/pages/auth/callback.vue"), meta: { layout: "auth" } },
  ],
});
