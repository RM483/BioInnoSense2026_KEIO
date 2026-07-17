/**
 * HydroPaw — 犬の健康を毎日そっと見守るプロダクト (SPA)。
 *
 * 構成: 4タブ(ホーム/履歴/愛犬/設定) + 測定はホームCTAから始まる
 * フルスクリーンの「イベント」(測定中→解析中→結果)。
 * ナビはモバイルで下部タブバー、iPad/Macでは上部セグメント。
 * データはDataProvider(Mock/BLE)経由 — 切替は providers/index.ts の1箇所。
 */
import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import {
  ChartIcon,
  GearIcon,
  HeartIcon,
  HouseIcon,
  PawIcon,
  WaveIcon,
} from './components/icons'
import type {
  ConnectionStatus,
  SensorSample,
  SessionSummary,
} from './providers/DataProvider'
import { createProvider } from './providers'
import { loadProfile, saveProfile, type DogProfile } from './lib/dogProfile'
import {
  DogView,
  HistoryView,
  HomeView,
  MeasureFlow,
  MeasureStartView,
  SettingsView,
  type FlowPhase,
} from './views'

const MAX_SAMPLES = 1800
const HISTORY_KEY = 'hydropaw.history.v1'
const MIN_ANALYZING_MS = 1400

type Tab = 'home' | 'measure' | 'history' | 'dog' | 'settings'

const TABS: { id: Tab; label: string; icon: (p: { size?: number }) => JSX.Element }[] = [
  { id: 'home', label: 'ホーム', icon: HouseIcon },
  { id: 'measure', label: '測定', icon: WaveIcon },
  { id: 'history', label: '履歴', icon: ChartIcon },
  { id: 'dog', label: '愛犬', icon: HeartIcon },
  { id: 'settings', label: '設定', icon: GearIcon },
]

function tabFromHash(): Tab {
  const h = location.hash.replace('#/', '')
  return (['home', 'measure', 'history', 'dog', 'settings'] as Tab[]).includes(
    h as Tab,
  )
    ? (h as Tab)
    : 'home'
}

export default function App() {
  const provider = useMemo(createProvider, [])
  const [tab, setTab] = useState<Tab>(tabFromHash)
  const [conn, setConn] = useState<ConnectionStatus>('disconnected')
  const [flow, setFlow] = useState<FlowPhase | null>(null)
  const [samples, setSamples] = useState<SensorSample[]>([])
  const [history, setHistory] = useState<SessionSummary[]>(loadHistory)
  const [result, setResult] = useState<SessionSummary | null>(null)
  const [profile, setProfile] = useState<DogProfile>(loadProfile)
  const [busy, setBusy] = useState(false)
  const sessionStart = useRef<Date | null>(null)
  const latest = samples.at(-1) ?? null

  // ---- SPAルーティング (hash) ----
  useEffect(() => {
    const onHash = () => setTab(tabFromHash())
    window.addEventListener('hashchange', onHash)
    return () => window.removeEventListener('hashchange', onHash)
  }, [])

  const go = useCallback((t: Tab) => {
    location.hash = `#/${t}`
    setTab(t)
    window.scrollTo({ top: 0 })
  }, [])

  // ---- Provider購読 ----
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

  // ---- 測定フロー ----
  const startMeasurement = useCallback(async () => {
    setBusy(true)
    try {
      if (conn !== 'connected') await provider.connect()
      setSamples([])
      sessionStart.current = new Date()
      await provider.startMeasurement()
      setFlow('measuring')
    } catch (e) {
      console.error(e)
      alert((e as Error).message)
    } finally {
      setBusy(false)
    }
  }, [provider, conn])

  const finishMeasurement = useCallback(async () => {
    setFlow('analyzing')
    const t0 = Date.now()
    const summary =
      (await provider.stopMeasurement()) ??
      localSummary(samples, sessionStart.current)
    if (summary && summary.sampleCount > 0) {
      setHistory((prev) => {
        const next = [summary, ...prev].slice(0, 100)
        localStorage.setItem(HISTORY_KEY, JSON.stringify(next))
        return next
      })
      setResult(summary)
    }
    // 「解析しています…」の間を最低確保(儀式としての測定体験)
    const wait = Math.max(0, MIN_ANALYZING_MS - (Date.now() - t0))
    setTimeout(() => setFlow(summary ? 'result' : null), wait)
  }, [provider, samples])

  const closeFlow = useCallback(() => {
    setFlow(null)
    setResult(null)
    go('home')
  }, [go])

  const connect = useCallback(async () => {
    setBusy(true)
    try {
      await provider.connect()
    } catch (e) {
      alert((e as Error).message)
    } finally {
      setBusy(false)
    }
  }, [provider])

  const disconnect = useCallback(async () => {
    setBusy(true)
    try {
      await provider.disconnect()
    } finally {
      setBusy(false)
    }
  }, [provider])

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
      {/* ---- ヘッダ ---- */}
      <header className="header">
        <div className="brand-avatar">
          <PawIcon size={22} />
        </div>
        <div className="titles">
          <div className="date">{today}</div>
          <h1>{profile.name}</h1>
        </div>
        <nav className="tabbar top" aria-label="ナビゲーション">
          {TABS.map(({ id, label, icon: Icon }) => (
            <button
              key={id}
              className={`tab ${tab === id ? 'active' : ''}`}
              onClick={() => go(id)}
            >
              <Icon size={20} />
              <span>{label}</span>
            </button>
          ))}
        </nav>
      </header>

      {/* ---- ビュー ---- */}
      {tab === 'home' && (
        <HomeView
          history={history}
          conn={conn}
          busy={busy}
          onStart={startMeasurement}
          onOpenHistory={() => go('history')}
        />
      )}
      {tab === 'measure' && (
        <MeasureStartView
          dogName={profile.name}
          conn={conn}
          busy={busy}
          onStart={startMeasurement}
        />
      )}
      {tab === 'history' && <HistoryView history={history} />}
      {tab === 'dog' && (
        <DogView
          profile={profile}
          historyCount={history.length}
          onSave={(p) => {
            saveProfile(p)
            setProfile(p)
          }}
        />
      )}
      {tab === 'settings' && (
        <SettingsView
          conn={conn}
          providerName={provider.name}
          latest={latest}
          busy={busy}
          onConnect={connect}
          onDisconnect={disconnect}
          onClearHistory={() => {
            localStorage.removeItem(HISTORY_KEY)
            setHistory([])
          }}
        />
      )}

      {/* ---- 下部タブバー (モバイル) ---- */}
      <nav className="tabbar bottom" aria-label="ナビゲーション">
        {TABS.map(({ id, label, icon: Icon }) => (
          <button
            key={id}
            className={`tab ${tab === id ? 'active' : ''}`}
            onClick={() => go(id)}
          >
            <Icon size={22} />
            <span>{label}</span>
          </button>
        ))}
      </nav>

      {/* ---- 測定フロー (フルスクリーンイベント) ---- */}
      {flow && (
        <MeasureFlow
          phase={flow}
          samples={samples}
          dogName={profile.name}
          result={result}
          onFinish={finishMeasurement}
          onDone={closeFlow}
        />
      )}
    </div>
  )
}

/* ---------- ヘルパ ---------- */

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
