/**
 * 各ビュー(ホーム/履歴/愛犬/設定) + 測定フロー(測定中→解析中→結果)。
 * 表示するのは「意味」— ppm等の数値は履歴・詳細・測定中の補助情報のみ。
 */
import { useState } from 'react'
import { Chart } from './components/Chart'
import {
  CheckIcon,
  ChevronIcon,
  PawIcon,
} from './components/icons'
import type {
  ConnectionStatus,
  SensorSample,
  SessionSummary,
} from './providers/DataProvider'
import { FLAG_WARMUP } from './providers/DataProvider'
import {
  actionLabel,
  assess,
  levelColor,
  levelForPpm,
  levelPhrase,
  levelShort,
  relativeTime,
  trendLabel,
} from './lib/assessment'
import { ageLabel, type DogProfile } from './lib/dogProfile'

/* ================= ホーム ================= */

export function HomeView(props: {
  history: SessionSummary[]
  conn: ConnectionStatus
  busy: boolean
  onStart: () => void
  onOpenHistory: () => void
}) {
  const a = assess(props.history)
  const trend = trendLabel(a)
  return (
    <div className="stack view">
      {/* 状態 → 変化 → 取るべき行動 の順に、3秒で安心を伝える */}
      <section className="card hero">
        <div className="hero-status">
          <span className="live-dot" style={{ background: levelColor[a.level] }} />
          <span className="phrase">{levelPhrase[a.level]}</span>
        </div>
        {trend && <div className="trend-line-label">{trend}</div>}
        <p className="comment">{actionLabel(a)}</p>
        {a.latest && (
          <div className="last-measured">
            最終測定 · {relativeTime(a.latest.startedAt)}
          </div>
        )}
      </section>

      {props.history.length >= 2 && (
        <section className="card" onClick={props.onOpenHistory} role="button">
          <div className="card-head">
            <span className="label plain">最近の推移</span>
            <span className="aside">
              <ChevronIcon size={14} />
            </span>
          </div>
          <TrendLine history={props.history} />
        </section>
      )}

      <div className="controls">
        <button
          className="btn primary"
          onClick={props.onStart}
          disabled={props.busy || props.conn === 'connecting'}
        >
          {props.conn === 'connecting' ? '接続しています…' : '測定をはじめる'}
        </button>
      </div>

      {props.history.length > 0 && (
        <section className="card">
          <div className="card-head">
            <span className="label plain">最近の記録</span>
          </div>
          <div className="history-list">
            {props.history.slice(0, 3).map((h, i) => (
              <HistoryRow key={`${h.startedAt}-${i}`} s={h} />
            ))}
          </div>
        </section>
      )}
    </div>
  )
}

/* ================= 測定 (開始前) ================= */

export function MeasureStartView(props: {
  dogName: string
  conn: ConnectionStatus
  busy: boolean
  onStart: () => void
}) {
  const connected = props.conn === 'connected'
  return (
    <div className="stack view">
      <section className="card flow" style={{ padding: '48px 24px' }}>
        <div
          className="ring-outer idle"
          style={{
            borderColor: `color-mix(in srgb, ${connected ? 'var(--accent)' : 'var(--text-tertiary)'} 30%, transparent)`,
          }}
        >
          <div className="ring-inner">
            <span style={{ color: connected ? 'var(--accent)' : 'var(--text-tertiary)' }}>
              <PawIcon size={40} />
            </span>
          </div>
        </div>
        <h2 className="flow-title">{props.dogName}の呼気を測定</h2>
        <p className="comment center">
          {connected
            ? 'マスクを軽くあてて、測定をはじめてください'
            : '「はじめる」と同時にデバイスへ接続します'}
        </p>
        <div className="controls" style={{ width: '100%', maxWidth: 380 }}>
          <button
            className="btn primary"
            onClick={props.onStart}
            disabled={props.busy || props.conn === 'connecting'}
          >
            {props.conn === 'connecting' ? '接続しています…' : 'はじめる'}
          </button>
        </div>
      </section>
    </div>
  )
}

