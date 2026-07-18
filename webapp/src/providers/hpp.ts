/**
 * HPP (HydroPaw Protocol) v1 — TypeScript実装。
 * firmware/App/Src/hpp.c / Flutter側 hpp_codec.dart と同一仕様
 * (テストベクタ: CMD_START_CONT(interval=1, seq=0) の CRC = 0x53CC)。
 */
export const HPP = {
  sof: 0xa5,
  version: 0x01,
  maxPayload: 48,
  headerSize: 5,
  crcSize: 2,

  cmdStartCont: 0x01,
  cmdStop: 0x02,
  cmdSingle: 0x03,
  cmdSleep: 0x04,
  cmdWake: 0x05,
  cmdGetStatus: 0x06,
  cmdGetInfo: 0x07,
  cmdZero: 0x08,
  cmdAckEvt: 0x09, // 信頼配送イベントの受領ACK(payload=SEQ)
  cmdBreath: 0x0a, // 呼気イベント測定セッション開始 (docs/18)

  ack: 0x40,
  nak: 0x41,
  evtData: 0x81,
  evtSummary: 0x82,
  evtStatus: 0x83,
  evtError: 0x84,
  evtInfo: 0x85,
  evtResult: 0x86, // 呼気解析結果30B (要ACK_EVT — 選択的ARQ)
  evtPhase: 0x87, // 状態遷移通知 {phase, detail}
} as const

export interface HppFrame {
  type: number
  seq: number
  payload: Uint8Array
}

/** CRC16 CCITT-FALSE (poly 0x1021, init 0xFFFF) */
export function hppCrc16(data: ArrayLike<number>, length?: number): number {
  let crc = 0xffff
  const n = length ?? data.length
  for (let i = 0; i < n; i++) {
    crc ^= (data[i] & 0xff) << 8
    for (let b = 0; b < 8; b++) {
      crc = crc & 0x8000 ? ((crc << 1) ^ 0x1021) & 0xffff : (crc << 1) & 0xffff
    }
  }
  return crc
}

export function hppEncode(
  type: number,
  seq: number,
  payload: ArrayLike<number> = [],
): Uint8Array {
  if (payload.length > HPP.maxPayload) throw new Error('payload too long')
  const frame = new Uint8Array(HPP.headerSize + payload.length + HPP.crcSize)
  frame[0] = HPP.sof
  frame[1] = HPP.version
  frame[2] = type
  frame[3] = seq & 0xff
  frame[4] = payload.length
  frame.set(Array.from(payload), HPP.headerSize)
  const body = HPP.headerSize + payload.length
  const crc = hppCrc16(frame, body)
  frame[body] = (crc >> 8) & 0xff // CRCのみビッグエンディアン
  frame[body + 1] = crc & 0xff
  return frame
}

/** ストリーミングデコーダ。破損時は先頭1バイト破棄で自己再同期。 */
export class HppDecoder {
  private buf: number[] = []
  crcErrors = 0
  resyncs = 0

  feed(chunk: ArrayLike<number>): HppFrame[] {
    this.buf.push(...Array.from(chunk))
    const frames: HppFrame[] = []

    while (this.buf.length > 0) {
      if (this.buf[0] !== HPP.sof) {
        this.buf.shift()
        continue
      }
      if (this.buf.length >= 2 && this.buf[1] !== HPP.version) {
        this.resyncs++
        this.buf.shift()
        continue
      }
      if (this.buf.length < HPP.headerSize) break

      const len = this.buf[4]
      if (len > HPP.maxPayload) {
        this.resyncs++
        this.buf.shift()
        continue
      }
      const total = HPP.headerSize + len + HPP.crcSize
      if (this.buf.length < total) break

      const body = total - HPP.crcSize
      const calc = hppCrc16(this.buf, body)
      const recv = (this.buf[body] << 8) | this.buf[body + 1]
      if (calc !== recv) {
        this.crcErrors++
        this.buf.shift()
        continue
      }

      frames.push({
        type: this.buf[2],
        seq: this.buf[3],
        payload: new Uint8Array(
          this.buf.slice(HPP.headerSize, HPP.headerSize + len),
        ),
      })
      this.buf.splice(0, total)
    }
    return frames
  }

  reset(): void {
    this.buf = []
  }
}

// ---- ペイロードのリトルエンディアン読み出しヘルパ ----
export function readEvtData(p: Uint8Array) {
  const v = new DataView(p.buffer, p.byteOffset, p.byteLength)
  return {
    timeMs: v.getUint32(0, true),
    h2Ppb: v.getInt32(4, true),
    tempC: v.getInt16(8, true) / 10,
    rh: v.getUint16(10, true) / 10,
    flags: p[12],
  }
}

export function readEvtSummary(p: Uint8Array) {
  const v = new DataView(p.buffer, p.byteOffset, p.byteLength)
  return {
    count: v.getUint16(0, true),
    avgPpb: v.getInt32(2, true),
    maxPpb: v.getInt32(6, true),
    minPpb: v.getInt32(10, true),
    durationS: v.getUint16(14, true),
  }
}

/** EVT_RESULT (30B) — firmware send_result / Dart resultXxx と1:1 */
export function readEvtResult(p: Uint8Array) {
  const v = new DataView(p.buffer, p.byteOffset, p.byteLength)
  return {
    sessionId: p[0],
    quality: p[1], // Q 0-100
    confidence: p[2], // C 0-100
    flags: p[3], // bit0:REMEASURE bit1:RH_OK bit2:TRUNCATED bit3:RETRIED
    baselinePpb: v.getInt32(4, true),
    peakPpb: v.getInt32(8, true),
    plateauPpb: v.getInt32(12, true),
    aucPpbS: v.getUint32(16, true),
    riseS: v.getUint16(20, true) / 10,
    durationS: v.getUint16(22, true) / 10,
    tempC: v.getInt16(24, true) / 10,
    rhDelta: v.getInt16(26, true) / 10,
    preMadPpb: v.getUint16(28, true),
  }
}

export function readEvtStatus(p: Uint8Array) {
  const v = new DataView(p.buffer, p.byteOffset, p.byteLength)
  return {
    state: p[0],
    batteryMv: v.getUint16(1, true),
    sensorOk: p[3] !== 0,
    uptimeS: v.getUint32(4, true),
    crcErrors: p.length >= 12 ? v.getUint16(8, true) : 0,
    resyncs: p.length >= 12 ? v.getUint16(10, true) : 0,
  }
}
