/**
 * SF Symbols的なミニマルアイコン(インラインSVG, 1.8px stroke)。
 * 絵文字・画像は使わない。currentColorで着色。
 */
interface IconProps {
  size?: number
}

const base = (size: number) => ({
  width: size,
  height: size,
  viewBox: '0 0 24 24',
  fill: 'none',
  stroke: 'currentColor',
  strokeWidth: 1.8,
  strokeLinecap: 'round' as const,
  strokeLinejoin: 'round' as const,
})

export const HouseIcon = ({ size = 22 }: IconProps) => (
  <svg {...base(size)}>
    <path d="M4 10.5 12 4l8 6.5" />
    <path d="M6 9.5V19a1 1 0 0 0 1 1h10a1 1 0 0 0 1-1V9.5" />
  </svg>
)

export const WaveIcon = ({ size = 22 }: IconProps) => (
  <svg {...base(size)}>
    <path d="M3 12h3l2.5-6 3.5 12 2.5-8 1.5 2H21" />
  </svg>
)

export const ChartIcon = ({ size = 22 }: IconProps) => (
  <svg {...base(size)}>
    <path d="M5 20V14" />
    <path d="M10 20V9" />
    <path d="M15 20v-7" />
    <path d="M20 20V5" />
  </svg>
)

export const HeartIcon = ({ size = 22 }: IconProps) => (
  <svg {...base(size)}>
    <path d="M12 20s-7-4.6-8.6-9C2.3 8 3.6 5 6.6 5c2 0 3.4 1.2 5.4 3.4C14 6.2 15.4 5 17.4 5c3 0 4.3 3 3.2 6-1.6 4.4-8.6 9-8.6 9Z" />
  </svg>
)

/** 設定 (SF "slider.horizontal.3" 風) */
export const GearIcon = ({ size = 22 }: IconProps) => (
  <svg {...base(size)}>
    <path d="M4 7h9M17 7h3" />
    <circle cx="15" cy="7" r="2" />
    <path d="M4 12h3M11 12h9" />
    <circle cx="9" cy="12" r="2" />
    <path d="M4 17h9M17 17h3" />
    <circle cx="15" cy="17" r="2" />
  </svg>
)

export const CheckIcon = ({ size = 40 }: IconProps) => (
  <svg {...base(size)} strokeWidth={2.2}>
    <path d="M5 12.5 10 17.5 19 7" />
  </svg>
)

export const ChevronIcon = ({ size = 16 }: IconProps) => (
  <svg {...base(size)}>
    <path d="M9 6l6 6-6 6" />
  </svg>
)

/** 小さなチェック(状態チップ用) */
export const CheckSmallIcon = ({ size = 12 }: IconProps) => (
  <svg {...base(size)} strokeWidth={2.6}>
    <path d="M5 12.5 10 17.5 19 7" />
  </svg>
)

/** 注意(!) — 色だけに依存せず状態を伝えるための記号 */
export const ExclamationIcon = ({ size = 12 }: IconProps) => (
  <svg {...base(size)} strokeWidth={2.6}>
    <path d="M12 4.5v10" />
    <path d="M12 19.4v.1" />
  </svg>
)

/** 肉球(塗り)。愛犬アバター用。 */
export const PawIcon = ({ size = 28 }: IconProps) => (
  <svg width={size} height={size} viewBox="0 0 24 24" fill="currentColor">
    <ellipse cx="7.2" cy="8.4" rx="1.9" ry="2.5" />
    <ellipse cx="12" cy="6.8" rx="2" ry="2.6" />
    <ellipse cx="16.8" cy="8.4" rx="1.9" ry="2.5" />
    <path d="M12 11.2c3.2 0 6 2.5 6 5.3 0 1.8-1.4 3-3.2 3-1.1 0-2-.5-2.8-.5s-1.7.5-2.8.5c-1.8 0-3.2-1.2-3.2-3 0-2.8 2.8-5.3 6-5.3Z" />
  </svg>
)