/* ================= 履歴 ================= */

export function HistoryView({ history }: { history: SessionSummary[] }) {
  return (
    <div className="stack view">
      {history.length === 0 ? (
        <section className="card">
          <div className="empty-note">まだ測定がありません</div>
        </section>
      ) : (
        <>
          <section className="card">
            <div className="card-head">
              <span className="label plain">最近の推移</span>
              <span className="aside">{history.length}件</span>
            </div>
            <TrendLine history={history} tall />
          </section>
          <section className="card">
            <div className="history-list">
              {history.map((h, i) => (
                <HistoryRow key={`${h.startedAt}-${i}`} s={h} detail />
              ))}
            </div>
          </section>
        </>
      )}
    </div>
  )
}

/* ================= 愛犬 ================= */

export function DogView(props: {
  profile: DogProfile
  historyCount: number
  onSave: (p: DogProfile) => void
}) {
  const [draft, setDraft] = useState(props.profile)
  const [saved, setSaved] = useState(false)
  const set = (k: keyof DogProfile) => (e: React.ChangeEvent<HTMLInputElement>) => {
    setSaved(false)
    setDraft({ ...draft, [k]: e.target.value })
  }
  return (
    <div className="stack view">
      <section className="card dog-hero">
        <div className="avatar big">
          <PawIcon size={40} />
        </div>
        <div className="dog-name">{draft.name || 'まだ名前がありません'}</div>
        <div className="dog-sub">
          {[draft.breed, ageLabel(draft), draft.weightKg && `${draft.weightKg}kg`]
            .filter(Boolean)
            .join(' · ')}
        </div>
        <div className="dog-count">これまでの記録 {props.historyCount}件</div>
      </section>

      <section className="card">
        <div className="card-head">
          <span className="label plain">プロフィール</span>
        </div>
        <div className="form">
          <label>
            <span>名前</span>
            <input value={draft.name} onChange={set('name')} />
          </label>
          <label>
            <span>犬種</span>
            <input value={draft.breed} onChange={set('breed')} />
          </label>
          <label>
            <span>体重 (kg)</span>
            <input value={draft.weightKg} onChange={set('weightKg')} inputMode="decimal" />
          </label>
          <label>
            <span>生まれた年</span>
            <input value={draft.birthYear} onChange={set('birthYear')} inputMode="numeric" />
          </label>
        </div>
        <div className="controls" style={{ marginTop: 18 }}>
          <button
            className="btn primary"
            onClick={() => {
              props.onSave(draft)
              setSaved(true)
            }}
          >
            {saved ? '保存しました' : '保存'}
          </button>
        </div>
      </section>
    </div>
  )
}

/* ================= 設定 ================= */

export function SettingsView(props: {
  conn: ConnectionStatus
  providerName: string
  latest: SensorSample | null
  busy: boolean
  onConnect: () => void
  onDisconnect: () => void
  onClearHistory: () => void
}) {
  const { conn, latest } = props
  return (
    <div className="stack view">
      <section className="card">
        <div className="card-head">
          <span className="label plain">測定デバイス</span>
        </div>
        <div className="kv">
          <div className="row">
            <span className="k">接続</span>
            <span className="v" style={conn === 'connected' ? { color: 'var(--success)' } : undefined}>
              {conn === 'connected' ? '接続中' : conn === 'connecting' ? '接続処理中…' : '未接続'}
            </span>
          </div>
          <div className="row">
            <span className="k">電池</span>
            <span className="v">{latest ? `${latest.battery}%` : '—'}</span>
          </div>
          <div className="row">
            <span className="k">温度 / 湿度</span>
            <span className="v">
              {latest
                ? `${latest.temperature.toFixed(1)}℃ / ${latest.humidity.toFixed(0)}%`
                : '—'}
            </span>
          </div>
          <div className="row">
            <span className="k">データソース</span>
            <span className="v">
              {props.providerName === 'Mock' ? 'デモ (実機なし)' : 'Bluetooth'}
            </span>
          </div>
        </div>
        <div className="controls" style={{ marginTop: 16 }}>
          {conn === 'connected' ? (
            <button className="btn ghost" onClick={props.onDisconnect} disabled={props.busy}>
              切断する
            </button>
          ) : (
            <button className="btn ghost" onClick={props.onConnect} disabled={props.busy}>
              接続する
            </button>
          )}
        </div>
      </section>

      <section className="card">
        <div className="card-head">
          <span className="label plain">データ</span>
        </div>
        <div className="kv">
          <div className="row">
            <span className="k">記録の削除</span>
            <button
              className="linklike danger"
              onClick={() => {
                if (confirm('すべての測定記録を削除しますか?')) props.onClearHistory()
              }}
            >
              すべて削除
            </button>
          </div>
        </div>
      </section>
    </div>
  )
}

