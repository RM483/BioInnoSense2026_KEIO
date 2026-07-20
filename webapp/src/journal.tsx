/**
 * 日誌 — 日付ごとの1枚カード + 1日分まとめ入力 (docs/21 v2.3)。
 *
 * - 「きょうの記録」は複数カテゴリを1回で入力し、最後に1回だけ保存 (§2)
 * - 健康日誌は1日各カテゴリ1件。当日分は編集として開く (§4)
 * - 履歴は記録が存在する最新3日分の日付カード。測定を上部で主表示 (§6-8)
 * - 同日の複数測定は同じカードにまとめ、注意結果を状態表示で優先 (§9,10)
 * Flutter版 history_page.dart / care_note_sheet.dart のミラー。
 */
import { useMemo, useState } from 'react'
import type { SessionSummary } from './providers/DataProvider'
import { levelForPpm, windowSummary, type HealthLevel } from './lib/assessment'
import {
  NOTE_CHOICES,
  NOTE_TYPES,
  dayKeyOf,
  noteIsConcern,
  noteValueLabel,
  type CareNote,
  type CareNoteType,
} from './lib/careNotes'
import { TrendLine } from './views'
import { CalendarIcon, ListIcon, PlusIcon } from './components/icons'

/* ================= 状態語 (§10,11) ================= */

type DayStatus = 'stable' | 'slight' | 'elevated' | 'unknown'

/** 不安をあおらない状態語 (§11) */
const DAY_STATUS_WORD: Record<DayStatus, string> = {
  stable: '安定しています',
  slight: '少し変化が見られました',
  elevated: 'いつもと違う傾向が見られました',
  unknown: '測定結果を確認できませんでした',
}

const ROW_WORD: Record<HealthLevel, string> = {
  none: '—',
  stable: '安定',
  slight: '少し変化',
  elevated: 'いつもと違う',
}

const STATUS_COLOR: Record<DayStatus, string> = {
  stable: 'var(--success)',
  slight: 'var(--warn)',
  elevated: 'var(--warn)', // 注意でも赤一色にしない (§11)
  unknown: 'var(--text-tertiary)',
}

const QUALITY_MIN = 60

const isReliable = (m: SessionSummary) =>
  m.quality === undefined || m.quality >= QUALITY_MIN

/**
 * その日の状態 (§10): 安定していない結果が1件でもあればそれを優先する。
 * 要確認(elevated) > 軽い変化(slight) > 安定 > 判定不能。
 */
function dayStatusOf(measurements: SessionSummary[]): DayStatus | null {
  if (measurements.length === 0) return null
  const reliable = measurements.filter(isReliable)
  if (reliable.length === 0) return 'unknown'
  const levels = reliable.map((m) => levelForPpm(m.avgPpb / 1000))
  if (levels.includes('elevated')) return 'elevated'
  if (levels.includes('slight')) return 'slight'
  return 'stable'
}

/* ================= 日付グループ ================= */

interface DayData {
  key: string
  date: Date
  /** その日の測定(新しい順) */
  measurements: SessionSummary[]
  /** カテゴリ別の最新1件 (§4: 重複データは最新を採用、削除はしない) */
  notes: Map<CareNoteType, CareNote>
}

function buildDays(
  history: SessionSummary[],
  notes: CareNote[],
): DayData[] {
  const map = new Map<string, DayData>()
  const dayOf = (iso: string) => {
    const d = new Date(iso)
    const key = dayKeyOf(d)
    if (!map.has(key)) {
      map.set(key, {
        key,
        date: new Date(d.getFullYear(), d.getMonth(), d.getDate()),
        measurements: [],
        notes: new Map(),
      })
    }
    return map.get(key)!
  }
  for (const m of history) {
    dayOf(m.startedAt).measurements.push(m)
  }
  for (const n of notes) {
    const day = dayOf(n.at)
    if (!day.notes.has(n.type)) day.notes.set(n.type, n) // 最新を採用
  }
  const days = [...map.values()]
  days.sort((a, b) => b.date.getTime() - a.date.getTime())
  for (const d of days) {
    d.measurements.sort(
      (a, b) =>
        new Date(b.startedAt).getTime() - new Date(a.startedAt).getTime(),
    )
  }
  return days
}

