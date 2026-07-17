/**
 * HydroPaw デバッグダッシュボード。
 * DataProvider(Mock/BLE)からの1Hzストリームを可視化する。
 * デザイントークン・情報設計はFlutterアプリと同一言語。
 */
import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { Chart } from './components/Chart'
import type {
  ConnectionStatus,
  SensorSample,
  SessionSummary,
} from './providers/DataProvider'
import { FLAG_WARMUP, H2_HIGH_PPM } from './providers/DataProvider'
import { createProvider } from './providers'

const MAX_SAMPLES = 1800
const HISTORY_KEY = 'hydropaw.history.v1'

export default function App() {
  const provider = useMemo(createProvider, [])
  const [conn, setConn] = useState<ConnectionStatus>('disconnected')
  const [measuring, setMeasuring] = useState(false)
  const [samples, setSamples] = useState<SensorSample[]>([])
  const [history, setHistory] = useState<SessionSummary[]>(loadHistory)
  const [busy, setBusy] = useState(false)
  const sessionStart = useRef<Date | null>(null)

  useEffect(() => {
    const offConn = provider.onConnection(setConn)
    const offSample = provider.onSample((s) =>
      setSamples((prev) => {
        const next = [...prev, s]
        return next.length > MAX_SAMPLES ? next.slice(-MAX_SAMPLES) : next
      }),
    )
    return () => {
      offConn()
      offSample()
    }
  }, [provider])

  const connect = useCallback(async () => {
    setBusy(true)
    try {
      await provider.connect()
    } catch (e) {
      console.error(e)
      alert((e as Error).message)
    } finally {
      setBusy(false)
    }
  }, [provider])

  const disconnect = useCallback(async () => {
    if (measuring) await provider.stopMeasurement()
    setMeasuring(false)
    await provider.disconnect()
  }, [provider, measuring])

  const start = useCallback(async () => {
    setBusy(true)
    try {
      setSamples([])
      sessionStart.current = new Date()
      await provider.startMeasurement()
      setMeasuring(true)
    } finally {
      setBusy(false)
    }
  }, [provider])

  const stop = useCallback(async () => {
    setBusy(true)
    try {
      const summary =
        (await provider.stopMeasurement()) ?? localSummary(samples, sessionStart.current)
      setMeasuring(false)
      if (summary && summary.sampleCount > 0) {
        setHistory((prev) => {
          const next = [summary, ...prev].slice(0, 50)
          localStorage.setItem(HISTORY_KEY, JSON.stringify(next))
          return next
        })
      }
    } finally {
      setBusy(false)
    }
  }, [provider, samples])

  const latest = samples.at(-1)
  const ppm = latest ? latest.hydrogen_ppb / 1000 : null
  const isHigh = (ppm ?? 0) >= H2_HIGH_PPM
  const warmingUp = latest ? (latest.flags & FLAG_WARMUP) !== 0 : false
  const stats = useMemo(() => sessionStats(samples), [samples])

  return (
    <div className="app">
      {/* ---- ヘッダ ---- */}
      <header className="header">
        <div className="brand">
          <h1>HydroPaw</h1>
          <span>debug console</span>
        </div>
        {provider.name === 'Mock' && <span className="pill accent">Mock</span>}
        <ConnectionPill conn={conn} />
      </header>

      <div className="grid">
        {/* ---- 左カラム ---- */}
        <div className="stack">
          <section className="card hero">
            <div
              className={`value ${ppm === null ? 'empty' : isHigh ? 'high' : ''}`}
            >
              {ppm === null ? '––' : ppm.toFixed(1)}
            </div>
            <div className="unit">ppm H₂</div>
            <div className="status">
              {warmingUp ? (
                <span className="pill warn">ウォームアップ中（参考値）</span>
              ) : ppm !== null ? (
                <span className={`pill ${isHigh ? 'warn' : 'ok'}`}>
                  <span className="dot" />
                  {isHigh ? '高め' : '基準内'}
                </span>
              ) : (
                <span className="pill muted">測定を開始してください</span>
              )}
            </div>
          </section>

          <section className="card chart-wrap">
            <Chart samples={samples} />
          </section>

          <section className="card stats">
            <Stat k="経過" v={formatElapsed(stats.elapsedMs)} />
            <Stat k="平均" v={fmt(stats.avgPpm)} />
            <Stat k="最大" v={fmt(stats.peakPpm)} />
            <Stat k="温度" v={latest ? `${latest.temperature.toFixed(1)}°` : '––'} />
            <Stat k="湿度" v={latest ? `${latest.humidity.toFixed(0)}%` : '––'} />
          </section>

          <div className="controls">
            {conn !== 'connected' ? (
              <button className="btn primary" onClick={connect} disabled={busy || conn === 'connecting'}>
                {conn === 'connecting' ? '接続中…' : 'デバイスに接続'}
              </button>
            ) : (
              <>
                <button
                  className={`btn ${measuring ? 'stop' : 'primary'}`}
                  onClick={measuring ? stop : start}
                  disabled={busy}
                >
                  {measuring ? '停止' : '測定をはじめる'}
                </button>
                <button className="btn ghost" onClick={disconnect} disabled={busy}>
                  切断
                </button>
              </>
            )}
          </div>
        </div>

        {/* ---- 右カラム ---- */}
        <div className="stack">
          <section className="card">
            <h2>プロフィール</h2>
            <div className="dog">
              <div className="avatar">🐕</div>
              <div>
                <div className="name">ポチ</div>
                <div className="detail">柴犬 · 4歳 · 8.2kg</div>
              </div>
            </div>
          </section>

          <section className="card">
            <h2>デバイス</h2>
            <div className="env">
              <div className="row">
                <span className="k">状態</span>
                <span className="v">
                  {latest ? statusLabel(latest.status) : conn === 'connected' ? '待機' : '—'}
                </span>
              </div>
              <div className="row">
                <span className="k">電池</span>
                <span className="v">{latest ? `${latest.battery}%` : '—'}</span>
              </div>
              <div className="row">
                <span className="k">プロバイダ</span>
                <span className="v">{provider.name}</span>
              </div>
            </div>
          </section>

          <section className="card">
            <h2>履歴</h2>
            {history.length === 0 ? (
              <div className="empty-note">まだ測定がありません</div>
            ) : (
              <div className="history-list">
                {history.map((h, i) => (
                  <HistoryRow key={`${h.startedAt}-${i}`} s={h} />
                ))}
              </div>
            )}
          </section>
        </div>
      </div>
    </div>
  )
}

