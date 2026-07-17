/**
 * MockProvider — 実機なしでダッシュボードを動かすためのデータ生成器。
 * ファームウェアの挙動(接続遅延・ACK・1Hzストリーム・ウォームアップ・
 * サマリ計算)を簡易に模倣する。
 */
import type {
  ConnectionStatus,
  DataProvider,
  DeviceStatus,
  SensorSample,
  SessionSummary,
  Unsubscribe,
} from './DataProvider'
import { FLAG_WARMUP } from './DataProvider'

export class MockProvider implements DataProvider {
  readonly name = 'Mock'

  private sampleListeners = new Set<(s: SensorSample) => void>()
  private connListeners = new Set<(c: ConnectionStatus) => void>()

  private timer: ReturnType<typeof setInterval> | null = null
  private connected = false
  private status: DeviceStatus = 'idle'

  // 模擬センサ状態
  private baselinePpb = 3200
  private breathPhase = 0
  private battery = 92
  private sessionStart: Date | null = null
  private count = 0
  private sum = 0
  private max = 0
  private min = Number.MAX_SAFE_INTEGER

  async connect(): Promise<void> {
    this.notifyConn('connecting')
    await sleep(700) // 実機の接続時間を模倣
    this.connected = true
    this.status = 'idle'
    this.notifyConn('connected')
  }

  async disconnect(): Promise<void> {
    this.stopTimer()
    this.connected = false
    this.status = 'idle'
    this.notifyConn('disconnected')
  }

  async startMeasurement(): Promise<void> {
    if (!this.connected) throw new Error('not connected')
    if (this.timer) return
    await sleep(60) // ACK往復
    this.status = 'measuring'
    this.sessionStart = new Date()
    this.count = 0
    this.sum = 0
    this.max = 0
    this.min = Number.MAX_SAFE_INTEGER
    this.emitSample() // 開始直後に1点
    this.timer = setInterval(() => this.emitSample(), 1000)
  }

  async stopMeasurement(): Promise<SessionSummary | null> {
    if (!this.timer) return null
    await sleep(60)
    this.stopTimer()
    this.status = 'idle'
    const startedAt = this.sessionStart ?? new Date()
    return {
      startedAt: startedAt.toISOString(),
      durationS: Math.round((Date.now() - startedAt.getTime()) / 1000),
      sampleCount: this.count,
      avgPpb: this.count === 0 ? 0 : Math.round(this.sum / this.count),
      maxPpb: this.max,
      minPpb: this.count === 0 ? 0 : this.min,
    }
  }

  onSample(cb: (s: SensorSample) => void): Unsubscribe {
    this.sampleListeners.add(cb)
    return () => this.sampleListeners.delete(cb)
  }

  onConnection(cb: (c: ConnectionStatus) => void): Unsubscribe {
    this.connListeners.add(cb)
    return () => this.connListeners.delete(cb)
  }

  // ---- 内部 ----

  private stopTimer() {
    if (this.timer) clearInterval(this.timer)
    this.timer = null
  }

  /** 呼気を模した波形: ベースライン + ドリフト + 周期的な呼気ピーク + ノイズ */
  private emitSample() {
    const elapsedMs = this.sessionStart
      ? Date.now() - this.sessionStart.getTime()
      : 0

    this.breathPhase += 0.1 + Math.random() * 0.04
    this.baselinePpb = clamp(
      this.baselinePpb + (Math.random() - 0.5) * 60,
      1500,
      9000,
    )
    const breath = Math.max(0, Math.sin(this.breathPhase)) * 2600
    const noise = (Math.random() - 0.5) * 240
    const ppb = Math.round(
      clamp(this.baselinePpb + breath + noise, 0, 130000),
    )

    let flags = 0
    if (elapsedMs < 60_000) flags |= FLAG_WARMUP

    if ((flags & 0x03) === 0) {
      this.count++
      this.sum += ppb
      this.max = Math.max(this.max, ppb)
      this.min = Math.min(this.min, ppb)
    }
    if (Math.random() < 0.02 && this.battery > 5) this.battery -= 1

    const sample: SensorSample = {
      timestamp: new Date().toISOString(),
      hydrogen_ppb: ppb,
      temperature: round1(24.8 + Math.random() * 0.7),
      humidity: round1(42.0 + Math.random() * 3.0),
      battery: this.battery,
      status: this.status,
      flags,
    }
    this.sampleListeners.forEach((cb) => cb(sample))
  }

  private notifyConn(c: ConnectionStatus) {
    this.connListeners.forEach((cb) => cb(c))
  }
}

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms))
const clamp = (v: number, lo: number, hi: number) =>
  Math.min(hi, Math.max(lo, v))
const round1 = (v: number) => Math.round(v * 10) / 10
