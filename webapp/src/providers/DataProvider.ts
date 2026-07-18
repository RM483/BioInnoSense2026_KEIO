/**
 * DataProvider — データ供給の抽象。
 * MockProvider(開発用) と BleProvider(実機, Web Bluetooth) が実装する。
 * UI層はこのインターフェースのみに依存し、実機到着後は
 * providers/index.ts の1箇所を切り替えるだけで移行できる。
 */

export type DeviceStatus = 'idle' | 'measuring' | 'sleep' | 'error'
export type ConnectionStatus = 'disconnected' | 'connecting' | 'connected'

/** 1秒毎に届く測定サンプル (STM32のEVT_DATA相当) */
export interface SensorSample {
  timestamp: string // ISO8601
  hydrogen_ppb: number
  temperature: number // ℃
  humidity: number // %
  battery: number // %
  status: DeviceStatus
  /** HPP flags (bit0:OUT_OF_RANGE bit1:STUCK bit2:WARMUP bit3:UNSTABLE) */
  flags: number
}

/** 測定終了時のサマリ (EVT_SUMMARY / EVT_RESULT相当) */
export interface SessionSummary {
  startedAt: string
  durationS: number
  sampleCount: number
  avgPpb: number
  maxPpb: number
  minPpb: number
  /** BAP品質スコア Q 0-100 (呼気モードのみ, docs/18 §S6) */
  quality?: number
  /** BAP信頼度スコア C 0-100 (計測器健全性, §S7) */
  confidence?: number
  /** EVT_RESULT flags (bit0:REMEASURE bit1:RH_OK …) */
  qualityFlags?: number
  /** 測定した犬 (多頭飼い対応, docs/21。App層が保存時に付与) */
  dogId?: string
}

export type Unsubscribe = () => void

export interface DataProvider {
  readonly name: string
  connect(): Promise<void>
  disconnect(): Promise<void>
  startMeasurement(): Promise<void>
  /** 停止し、サマリを返す(サマリ喪失時はnull) */
  stopMeasurement(): Promise<SessionSummary | null>

  onSample(cb: (s: SensorSample) => void): Unsubscribe
  onConnection(cb: (c: ConnectionStatus) => void): Unsubscribe
}

export const H2_HIGH_PPM = 20.0
export const FLAG_OUT_OF_RANGE = 1 << 0
export const FLAG_STUCK = 1 << 1
export const FLAG_WARMUP = 1 << 2
export const FLAG_UNSTABLE = 1 << 3