/* ================= 測定フロー (フルスクリーン) ================= */

export type FlowPhase = 'measuring' | 'analyzing' | 'result'

export function MeasureFlow(props: {
  phase: FlowPhase
  samples: SensorSample[]
  dogName: string
  result: SessionSummary | null
  onFinish: () => void
  onDone: () => void
}) {
  const { phase, samples } = props
  const latest = samples.at(-1)
  const ppm = latest ? latest.hydrogen_ppb / 1000 : null
  const level = ppm === null ? 'none' : levelForPpm(ppm)
  const warmingUp = latest ? (latest.flags & FLAG_WARMUP) !== 0 : false
  const color = levelColor[level]

  if (phase === 'result' && props.result) {
    const r = props.result
    const rLevel = levelForPpm(r.avgPpb / 1000)
    return (
      <div className="overlay">
        <div className="flow view">
          <div
            className="result-badge"
            style={{ background: `color-mix(in srgb, ${levelColor[rLevel]} 12%, transparent)`, color: levelColor[rLevel] }}
          >
            <CheckIcon size={40} />
          </div>
          <h2 className="flow-title">測定できました</h2>
          <p className="comment center">{levelPhrase[rLevel]}</p>
          <div className="card stats-inline">
            <div className="stat">
              <div className="v">{Math.max(1, Math.round(r.durationS / 60))}分</div>
              <div className="k">測定時間</div>
            </div>
            <div className="sep" />
            <div className="stat">
              <div className="v">{(r.avgPpb / 1000).toFixed(1)}</div>
              <div className="k">平均 ppm</div>
            </div>
            <div className="sep" />
            <div className="stat">
              <div className="v">{(r.maxPpb / 1000).toFixed(1)}</div>
              <div className="k">最大 ppm</div>
            </div>
          </div>
          <div className="controls" style={{ width: '100%', maxWidth: 380 }}>
            <button className="btn primary" onClick={props.onDone}>
              ホームに戻る
            </button>
          </div>
        </div>
      </div>
    )
  }

  const analyzing = phase === 'analyzing'
  return (
    <div className="overlay">
      <div className="flow view">
        <div className="ring-outer" style={{ borderColor: `color-mix(in srgb, ${color} 30%, transparent)` }}>
          <div className="ring-inner">
            {analyzing ? (
              <span className="ring-analyzing">解析しています…</span>
            ) : (
              <>
                <span className="ring-word" style={{ color: ppm === null ? 'var(--text-tertiary)' : color }}>
                  {ppm === null ? '…' : levelShort[level]}
                </span>
                {ppm !== null && <span className="ring-ppm">{ppm.toFixed(1)} ppm</span>}
              </>
            )}
          </div>
        </div>
        <h2 className="flow-title">{props.dogName}</h2>
        <p className="comment center">
          {analyzing
            ? '今日のコンディションをまとめています'
            : warmingUp
              ? 'ウォームアップ中（参考値）'
              : 'そのまま、やさしく'}
        </p>

        <div className="flow-spark" style={{ opacity: analyzing ? 0 : 1 }}>
          {samples.length >= 2 && <Chart samples={samples} />}
        </div>

        <div className="controls" style={{ width: '100%', maxWidth: 380, opacity: analyzing ? 0 : 1 }}>
          <button className="btn stop" onClick={props.onFinish} disabled={analyzing}>
            終了する
          </button>
        </div>
      </div>
    </div>
  )
}

