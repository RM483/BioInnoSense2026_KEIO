/**
 * 健康日誌ストア (localStorage) — Flutter版 CareNote のミラー (docs/21 §日誌)。
 * 構造化データ(type/rating) + 自由記述(memo) を保存し、将来のAI解析に備える。
 */
export type CareNoteType =
  | 'walk' // 散歩
  | 'appetite' // 食欲
  | 'poop' // 排便
  | 'medicine' // 薬
  | 'condition' // 体調
  | 'memo' // 自由メモ

export type CareRating = 'good' | 'normal' | 'concern'

export interface CareNote {
  id: string
  dogId: string
  at: string // ISO8601
  type: CareNoteType
  rating?: CareRating // 食欲/排便/体調のみ
  memo: string
  schema: 1
}

export const NOTE_TYPES: { type: CareNoteType; label: string }[] = [
  { type: 'walk', label: '散歩' },
  { type: 'appetite', label: '食欲' },
  { type: 'poop', label: '排便' },
  { type: 'medicine', label: '薬' },
  { type: 'condition', label: '体調' },
  { type: 'memo', label: 'メモ' },
]

export const RATINGS: { rating: CareRating; label: string }[] = [
  { rating: 'good', label: '良い' },
  { rating: 'normal', label: 'ふつう' },
  { rating: 'concern', label: '気になる' },
]

export const noteTypeLabel = (t: CareNoteType): string =>
  NOTE_TYPES.find((n) => n.type === t)?.label ?? 'メモ'

export const ratingLabel = (r: CareRating): string =>
  RATINGS.find((x) => x.rating === r)?.label ?? ''

export const hasRating = (t: CareNoteType): boolean =>
  t === 'appetite' || t === 'poop' || t === 'condition'

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
  localStorage.setItem(KEY, JSON.stringify(notes.slice(0, 500)))
}
