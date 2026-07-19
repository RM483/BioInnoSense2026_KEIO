/**
 * SPA動作検証 (jsdom + MockProvider実物) — IA v2.1 (docs/21)。
 * 初回設定 → ホーム(犬切替/確認つき測定) → 日誌 → 犬管理(削除/見守り終了/再開/上限)。
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

/** 起動 + 初回設定(頭数)を回答する */
async function boot(headCount = 1) {
  render(<App />)
  await tick(10)
  if (headCount > 1) {
    fireEvent.click(screen.getByText(`${headCount}頭`))
  }
  fireEvent.click(screen.getByText('はじめる'))
  await tick(10)
}

/** ホームのCTA → 対象犬の確認 → 測定開始 */
async function startMeasure(dogName: string) {
  fireEvent.click(screen.getByText(`${dogName}の測定をはじめる`))
  await tick(10)
  expect(screen.getByText(`${dogName}を測定します`)).toBeTruthy() // 確認 (§3)
  fireEvent.click(screen.getByText('測定を開始'))
  await tick(10)
}

describe('HydroPaw Web SPA (MockProvider, IA v2.1)', () => {
  beforeEach(() => {
    cleanup()
    localStorage.clear()
    location.hash = ''
    vi.useFakeTimers()
  })

  it('測定イベント: 確認→測定中→解析中→結果→ホーム反映→日誌', async () => {
    await boot()

    // ホーム: 意味の言葉が主役、CTAは名前入りで1つ (§1,3)
    expect(screen.getByText('はじめての測定をしてみましょう')).toBeTruthy()
    expect(screen.getByText('ポチの測定をはじめる')).toBeTruthy()
    expect(document.querySelector('.overlay')).toBeNull()

    await startMeasure('ポチ')
    expect(screen.getByText('接続しています…')).toBeTruthy()
    await tick(900)

    // フルスクリーンの測定中ビュー
    expect(document.querySelector('.overlay')).toBeTruthy()
    await tick(1100)
    expect(document.querySelector('.ring-word')!.textContent).toBe('…')
    const ppm1 = document.querySelector('.ring-ppm')!.textContent!
    expect(ppm1).toMatch(/ppm/)
    await tick(2100)
    expect(document.querySelector('.ring-ppm')!.textContent).not.toBe(ppm1)

    // 終了 → 解析中(最低1.4s) → 結果
    fireEvent.click(screen.getByText('終了する'))
    await tick(200)
    expect(screen.getByText('解析しています…')).toBeTruthy()
    await tick(1500)
    expect(screen.getByText('測定できました')).toBeTruthy()

    // ホームへ → 評価が更新される
    fireEvent.click(screen.getByText('ホームに戻る'))
    await tick(50)
    expect(document.querySelector('.overlay')).toBeNull()
    expect(
      ['今日は安定しています', '少し高めです。様子を見ましょう', '高めの値が続いています'],
    ).toContain(document.querySelector('.home-words .phrase')!.textContent)

    // 記録はポチのデータとして保存されている (§3,15)
    const saved = JSON.parse(localStorage.getItem('hydropaw.history.v1')!)
    expect(saved[0].dogId).toBe('dog-1')

    // 日誌はホーム配下
    fireEvent.click(screen.getByText('履歴を見る'))
    await tick(10)
    expect(screen.getByText('日誌')).toBeTruthy()
    expect(document.querySelectorAll('.history-item').length).toBeGreaterThan(0)
  }, 15000)

  it('3タブIA: 設定に技術情報+愛犬の登録設定、Dogsは縦一覧で編集できる', async () => {
    await boot()

    const bottomTabs = document.querySelectorAll('.tabbar.bottom .tab')
    expect(bottomTabs.length).toBe(3)

    // 設定: デバイス → 愛犬の登録設定 → データ の順 (§10)
    fireEvent.click(screen.getAllByText('設定')[0])
    await tick(10)
    const labels = Array.from(
      document.querySelectorAll('.card-head .label'),
    ).map((e) => e.textContent)
    expect(labels).toEqual(['測定デバイス', '愛犬の登録設定', 'データ'])
    expect(screen.getByText('見守る愛犬')).toBeTruthy() // v2.2 §7

    // ヘッダーは「日付+設定」— 犬の名前を出さない (v2.2 §4)
    expect(document.querySelector('.header h1')!.textContent).toBe('設定')

    // 愛犬: 縦一覧カード + 編集 (§4)。ヘッダーは「愛犬」(§3)
    fireEvent.click(screen.getAllByText('愛犬')[0])
    await tick(10)
    expect(document.querySelector('.header h1')!.textContent).toBe('愛犬')
    expect(document.querySelector('.dog-card.vertical')).toBeTruthy()
    expect(document.querySelector('.dog-rail')).toBeNull() // 横スワイプ廃止
    fireEvent.click(screen.getAllByText('プロフィールを編集')[0])
    await tick(10)
    const nameInput = document.querySelector('.form label input') as HTMLInputElement
    fireEvent.change(nameInput, { target: { value: 'ハチ' } })
    fireEvent.click(screen.getByText('保存'))
    await tick(10)
    expect(document.querySelector('.dog-name')!.textContent).toBe('ハチ')
  })

  it('ホームの犬切替: 見守り中の犬だけを切り替え、記録は犬ごとにスコープされる', async () => {
    await boot(2) // 上限2頭

    // 記録を1件つける(ポチ)
    fireEvent.click(screen.getByText('きょうの記録'))
    await tick(10)
    // ホームの「きょうのケア」行にも「食欲」があるため、シート内のチップを特定する
    const sheetChip = Array.from(
      document.querySelectorAll('.sheet .select-chip'),
    ).find((el) => el.textContent === '食欲')!
    fireEvent.click(sheetChip)
    fireEvent.click(screen.getByText('気になる'))
    fireEvent.change(document.querySelector('.memo-input')!, {
      target: { value: '朝ごはんを半分残した' },
    })
    fireEvent.click(screen.getByText('保存'))
    await tick(20)
    const notes = JSON.parse(localStorage.getItem('hydropaw.notes.v1')!)
    expect(notes[0].type).toBe('appetite')
    expect(notes[0].rating).toBe('concern')
    expect(notes[0].schema).toBe(1)

    // 犬を追加(名前を入れて保存した時点で正式作成 §5A)
    fireEvent.click(screen.getAllByText('愛犬')[0])
    await tick(10)
    fireEvent.click(screen.getByText('＋ 新しい愛犬を追加'))
    await tick(10)
    fireEvent.change(document.querySelector('.form label input')!, {
      target: { value: 'モカ' },
    })
    fireEvent.click(screen.getByText('保存'))
    await tick(10)
    expect(document.querySelectorAll('.dog-card.vertical').length).toBe(2)

    // ホーム: 犬ごとの全面ページが並び、スワイプ(スクロール)で切替 (v2.2 §2)
    fireEvent.click(screen.getAllByText('ホーム')[0])
    await tick(10)
    const pages = document.querySelectorAll('.home-page')
    expect(pages.length).toBe(2)
    expect(pages[0].textContent).toContain('ポチの測定をはじめる')
    expect(pages[1].textContent).toContain('モカの測定をはじめる')
    expect(pages[0].textContent).toContain('1 / 2')
    expect(pages[1].textContent).toContain('2 / 2')

    // スクロール停止位置で2頭目のページへ確定させる
    const rail = document.querySelector('.home-rail') as HTMLElement
    Object.defineProperty(rail, 'clientWidth', { value: 390 })
    rail.scrollLeft = 390
    fireEvent.scroll(rail)
    await tick(150)

    // モカの日誌にはポチの記録が出ない (§12,15)
    fireEvent.click(screen.getAllByText('履歴を見る')[0])
    await tick(10)
    expect(document.body.textContent).not.toContain('朝ごはんを半分残した')
  })

  it('犬管理: 上限案内→設定で拡張、記録なしは削除警告、記録ありは見守り終了→空状態→再開', async () => {
    await boot(1) // 上限1頭

    // 測定してポチに記録をつける(見守り終了の対象にするため)
    await startMeasure('ポチ')
    await tick(900)
    await tick(3300)
    fireEvent.click(screen.getByText('終了する'))
    await tick(1700)
    fireEvent.click(screen.getByText('ホームに戻る'))
    await tick(50)

    // 上限1頭のまま追加 → 理由と解決方法を提示 (§11)
    fireEvent.click(screen.getAllByText('愛犬')[0])
    await tick(10)
    fireEvent.click(screen.getByText('＋ 新しい愛犬を追加'))
    await tick(10)
    expect(screen.getByText('登録できる犬の数に達しています')).toBeTruthy()
    fireEvent.click(screen.getByText('設定を開く'))
    await tick(10)
    expect(screen.getByText('愛犬の登録設定')).toBeTruthy()
    expect(screen.getByText('見守る愛犬')).toBeTruthy() // v2.2 §7

    // 設定で2頭へ — 確認なしで即時反映+短い通知 (v2.2 §11)
    fireEvent.click(screen.getByLabelText('増やす'))
    await tick(10)
    expect(screen.getByText('2頭')).toBeTruthy()
    expect(document.body.textContent).toContain('2頭まで見守れるようになりました')
    await tick(5000) // トーストの消滅を待つ

    // 記録なしの犬(モカ)を追加 → 削除は名前入り文言+警告つき (§5B, v2.2 §5)
    fireEvent.click(screen.getAllByText('愛犬')[0])
    await tick(10)
    fireEvent.click(screen.getByText('＋ 新しい愛犬を追加'))
    await tick(10)
    fireEvent.change(document.querySelector('.form label input')!, {
      target: { value: 'モカ' },
    })
    fireEvent.click(screen.getByText('保存'))
    await tick(10)
    fireEvent.click(screen.getByText('モカのプロフィールを削除する'))
    await tick(10)
    expect(document.body.textContent).toContain('元に戻せません')
    fireEvent.click(screen.getByText('削除する'))
    await tick(5000) // 登録トーストの消滅も待つ
    expect(document.body.textContent).not.toContain('モカ')

    // 記録ありのポチには削除ではなく名前入りの見守り終了が出る (§5C,6, v2.2 §5)
    expect(screen.queryByText('ポチのプロフィールを削除する')).toBeNull()
    fireEvent.click(screen.getByText('ポチの見守りを終了する'))
    await tick(10)
    expect(document.body.textContent).toContain('後から見守りを再開できます')
    fireEvent.click(screen.getByText('見守りを終了する'))
    await tick(10)

    // 見守りを終了した犬セクションに残り、記録は消えない (§7,15)
    expect(screen.getByText('見守りを終了した犬')).toBeTruthy()
    expect(JSON.parse(localStorage.getItem('hydropaw.history.v1')!).length)
      .toBeGreaterThan(0)

    // ホームは空状態 (§8)
    fireEvent.click(screen.getAllByText('ホーム')[0])
    await tick(10)
    expect(screen.getByText('現在見守っている犬はいません')).toBeTruthy()

    // 再開するとホームに戻ってくる (§7)
    fireEvent.click(screen.getAllByText('愛犬')[0])
    await tick(10)
    fireEvent.click(screen.getByText('見守りを再開する'))
    await tick(10)
    fireEvent.click(screen.getAllByText('ホーム')[0])
    await tick(10)
    expect(screen.getByText('ポチの測定をはじめる')).toBeTruthy()
  }, 20000)

  it('頭数を減らす場合: ラジオ選択→最終確認→適用。キャンセルは無変更 (v2.2 §8-10)', async () => {
    await boot(2)

    // 2頭目を追加
    fireEvent.click(screen.getAllByText('愛犬')[0])
    await tick(10)
    fireEvent.click(screen.getByText('＋ 新しい愛犬を追加'))
    await tick(10)
    fireEvent.change(document.querySelector('.form label input')!, {
      target: { value: 'モカ' },
    })
    fireEvent.click(screen.getByText('保存'))
    await tick(5100) // 登録トースト消滅待ち

    // 設定で1頭へ減らす → 柔らかい文言の選択フロー (§8)
    fireEvent.click(screen.getAllByText('設定')[0])
    await tick(10)
    fireEvent.click(screen.getByLabelText('減らす'))
    await tick(10)
    expect(screen.getByText('見守る愛犬を変更します')).toBeTruthy()
    expect(document.body.textContent).toContain('見守りを終了する愛犬を1頭選んでください')
    expect(document.body.textContent).toContain('これまでの記録は削除されません')

    // ラジオ式単一選択 (§9): 最初はポチが選択済み。モカを押すと即切替
    const radios = () =>
      Array.from(document.querySelectorAll('[role="radio"]')) as HTMLElement[]
    expect(radios()[0].getAttribute('aria-checked')).toBe('true') // ポチ
    fireEvent.click(radios()[1]) // モカを直接タップ
    expect(radios()[1].getAttribute('aria-checked')).toBe('true')
    expect(radios()[0].getAttribute('aria-checked')).toBe('false')
    // 選択中の再タップで未選択にならない
    fireEvent.click(radios()[1])
    expect(radios()[1].getAttribute('aria-checked')).toBe('true')

    // ---- キャンセル: 状態も上限も変わらない (§10) ----
    fireEvent.click(screen.getByText('見守りを終了して変更'))
    await tick(10)
    expect(screen.getByText('モカの見守りを終了しますか？')).toBeTruthy()
    fireEvent.click(screen.getByText('キャンセル'))
    await tick(10)
    expect(document.querySelector('.stepper-value')!.textContent).toBe('2頭') // 上限は2のまま
    fireEvent.click(screen.getAllByText('愛犬')[0])
    await tick(10)
    expect(screen.queryByText('見守りを終了した犬')).toBeNull() // 見守り継続

    // ---- 今度は最終確認まで進めて適用 (§10) ----
    fireEvent.click(screen.getAllByText('設定')[0])
    await tick(10)
    fireEvent.click(screen.getByLabelText('減らす'))
    await tick(10)
    fireEvent.click(
      radios().find((r) => r.textContent === 'モカ')!,
    )
    fireEvent.click(screen.getByText('見守りを終了して変更'))
    await tick(10)
    expect(document.body.textContent).toContain('後から見守りを再開できます')
    fireEvent.click(screen.getAllByText('見守りを終了して変更').at(-1)!)
    await tick(10)

    // リロード相当: 状態が保持される (§12,15)
    cleanup()
    location.hash = ''
    render(<App />)
    await tick(10)
    expect(document.querySelector('.sheet-title')).toBeNull() // 初回設定は出ない
    expect(screen.getByText('ポチの測定をはじめる')).toBeTruthy()
    fireEvent.click(screen.getAllByText('愛犬')[0])
    await tick(10)
    expect(screen.getByText('見守りを終了した犬')).toBeTruthy()
    expect(document.body.textContent).toContain('モカ')
    expect(document.body.textContent).toContain('見守り中 1 / 1頭')
  })
})
