/**
 * 依存ゼロのSVG折れ線チャート — Apple Health参照。
 * 右側Y軸ラベル・薄い水平グリッド・最新点のハイライト・閾値破線。
 */
import { useMemo } from 'react'
import type { SensorSample } from '../providers/DataProvider'
import { H2_HIGH_PPM } from '../providers/DataProvider'

const W = 720
const H = 230
const PAD = { top: 14, right: 44, bottom: 22, left: 8 }

interface Props {
  samples: SensorSample[]
  window?: number
}

export function Chart({ samples, window: win = 300 }: Props) {
  const visible = samples.length <= win ? samples : samples.slice(-win)

  const { path, area, maxY, gridYs, threshY, last } = useMemo(() => {
    const ppms = visible.map((s) => s.hydrogen_ppb / 1000)
    const maxVal = Math.max(H2_HIGH_PPM * 1.2, ...ppms.map((v) => v * 1.1), 1)
    const iw = W - PAD.left - PAD.right
    const ih = H - PAD.top - PAD.bottom

    const x = (i: number) =>
      PAD.left + (visible.length <= 1 ? iw : (i / (visible.length - 1)) * iw)
    const y = (v: number) => PAD.top + ih - (v / maxVal) * ih

    let d = ''
    ppms.forEach((v, i) => {
      d += `${i === 0 ? 'M' : 'L'}${x(i).toFixed(1)},${y(v).toFixed(1)}`
    })
    const a =
      ppms.length > 1
        ? `${d}L${x(ppms.length - 1).toFixed(1)},${(PAD.top + ih).toFixed(1)}L${PAD.left},${(PAD.top + ih).toFixed(1)}Z`
        : ''

    const step = niceStep(maxVal / 4)
    const ys: { v: number; y: number }[] = []
    for (let v = 0; v <= maxVal; v += step) ys.push({ v, y: y(v) })

    const lastPt =
      ppms.length > 0
        ? { x: x(ppms.length - 1), y: y(ppms[ppms.length - 1]) }
        : null

    return {
      path: d,
      area: a,
      maxY: maxVal,
      gridYs: ys,
      threshY: y(H2_HIGH_PPM),
      last: lastPt,
    }
  }, [visible])

  return (
    <svg
      className="chart-svg"
      viewBox={`0 0 ${W} ${H}`}
      preserveAspectRatio="none"
      role="img"
      aria-label="H2 ppm chart"
    >
      <defs>
        <linearGradient id="areaFill" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stopColor="var(--accent)" stopOpacity="0.14" />
          <stop offset="100%" stopColor="var(--accent)" stopOpacity="0" />
        </linearGradient>
      </defs>

      {/* 水平グリッド + 右側Y軸ラベル (Health流) */}
      {gridYs.map(({ v, y }) => (
        <g key={v}>
          <line
            x1={PAD.left}
            x2={W - PAD.right}
            y1={y}
            y2={y}
            stroke="var(--hairline)"
            strokeWidth="1"
          />
          <text className="axis-label" x={W - PAD.right + 8} y={y + 3.5}>
            {v}
          </text>
        </g>
      ))}

      {/* 高値閾値 */}
      {H2_HIGH_PPM < maxY && (
        <line
          x1={PAD.left}
          x2={W - PAD.right}
          y1={threshY}
          y2={threshY}
          stroke="var(--warn)"
          strokeOpacity="0.5"
          strokeWidth="1"
          strokeDasharray="5 5"
        />
      )}

      {/* データ */}
      {area && <path className="chart-line" d={area} fill="url(#areaFill)" />}
      {path && (
        <path
          className="chart-line"
          d={path}
          fill="none"
          stroke="var(--accent)"
          strokeWidth="2.2"
          strokeLinejoin="round"
          strokeLinecap="round"
        />
      )}

      {/* 最新点のハイライト */}
      {last && (
        <g className="chart-line">
          <circle cx={last.x} cy={last.y} r="7" fill="var(--accent)" fillOpacity="0.15" />
          <circle cx={last.x} cy={last.y} r="3.5" fill="var(--accent)" stroke="var(--card)" strokeWidth="1.5" />
        </g>
      )}
    </svg>
  )
}

function niceStep(raw: number): number {
  const pow = Math.pow(10, Math.floor(Math.log10(Math.max(raw, 0.1))))
  const n = raw / pow
  const nice = n <= 1 ? 1 : n <= 2 ? 2 : n <= 5 ? 5 : 10
  return nice * pow
}
