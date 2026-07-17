/**
 * 依存ゼロのSVG折れ線チャート。
 * アクセント色の細線 + ごく薄い面 + 閾値の破線のみの静かな表現。
 */
import { useMemo } from 'react'
import type { SensorSample } from '../providers/DataProvider'
import { H2_HIGH_PPM } from '../providers/DataProvider'

const W = 720
const H = 240
const PAD = { top: 12, right: 12, bottom: 24, left: 44 }

interface Props {
  samples: SensorSample[]
  window?: number
}

export function Chart({ samples, window: win = 300 }: Props) {
  const visible = samples.length <= win ? samples : samples.slice(-win)

  const { path, area, maxY, gridYs, threshY } = useMemo(() => {
    const ppms = visible.map((s) => s.hydrogen_ppb / 1000)
    const maxVal = Math.max(H2_HIGH_PPM * 1.2, ...ppms.map((v) => v * 1.1), 1)
    const iw = W - PAD.left - PAD.right
    const ih = H - PAD.top - PAD.bottom

    const x = (i: number) =>
      PAD.left + (visible.length <= 1 ? 0 : (i / (visible.length - 1)) * iw)
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
    for (let v = 0; v <= maxVal; v += step) {
      ys.push({ v, y: y(v) })
    }
    return { path: d, area: a, maxY: maxVal, gridYs: ys, threshY: y(H2_HIGH_PPM) }
  }, [visible])

  return (
    <svg
      className="chart-svg"
      viewBox={`0 0 ${W} ${H}`}
      preserveAspectRatio="none"
      role="img"
      aria-label="H2 ppm chart"
    >
      {/* 水平グリッド + Y軸ラベル */}
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
          <text className="axis-label" x={PAD.left - 8} y={y + 3.5} textAnchor="end">
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
          strokeOpacity="0.55"
          strokeWidth="1"
          strokeDasharray="6 5"
        />
      )}

      {/* データ */}
      {area && <path d={area} fill="var(--accent)" fillOpacity="0.06" />}
      {path && (
        <path
          d={path}
          fill="none"
          stroke="var(--accent)"
          strokeWidth="2"
          strokeLinejoin="round"
          strokeLinecap="round"
        />
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
