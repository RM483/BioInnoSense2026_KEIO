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
  /** 前回測定のレベル(比較の文言を安心方向に整えるために使用) */
  prevLevel: HealthLevel | null
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
    return { level: 'none', trend: 'none', prevLevel: null, latest: null, isStale: false }
  }
  const latest = history[0]
  const level = levelForPpm(latest.avgPpb / 1000)

  let trend: HealthTrend = 'none'
  let prevLevel: HealthLevel | null = null
  if (history.length >= 2) {
    const prev = history[1].avgPpb / 1000
    const cur = latest.avgPpb / 1000
    prevLevel = levelForPpm(prev)
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
    prevLevel,
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

/**
 * 前回からの変化(なければnull)。
 * 医学的に問題のない変動(正常範囲内)では不安を与える表現を避け、
 * 現在の状態と整合する言葉を選ぶ。
 */
export function trendLabel(a: Assessment): string | null {
  if (a.trend === 'none') return null
  const bothStable = a.level === 'stable' && a.prevLevel === 'stable'

  switch (a.trend) {
    case 'improving':
      // 高め→正常へ戻った時だけ「改善」を明言(正常内の低下はノイズ)
      return a.prevLevel !== 'stable' && a.level === 'stable'
        ? '前回より改善しています'
        : bothStable
          ? '安定した状態が続いています'
          : '前回より落ち着いてきています'
    case 'worsening':
      // 正常範囲内の上振れは「変動」— 不安を与えない
      return a.level === 'stable'
        ? '正常範囲内でわずかに変動しています'
        : '前回より少し上がっています'
    case 'steady':
      return bothStable ? '安定した状態が続いています' : '前回と変わりありません'
    default:
      return null
  }
}

/**
 * 直近ウィンドウ(グラフ表示分)の言葉による要約。
 * グラフの下に添えて「線の意味」を一文で伝える。
 */
export function windowSummary(history: SessionSummary[], window = 7): string {
  const ppms = history.slice(0, window).map((h) => h.avgPpb / 1000)
  if (ppms.length === 0) return ''
  const latestLevel = levelForPpm(ppms[0])
  const anyAbove = ppms.some((v) => v >= STABLE_MAX_PPM)

  if (latestLevel === 'elevated') {
    return '高めの状態です。続くようなら受診をおすすめします'
  }
  if (latestLevel === 'slight') {
    return '正常範囲をやや上回っています。様子を見ましょう'
  }
  return anyAbove
    ? '高めの日もありましたが、いまは正常範囲に戻っています'
    : '正常範囲内で推移しています'
}

/** ユーザーが取るべき行動(ホームで最も大切な一文) */
export function actionLabel(a: Assessment): string {
  if (a.level === 'none') return '1回3分ほどで、今日のコンディションを記録できます'
  if (a.isStale) return 'そろそろ今日の測定をおすすめします'
  switch (a.level) {
    case 'stable':
      return '通常どおり過ごして大丈夫そうです'
    case 'slight':
      return '今日は少し気にかけて、水分と食事をみてあげてください'
    case 'elevated':
      return '続くようであれば、かかりつけの獣医師に相談しましょう'
    default:
      return ''
  }
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