/* ================= 日誌ビュー ================= */

export function JournalView(props: {
  history: SessionSummary[]
  notes: CareNote[]
  onBack: () => void
  onEditToday: () => void // きょうの記録(追加も編集も同じ画面 §16)
  onDeleteDay: (dayKey: string) => void
  onStartMeasure: () => void
}) {
  const [calendarMode, setCalendarMode] = useState(false)
  const [visibleDays, setVisibleDays] = useState(3) // 最新3日分 (§6)

  const days = useMemo(
    () => buildDays(props.history, props.notes),
    [props.history, props.notes],
  )
  const todayKey = dayKeyOf(new Date())

  return (
    <div className="stack view">
      {/* ---- 画面ヘッダ ---- */}
      <div className="journal-head">
        <button className="back-btn" onClick={props.onBack} aria-label="ホームに戻る">
          ‹ ホーム
        </button>
        <h2 className="journal-title">日誌</h2>
        <div className="journal-actions">
          <button
            className="icon-btn"
            onClick={() => setCalendarMode((v) => !v)}
            aria-label={calendarMode ? '日誌表示' : 'カレンダー表示'}
            title={calendarMode ? '日誌表示' : 'カレンダー表示'}
          >
            {calendarMode ? <ListIcon size={19} /> : <CalendarIcon size={19} />}
          </button>
          <button
            className="icon-btn"
            onClick={props.onEditToday}
            aria-label="きょうの記録"
            title="きょうの記録"
          >
            <PlusIcon size={19} />
          </button>
        </div>
      </div>

      {days.length === 0 ? (
        <section className="card empty-card">
          <div className="empty-note">まだ記録がありません</div>
          <button className="link-btn" onClick={props.onStartMeasure}>
            測定をはじめる
          </button>
        </section>
      ) : calendarMode ? (
        <CalendarView
          days={days}
          todayKey={todayKey}
          onEditToday={props.onEditToday}
          onDeleteDay={props.onDeleteDay}
        />
      ) : (
        <>
          {props.history.length >= 2 && (
            <section className="card">
              <div className="card-head">
                <span className="label plain">最近の推移</span>
              </div>
              <TrendLine history={props.history} tall />
              <p className="trend-summary">{windowSummary(props.history, 14)}</p>
            </section>
          )}

          {/* ---- 日付カード: 記録が存在する最新N日分 (§6) ---- */}
          {days.slice(0, visibleDays).map((day) => (
            <DayCard
              key={day.key}
              day={day}
              isToday={day.key === todayKey}
              onEditToday={props.onEditToday}
              onDeleteDay={props.onDeleteDay}
            />
          ))}

          {/* ---- 過去の記録 (§17) ---- */}
          {days.length > visibleDays && (
            <button
              className="link-btn center"
              onClick={() => setVisibleDays((v) => v + 7)}
            >
              過去の記録を見る
            </button>
          )}
        </>
      )}
    </div>
  )
}

/* ================= 日付カード (§7) ================= */

