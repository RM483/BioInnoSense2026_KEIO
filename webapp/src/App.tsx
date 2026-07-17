/**
 * HydroPaw — 犬の健康を毎日そっと見守るプロダクトのWeb体験。
 *
 * 設計思想 (Apple Health / Fitness を参照):
 * - 主役は「今日は安定しています」という意味の言葉。ppmは補助情報。
 * - 単一カラム・十分な余白・静かなカード・控えめなアニメーション。
 * - 測定中だけライブビュー(状態の言葉 + 小さな数値 + 1本の線)に切り替わる。
 * - デバイス・温湿度などの技術情報は最下部の「詳細」に隔離する。
 * データは DataProvider (Mock/BLE) 経由 — 差し替えは providers/index.ts。
 */
import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { Chart } from './components/Chart'
import type {
  ConnectionStatus,
  SensorSample,
  SessionSummary,
} from './providers/DataProvider'
import { FLAG_WARMUP } from './providers/DataProvider'
import { createProvider } from './providers'
import {
  assess,
  assessmentComment,
  levelColor,
  levelForPpm,
  levelPhrase,
  levelShort,
  relativeTime,
} from './lib/assessment'

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

  const start = useCallback(async () => {
    setBusy(true)
    try {
      if (conn !== 'connected') await provider.connect()
      setSamples([])
      sessionStart.current = new Date()
      await provider.startMeasurement()
      setMeasuring(true)
    } catch (e) {
      console.error(e)
      alert((e as Error).message)
    } finally {
      setBusy(false)
    }
  }, [provider, conn])

  const stop = useCallback(async () => {
    setBusy(true)
    try {
      const summary =
        (await provider.stopMeasurement()) ??
        localSummary(samples, sessionStart.current)
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
  const livePpm = latest ? latest.hydrogen_ppb / 1000 : null
  const liveLevel = livePpm === null ? 'none' : levelForPpm(livePpm)
  const warmingUp = latest ? (latest.flags & FLAG_WARMUP) !== 0 : false
  const assessment = useMemo(() => assess(history), [history])
  const today = useMemo(
    () =>
      new Intl.DateTimeFormat('ja-JP', {
        month: 'long',
        day: 'numeric',
        weekday: 'short',
      }).format(new Date()),
    [],
  )

  return (
    <div className="app">
      {/* ---- ヘッダ: 日付 + 犬の名前 ---- */}
      <header className="header">
        <div className="titles">
          <div className="date">{today}</div>
          <h1>ポチ</h1>
        </div>
        <div className="pills">
          {provider.name === 'Mock' && <span className="pill accent">デモ</span>}
          <ConnectionPill conn={conn} />
        </div>
      </header>

      <div className="stack">
        {measuring ? (
          /* ============ 測定中ビュー ============ */
          <>
            <section className="card hero">
              <div className="card-head">
                <span className="label">測定中</span>
                <span className="aside">
                  {latest ? elapsedLabel(latest) : '00:00'}
                </span>
              </div>
              <div className="live">
                <span
                  className="live-dot"
                  style={{ background: levelColor[liveLevel] }}
                />
                <span className="phrase" style={{ color: levelColor[liveLevel] }}>
                  {livePpm === null ? '待機中…' : levelShort[liveLevel]}
                </span>
              </div>
              <div className="live-sub">
                {livePpm !== null && (
                  <span className="value-sub">{livePpm.toFixed(1)} ppm</span>
                )}
                {warmingUp && (
                  <span className="pill warn">ウォームアップ中（参考値）</span>
                )}
              </div>
            </section>

            <section className="card chart-card">
              <div className="card-head">
                <span className="label plain">セッション推移</span>
              </div>
              <Chart samples={samples} />
            </section>

            <div className="controls">
              <button className="btn stop" onClick={stop} disabled={busy}>
                終了する
              </button>
            </div>
          </>
        ) : (
          /* ============ ホームビュー ============ */
          <>
            <section className="card hero">
              <div className="hero-status">
                <span
                  className="live-dot"
                  style={{ background: levelColor[assessment.level] }}
                />
                <span className="phrase">{levelPhrase[assessment.level]}</span>
              </div>
              <p className="comment">{assessmentComment(assessment)}</p>
              {assessment.latest && (
                <div className="last-measured">
                  最終測定 · {relativeTime(assessment.latest.startedAt)}
                </div>
              )}
            </section>

            {history.length >= 2 && (
              <section className="card">
                <div className="card-head">
                  <span className="label plain">最近の推移</span>
                </div>
                <TrendBars history={history} />
              </section>
            )}

            <div className="controls">
              <button
                className="btn primary"
                onClick={start}
                disabled={busy || conn === 'connecting'}
              >
                {conn === 'connecting' ? '接続しています…' : '測定をはじめる'}
              </button>
            </div>

            {history.length > 0 && (
              <section className="card">
                <div className="card-head">
                  <span className="label plain">履歴</span>
                  <span className="aside">{history.length}件</span>
                </div>
                <div className="history-list">
                  {history.slice(0, 8).map((h, i) => (
                    <HistoryRow key={`${h.startedAt}-${i}`} s={h} />
                  ))}
                </div>
              </section>
            )}

            {/* ---- 技術情報はいちばん下に隔離 ---- */}
            <section className="card details">
              <div className="card-head">
                <span className="label plain">詳細</span>
              </div>
              <div className="kv">
                <div className="row">
                  <span className="k">接続</span>
                  <span className="v">{connLabel(conn)}</span>
                </div>
                {conn !== 'connected' && (
                  <div className="row">
                    <span className="k"></span>
                    <button className="linklike" onClick={connect} disabled={busy}>
                      デバイスに接続する
                    </button>
                  </div>
                )}
                <div className="row">
                  <span className="k">温度</span>
                  <span className="v">
                    {latest ? `${latest.temperature.toFixed(1)}℃` : '—'}
                  </span>
                </div>
                <div className="row">
                  <span className="k">湿度</span>
                  <span className="v">
                    {latest ? `${latest.humidity.toFixed(0)}%` : '—'}
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
          </>
        )}
      </div>
    </div>
  )
}

/* ---------- 部品 ---------- */

function ConnectionPill({ conn }: { conn: ConnectionStatus }) {
  const cls =
    conn === 'connected' ? 'ok' : conn === 'connecting' ? 'warn' : 'muted'
  return (
    <span className={`pill ${cls}`}>
      <span className="dot" />
      {connLabel(conn)}
    </span>
  )
}

function connLabel(conn: ConnectionStatus): string {
  return conn === 'connected'
    ? '接続中'
    : conn === 'connecting'
      ? '接続処理中…'
      : '未接続'
}

/** 数値を出さない最近の推移(色 = その日の状態) */
function TrendBars({ history }: { history: SessionSummary[] }) {
  const items = history.slice(0, 7).reverse()
  const maxPpm = Math.max(10, ...items.map((h) => h.avgPpb / 1000))
  return (
    <div className="trend-bars">
      {items.map((h, i) => {
        const ppm = h.avgPpb / 1000
        return (
          <div className="trend-slot" key={`${h.startedAt}-${i}`}>
            <div
              className="trend-bar"
              style={{
                height: `${Math.max(12, (ppm / maxPpm) * 100)}%`,
                background: levelColor[levelForPpm(ppm)],
              }}
            />
          </div>
        )
      })}
    </div>
  )
}

function HistoryRow({ s }: { s: SessionSummary }) {
  const ppm = s.avgPpb / 1000
  const level = levelForPpm(ppm)
  const d = new Date(s.startedAt)
  const when = `${d.getMonth() + 1}/${d.getDate()} ${pad(d.getHours())}:${pad(d.getMinutes())}`
  return (
    <div className="history-item">
      <span className="level-dot" style={{ background: levelColor[level] }} />
      <span className="level-label">{levelShort[level]}</span>
      <span className="when">{when}</span>
      <span className="meta">{ppm.toFixed(1)} ppm</span>
    </div>
  )
}

/* ---------- ヘルパ ---------- */

function elapsedLabel(latest: SensorSample): string {
  // MockはEVT_DATA相当のtimestampを持つ; セッション経過はサンプル数から近似しない
  return new Intl.DateTimeFormat('ja-JP', {
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
  }).format(new Date(latest.timestamp))
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
    avgPpb: ppbs.length
      ? Math.round(ppbs.reduce((a, b) => a + b, 0) / ppbs.length)
      : 0,
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

const pad = (n: number) => String(n).padStart(2, '0')
