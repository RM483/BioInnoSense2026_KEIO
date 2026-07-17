/**
 * Provider切替はこの1箇所のみ。
 * - 開発(実機なし): MockProvider
 * - 実機(Web Bluetooth): BleProvider  ※ `VITE_PROVIDER=ble` で切替
 */
import type { DataProvider } from './DataProvider'
import { BleProvider } from './BleProvider'
import { MockProvider } from './MockProvider'

export function createProvider(): DataProvider {
  return import.meta.env.VITE_PROVIDER === 'ble'
    ? new BleProvider()
    : new MockProvider()
}
