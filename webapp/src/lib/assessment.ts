/**
 * 測定データ → 「人が理解できる意味」への変換。
 * Flutter側 features/insights/domain/health_assessment.dart と同一ロジック。
 * UIはppmを直接解釈せず、この層の言葉と色だけを表示する。
 */
import type { SessionSummary } from '../providers/DataProvider'
import { H2_HIGH_PPM } from '../providers/DataProvider'

export type HealthLevel = 'none' | 'stable' | 'slight' | 'elevated'
export type HealthTrend = 'none' | 'improving' | 'steady' | 'worsening'

export const STABLE_MAX_PPM = 10.0
const STALE_AFTER_MS = 24 * 60 * 60 * 1000

export interface Assessment {
  level: HealthLevel
  trend: HealthTrend
  latest: SessionSummary | null
  isStale: boolean
}

export function levelForPpm(avgPpm: number): HealthLevel {
  if (avgPpm >= H2_HIGH_PPM) return 'elevated'
  if (avgPpm >= STABLE_MAX_PPM) return 'slight'
  return 'stable'
}

/** 新しい順の履歴から評価を作る */
export function assess(history: SessionSummary[], now = Date.now()): Assessment {
  if (history.length === 0) {
    return { level: 'none', trend: 'none', latest: null, isStale: false }
  }
  const latest = history[0]
  const level = levelForPpm(latest.avgPpb / 1000)

  let trend: HealthTrend = 'none'
  if (history.length >= 2) {
    const prev = history[1].avgPpb / 1000
    const cur = latest.avgPpb / 1000
    if (prev > 0.5) {
      const change = (cur - prev) / prev
      trend = change <= -0.2 ? 'improving' : change >= 0.2 ? 'worsening' : 'steady'
    } else {
      trend = cur < STABLE_MAX_PPM ? 'steady' : 'worsening'
    }
  }

  return {
    level,
    trend,
    latest,
    isStale: now - new Date(latest.startedAt).getTime() >= STALE_AFTER_MS,
  }
}

export const levelPhrase: Record<HealthLevel, string> = {
  none: 'はじめての測定をしてみましょう',
  stable: '今日は安定しています',
  slight: '少し高めです。様子を見ましょう',
  elevated: '高めの値が続いています',
}

export const levelShort: Record<HealthLevel, string> = {
  none: '—',
  stable: '安定',
  slight: 'やや高め',
  elevated: '高め',
}

/** CSSカラートークン名 */
export const levelColor: Record<HealthLevel, string> = {
  none: 'var(--accent)',
  stable: 'var(--success)',
  slight: 'var(--warn)',
  elevated: 'var(--danger)',
}

export function assessmentComment(a: Assessment): string {
  if (a.level === 'none') return '1回3分ほどで、毎日のコンディションを記録できます'
  if (a.isStale) return 'そろそろ今日の測定をおすすめします'
  switch (a.trend) {
    case 'improving':
      return '前回より落ち着いてきています'
    case 'worsening':
      return '前回より少し上がっています'
    case 'steady':
      return '前回と変わりありません'
    case 'none':
      break
  }
  switch (a.level) {
    case 'stable':
      return 'この調子で見守っていきましょう'
    case 'slight':
      return '食事の内容をメモしておくと役立ちます'
    case 'elevated':
      return '続くようなら、かかりつけの獣医師にご相談ください'
    default:
      return ''
  }
}

export function relativeTime(iso: string, now = Date.now()): string {
  const d = now - new Date(iso).getTime()
  const min = Math.floor(d / 60000)
  if (min < 1) return 'たった今'
  if (min < 60) return `${min}分前`
  const h = Math.floor(min / 60)
  if (h < 24) return `${h}時間前`
  return `${Math.floor(h / 24)}日前`
}