function DayCard(props: {
  day: DayData
  isToday: boolean
  onEditToday: () => void
  onDeleteDay: (dayKey: string) => void
}) {
  const { day } = props
  const [menuOpen, setMenuOpen] = useState(false)
  const [showAll, setShowAll] = useState(false)
  const [memoOpen, setMemoOpen] = useState(false)

  const status = dayStatusOf(day.measurements)
  const latest = day.measurements[0]
  const latestLevel: HealthLevel | null = latest
    ? isReliable(latest)
      ? levelForPpm(latest.avgPpb / 1000)
      : 'none'
    : null
  // 状態表示は注意結果を優先。最新測定と判定が違う時は短い補足 (§10)
  const mismatch =
    status !== null &&
    latest !== undefined &&
    ((status === 'elevated' && latestLevel !== 'elevated') ||
      (status === 'slight' && latestLevel === 'stable'))

  const memoNote = day.notes.get('memo')
  const journalRows = NOTE_TYPES.filter(
    (t) => t.type !== 'memo' && day.notes.has(t.type),
  )
  const hasJournal = journalRows.length > 0 || memoNote !== undefined
  const menuItems = [
    ...(props.isToday ? (['edit'] as const) : []),
    ...(hasJournal ? (['delete'] as const) : []),
  ]

  const memoText = memoNote?.memo ?? ''
  const memoLong = memoText.length > 100

  return (
    <section className="card day-card">
      {/* ---- 1. その日の状態 (§7,10,11) ---- */}
      <div className="day-head">
        <span className="day-title">{dayLabel(day.date)}</span>
        {status !== null && (
          <span className="day-status" style={{ color: STATUS_COLOR[status] }}>
            <span className="level-dot" style={{ background: STATUS_COLOR[status] }} />
            {DAY_STATUS_WORD[status]}
          </span>
        )}
        {menuItems.length > 0 && (
          <div className="card-menu-wrap">
            <button
              className="icon-btn"
              aria-label="操作メニュー"
              onClick={() => setMenuOpen((v) => !v)}
            >
              …
            </button>
            {menuOpen && (
              <>
                <div className="menu-backdrop" onClick={() => setMenuOpen(false)} />
                <div className="card-menu" role="menu">
                  {menuItems.includes('edit') && (
                    <button
                      role="menuitem"
                      onClick={() => {
                        setMenuOpen(false)
                        props.onEditToday()
                      }}
                    >
                      きょうの記録を編集
                    </button>
                  )}
                  {menuItems.includes('delete') && (
                    <button
                      role="menuitem"
                      className="danger-text"
                      onClick={() => {
                        setMenuOpen(false)
                        // 健康日誌のみ削除。測定結果は残す (§15,20)
                        if (
                          confirm(
                            'この日の健康日誌を削除しますか？測定結果は削除されません。',
                          )
                        ) {
                          props.onDeleteDay(day.key)
                        }
                      }}
                    >
                      健康日誌を削除
                    </button>
                  )}
                </div>
              </>
            )}
          </div>
        )}
      </div>

      {/* ---- 2. 測定結果(主表示 §8,9) ---- */}
      {latest ? (
        <div className="measure-block">
          <div className="measure-main">
            <span className="measure-label">最新の測定</span>
            <span className="measure-value">
              {(latest.avgPpb / 1000).toFixed(1)}
              <span className="unit"> ppm</span>
            </span>
            <span className="measure-time">{timeOf(latest.startedAt)}</span>
          </div>
          {mismatch && (
            <p className="measure-note">
              この日の測定のうち1件で、いつもと異なる傾向が見られました。
            </p>
          )}
          {day.measurements.length >= 2 && (
            <div className="measure-list">
              <span className="measure-count">
                この日の測定 {day.measurements.length}回
              </span>
              {(day.measurements.length <= 2 || showAll
                ? day.measurements
                : day.measurements.slice(0, 1)
              ).map((m, i) => (
                <div key={i} className="m-row">
                  <span className="when">{timeOf(m.startedAt)}</span>
                  <span className="m-ppm">
                    {(m.avgPpb / 1000).toFixed(1)} ppm
                  </span>
                  <span
                    className="m-word"
                    style={{
                      color: isReliable(m)
                        ? STATUS_COLOR[
                            levelForPpm(m.avgPpb / 1000) as DayStatus
                          ] ?? 'var(--text-secondary)'
                        : 'var(--text-tertiary)',
                    }}
                  >
                    {isReliable(m)
                      ? ROW_WORD[levelForPpm(m.avgPpb / 1000)]
                      : '判定不能'}
                  </span>
                </div>
              ))}
              {day.measurements.length > 2 && (
                <button
                  className="linklike subtle"
                  onClick={() => setShowAll((v) => !v)}
                >
                  {showAll ? '閉じる' : 'すべて見る'}
                </button>
              )}
            </div>
          )}
        </div>
      ) : (
        // 測定がない日は控えめに (§18)
        <p className="measure-empty">この日の測定記録はありません</p>
      )}

      {/* ---- 3. 健康日誌 (§13) ---- */}
      {journalRows.length > 0 && (
        <div className="journal-rows">
          {journalRows.map(({ type, label }) => {
            const n = day.notes.get(type)!
            return (
              <div key={type} className="j-row">
                <span className="j-label">{label}</span>
                <span
                  className="j-value"
                  style={
                    noteIsConcern(n) ? { color: 'var(--warn)' } : undefined
                  }
                >
                  {noteValueLabel(n) || '—'}
                </span>
                {n.memo && <span className="j-memo">{n.memo}</span>}
              </div>
            )
          })}
        </div>
      )}

      {/* ---- 4. 自由メモ (§14) ---- */}
      {memoNote && memoText && (
        <div className="memo-block">
          <span className="j-label">メモ</span>
          <p className={`memo-text ${memoLong && !memoOpen ? 'clamp' : ''}`}>
            {memoText}
          </p>
          {memoLong && (
            <button
              className="linklike subtle"
              onClick={() => setMemoOpen((v) => !v)}
            >
              {memoOpen ? '閉じる' : '続きを読む'}
            </button>
          )}
        </div>
      )}
    </section>
  )
}

