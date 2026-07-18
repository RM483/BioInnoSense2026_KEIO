/// <reference types="web-bluetooth" />
/**
 * BleProvider — Web Bluetooth経由でHydroPaw実機(AC02透過UART + HPP)に
 * 接続するDataProvider実装。
 *
 * 実機到着後に providers/index.ts で MockProvider から差し替える。
 * UUIDはAC02実機で要確認 (docs/03_ble_spec.md / Flutter側 BleUuids と同一)。
 *
 * 注意: Web BluetoothはChrome系のみ・HTTPSまたはlocalhostでのみ動作。
 */
import type {
  ConnectionStatus,
  DataProvider,
  SensorSample,
  SessionSummary,
  Unsubscribe,
} from './DataProvider'
import {
  HPP,
  HppDecoder,
  hppEncode,
  readEvtData,
  readEvtResult,
  readEvtSummary,
} from './hpp'

const SERVICE_UUID = '0179bbd0-5351-48b5-bf6d-2167639bc867'
const TX_UUID = '0179bbd1-5351-48b5-bf6d-2167639bc867' // FW→App Notify
const RX_UUID = '0179bbd2-5351-48b5-bf6d-2167639bc867' // App→FW Write
const NAME_PREFIX = 'HydroPaw'

export class BleProvider implements DataProvider {
  readonly name = 'BLE'

  private sampleListeners = new Set<(s: SensorSample) => void>()
  private connListeners = new Set<(c: ConnectionStatus) => void>()

  private device: BluetoothDevice | null = null
  private rxChar: BluetoothRemoteGATTCharacteristic | null = null
  private decoder = new HppDecoder()
  private seq = 0
  private measuring = false
  private batteryMv = 0
  private summaryWaiter: ((s: SessionSummary | null) => void) | null = null
  private sessionStart: Date | null = null

  async connect(): Promise<void> {
    if (!('bluetooth' in navigator)) {
      throw new Error(
        'Web Bluetooth未対応のブラウザです (Chrome/Edgeで開いてください)',
      )
    }
    this.notifyConn('connecting')
    try {
      const device = await navigator.bluetooth.requestDevice({
        filters: [{ namePrefix: NAME_PREFIX }],
        optionalServices: [SERVICE_UUID],
      })
      this.device = device
      device.addEventListener('gattserverdisconnected', () =>
        this.notifyConn('disconnected'),
      )

      const server = await device.gatt!.connect()
      const service = await server.getPrimaryService(SERVICE_UUID)
      const tx = await service.getCharacteristic(TX_UUID)
      this.rxChar = await service.getCharacteristic(RX_UUID)

      this.decoder.reset()
      await tx.startNotifications()
      tx.addEventListener('characteristicvaluechanged', (e) => {
        const dv = (e.target as BluetoothRemoteGATTCharacteristic).value
        if (dv) this.onChunk(new Uint8Array(dv.buffer))
      })
      this.notifyConn('connected')
    } catch (e) {
      this.notifyConn('disconnected')
      throw e
    }
  }

  async disconnect(): Promise<void> {
    this.device?.gatt?.disconnect()
    this.device = null
    this.rxChar = null
    this.notifyConn('disconnected')
  }

  async startMeasurement(): Promise<void> {
    this.sessionStart = new Date()
    this.measuring = true
    await this.send(HPP.cmdStartCont, [1])
  }

  async stopMeasurement(): Promise<SessionSummary | null> {
    const summary = new Promise<SessionSummary | null>((resolve) => {
      this.summaryWaiter = resolve
      setTimeout(() => {
        if (this.summaryWaiter === resolve) {
          this.summaryWaiter = null
          resolve(null) // サマリ喪失(呼び出し側でローカル統計を使う)
        }
      }, 3000)
    })
    await this.send(HPP.cmdStop)
    this.measuring = false
    return summary
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

  private notifyConn(c: ConnectionStatus) {
    this.connListeners.forEach((cb) => cb(c))
  }

  private async send(type: number, payload: number[] = []): Promise<void> {
    if (!this.rxChar) throw new Error('not connected')
    await this.rxChar.writeValueWithoutResponse(
      hppEncode(type, this.seq++, payload) as BufferSource,
    )
  }

  /** 信頼配送イベントの重複排除済みSEQ。8bit巡回のため直近16件のみ保持
   *  (無制限だとSEQ再利用時に新フレームを誤って捨てる — レビューF3) */
  private ackedSeqs: number[] = []

  /** 信頼配送イベントを受領: ACK_EVTを返し、ARQ再送(重複)ならfalse */
  private ackReliable(seq: number): boolean {
    void this.send(HPP.cmdAckEvt, [seq]).catch(() => {})
    if (this.ackedSeqs.includes(seq)) return false
    this.ackedSeqs.push(seq)
    if (this.ackedSeqs.length > 16) this.ackedSeqs.shift()
    return true
  }

  private onChunk(chunk: Uint8Array) {
    for (const f of this.decoder.feed(chunk)) {
      switch (f.type) {
        case HPP.evtResult: {
          if (!this.ackReliable(f.seq)) break
          const r = readEvtResult(f.payload)
          // 呼気モードの結果もサマリ待ちへ渡す(代表値=プラトー, docs/18)
          this.summaryWaiter?.({
            startedAt: (this.sessionStart ?? new Date()).toISOString(),
            durationS: Math.round(r.durationS),
            sampleCount: 0,
            avgPpb: r.plateauPpb,
            maxPpb: r.peakPpb,
            minPpb: r.baselinePpb,
            quality: r.quality,
            confidence: r.confidence,
            qualityFlags: r.flags,
          })
          this.summaryWaiter = null
          break
        }
        case HPP.evtData: {
          const d = readEvtData(f.payload)
          this.sampleListeners.forEach((cb) =>
            cb({
              timestamp: new Date().toISOString(),
              hydrogen_ppb: d.h2Ppb,
              temperature: d.tempC,
              humidity: d.rh,
              battery: this.batteryPercent(),
              status: this.measuring ? 'measuring' : 'idle',
              flags: d.flags,
            }),
          )
          break
        }
        case HPP.evtSummary: {
          if (!this.ackReliable(f.seq)) break // FW v1.2はサマリも信頼配送
          const s = readEvtSummary(f.payload)
          this.summaryWaiter?.({
            startedAt: (this.sessionStart ?? new Date()).toISOString(),
            durationS: s.durationS,
            sampleCount: s.count,
            avgPpb: s.avgPpb,
            maxPpb: s.maxPpb,
            minPpb: s.minPpb,
          })
          this.summaryWaiter = null
          break
        }
        case HPP.evtStatus: {
          const v = new DataView(f.payload.buffer)
          this.batteryMv = v.getUint16(1, true)
          break
        }
      }
    }
  }

  /** 電池電圧[mV] → ざっくり% (Li-ion 3.3-4.2V) */
  private batteryPercent(): number {
    if (this.batteryMv === 0) return 100
    const pct = ((this.batteryMv - 3300) / (4200 - 3300)) * 100
    return Math.round(Math.min(100, Math.max(0, pct)))
  }
}