/* ---------- 小さな部品 ---------- */

function ConnectionPill({ conn }: { conn: ConnectionStatus }) {
  const cls =
    conn === 'connected' ? 'ok' : conn === 'connecting' ? 'warn' : 'muted'
  const label =
    conn === 'connected' ? '接続中' : conn === 'connecting' ? '接続処理中…' : '未接続'
  return (
    <span className={`pill ${cls}`}>
      <span className="dot" />
      {label}
    </span>
  )
}

function Stat({ k, v }: { k: string; v: string }) {
  return (
    <div className="stat">
      <div className="v">{v}</div>
      <div className="k">{k}</div>
    </div>
  )
}

function HistoryRow({ s }: { s: SessionSummary }) {
  const avg = s.avgPpb / 1000
  const d = new Date(s.startedAt)
  const when = `${d.getMonth() + 1}/${d.getDate()} ${pad(d.getHours())}:${pad(d.getMinutes())}`
  return (
    <div className="history-item">
      <span className="when">{when}</span>
      <span className={`avg ${avg >= H2_HIGH_PPM ? 'high' : ''}`}>
        {avg.toFixed(1)} ppm
      </span>
      <span className="meta">
        max {(s.maxPpb / 1000).toFixed(1)} · {Math.round(s.durationS / 60)}min
      </span>
    </div>
  )
}

/* ---------- ヘルパ ---------- */

function sessionStats(samples: SensorSample[]) {
  if (samples.length === 0) {
    return { avgPpm: null, peakPpm: null, elapsedMs: 0 }
  }
  const valid = samples.filter((s) => (s.flags & 0x03) === 0 && !(s.flags & FLAG_WARMUP))
  const ppms = valid.map((s) => s.hydrogen_ppb / 1000)
  const all = samples.map((s) => s.hydrogen_ppb / 1000)
  const first = new Date(samples[0].timestamp).getTime()
  const last = new Date(samples[samples.length - 1].timestamp).getTime()
  return {
    avgPpm: ppms.length ? ppms.reduce((a, b) => a + b, 0) / ppms.length : null,
    peakPpm: Math.max(...all),
    elapsedMs: last - first,
  }
}

function localSummary(
  samples: SensorSample[],
  started: Date | null,
): SessionSummary | null {
  if (samples.length === 0) return null
  const valid = samples.filter((s) => (s.flags & 0x03) === 0)
  const ppbs = valid.map((s) => s.hydrogen_ppb)
  const startedAt = started ?? new Date(samples[0].timestamp)
  return {
    startedAt: startedAt.toISOString(),
    durationS: Math.round((Date.now() - startedAt.getTime()) / 1000),
    sampleCount: valid.length,
    avgPpb: ppbs.length ? Math.round(ppbs.reduce((a, b) => a + b, 0) / ppbs.length) : 0,
    maxPpb: ppbs.length ? Math.max(...ppbs) : 0,
    minPpb: ppbs.length ? Math.min(...ppbs) : 0,
  }
}

function loadHistory(): SessionSummary[] {
  try {
    return JSON.parse(localStorage.getItem(HISTORY_KEY) ?? '[]')
  } catch {
    return []
  }
}

function statusLabel(s: SensorSample['status']): string {
  return { idle: '待機', measuring: '測定中', sleep: 'スリープ', error: 'エラー' }[s]
}

const fmt = (v: number | null) => (v === null ? '––' : v.toFixed(1))
const pad = (n: number) => String(n).padStart(2, '0')

function formatElapsed(ms: number): string {
  const s = Math.floor(ms / 1000)
  return `${pad(Math.floor(s / 60))}:${pad(s % 60)}`
}
