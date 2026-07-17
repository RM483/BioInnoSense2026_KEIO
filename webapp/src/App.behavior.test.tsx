/**
 * App動作検証 (jsdom + MockProvider実物)。
 * 「実際に動くこと」の確認: 接続→測定→1Hz更新→停止→履歴。
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

  it('接続→測定開始で水素濃度が1秒毎に更新され、温湿度・電池・状態も表示される', async () => {
    render(<App />)

    // 初期状態
    expect(screen.getByText('未接続')).toBeTruthy()
    expect(document.querySelector('.hero .value')!.textContent).toBe('––')

    // 接続 (Mockは700ms遅延)
    fireEvent.click(screen.getByText('デバイスに接続'))
    await tick(10)
    expect(screen.getByText('接続処理中…')).toBeTruthy() // 接続中の状態表示
    await tick(800)
    expect(screen.getByText('接続中')).toBeTruthy()

    // 測定開始
    fireEvent.click(screen.getByText('測定をはじめる'))
    await tick(100) // ACK
    expect(screen.getByText('停止')).toBeTruthy()

    // 1秒毎の更新: 現在値が '––' でなくなる
    await tick(1100)
    const value1 = document.querySelector('.hero .value')!.textContent!
    expect(value1).not.toBe('––')
    expect(screen.getByText('ウォームアップ中（参考値）')).toBeTruthy()

    // さらに2秒 → 値が変化(1Hz更新)
    await tick(2100)
    const value2 = document.querySelector('.hero .value')!.textContent!
    expect(value2).not.toBe(value1)

    // 温度・湿度・電池の表示
    const nums = [...document.querySelectorAll('.metric .num')].map(
      (e) => e.textContent,
    )
    expect(nums).toHaveLength(4)
    // 最大/温度/湿度は表示中 (平均はウォームアップ60s間は参考値扱いで '––')
    expect(nums.slice(1).every((n) => n && n !== '––')).toBe(true)
    const battery = [...document.querySelectorAll('.kv .row')].find((r) =>
      r.textContent!.includes('電池'),
    )!
    expect(battery.textContent).toMatch(/\d+%/)
    // デバイス状態
    expect(screen.getByText('測定中')).toBeTruthy()

    // グラフがリアルタイム描画されている (SVG path が伸びる)
    const d1 = document.querySelector('svg path[stroke]')!.getAttribute('d')!
    await tick(2100)
    const d2 = document.querySelector('svg path[stroke]')!.getAttribute('d')!
    expect(d2.length).toBeGreaterThan(d1.length)

    // 停止 → 履歴に1件追加
    fireEvent.click(screen.getByText('停止'))
    await tick(200)
    expect(screen.getByText('測定をはじめる')).toBeTruthy()
    expect(document.querySelectorAll('.history-item').length).toBe(1)

    // 切断 → 未接続表示
    fireEvent.click(screen.getByText('切断'))
    await tick(100)
    expect(screen.getByText('未接続')).toBeTruthy()
    expect(screen.getByText('デバイスに接続')).toBeTruthy()
  }, 15000)

  it('履歴はlocalStorageに保存され、リロード後も表示される', async () => {
    render(<App />)
    fireEvent.click(screen.getByText('デバイスに接続'))
    await tick(800)
    fireEvent.click(screen.getByText('測定をはじめる'))
    await tick(3300)
    fireEvent.click(screen.getByText('停止'))
    await tick(200)
    expect(document.querySelectorAll('.history-item').length).toBe(1)

    cleanup()
    render(<App />) // リロード相当
    expect(document.querySelectorAll('.history-item').length).toBe(1)
  })
})
