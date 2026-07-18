/**
 * SPA動作検証 (jsdom + MockProvider実物)。
 * ホーム→測定(イベント)→解析中→結果→ホーム反映、タブ遷移、永続化。
 *   npx vitest run
 */
// @vitest-environment jsdom
import { describe, it, expect, beforeEach, vi } from 'vitest'
import { render, screen, fireEvent, act, cleanup } from '@testing-library/react'
import App from './App'

async function tick(ms: number) {
  await act(async () => {
    await vi.advanceTimersByTimeAsync(ms)
  })
}

describe('HydroPaw Web SPA (MockProvider)', () => {
  beforeEach(() => {
    cleanup()
    localStorage.clear()
    location.hash = ''
    vi.useFakeTimers()
  })

  it('測定イベント: ホーム→測定中→解析中→結果→ホームに意味が反映される', async () => {
    render(<App />)

    // ホーム: 意味の言葉が主役、専門用語なし
    expect(screen.getByText('はじめての測定をしてみましょう')).toBeTruthy()
    expect(document.querySelector('.overlay')).toBeNull()

    // 測定開始(自動接続)
    fireEvent.click(screen.getByText('測定をはじめる'))
    await tick(10)
    expect(screen.getByText('接続しています…')).toBeTruthy()
    await tick(900)

    // フルスクリーンの測定中ビュー
    expect(document.querySelector('.overlay')).toBeTruthy()
    await tick(1100)
    // ウォームアップ中は状態語を断定しない(「…」+ 参考値のppmのみ)
    expect(document.querySelector('.ring-word')!.textContent).toBe('…')
    const ppm1 = document.querySelector('.ring-ppm')!.textContent!
    expect(ppm1).toMatch(/ppm/)

    // 1Hz更新 + グラフ伸長
    const d1 = document.querySelector('svg path[stroke]')!.getAttribute('d')!
    await tick(2100)
    const ppm2 = document.querySelector('.ring-ppm')!.textContent!
    expect(ppm2).not.toBe(ppm1)
    const d2 = document.querySelector('svg path[stroke]')!.getAttribute('d')!
    expect(d2.length).toBeGreaterThan(d1.length)

    // 終了 → 解析中(最低1.4s) → 結果
    fireEvent.click(screen.getByText('終了する'))
    await tick(200)
    expect(screen.getByText('解析しています…')).toBeTruthy()
    await tick(1500)
    expect(screen.getByText('測定できました')).toBeTruthy()
    expect(screen.getByText('測定時間')).toBeTruthy()

    // ホームへ → 評価が更新され、リングと言葉が主役に
    fireEvent.click(screen.getByText('ホームに戻る'))
    await tick(50)
    expect(document.querySelector('.overlay')).toBeNull()
    expect(document.querySelector('.care-ring')).toBeTruthy()
    expect(
      ['今日は安定しています', '少し高めです。様子を見ましょう', '高めの値が続いています'],
    ).toContain(document.querySelector('.home-words .phrase')!.textContent)
    expect(document.querySelector('.last-measured')!.textContent).toContain(
      '最終測定',
    )

    // 記録の住所は履歴タブ
    fireEvent.click(screen.getAllByText('履歴')[0])
    await tick(10)
    expect(document.querySelectorAll('.history-item').length).toBeGreaterThan(0)
  }, 15000)

  it('タブ遷移: 設定に技術情報が隔離され、愛犬プロフィールが編集できる', async () => {
    render(<App />)

    // ホームには電池・温度が無い
    expect(document.body.textContent).not.toContain('電池')

    // 設定タブ → デバイス情報
    fireEvent.click(screen.getAllByText('設定')[0])
    await tick(10)
    expect(document.body.textContent).toContain('電池')
    expect(document.body.textContent).toContain('データソース')

    // 愛犬タブ → 名前を変更して保存 → ヘッダに反映
    fireEvent.click(screen.getAllByText('愛犬')[0])
    await tick(10)
    const nameInput = document.querySelector('.form input') as HTMLInputElement
    fireEvent.change(nameInput, { target: { value: 'ハチ' } })
    fireEvent.click(screen.getByText('保存'))
    await tick(10)
    expect(document.querySelector('.header h1')!.textContent).toBe('ハチ')
  })

  it('履歴はlocalStorageに永続化され、リロード後も評価が表示される', async () => {
    render(<App />)
    fireEvent.click(screen.getByText('測定をはじめる'))
    await tick(900)
    await tick(3300)
    fireEvent.click(screen.getByText('終了する'))
    await tick(1700)
    fireEvent.click(screen.getByText('ホームに戻る'))
    await tick(50)

    cleanup()
    location.hash = ''
    render(<App />) // リロード相当
    expect(document.querySelector('.home-words .phrase')!.textContent).not.toBe(
      'はじめての測定をしてみましょう',
    )
  })
})
