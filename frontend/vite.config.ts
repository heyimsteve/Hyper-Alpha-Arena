import path from "path"
import react from "@vitejs/plugin-react"
import { defineConfig } from "vite"

export default defineConfig({
  plugins: [react()],
  build: {
    rollupOptions: {
      output: {
        entryFileNames: `assets/[name]-[hash]-${Date.now()}.js`,
        chunkFileNames: `assets/[name]-[hash]-${Date.now()}.js`,
        assetFileNames: `assets/[name]-[hash]-${Date.now()}.[ext]`
      }
    }
  },
  server: {
    host: "0.0.0.0",
    port: 5173,  // Frontend dev server port (different from backend 8802)
    allowedHosts: true,  // Allow all hosts for flexible deployment
    proxy: {
      '/api': {
        target: 'http://127.0.0.1:8802',  // Backend API
        changeOrigin: true,
        timeout: 60000,  // 60 second timeout for slow startup
      },
      '/ws': {
        target: 'ws://127.0.0.1:8802',  // Backend WebSocket
        changeOrigin: true,
        ws: true,
        timeout: 60000,  // 60 second timeout
      },
    },
  },
  resolve: {
    alias: {
      "@": path.resolve(__dirname, "./app"),
    },
  },
})