/* ================= カレンダー表示 (必要な時だけ §17) ================= */

function CalendarView(props: {
  days: DayData[]
  todayKey: string
  onEditToday: () => void
  onDeleteDay: (dayKey: string) => void
}) {
  const now = new Date()
  const [month, setMonth] = useState(new Date(now.getFullYear(), now.getMonth(), 1))
  const [selected, setSelected] = useState(dayKeyOf(now))

  const byKey = useMemo(
    () => new Map(props.days.map((d) => [d.key, d])),
    [props.days],
  )
  const firstWeekday = month.getDay()
  const daysInMonth = new Date(month.getFullYear(), month.getMonth() + 1, 0).getDate()
  const selectedDay = byKey.get(selected)

  const monthLabel = new Intl.DateTimeFormat('ja-JP', {
    year: 'numeric',
    month: 'long',
  }).format(month)

  return (
    <>
      <section className="card">
        <div className="cal-head">
          <span className="cal-month">{monthLabel}</span>
          <div>
            <button className="icon-btn" aria-label="前の月"
              onClick={() => setMonth(new Date(month.getFullYear(), month.getMonth() - 1, 1))}>
              ‹
            </button>
            <button className="icon-btn" aria-label="次の月"
              onClick={() => setMonth(new Date(month.getFullYear(), month.getMonth() + 1, 1))}>
              ›
            </button>
          </div>
        </div>
        <div className="cal-grid">
          {['日', '月', '火', '水', '木', '金', '土'].map((w) => (
            <div key={w} className="cal-week">{w}</div>
          ))}
          {Array.from({ length: firstWeekday }).map((_, i) => (
            <div key={`sp-${i}`} />
          ))}
          {Array.from({ length: daysInMonth }).map((_, i) => {
            const d = new Date(month.getFullYear(), month.getMonth(), i + 1)
            const key = dayKeyOf(d)
            const data = byKey.get(key)
            const isSel = key === selected
            const status = data ? dayStatusOf(data.measurements) : null
            const dot = data
              ? status
                ? STATUS_COLOR[status]
                : 'var(--accent)'
              : null
            return (
              <button
                key={i}
                className={`cal-day ${isSel ? 'sel' : ''} ${key === props.todayKey ? 'today' : ''}`}
                onClick={() => setSelected(key)}
              >
                <span>{i + 1}</span>
                <span className="cal-dot" style={{ background: dot ?? 'transparent' }} />
              </button>
            )
          })}
        </div>
      </section>

      {selectedDay ? (
        <DayCard
          day={selectedDay}
          isToday={selected === props.todayKey}
          onEditToday={props.onEditToday}
          onDeleteDay={props.onDeleteDay}
        />
      ) : (
        <p className="comment">この日の記録はありません</p>
      )}
    </>
  )
}

/* ================= 日付ヘルパ ================= */

const pad = (n: number) => String(n).padStart(2, '0')

const timeOf = (iso: string) => {
  const d = new Date(iso)
  return `${pad(d.getHours())}:${pad(d.getMinutes())}`
}

