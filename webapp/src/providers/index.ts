/**
 * Provider切替はこの1箇所のみ。
 * - 既定: BleProvider (実機, Web Bluetooth) — 実機運用が本線のため
 * - デモ(実機なし): MockProvider ※ `VITE_PROVIDER=mock` で切替
 *   例) PowerShell: $env:VITE_PROVIDER="mock"; npm run dev
 */
import type { DataProvider } from './DataProvider'
import { BleProvider } from './BleProvider'
import { MockProvider } from './MockProvider'

export function createProvider(): DataProvider {
  return import.meta.env.VITE_PROVIDER === 'mock'
    ? new MockProvider()
    : new BleProvider()
}
