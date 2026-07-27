/**
 * 確認・設定用のボトムシート群 (docs/21 v2.2)。
 * 破壊的操作(削除/見守り終了)と測定対象の確認は必ずここを通す。
 */
import { useState } from 'react'
import { PawIcon } from './components/icons'
import type { Dog } from './lib/dogs'

/** 犬アバター(写真があれば写真、なければ肉球 §6) */
function DogAvatar({ dog }: { dog?: Dog }) {
  return (
    <div className="sheet-avatar">
      {dog?.photo ? (
        <img src={dog.photo} alt="" className="dog-photo" />
      ) : (
        <PawIcon size={30} />
      )}
    </div>
  )
}

/** 汎用確認シート */
export function ConfirmSheet(props: {
  title: string
  body: string
  confirmLabel: string
  danger?: boolean
  dog?: Dog // 指定時はアバターを表示
  onConfirm: () => void
  onClose: () => void
}) {
  return (
    <SheetBase onClose={props.onClose} label={props.title}>
      {props.dog !== undefined && <DogAvatar dog={props.dog} />}
      <h3 className="sheet-title center">{props.title}</h3>
      <p className="sheet-body">{props.body}</p>
      <button
        className={`btn ${props.danger ? 'stop' : 'primary'}`}
        onClick={props.onConfirm}
      >
        {props.confirmLabel}
      </button>
      <button className="btn ghost" onClick={props.onClose}>
        キャンセル
      </button>
    </SheetBase>
  )
}

/** 測定対象の確認 — 誤った犬への記録保存を防ぐ (§3) */
export function MeasureConfirmSheet(props: {
  dog: Dog
  onStart: () => void
  onClose: () => void
}) {
  return (
    <SheetBase onClose={props.onClose} label="測定対象の確認">
      <DogAvatar dog={props.dog} />
      <h3 className="sheet-title center">{props.dog.name}を測定します</h3>
      <button className="btn primary" onClick={props.onStart}>
        測定を開始
      </button>
      <button className="btn ghost" onClick={props.onClose}>
        キャンセル
      </button>
    </SheetBase>
  )
}

/** 上限到達 — 理由と解決方法(設定へ)を示す (§11) */
export function LimitSheet(props: {
  title: string
  body: string
  onOpenSettings: () => void
  onClose: () => void
}) {
  return (
    <SheetBase onClose={props.onClose} label={props.title}>
      <h3 className="sheet-title center">{props.title}</h3>
      <p className="sheet-body">{props.body}</p>
      <button className="btn primary" onClick={props.onOpenSettings}>
        設定を開く
      </button>
      <button className="btn ghost" onClick={props.onClose}>
        キャンセル
      </button>
    </SheetBase>
  )
}

/** 初回設定 — 一緒に暮らしている犬の頭数 (§9) */
export function FirstRunSheet(props: { onDone: (n: number) => void }) {
  const [n, setN] = useState(1)
  return (
    <div className="overlay sheet-overlay">
      <div className="sheet" role="dialog" aria-label="はじめまして">
        <div className="sheet-handle" />
        <h3 className="sheet-title center">はじめまして 🐾</h3>
        <p className="sheet-body">
          現在、一緒に暮らしている犬は何頭ですか？
          <br />
          (あとから設定でいつでも変えられます)
        </p>
        <div className="chip-row ratings">
          {[1, 2, 3].map((v) => (
            <button
              key={v}
              className={`select-chip wide ${n === v ? 'on' : ''}`}
              onClick={() => setN(v)}
            >
              {v}頭
            </button>
          ))}
        </div>
        <button className="btn primary" onClick={() => props.onDone(n)}>
          はじめる
        </button>
      </div>
    </div>
  )
}

/**
 * 見守る愛犬を減らす際、見守りを終了する愛犬を選ぶ (§8,9)。
 * ラジオボタン式の単一選択: 常に1頭だけが選択され、別の犬をタップすると
 * 即座に切り替わる。再タップで未選択にはならない。
 * 確定するとここでは状態を変えず、最終確認(§10)はApp側が出す。
 */
export function ReduceSheet(props: {
  watching: Dog[]
  onConfirm: (archiveId: string) => void
  onClose: () => void
}) {
  const [sel, setSel] = useState(props.watching[0]?.id ?? '')
  return (
    <SheetBase onClose={props.onClose} label="見守る愛犬を変更">
      <h3 className="sheet-title center">見守る愛犬を変更します</h3>
      <p className="sheet-body">
        現在{props.watching.length}頭を見守っています。
        見守りを終了する愛犬を1頭選んでください。
        これまでの記録は削除されません。
      </p>
      <div className="reduce-list" role="radiogroup" aria-label="見守りを終了する愛犬">
        {props.watching.map((d) => (
          <button
            key={d.id}
            role="radio"
            aria-checked={sel === d.id}
            className={`select-chip wide ${sel === d.id ? 'on warn' : ''}`}
            onClick={() => setSel(d.id)}
          >
            {d.name}
          </button>
        ))}
      </div>
      <button
        className="btn primary"
        disabled={sel === ''}
        onClick={() => props.onConfirm(sel)}
      >
        見守りを終了して変更
      </button>
      <button className="btn ghost" onClick={props.onClose}>
        キャンセル
      </button>
    </SheetBase>
  )
}

/* ---------- 共通土台 ---------- */

function SheetBase(props: {
  label: string
  onClose: () => void
  children: React.ReactNode
}) {
  return (
    <div className="overlay sheet-overlay" onClick={props.onClose}>
      <div
        className="sheet"
        role="dialog"
        aria-label={props.label}
        onClick={(e) => e.stopPropagation()}
      >
        <div className="sheet-handle" />
        {props.children}
      </div>
    </div>
  )
}
