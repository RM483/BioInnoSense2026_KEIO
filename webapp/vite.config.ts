import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

export default defineConfig({
  plugins: [react()],
  // 相対パス出力: `npm run build` の成果物を file:// や任意のサブパスでも
  // 開けるようにする (デモ配布・オフライン確認用)
  base: './',
  server: { port: 5173 },
})
