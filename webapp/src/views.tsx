/**
 * ホーム / 設定 + 測定フロー(測定中→解析中→結果) + 共有部品 (IA v2 — docs/21)。
 * ホーム=測定の入口。日誌は journal.tsx、犬管理は dogsView.tsx に住む。
 * 表示するのは「意味」— ppm等の数値は日誌・詳細・測定中の補助情報のみ。
 */
import { useEffect, useRef } from 'react'
import { Chart } from './components/Chart'
import {
  BookIcon,
  CheckIcon,
  CheckSmallIcon,
  ExclamationIcon,
  PawIcon,
  PenIcon,
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
import type { Dog } from './lib/dogs'
import {
  type CareNote,
  noteTypeLabel,
  ratingLabel,
} from './lib/careNotes'

/* ================= ホーム ================= */

/**
 * ホーム = 測定の入口 + 見守り中の犬の切り替え (docs/21 v2.2 §1,2)。
 * - 犬ごとのホームを「1枚のページ」として横スクロール(scroll-snap)。
 *   指に追従してページ全体(リング/名前/状態/7日/CTA/副導線)がスライドし、
 *   ページ単位で自然に停止する。挨拶・日付・ナビは固定。
 * - 主CTAは大きな「◯◯の測定をはじめる」1つ。副導線はその下の段 (§1)
 * - 見守り中が0頭なら空状態を表示する (§8)
 */
export function HomeView(props: {
  dogs: Dog[] // 見守り中の犬のみ
  index: number
  historyFor: (dogId: string) => SessionSummary[]
  notesFor: (dogId: string) => CareNote[] // きょうの日誌 (ケアタスク用)
  conn: ConnectionStatus
  busy: boolean
  onIndex: (i: number) => void
  onStart: (dog: Dog) => void
  onOpenHistory: () => void
  onAddNote: () => void
  onQuickNote: (type: CareNote['type']) => void
  onRegisterDog: () => void
}) {
  const railRef = useRef<HTMLDivElement>(null)
  const settleTimer = useRef<number | undefined>(undefined)

  // 初期表示・外部からの切替時: 選択中のページへスクロールを合わせる
  useEffect(() => {
    const rail = railRef.current
    if (!rail) return
    const target = props.index * rail.clientWidth
    if (Math.abs(rail.scrollLeft - target) > rail.clientWidth / 2) {
      if (typeof rail.scrollTo === 'function') {
        rail.scrollTo({ left: target })
      }
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [props.index, props.dogs.length])

  // ---- 空状態: 見守り中の犬がいない (§8) ----
  if (props.dogs.length === 0) {
    return (
      <div className="stack view home-canvas">
        <div className="greeting">{greeting()} · {todayLabel()}</div>
        <button className="care-ring" onClick={props.onRegisterDog}
          aria-label="愛犬を登録する"
          style={{ background: 'color-mix(in srgb, var(--accent) 7%, transparent)' }}>
          <span className="care-ring-rim"
            style={{ borderColor: 'color-mix(in srgb, var(--accent) 55%, transparent)' }}>
            <span className="care-ring-face"><PawIcon size={62} /></span>
          </span>
        </button>
        <div className="home-words">
          <h2 className="phrase">現在見守っている犬はいません</h2>
          <p className="action">愛犬を登録すると、健康状態や測定結果を記録できます。</p>
        </div>
        <div className="controls home-cta">
          <button className="btn primary" onClick={props.onRegisterDog}>
            愛犬を登録する
          </button>
        </div>
      </div>
    )
  }

  // スクロール停止位置からページを確定し、見守る犬を切り替える
  const onScroll = () => {
    const rail = railRef.current
    if (!rail || rail.clientWidth === 0) return
    window.clearTimeout(settleTimer.current)
    settleTimer.current = window.setTimeout(() => {
      const i = Math.round(rail.scrollLeft / rail.clientWidth)
      if (i !== props.index && i >= 0 && i < props.dogs.length) {
        props.onIndex(i)
      }
    }, 90)
  }

  return (
    <div className="view home-canvas full">
      {/* ---- Apple Health流の大見出し: 小さな挨拶 + 太い日付 ---- */}
      <div className="home-head">
        <div className="home-head-kicker">{greeting()}</div>
        <h1 className="home-head-title">{todayLabel()}</h1>
      </div>

      {/* ---- 犬ごとのページ(全体がスライド §2) ---- */}
      <div className="home-rail" ref={railRef} onScroll={onScroll}>
        {props.dogs.map((dog, i) => (
          <DogHomePage
            key={dog.id}
            dog={dog}
            history={props.historyFor(dog.id)}
            todayNotes={props.notesFor(dog.id)}
            pageIndex={i}
            pageCount={props.dogs.length}
            conn={props.conn}
            busy={props.busy}
            onStart={() => props.onStart(dog)}
            onOpenHistory={props.onOpenHistory}
            onAddNote={props.onAddNote}
            onQuickNote={props.onQuickNote}
          />
        ))}
      </div>
    </div>
  )
}

/** 犬1頭ぶんのホームページ(リング〜副導線までがひとまとまり) */
function DogHomePage(props: {
  dog: Dog
  history: SessionSummary[]
  todayNotes: CareNote[]
  pageIndex: number
  pageCount: number
  conn: ConnectionStatus
  busy: boolean
  onStart: () => void
  onOpenHistory: () => void
  onAddNote: () => void
  onQuickNote: (type: CareNote['type']) => void
}) {
  const { dog, history } = props
  const a = assess(history)
  const trend = trendLabel(a)
  const color = levelColor[a.level === 'none' ? 'none' : a.level]

  return (
    <div className="home-page stack">
      {/* ---- ヒーローカード: リング(左) × 状態の言葉(右) — CareKit様式 ---- */}
      <section className="hero-card">
        <button
          className="care-ring hero-ring"
          style={{ background: `color-mix(in srgb, ${color} 8%, transparent)` }}
          onClick={props.onStart}
          aria-label={`${dog.name}の測定をはじめる`}
        >
          <span
            className="care-ring-rim"
            style={{ borderColor: `color-mix(in srgb, ${color} 55%, transparent)` }}
          >
            <span className="care-ring-face">
              {dog.photo ? (
                <img src={dog.photo} alt="" className="dog-photo" />
              ) : (
                <PawIcon size={44} />
              )}
            </span>
          </span>
        </button>
        <div className="hero-words">
          <div className="dog-label">{dog.name}</div>
          <h2 className="phrase">{levelPhrase[a.level]}</h2>
          {trend && <div className="hero-trend">{trend}</div>}
          <p className="action">{actionLabel(a)}</p>
          {a.latest && (
            <div className="last-measured">
              最終測定 · {relativeTime(a.latest.startedAt)}
            </div>
          )}
        </div>
      </section>

      {props.pageCount > 1 && (
        <div className="dog-pager center"
          aria-label={`${props.pageIndex + 1} / ${props.pageCount}頭目`}>
          <span className="dots">
            {Array.from({ length: props.pageCount }).map((_, i) => (
              <span key={i}
                className={`dot ${i === props.pageIndex ? 'on' : ''}`} />
            ))}
          </span>
          <span className="pager-count">
            {props.pageIndex + 1} / {props.pageCount}
          </span>
        </div>
      )}

      {/* ---- ここ7日のようす — CareKitチャートカード ---- */}
      {history.length >= 2 && (
        <section className="card trend-card" onClick={props.onOpenHistory} role="button">
          <div className="card-head">
            <span className="label plain">ここ7日のようす</span>
            <StatusChip level={a.level} />
          </div>
          <TrendLine history={history} />
          <p className="trend-summary">{windowSummary(history)}</p>
        </section>
      )}

      {/* ---- きょうのケア: Task→Outcome を1日の単位で可視化 ----
       * CareKitのデイリータスクカード様式 (docs/22 §2)。
       * 完了サークルが「済んだ/まだ」を色に頼らず伝える。 */}
      <CareTasks
        history={history}
        todayNotes={props.todayNotes}
        onStart={props.onStart}
        onOpenHistory={props.onOpenHistory}
        onQuickNote={props.onQuickNote}
      />

      {/* ---- 1段目: 大きな主CTA (§1) / 2段目: 副導線 ---- */}
      <div className="controls home-cta">
        <button
          className="btn primary main-cta"
          onClick={props.onStart}
          disabled={props.busy || props.conn === 'connecting'}
        >
          {props.conn === 'connecting'
            ? '接続しています…'
            : `${dog.name}の測定をはじめる`}
        </button>
        <div className="quiet-links">
          <button className="quiet-link" onClick={props.onOpenHistory}>
            <BookIcon size={17} />
            履歴を見る
          </button>
          <span className="quiet-sep" />
          <button className="quiet-link" onClick={props.onAddNote}>
            <PenIcon size={17} />
            きょうの記録
          </button>
        </div>
      </div>
    </div>
  )
}

/** きょうのケア — CareKit流デイリータスク (docs/22 §2)。
 *  Task(やること) と Outcome(今日の結果) を分離して考え、
 *  Outcomeの有無を完了サークルで示す。未完了もタップ1回で記録へ。 */
function CareTasks(props: {
  history: SessionSummary[]
  todayNotes: CareNote[]
  onStart: () => void
  onOpenHistory: () => void
  onQuickNote: (type: CareNote['type']) => void
}) {
  const measuredToday = props.history.some((h) =>
    isToday(new Date(h.startedAt)),
  )
  const lastToday = props.history.find((h) => isToday(new Date(h.startedAt)))
  const noteOf = (t: CareNote['type']) =>
    props.todayNotes.find((n) => n.type === t)

  const rows: {
    key: string
    label: string
    detail: string
    done: boolean
    onTap: () => void
  }[] = [
    {
      key: 'measure',
      label: '呼気の測定',
      detail: measuredToday
        ? `済み · ${timeOf(lastToday!.startedAt)}`
        : '1日1回 · 3分ほど',
      done: measuredToday,
      onTap: measuredToday ? props.onOpenHistory : props.onStart,
    },
    ...(['walk', 'appetite', 'medicine'] as const).map((t) => {
      const n = noteOf(t)
      return {
        key: t,
        label: noteTypeLabel(t),
        detail: n
          ? `済み · ${timeOf(n.at)}${n.rating ? ` · ${ratingLabel(n.rating)}` : ''}`
          : 'タップで記録',
        done: !!n,
        onTap: () => props.onQuickNote(t),
      }
    }),
  ]

  return (
    <section className="care-tasks">
      <div className="card-head">
        <span className="label plain">きょうのケア</span>
        <span className="aside">
          {rows.filter((r) => r.done).length} / {rows.length}
        </span>
      </div>
      <div className="task-list">
        {rows.map((r) => (
          <button
            key={r.key}
            className={`task-row ${r.done ? 'done' : ''}`}
            onClick={r.onTap}
            aria-label={`${r.label} — ${r.detail}`}
          >
            <span className="task-check" aria-hidden="true">
              {r.done && <CheckIcon size={15} />}
            </span>
            <span className="task-texts">
              <span className="task-label">{r.label}</span>
              <span className="task-detail">{r.detail}</span>
            </span>
          </button>
        ))}
      </div>
    </section>
  )
}

const isToday = (d: Date): boolean => {
  const now = new Date()
  return (
    d.getFullYear() === now.getFullYear() &&
    d.getMonth() === now.getMonth() &&
    d.getDate() === now.getDate()
  )
}

const timeOf = (iso: string): string =>
  new Intl.DateTimeFormat('ja-JP', { hour: '2-digit', minute: '2-digit' })
    .format(new Date(iso))

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

/* ================= 設定 ================= */

export function SettingsView(props: {
  conn: ConnectionStatus
  providerName: string
  latest: SensorSample | null
  busy: boolean
  maxDogs: number
  watchingCount: number
  onChangeMaxDogs: (n: number) => void // 減数時の選択フローはApp側
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

      {/* ---- 愛犬の登録設定 (デバイスとデータの間 §10) ---- */}
      <section className="card" id="dog-settings">
        <div className="card-head">
          <span className="label plain">愛犬の登録設定</span>
        </div>
        <div className="kv">
          <div className="row">
            <span className="k">見守る愛犬</span>
            <span className="v stepper">
              <button
                className="icon-btn"
                aria-label="減らす"
                disabled={props.maxDogs <= 1}
                onClick={() => props.onChangeMaxDogs(props.maxDogs - 1)}
              >
                −
              </button>
              <span className="stepper-value">{props.maxDogs}頭</span>
              <button
                className="icon-btn"
                aria-label="増やす"
                disabled={props.maxDogs >= 9}
                onClick={() => props.onChangeMaxDogs(props.maxDogs + 1)}
              >
                ＋
              </button>
            </span>
          </div>
          <div className="row">
            <span className="k">現在見守り中</span>
            <span className="v">{props.watchingCount}頭</span>
          </div>
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
                {/* ウォームアップ中は状態語を断定しない(Flutter側F5と同じ) */}
                <span
                  className="ring-word"
                  style={{ color: ppm === null || warmingUp ? 'var(--text-tertiary)' : color }}
                >
                  {ppm === null || warmingUp ? '…' : levelShort[level]}
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
  /* rightは最新点のハロー(半径~6)が縁に接しないよう20 — 監査P6 */
  const PAD = { left: 6, right: 20, top: 8, bottom: 8 }
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
