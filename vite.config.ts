import { fileURLToPath, URL } from "node:url";
import { defineConfig } from "vite";
import vue from "@vitejs/plugin-vue";

export default defineConfig({
  plugins: [vue()],
  resolve: {
    // Same alias Nuxt uses for its source folder, so imports survive a move to Nuxt.
    alias: { "~": fileURLToPath(new URL("./app", import.meta.url)) },
  },
});
