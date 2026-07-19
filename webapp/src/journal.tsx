/**
 * 日誌 — 測定と健康日誌をひとつのタイムラインで振り返る (docs/21 §履歴/日誌)。
 * 普段は「今日・きのう・おととい…」の日誌形式。カレンダーは必要な時だけ切替。
 * Flutter版 history_page.dart のミラー。
 */
import { useMemo, useState } from 'react'
import type { SessionSummary } from './providers/DataProvider'
import { levelColor, levelForPpm, windowSummary } from './lib/assessment'
import {
  NOTE_TYPES as NOTE_TYPE_CHIPS,
  RATINGS as RATING_CHIPS,
  hasRating,
  noteTypeLabel,
  ratingLabel,
  type CareNote,
} from './lib/careNotes'
import { HistoryRow, TrendLine } from './views'
import { CalendarIcon, ListIcon, PlusIcon } from './components/icons'

/** タイムラインの1件(測定 or 日誌)。 */
type Entry =
  | { kind: 'measurement'; at: Date; m: SessionSummary }
  | { kind: 'note'; at: Date; n: CareNote }

export function JournalView(props: {
  history: SessionSummary[]
  notes: CareNote[]
  onBack: () => void
  onAddNote: () => void
  onDeleteNote: (id: string) => void
  onStartMeasure: () => void
}) {
  const [calendarMode, setCalendarMode] = useState(false)

  const entries = useMemo<Entry[]>(() => {
    const list: Entry[] = [
      ...props.history.map((m) => ({
        kind: 'measurement' as const,
        at: new Date(m.startedAt),
        m,
      })),
      ...props.notes.map((n) => ({
        kind: 'note' as const,
        at: new Date(n.at),
        n,
      })),
    ]
    return list.sort((a, b) => b.at.getTime() - a.at.getTime())
  }, [props.history, props.notes])

  return (
    <div className="stack view">
      {/* ---- 画面ヘッダ: 戻る + タイトル + 切替/追加 ---- */}
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
            onClick={props.onAddNote}
            aria-label="きょうの記録"
            title="きょうの記録"
          >
            <PlusIcon size={19} />
          </button>
        </div>
      </div>

      {entries.length === 0 ? (
        <section className="card empty-card">
          {/* 空状態を行き止まりにしない (docs/17 §9) */}
          <div className="empty-note">まだ記録がありません</div>
          <button className="link-btn" onClick={props.onStartMeasure}>
            測定をはじめる
          </button>
        </section>
      ) : calendarMode ? (
        <CalendarView entries={entries} onDeleteNote={props.onDeleteNote} />
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
          <TimelineList entries={entries} onDeleteNote={props.onDeleteNote} />
        </>
      )}
    </div>
  )
}

/* ---------------- 日誌タイムライン ---------------- */

function TimelineList({
  entries,
  onDeleteNote,
}: {
  entries: Entry[]
  onDeleteNote: (id: string) => void
}) {
  const groups: { label: string; items: Entry[] }[] = []
  let lastKey = ''
  for (const e of entries) {
    const key = dayKey(e.at)
    if (key !== lastKey) {
      groups.push({ label: dayLabel(e.at), items: [] })
      lastKey = key
    }
    groups[groups.length - 1].items.push(e)
  }
  return (
    <>
      {groups.map((g, gi) => (
        <section key={gi} className="journal-day">
          <div className="day-label">{g.label}</div>
          <div className="card">
            <div className="history-list">
              {g.items.map((e, i) =>
                e.kind === 'measurement' ? (
                  <HistoryRow key={`m-${i}`} s={e.m} detail />
                ) : (
                  <NoteRow key={`n-${e.n.id}`} note={e.n} onDelete={onDeleteNote} />
                ),
              )}
            </div>
          </div>
        </section>
      ))}
    </>
  )
}

export function NoteRow({
  note,
  onDelete,
}: {
  note: CareNote
  onDelete: (id: string) => void
}) {
  const d = new Date(note.at)
  const when = `${pad(d.getHours())}:${pad(d.getMinutes())}`
  const concern = note.rating === 'concern'
  return (
    <div className="history-item note-item">
      <span
        className="note-type"
        style={concern ? { color: 'var(--warn)' } : undefined}
      >
        {noteTypeLabel(note.type)}
        {note.rating ? ` · ${ratingLabel(note.rating)}` : ''}
      </span>
      {note.memo && <span className="note-memo">{note.memo}</span>}
      <span className="when">{when}</span>
      <button
        className="linklike danger small"
        onClick={() => {
          if (confirm('この記録を削除しますか?')) onDelete(note.id)
        }}
        aria-label="この記録を削除"
      >
        削除
      </button>
    </div>
  )
}

/* ---------------- カレンダー表示(必要な時だけ) ---------------- */

