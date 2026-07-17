/**
 * App動作検証 (jsdom + MockProvider実物)。
 * 「意味が主役」のプロダクト体験: ホーム→測定→ライブ更新→終了→
 * ホームに意味の言葉と履歴が反映される、までを実行して確認する。
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

describe('HydroPaw Web (MockProvider)', () => {
  beforeEach(() => {
    cleanup()
    localStorage.clear()
    vi.useFakeTimers()
  })

  it('ホームは意味の言葉が主役 → 測定中は状態+小さなppm → 終了で履歴と評価に反映', async () => {
    render(<App />)

    // 初期ホーム: 専門用語ではなく促しの言葉
    expect(screen.getByText('はじめての測定をしてみましょう')).toBeTruthy()
    expect(screen.getAllByText('未接続').length).toBeGreaterThan(0)
    expect(document.querySelector('.metric')).toBeNull() // 数値タイルは無い

    // 測定開始(未接続なら自動で接続してから開始)
    fireEvent.click(screen.getByText('測定をはじめる'))
    await tick(10)
    expect(screen.getByText('接続しています…')).toBeTruthy()
    await tick(900) // 接続700ms + ACK
    expect(screen.getByText('接続中')).toBeTruthy()
    expect(screen.getByText('測定中')).toBeTruthy()

    // ライブ更新: 状態の言葉 + 小さなppm
    await tick(1100)
    const ppm1 = document.querySelector('.value-sub')!.textContent!
    expect(ppm1).toMatch(/ppm/)
    expect(screen.getByText('ウォームアップ中（参考値）')).toBeTruthy()
    expect(['安定', 'やや高め', '高め']).toContain(
      document.querySelector('.live .phrase')!.textContent,
    )

    // 1Hzで値が動く
    await tick(2100)
    const ppm2 = document.querySelector('.value-sub')!.textContent!
    expect(ppm2).not.toBe(ppm1)

    // グラフが伸びる
    const d1 = document.querySelector('svg path[stroke]')!.getAttribute('d')!
    await tick(2100)
    const d2 = document.querySelector('svg path[stroke]')!.getAttribute('d')!
    expect(d2.length).toBeGreaterThan(d1.length)

    // 終了 → ホームへ戻り、意味の言葉 + 履歴 + 最終測定時刻
    fireEvent.click(screen.getByText('終了する'))
    await tick(200)
    expect(screen.getByText('測定をはじめる')).toBeTruthy()
    expect(document.querySelectorAll('.history-item').length).toBe(1)
    expect(
      ['今日は安定しています', '少し高めです。様子を見ましょう', '高めの値が続いています'],
    ).toContain(document.querySelector('.hero .phrase')!.textContent)
    expect(document.querySelector('.last-measured')!.textContent).toContain(
      '最終測定',
    )

    // 技術情報(温湿度・電池)は「詳細」カードに隔離されている
    const details = document.querySelector('.details')!
    expect(details.textContent).toMatch(/温度/)
    expect(details.textContent).toMatch(/電池.*\d+%/)
  }, 15000)

  it('履歴はlocalStorageに保存され、リロード後も評価が表示される', async () => {
    render(<App />)
    fireEvent.click(screen.getByText('測定をはじめる'))
    await tick(900)
    await tick(3300)
    fireEvent.click(screen.getByText('終了する'))
    await tick(200)
    expect(document.querySelectorAll('.history-item').length).toBe(1)

    cleanup()
    render(<App />) // リロード相当
    expect(document.querySelectorAll('.history-item').length).toBe(1)
    expect(document.querySelector('.hero .phrase')!.textContent).not.toBe(
      'はじめての測定をしてみましょう',
    )
  })
})