function dayLabel(d: Date): string {
  const now = new Date()
  const today = new Date(now.getFullYear(), now.getMonth(), now.getDate())
  const day = new Date(d.getFullYear(), d.getMonth(), d.getDate())
  const diff = Math.round((today.getTime() - day.getTime()) / 86400000)
  if (diff === 0) return '今日'
  if (diff === 1) return 'きのう'
  if (diff === 2) return 'おととい'
  return new Intl.DateTimeFormat('ja-JP', {
    month: 'long',
    day: 'numeric',
    weekday: 'short',
  }).format(d)
}

/* ================= きょうの記録(まとめ入力 §2-5) ================= */

export interface DayEntryInput {
  type: CareNoteType
  choice?: string
  memo: string
}

interface Draft {
  choice?: string
  memo: string
}

export function NoteSheet(props: {
  /** 当日の既存記録(カテゴリ別最新)。編集として開く (§4) */
  existing: Map<CareNoteType, CareNote>
  onSave: (entries: DayEntryInput[]) => void
  onClose: () => void
}) {
  const [active, setActive] = useState<CareNoteType>('walk')
  const [dirty, setDirty] = useState(false)
  const [drafts, setDrafts] = useState<Record<CareNoteType, Draft>>(() => {
    const init = {} as Record<CareNoteType, Draft>
    for (const { type } of NOTE_TYPES) {
      const n = props.existing.get(type)
      init[type] = { choice: n?.choice, memo: n?.memo ?? '' }
    }
    return init
  })

  const hasContent = (t: CareNoteType) =>
    drafts[t].choice !== undefined || drafts[t].memo.trim() !== ''

  const setDraft = (t: CareNoteType, d: Partial<Draft>) => {
    setDirty(true)
    setDrafts((prev) => ({ ...prev, [t]: { ...prev[t], ...d } }))
  }

  // 未保存の変更がある時だけ確認して閉じる (§5)
  const requestClose = () => {
    if (!dirty || confirm('入力した内容を保存せずに閉じますか？')) {
      props.onClose()
    }
  }

  const save = () => {
    const entries: DayEntryInput[] = NOTE_TYPES.filter(({ type }) =>
      hasContent(type),
    ).map(({ type }) => ({
      type,
      choice: drafts[type].choice,
      memo: drafts[type].memo.trim(),
    }))
    props.onSave(entries)
  }

  const activeDraft = drafts[active]
  const choices = NOTE_CHOICES[active]

  return (
    <div className="overlay sheet-overlay" onClick={requestClose}>
      <div
        className="sheet"
        role="dialog"
        aria-label="きょうの記録"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="sheet-handle" />
        <h3 className="sheet-title">きょうの記録</h3>

        {/* ---- カテゴリ: 未入力 / 入力済み(点) / 選択中 (§5) ---- */}
        <div className="chip-row">
          {NOTE_TYPES.map(({ type, label }) => (
            <button
              key={type}
              className={`select-chip ${active === type ? 'on' : ''} ${
                hasContent(type) && active !== type ? 'filled' : ''
              }`}
              onClick={() => setActive(type)}
            >
              {label}
              {hasContent(type) && <span className="filled-dot" />}
            </button>
          ))}
        </div>

        {/* ---- 選択中カテゴリの選択肢 (§3) ---- */}
        {choices.length > 0 && (
          <div className="chip-row choice-grid">
            {choices.map((c) => (
              <button
                key={c.value}
                className={`select-chip wide ${
                  activeDraft.choice === c.value ? 'on' : ''
                }`}
                onClick={() => setDraft(active, { choice: c.value })}
              >
                {c.label}
              </button>
            ))}
          </div>
        )}

        {/* ---- 任意メモ (memoカテゴリは本文) ---- */}
        <textarea
          className="memo-input"
          placeholder={active === 'memo' ? '自由にメモ…' : '補足メモ（任意）'}
          rows={2}
          value={activeDraft.memo}
          onChange={(e) => setDraft(active, { memo: e.target.value })}
        />

        {/* ---- まとめて1回で保存 (§2) ---- */}
        <button className="btn primary" onClick={save}>
          きょうの記録を保存
        </button>
      </div>
    </div>
  )
}