function CalendarView({
  entries,
  onDeleteNote,
}: {
  entries: Entry[]
  onDeleteNote: (id: string) => void
}) {
  const now = new Date()
  const [month, setMonth] = useState(new Date(now.getFullYear(), now.getMonth(), 1))
  const [selected, setSelected] = useState(
    new Date(now.getFullYear(), now.getMonth(), now.getDate()),
  )

  const byDay = useMemo(() => {
    const map = new Map<string, Entry[]>()
    for (const e of entries) {
      const k = dayKey(e.at)
      if (!map.has(k)) map.set(k, [])
      map.get(k)!.push(e)
    }
    return map
  }, [entries])

  const firstWeekday = month.getDay() // 日曜=0
  const daysInMonth = new Date(month.getFullYear(), month.getMonth() + 1, 0).getDate()
  const dayEntries = byDay.get(dayKey(selected)) ?? []

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
            <button
              className="icon-btn"
              aria-label="前の月"
              onClick={() =>
                setMonth(new Date(month.getFullYear(), month.getMonth() - 1, 1))
              }
            >
              ‹
            </button>
            <button
              className="icon-btn"
              aria-label="次の月"
              onClick={() =>
                setMonth(new Date(month.getFullYear(), month.getMonth() + 1, 1))
              }
            >
              ›
            </button>
          </div>
        </div>
        <div className="cal-grid">
          {['日', '月', '火', '水', '木', '金', '土'].map((w) => (
            <div key={w} className="cal-week">
              {w}
            </div>
          ))}
          {Array.from({ length: firstWeekday }).map((_, i) => (
            <div key={`sp-${i}`} />
          ))}
          {Array.from({ length: daysInMonth }).map((_, i) => {
            const d = new Date(month.getFullYear(), month.getMonth(), i + 1)
            const es = byDay.get(dayKey(d)) ?? []
            const isSel = dayKey(d) === dayKey(selected)
            const isToday = dayKey(d) === dayKey(now)
            // 測定があれば状態色、日誌のみはアクセントの点
            let dot: string | null = null
            for (const e of es) {
              if (e.kind === 'measurement') {
                dot = levelColor[levelForPpm(e.m.avgPpb / 1000)]
              }
            }
            if (!dot && es.length > 0) dot = 'var(--accent)'
            return (
              <button
                key={i}
                className={`cal-day ${isSel ? 'sel' : ''} ${isToday ? 'today' : ''}`}
                onClick={() => setSelected(d)}
              >
                <span>{i + 1}</span>
                <span
                  className="cal-dot"
                  style={{ background: dot ?? 'transparent' }}
                />
              </button>
            )
          })}
        </div>
      </section>

      <section className="journal-day">
        <div className="day-label">{dayLabel(selected)}</div>
        {dayEntries.length === 0 ? (
          <p className="comment">この日の記録はありません</p>
        ) : (
          <div className="card">
            <div className="history-list">
              {dayEntries.map((e, i) =>
                e.kind === 'measurement' ? (
                  <HistoryRow key={`m-${i}`} s={e.m} detail />
                ) : (
                  <NoteRow key={`n-${e.n.id}`} note={e.n} onDelete={onDeleteNote} />
                ),
              )}
            </div>
          </div>
        )}
      </section>
    </>
  )
}

/* ---------------- 日付ヘルパ ---------------- */

const pad = (n: number) => String(n).padStart(2, '0')

function dayKey(d: Date): string {
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`
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

/* ---------------- 日誌入力シート(3タップで記録) ---------------- */

export function NoteSheet(props: {
  onSave: (input: {
    type: CareNote['type']
    rating?: CareNote['rating']
    memo: string
  }) => void
  onClose: () => void
  /** ホームのケアタスクから開いた場合の初期種別 (docs/22 CareKit適用) */
  initialType?: CareNote['type']
}) {
  const [type, setType] = useState<CareNote['type']>(props.initialType ?? 'walk')
  const [rating, setRating] = useState<NonNullable<CareNote['rating']>>('normal')
  const [memo, setMemo] = useState('')

  return (
    <div className="overlay sheet-overlay" onClick={props.onClose}>
      <div
        className="sheet"
        role="dialog"
        aria-label="きょうの記録"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="sheet-handle" />
        <h3 className="sheet-title">きょうの記録</h3>

        <div className="chip-row">
          {NOTE_TYPE_CHIPS.map((c) => (
            <button
              key={c.type}
              className={`select-chip ${type === c.type ? 'on' : ''}`}
              onClick={() => setType(c.type)}
            >
              {c.label}
            </button>
          ))}
        </div>

        {hasRating(type) && (
          <div className="chip-row ratings">
            {RATING_CHIPS.map((c) => (
              <button
                key={c.rating}
                className={`select-chip wide ${rating === c.rating ? 'on' : ''} ${
                  c.rating === 'concern' ? 'warn' : ''
                }`}
                onClick={() => setRating(c.rating)}
              >
                {c.label}
              </button>
            ))}
          </div>
        )}

        <textarea
          className="memo-input"
          placeholder="自由にメモ…"
          rows={2}
          value={memo}
          onChange={(e) => setMemo(e.target.value)}
        />

        <button
          className="btn primary"
          onClick={() =>
            props.onSave({
              type,
              rating: hasRating(type) ? rating : undefined,
              memo: memo.trim(),
            })
          }
        >
          保存
        </button>
      </div>
    </div>
  )
}
