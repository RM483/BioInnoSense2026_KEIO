/**
 * 各ビュー(ホーム/履歴/愛犬/設定) + 測定フロー(測定中→解析中→結果)。
 * 表示するのは「意味」— ppm等の数値は履歴・詳細・測定中の補助情報のみ。
 */
import { useState } from 'react'
import { Chart } from './components/Chart'
import {
  CheckIcon,
  CheckSmallIcon,
  ExclamationIcon,
  PawIcon,
} from './components/icons'
import type {
  ConnectionStatus,
  SensorSample,
  SessionSummary,
} from './providers/DataProvider'
import { FLAG_WARMUP, H2_HIGH_PPM } from './providers/DataProvider'
import {
  STABLE_MAX_PPM,
  actionLabel,
  assess,
  levelColor,
  levelForPpm,
  levelPhrase,
  levelShort,
  relativeTime,
  trendLabel,
  windowSummary,
  type HealthLevel,
} from './lib/assessment'
import { ageLabel, type DogProfile } from './lib/dogProfile'

/* ================= ホーム ================= */

export function HomeView(props: {
  history: SessionSummary[]
  dogName: string
  conn: ConnectionStatus
  busy: boolean
  onStart: () => void
  onOpenHistory: () => void
}) {
  const a = assess(props.history)
  const trend = trendLabel(a)
  const color = levelColor[a.level === 'none' ? 'none' : a.level]
  return (
    <div className="stack view home-canvas">
      {/* ---- 挨拶 (話しかける入口) ---- */}
      <div className="greeting">{greeting()} · {todayLabel()}</div>

      {/* ---- 見守りリング (主役 / docs/16 案B) ---- */}
      <button
        className="care-ring"
        style={{ background: `color-mix(in srgb, ${color} 7%, transparent)` }}
        onClick={props.onStart}
        aria-label="測定をはじめる"
      >
        <span
          className="care-ring-rim"
          style={{ borderColor: `color-mix(in srgb, ${color} 55%, transparent)` }}
        >
          <span className="care-ring-face">
            <PawIcon size={62} />
          </span>
        </span>
      </button>

      {/* ---- 言葉: 名前 → 状態 → 変化 → 行動 → 最終測定 ---- */}
      <div className="home-words">
        <div className="dog-label">{props.dogName}</div>
        <h2 className="phrase">{levelPhrase[a.level]}</h2>
        {trend && <div className="trend-line-label center">{trend}</div>}
        <p className="action">{actionLabel(a)}</p>
        {a.latest && (
          <div className="last-measured center">
            最終測定 · {relativeTime(a.latest.startedAt)}
          </div>
        )}
      </div>

      {/* ---- ここ7日のようす (平置き・カードにしない) ---- */}
      {props.history.length >= 2 && (
        <section className="trend-flat" onClick={props.onOpenHistory} role="button">
          <div className="card-head">
            <span className="label plain">ここ7日のようす</span>
            <StatusChip level={a.level} />
          </div>
          <TrendLine history={props.history} />
          <p className="trend-summary">{windowSummary(props.history)}</p>
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
    </div>
  )
}

function greeting(): string {
  const h = new Date().getHours()
  if (h < 11) return 'おはようございます'
  if (h < 18) return 'こんにちは'
  return 'こんばんは'
}

function todayLabel(): string {
  return new Intl.DateTimeFormat('ja-JP', {
    month: 'long',
    day: 'numeric',
    weekday: 'short',
  }).format(new Date())
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
              <span className="label plain">最近の健康状態</span>
              <span className="aside">{history.length}件</span>
            </div>
            <TrendLine history={history} tall />
            <p className="trend-summary">{windowSummary(history, 14)}</p>
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
          {r.quality !== undefined && <QualityBadge quality={r.quality} />}
          {(r.qualityFlags ?? 0) & 0x01 ? (
            <p className="comment center" style={{ fontSize: 13 }}>
              もういちど測ると、より確かな記録になります
            </p>
          ) : null}
          {r.confidence !== undefined && r.confidence < 70 ? (
            <p className="comment center" style={{ fontSize: 13, color: 'var(--warn)' }}>
              センサーの調子がいつもと違うようです。数値は参考としてご覧ください
            </p>
          ) : null}
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

/** 測定の質を言葉で伝えるバッジ (Q≥80 高い / 60-79 ふつう / <60 低い)。
 *  数値のQ/Cは出さない — 意味だけを渡す (docs/17 / docs/18 §S6)。 */
function QualityBadge({ quality }: { quality: number }) {
  const [label, color] =
    quality >= 80
      ? ['高い', 'var(--success)']
      : quality >= 60
        ? ['ふつう', 'var(--accent)']
        : ['低い', 'var(--warn)']
  return (
    <span
      style={{
        display: 'inline-block',
        padding: '6px 14px',
        borderRadius: 999,
        fontSize: 12.5,
        fontWeight: 600,
        color,
        background: `color-mix(in srgb, ${color} 12%, transparent)`,
      }}
    >
      測定の質 · {label}
    </span>
  )
}

/**
 * 健康状態の変化 — 「良くなった/変わらない/悪くなった」が一目で分かる折れ線。
 *
 * 意味が読めるように:
 * - 縦軸は絶対スケール(0基準)。線の高さ自体が状態を表す
 * - 正常範囲(安定ゾーン)を薄い緑の帯で敷く。上に「注意」「受診推奨」ゾーン
 * - 右端にゾーン名の補助ラベル
 * - 強調するのは現在(最新)の1点だけ — 状態色 + ハロー
 * 数値・軸ラベルは出さない(数値の居場所は履歴・詳細)。
 */
export function TrendLine({
  history,
  tall = false,
}: {
  history: SessionSummary[]
  tall?: boolean
}) {
  const W = 640
  const H = tall ? 132 : 96
  // ラベルは帯の内側(左)に置く。右は最新点のハロー(8px)ぶんを確保 (docs/16 R7/R13)
  const PAD = { left: 6, right: 16, top: 8, bottom: 8 }
  const items = history.slice(0, tall ? 14 : 7).reverse()
  const ppms = items.map((h) => h.avgPpb / 1000)
  if (ppms.length < 2) return null

  // 絶対スケール(0基準)。全点が正常範囲なら帯が主役になる高さに、
  // 高い日があるときだけ上方向へ広がる。
  const dataMax = Math.max(...ppms)
  const maxY = Math.max(STABLE_MAX_PPM * 1.35, dataMax * 1.2)
  const x = (i: number) =>
    PAD.left + (i / (ppms.length - 1)) * (W - PAD.left - PAD.right)
  const y = (v: number) =>
    PAD.top + (1 - v / maxY) * (H - PAD.top - PAD.bottom)

  let d = ''
  ppms.forEach((v, i) => {
    d += `${i === 0 ? 'M' : 'L'}${x(i).toFixed(1)},${y(v).toFixed(1)}`
  })
  const lastLevel = levelForPpm(ppms[ppms.length - 1])
  const lastColor = levelColor[lastLevel]
  const plotRight = W - PAD.right

  const yStable = y(STABLE_MAX_PPM)
  const yBottom = H - PAD.bottom
  // 受診の目安(20ppm)ラインは、データが近づいた時だけ静かに現れる
  const showGuide = dataMax >= STABLE_MAX_PPM * 1.2
  const yGuide = y(H2_HIGH_PPM)

  return (
    <div className="trend-wrap" style={{ height: H }}>
      <svg
        className="trend-svg"
        viewBox={`0 0 ${W} ${H}`}
        preserveAspectRatio="none"
        role="img"
        aria-label="最近の健康状態"
      >
        {/* ---- 正常範囲: ごく薄い緑の帯(これ以外の帯は敷かない) ---- */}
        <rect
          x={PAD.left}
          y={yStable}
          width={plotRight - PAD.left}
          height={Math.max(0, yBottom - yStable)}
          fill="var(--success)"
          fillOpacity="0.07"
          rx="6"
        />
        <line
          x1={PAD.left}
          x2={plotRight}
          y1={yStable}
          y2={yStable}
          stroke="var(--success)"
          strokeOpacity="0.25"
          strokeWidth="1"
        />

        {/* ---- 受診の目安(必要なときだけ) ---- */}
        {showGuide && yGuide > PAD.top && (
          <line
            x1={PAD.left}
            x2={plotRight}
            y1={yGuide}
            y2={yGuide}
            stroke="var(--danger)"
            strokeOpacity="0.35"
            strokeWidth="1"
            strokeDasharray="5 5"
          />
        )}

        {/* ---- 推移線(中立色 — 色の意味は点にだけ持たせる) ---- */}
        <path
          d={d}
          fill="none"
          stroke="var(--text-secondary)"
          strokeOpacity="0.65"
          strokeWidth="2"
          strokeLinecap="round"
          strokeLinejoin="round"
        />
        {ppms.slice(0, -1).map((v, i) => (
          <circle
            key={i}
            cx={x(i)}
            cy={y(v)}
            r="2.2"
            fill="var(--card)"
            stroke="var(--text-secondary)"
            strokeOpacity="0.65"
            strokeWidth="1.4"
          />
        ))}

        {/* ---- 現在(最新)だけを状態色で強調 ---- */}
        <circle
          cx={x(ppms.length - 1)}
          cy={y(ppms[ppms.length - 1])}
          r="8"
          fill={lastColor}
          fillOpacity="0.18"
        />
        <circle
          cx={x(ppms.length - 1)}
          cy={y(ppms[ppms.length - 1])}
          r="3.8"
          fill={lastColor}
          stroke="var(--card)"
          strokeWidth="1.5"
        />
      </svg>

      {/* ---- ラベル(HTMLオーバーレイ: 帯の内側左に置き点と衝突しない) ---- */}
      <span
        className="band-label"
        style={{
          bottom: 6,
          color: 'var(--success)',
        }}
      >
        正常範囲
      </span>
      {showGuide && yGuide > PAD.top + 8 && (
        <span
          className="band-label"
          style={{ top: `${(yGuide / H) * 100}%`, color: 'var(--danger)' }}
        >
          受診の目安
        </span>
      )}
    </div>
  )
}

/** 状態チップ — 色 + 記号 + 語 の三重で伝える(色覚に依存しない) */
export function StatusChip({ level }: { level: HealthLevel }) {
  if (level === 'none') return null
  const color = levelColor[level]
  return (
    <span
      className="chip"
      style={{
        color,
        background: `color-mix(in srgb, ${color} 10%, transparent)`,
      }}
    >
      {level === 'stable' ? (
        <CheckSmallIcon size={11} />
      ) : (
        <ExclamationIcon size={11} />
      )}
      {levelShort[level]}
    </span>
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