/* ================= 共有部品 ================= */

/**
 * 最近の推移 — 直感的に「上がった/下がった」が分かる1本の折れ線。
 * 軸・数値は出さない(意味はホーム、数値は履歴・詳細)。最新点だけを強調。
 */
export function TrendLine({
  history,
  tall = false,
}: {
  history: SessionSummary[]
  tall?: boolean
}) {
  const W = 640
  const H = tall ? 110 : 72
  const PAD = { x: 6, y: 10 }
  const items = history.slice(0, tall ? 14 : 7).reverse()
  const ppms = items.map((h) => h.avgPpb / 1000)
  if (ppms.length < 2) return null

  const min = Math.min(...ppms)
  const max = Math.max(...ppms)
  const span = Math.max(max - min, 1) // 変化が小さくても線が死なない程度に
  const x = (i: number) => PAD.x + (i / (ppms.length - 1)) * (W - PAD.x * 2)
  const y = (v: number) =>
    PAD.y + (1 - (v - min) / span) * (H - PAD.y * 2)

  let d = ''
  ppms.forEach((v, i) => {
    d += `${i === 0 ? 'M' : 'L'}${x(i).toFixed(1)},${y(v).toFixed(1)}`
  })
  const area = `${d}L${x(ppms.length - 1).toFixed(1)},${H}L${PAD.x},${H}Z`
  const lastLevel = levelForPpm(ppms[ppms.length - 1])
  const lastColor = levelColor[lastLevel]

  return (
    <svg
      className="trend-svg"
      viewBox={`0 0 ${W} ${H}`}
      preserveAspectRatio="none"
      style={{ height: H }}
      role="img"
      aria-label="最近の推移"
    >
      <path d={area} fill="var(--accent)" fillOpacity="0.06" />
      <path
        d={d}
        fill="none"
        stroke="var(--accent)"
        strokeWidth="2"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
      {/* 各測定点(控えめ) */}
      {ppms.slice(0, -1).map((v, i) => (
        <circle
          key={i}
          cx={x(i)}
          cy={y(v)}
          r="2.2"
          fill="var(--card)"
          stroke="var(--accent)"
          strokeWidth="1.4"
        />
      ))}
      {/* 最新点は状態色で強調 */}
      <circle
        cx={x(ppms.length - 1)}
        cy={y(ppms[ppms.length - 1])}
        r="7"
        fill={lastColor}
        fillOpacity="0.15"
      />
      <circle
        cx={x(ppms.length - 1)}
        cy={y(ppms[ppms.length - 1])}
        r="3.4"
        fill={lastColor}
        stroke="var(--card)"
        strokeWidth="1.5"
      />
    </svg>
  )
}

export function HistoryRow({
  s,
  detail = false,
}: {
  s: SessionSummary
  detail?: boolean
}) {
  const ppm = s.avgPpb / 1000
  const level = levelForPpm(ppm)
  const d = new Date(s.startedAt)
  const when = `${d.getMonth() + 1}/${d.getDate()} ${pad(d.getHours())}:${pad(d.getMinutes())}`
  return (
    <div className="history-item">
      <span className="level-dot" style={{ background: levelColor[level] }} />
      <span className="level-label">{levelShort[level]}</span>
      <span className="when">{when}</span>
      <span className="meta">
        {ppm.toFixed(1)} ppm
        {detail ? ` · ${Math.max(1, Math.round(s.durationS / 60))}分` : ''}
      </span>
    </div>
  )
}

const pad = (n: number) => String(n).padStart(2, '0')
