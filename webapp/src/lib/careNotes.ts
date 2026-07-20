/**
 * 健康日誌ストア (localStorage) — docs/21 v2.3。
 *
 * 考え方 (§1,4):
 * - 測定以外の健康日誌は「1日につき各カテゴリ1件まで」
 * - 保存はカテゴリ別レコードのまま(既存データ互換)、upsertで重複を防ぐ
 * - schema 2: 構造化された選択(choice) + 任意の補足メモ(memo)
 * - schema 1(旧): rating(良い/ふつう/気になる) — 読み取り互換を維持し、
 *   既存データは削除・変換しない(§19)
 */
export type CareNoteType =
  | 'walk' // 散歩
  | 'appetite' // 食欲
  | 'poop' // 排便
  | 'medicine' // 薬
  | 'condition' // 体調
  | 'memo' // 自由メモ

/** 旧schema1の3段階評価(読み取り互換用) */
export type CareRating = 'good' | 'normal' | 'concern'

export interface CareNote {
  id: string
  dogId: string
  at: string // ISO8601
  type: CareNoteType
  /** schema2: カテゴリ別の選択肢の値 (§3) */
  choice?: string
  /** schema1(旧)の評価 — 新規保存では使わない */
  rating?: CareRating
  /** 自由記述(memoカテゴリ本文、他カテゴリでは補足メモ) */
  memo: string
  schema: 1 | 2
}

export const NOTE_TYPES: { type: CareNoteType; label: string }[] = [
  { type: 'walk', label: '散歩' },
  { type: 'appetite', label: '食欲' },
  { type: 'poop', label: '排便' },
  { type: 'medicine', label: '薬' },
  { type: 'condition', label: '体調' },
  { type: 'memo', label: 'メモ' },
]

export const noteTypeLabel = (t: CareNoteType): string =>
  NOTE_TYPES.find((n) => n.type === t)?.label ?? 'メモ'

/** カテゴリごとのよく使う選択肢 (§3)。memoは自由記述のみ */
export const NOTE_CHOICES: Record<
  CareNoteType,
  { value: string; label: string }[]
> = {
  walk: [
    { value: 'none', label: '行かなかった' },
    { value: 'short', label: '短め' },
    { value: 'usual', label: 'いつも通り' },
    { value: 'long', label: '長め' },
  ],
  appetite: [
    { value: 'none', label: '食べなかった' },
    { value: 'less', label: '少なめ' },
    { value: 'normal', label: 'ふつう' },
    { value: 'lots', label: 'よく食べた' },
  ],
  poop: [
    { value: 'none', label: 'なし' },
    { value: 'less', label: '少なめ' },
    { value: 'usual', label: 'いつも通り' },
    { value: 'more', label: '多め' },
  ],
  medicine: [
    { value: 'none', label: 'なし' },
    { value: 'taken', label: '飲んだ' },
  ],
  condition: [
    { value: 'concern', label: '気になる' },
    { value: 'slight', label: '少し気になる' },
    { value: 'usual', label: 'いつも通り' },
    { value: 'energetic', label: '元気' },
  ],
  memo: [],
}

const LEGACY_RATING_LABEL: Record<CareRating, string> = {
  good: '良い',
  normal: 'ふつう',
  concern: '気になる',
}

/** 表示用: 選択内容の言葉。旧schema1のratingにも対応 (§19) */
export function noteValueLabel(n: CareNote): string {
  if (n.choice) {
    const c = NOTE_CHOICES[n.type].find((x) => x.value === n.choice)
    if (c) return c.label
  }
  if (n.rating) return LEGACY_RATING_LABEL[n.rating]
  return ''
}

/** 「気になる」系の選択か(控えめな注意色に使う) */
export function noteIsConcern(n: CareNote): boolean {
  return (
    n.rating === 'concern' ||
    (n.type === 'condition' &&
      (n.choice === 'concern' || n.choice === 'slight')) ||
    (n.type === 'appetite' && n.choice === 'none')
  )
}

const pad = (x: number) => String(x).padStart(2, '0')

/** ローカル日付キー yyyy-mm-dd */
export function dayKeyOf(d: Date): string {
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`
}

export const noteDayKey = (n: CareNote): string => dayKeyOf(new Date(n.at))

/**
 * ある日のカテゴリ別「最新1件」を返す (§4)。
 * 旧データに同日同カテゴリの重複があっても、削除せず最新だけを採用する。
 */
export function notesOfDay(
  notes: CareNote[],
  dogId: string,
  dayKey: string,
): Map<CareNoteType, CareNote> {
  const map = new Map<CareNoteType, CareNote>()
  // notesは新しい順 — 先勝ちで最新を採用
  for (const n of notes) {
    if (n.dogId !== dogId) continue
    if (noteDayKey(n) !== dayKey) continue
    if (!map.has(n.type)) map.set(n.type, n)
  }
  return map
}

const KEY = 'hydropaw.notes.v1'

export function loadNotes(): CareNote[] {
  try {
    const arr = JSON.parse(localStorage.getItem(KEY) ?? '[]')
    return Array.isArray(arr) ? arr : []
  } catch {
    return []
  }
}

export function saveNotes(notes: CareNote[]): void {
  localStorage.setItem(KEY, JSON.stringify(notes.slice(0, 800)))
}
