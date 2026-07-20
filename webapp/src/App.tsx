/**
 * HydroPaw — 犬の健康を毎日そっと見守るプロダクト (SPA)。
 *
 * IA v2.1 (docs/21, Flutter版と同一):
 *   3タブ(ホーム/愛犬/設定)。ホーム=測定の入口+見守り中の犬の左右スワイプ切替。
 *   測定はフルスクリーンの「イベント」で、開始前に対象犬を確認し、開始時点で
 *   対象犬を固定する。愛犬タブは縦一覧で管理(削除/見守り終了/再開/追加)。
 *   見守る犬の上限(maxDogs)は初回に質問し、設定で変更できる。
 * データはDataProvider(Mock/BLE)経由 — 切替は providers/index.ts の1箇所。
 */
import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { GearIcon, HeartIcon, HouseIcon, PawIcon } from './components/icons'
import type {
  ConnectionStatus,
  SensorSample,
  SessionSummary,
} from './providers/DataProvider'
import { createProvider } from './providers'
import {
  archivedDogs,
  dogLabel,
  draftDogs,
  isComplete,
  loadDogs,
  newDogId,
  normalize,
  saveDogs,
  selectedDog,
  watchingDogs,
  type Dog,
  type DogsState,
} from './lib/dogs'
import {
  dayKeyOf,
  loadNotes,
  noteDayKey,
  notesOfDay,
  saveNotes,
  type CareNote,
} from './lib/careNotes'
import { DogsView } from './dogsView'
import { JournalView, NoteSheet, type DayEntryInput } from './journal'
import {
  ConfirmSheet,
  FirstRunSheet,
  LimitSheet,
  MeasureConfirmSheet,
  ReduceSheet,
} from './sheets'
import { HomeView, MeasureFlow, SettingsView, type FlowPhase } from './views'

const MAX_SAMPLES = 1800
const HISTORY_KEY = 'hydropaw.history.v1'
const MIN_ANALYZING_MS = 1400

type Tab = 'home' | 'dogs' | 'settings'
type Route = Tab | 'history'

const TABS: { id: Tab; label: string; icon: (p: { size?: number }) => JSX.Element }[] = [
  { id: 'home', label: 'ホーム', icon: HouseIcon },
  { id: 'dogs', label: '愛犬', icon: HeartIcon },
  { id: 'settings', label: '設定', icon: GearIcon },
]

const tabOf = (r: Route): Tab => (r === 'history' ? 'home' : r)

function routeFromHash(): Route {
  const h = location.hash.replace('#/', '')
  if ((['home', 'dogs', 'settings', 'history'] as Route[]).includes(h as Route)) {
    return h as Route
  }
  if (h === 'dog') return 'dogs'
  return 'home'
}

/** モーダル(シート)の排他状態 */
type Sheet =
  | { kind: 'none' }
  | { kind: 'note' }
  | { kind: 'measureConfirm'; dog: Dog }
  | { kind: 'deleteDog'; dog: Dog }
  | { kind: 'endWatch'; dog: Dog }
  | { kind: 'limit'; title: string; body: string }
  | { kind: 'reduce'; newMax: number }
  // 減数時の最終確認 (§10): ここで確定するまで状態は変えない
  | { kind: 'reduceConfirm'; newMax: number; dog: Dog }

export default function App() {
  const provider = useMemo(createProvider, [])
  const [route, setRoute] = useState<Route>(routeFromHash)
  const [conn, setConn] = useState<ConnectionStatus>('disconnected')
  const [flow, setFlow] = useState<FlowPhase | null>(null)
  const [samples, setSamples] = useState<SensorSample[]>([])
  const [history, setHistory] = useState<SessionSummary[]>(loadHistory)
  const [notes, setNotes] = useState<CareNote[]>(loadNotes)
  const [result, setResult] = useState<SessionSummary | null>(null)
  const [dogState, setDogState] = useState<DogsState>(loadDogs)
  const [sheet, setSheet] = useState<Sheet>({ kind: 'none' })
  const [busy, setBusy] = useState(false)
  const [notice, setNotice] = useState<string | null>(null)
  const noticeTimer = useRef<number | undefined>(undefined)
  const showNotice = useCallback((m: string) => {
    setNotice(m)
    window.clearTimeout(noticeTimer.current)
    noticeTimer.current = window.setTimeout(() => setNotice(null), 4500)
  }, [])
  const sessionStart = useRef<Date | null>(null)
  /** 測定対象は開始時点で固定する (§3) — スワイプで切り替わっても変わらない */
  const sessionDogId = useRef<string>('')
  const latest = samples.at(-1) ?? null

  const watching = watchingDogs(dogState)
  const dog = selectedDog(dogState) // 見守り中0頭ならnull
  const dogIndex = Math.max(0, watching.findIndex((d) => d.id === dog?.id))
  const maxDogs = dogState.maxDogs ?? 1

  // ---- 選択中の犬でスコープしたデータ(dogId無しは旧データとして全犬に表示) ----
  const dogHistory = useMemo(
    () => (dog ? history.filter((h) => !h.dogId || h.dogId === dog.id) : []),
    [history, dog],
  )
  const dogNotes = useMemo(
    () => (dog ? notes.filter((n) => n.dogId === dog.id) : []),
    [notes, dog],
  )

  /** 記録の有無 — 削除可否の判定 (§5)。測定・日誌のどちらか1件でもあれば真 */
  const hasRecords = useCallback(
    (dogId: string) =>
      history.some((h) => h.dogId === dogId) ||
      notes.some((n) => n.dogId === dogId),
    [history, notes],
  )

  // ---- SPAルーティング (hash) ----
  useEffect(() => {
    const onHash = () => setRoute(routeFromHash())
    window.addEventListener('hashchange', onHash)
    return () => window.removeEventListener('hashchange', onHash)
  }, [])

  const go = useCallback((r: Route) => {
    location.hash = `#/${r}`
    setRoute(r)
    window.scrollTo({ top: 0 })
  }, [])

  // ---- Provider購読 ----
  useEffect(() => {
    const offConn = provider.onConnection(setConn)
    const offSample = provider.onSample((s) =>
      setSamples((prev) => {
        const next = [...prev, s]
        return next.length > MAX_SAMPLES ? next.slice(-MAX_SAMPLES) : next
      }),
    )
    return () => {
      offConn()
      offSample()
    }
  }, [provider])

  // ---- 犬の状態更新(保存+選択の安全化 §15) ----
  const updateDogs = useCallback((next: DogsState) => {
    const n = normalize(next)
    saveDogs(n)
    setDogState(n)
  }, [])

  // ---- 測定フロー ----
  /** CTA → 対象犬の確認シート (§3) */
  const requestMeasurement = useCallback(() => {
    if (!dog) return
    setSheet({ kind: 'measureConfirm', dog })
  }, [dog])

  /** 確認後: 対象犬を固定して開始 */
  const startMeasurement = useCallback(
    async (target: Dog) => {
      setSheet({ kind: 'none' })
      setBusy(true)
      try {
        if (conn !== 'connected') await provider.connect()
        setSamples([])
        sessionStart.current = new Date()
        sessionDogId.current = target.id // ここで固定 — 以後スワイプ不可(フルスクリーン)
        await provider.startMeasurement()
        setFlow('measuring')
      } catch (e) {
        console.error(e)
        showNotice('接続できませんでした。デバイスの電源を確認して、もういちどお試しください')
      } finally {
        setBusy(false)
      }
    },
    [provider, conn, showNotice],
  )

  const finishMeasurement = useCallback(async () => {
    setFlow('analyzing')
    const t0 = Date.now()
    const raw =
      (await provider.stopMeasurement()) ??
      localSummary(samples, sessionStart.current)
    // 保存先は開始時に固定した犬 (§3, §15)
    const summary = raw ? { ...raw, dogId: sessionDogId.current } : null
    if (summary && summary.sampleCount > 0) {
      setHistory((prev) => {
        const next = [summary, ...prev].slice(0, 100)
        localStorage.setItem(HISTORY_KEY, JSON.stringify(next))
        return next
      })
      setResult(summary)
    }
    const wait = Math.max(0, MIN_ANALYZING_MS - (Date.now() - t0))
    setTimeout(() => setFlow(summary ? 'result' : null), wait)
  }, [provider, samples])

  const closeFlow = useCallback(() => {
    setFlow(null)
    setResult(null)
    go('home')
  }, [go])

  // ---- 健康日誌 (v2.3: 1日1件・まとめ保存) ----
  /**
   * きょうの記録をまとめてupsertする (§2,4)。
   * カテゴリごとに「今日の既存レコードがあれば更新、なければ追加」。
   * 同じ日に同じカテゴリの行を重複追加しない。旧重複データは削除しない (§19)。
   */
  const saveDayNotes = useCallback(
    (entries: DayEntryInput[]) => {
      if (!dog) return
      const todayKey = dayKeyOf(new Date())
      setNotes((prev) => {
        const next = [...prev]
        for (const e of entries) {
          const idx = next.findIndex(
            (n) =>
              n.dogId === dog.id &&
              n.type === e.type &&
              noteDayKey(n) === todayKey,
          )
          if (idx >= 0) {
            // 既存(最新)を更新 — 別カテゴリの内容には触れない (§20)
            next[idx] = {
              ...next[idx],
              choice: e.choice,
              memo: e.memo,
              schema: 2,
            }
          } else {
            next.unshift({
              id: `n-${Date.now()}-${e.type}`,
              dogId: dog.id,
              at: new Date().toISOString(),
              type: e.type,
              choice: e.choice,
              memo: e.memo,
              schema: 2,
            })
          }
        }
        saveNotes(next)
        return next
      })
      setSheet({ kind: 'none' })
      showNotice('きょうの記録を保存しました')
    },
    [dog, showNotice],
  )

  /** その日の健康日誌をすべて削除する。測定結果は削除しない (§15,20) */
  const deleteDayJournal = useCallback(
    (dayKey: string) => {
      if (!dog) return
      setNotes((prev) => {
        const next = prev.filter(
          (n) => !(n.dogId === dog.id && noteDayKey(n) === dayKey),
        )
        saveNotes(next)
        return next
      })
    },
    [dog],
  )

  /** 当日の既存記録(カテゴリ別最新) — シートを編集状態で開くために使う (§4) */
  const todayNotes = useMemo(
    () =>
      dog
        ? notesOfDay(notes, dog.id, dayKeyOf(new Date()))
        : new Map<CareNote['type'], CareNote>(),
    [notes, dog],
  )

  // ---- 犬の管理 (§5-7, §11-13) ----
  const limitBody = (name?: string) =>
    name
      ? `${name}の見守りを再開するには、設定から見守る犬の数を変更してください。`
      : `現在の設定では、${maxDogs}頭まで見守れます。新しい犬を追加する場合は、設定から見守る犬の数を変更してください。`

  /** 追加ボタン: 上限内ならフォームを開かせる (§11) */
  const requestAddDog = useCallback((): boolean => {
    if (watching.length >= maxDogs) {
      setSheet({ kind: 'limit', title: '登録できる犬の数に達しています', body: limitBody() })
      return false
    }
    return true
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [watching.length, maxDogs])

  /** 名前を入力して保存した時点で正式に作成 (§5A) */
  const createDog = useCallback(
    (d: Omit<Dog, 'id'>) => {
      if (!isComplete(d as Dog)) return
      const id = newDogId(dogState)
      updateDogs({
        ...dogState,
        dogs: [...dogState.dogs, { ...d, id, archived: false }],
        selectedId: dogState.selectedId || id,
      })
      showNotice(`${d.name}を登録しました`)
    },
    [dogState, updateDogs, showNotice],
  )

  const saveDog = useCallback(
    (d: Dog) =>
      updateDogs({
        ...dogState,
        dogs: dogState.dogs.map((x) => (x.id === d.id ? d : x)),
      }),
    [dogState, updateDogs],
  )

  /** 完全削除 — 記録なし/未設定のみ。実行前に必ず確認 (§5A,5B) */
  const deleteDog = useCallback(
    (d: Dog) => {
      if (hasRecords(d.id)) return // 防御 (§15)
      updateDogs({
        ...dogState,
        dogs: dogState.dogs.filter((x) => x.id !== d.id),
      })
      setSheet({ kind: 'none' })
    },
    [dogState, hasRecords, updateDogs],
  )

  /** 見守り終了 — データは残す (§5C,6) */
  const endWatch = useCallback(
    (d: Dog) => {
      updateDogs({
        ...dogState,
        dogs: dogState.dogs.map((x) =>
          x.id === d.id ? { ...x, archived: true } : x,
        ),
      })
      setSheet({ kind: 'none' })
    },
    [dogState, updateDogs],
  )

  /** 見守り再開 — 上限に空きがなければ設定へ誘導 (§7) */
  const resumeDog = useCallback(
    (d: Dog) => {
      if (watching.length >= maxDogs) {
        setSheet({
          kind: 'limit',
          title: '見守る犬の数に達しています',
          body: limitBody(d.name),
        })
        return
      }
      updateDogs({
        ...dogState,
        dogs: dogState.dogs.map((x) =>
          x.id === d.id ? { ...x, archived: false } : x,
        ),
        selectedId: dogState.selectedId || d.id,
      })
      showNotice(`${d.name}の見守りを再開しました`)
    },
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [dogState, watching.length, maxDogs, updateDogs, showNotice],
  )

  /** 上限変更 (§11-13)。増やす=即時+短い通知 / 減らして超過=選択フローへ */
  const changeMaxDogs = useCallback(
    (n: number) => {
      if (n < 1) return
      if (n < watching.length) {
        setSheet({ kind: 'reduce', newMax: n })
        return
      }
      updateDogs({ ...dogState, maxDogs: n })
      if (n > (dogState.maxDogs ?? 0)) {
        showNotice(`${n}頭まで見守れるようになりました`) // §11: 確認なし・即時
      }
    },
    [dogState, watching.length, updateDogs, showNotice],
  )

  /** 最終確認(§10)を経てから、見守り終了+上限変更を同時に適用する */
  const applyReduce = useCallback(
    (newMax: number, archiveId: string) => {
      updateDogs({
        ...dogState,
        maxDogs: newMax,
        dogs: dogState.dogs.map((x) =>
          x.id === archiveId ? { ...x, archived: true } : x,
        ),
      })
      setSheet({ kind: 'none' })
    },
    [dogState, updateDogs],
  )

  const connect = useCallback(async () => {
    setBusy(true)
    try {
      await provider.connect()
    } catch (e) {
      console.error(e)
      showNotice('接続できませんでした。デバイスの電源を確認して、もういちどお試しください')
    } finally {
      setBusy(false)
    }
  }, [provider, showNotice])

  const disconnect = useCallback(async () => {
    setBusy(true)
    try {
      await provider.disconnect()
    } finally {
      setBusy(false)
    }
  }, [provider])

  const today = useMemo(
    () =>
      new Intl.DateTimeFormat('ja-JP', {
        month: 'long',
        day: 'numeric',
        weekday: 'short',
      }).format(new Date()),
    [],
  )

  const tab = tabOf(route)
  // 画面タイトル: 日付 + 画面名 (§3,4)。犬の名前はページタイトルにしない
  const pageTitle = switchTitle(route, dog)

  return (
    <div className="app">
      {/* ---- ヘッダ ---- */}
      <header className={`header ${route === 'home' ? 'home-mode' : ''}`}>
        <div className="brand-avatar">
          <PawIcon size={22} />
        </div>
        <div className="titles">
          <div className="date">{today}</div>
          <h1>{pageTitle}</h1>
        </div>
        <nav className="tabbar top" aria-label="ナビゲーション">
          {TABS.map(({ id, label, icon: Icon }) => (
            <button
              key={id}
              className={`tab ${tab === id ? 'active' : ''}`}
              onClick={() => go(id)}
            >
              <Icon size={20} />
              <span>{label}</span>
            </button>
          ))}
        </nav>
      </header>

      {/* ---- ビュー ---- */}
      {route === 'home' && (
        <HomeView
          dogs={watching}
          index={dogIndex}
          historyFor={(id) =>
            history.filter((h) => !h.dogId || h.dogId === id)
          }
          conn={conn}
          busy={busy}
          onIndex={(i) => {
            const d = watching[i]
            if (d) updateDogs({ ...dogState, selectedId: d.id })
          }}
          onStart={(d) => setSheet({ kind: 'measureConfirm', dog: d })}
          onOpenHistory={() => go('history')}
          onAddNote={() => setSheet({ kind: 'note' })}
          onRegisterDog={() => go('dogs')}
        />
      )}
      {route === 'history' && (
        <JournalView
          history={dogHistory}
          notes={dogNotes}
          onBack={() => go('home')}
          onEditToday={() => setSheet({ kind: 'note' })}
          onDeleteDay={deleteDayJournal}
          onStartMeasure={requestMeasurement}
        />
      )}
      {route === 'dogs' && (
        <DogsView
          watching={watching}
          archived={archivedDogs(dogState)}
          drafts={draftDogs(dogState)}
          maxDogs={maxDogs}
          hasRecords={hasRecords}
          onSave={saveDog}
          onCreate={createDog}
          onDelete={(d) => setSheet({ kind: 'deleteDog', dog: d })}
          onEndWatch={(d) => setSheet({ kind: 'endWatch', dog: d })}
          onResume={resumeDog}
          onAddRequest={requestAddDog}
        />
      )}
      {route === 'settings' && (
        <SettingsView
          conn={conn}
          providerName={provider.name}
          latest={latest}
          busy={busy}
          maxDogs={maxDogs}
          watchingCount={watching.length}
          onChangeMaxDogs={changeMaxDogs}
          onConnect={connect}
          onDisconnect={disconnect}
          onClearHistory={() => {
            localStorage.removeItem(HISTORY_KEY)
            setHistory([])
          }}
        />
      )}

      {/* ---- 下部タブバー ---- */}
      <nav className="tabbar bottom" aria-label="ナビゲーション">
        {TABS.map(({ id, label, icon: Icon }) => (
          <button
            key={id}
            className={`tab ${tab === id ? 'active' : ''}`}
            onClick={() => go(id)}
          >
            <Icon size={22} />
            <span>{label}</span>
          </button>
        ))}
      </nav>

      {/* ---- 非ブロッキング通知 ---- */}
      {notice && (
        <div className="toast" role="status" aria-live="polite">
          {notice}
        </div>
      )}

      {/* ---- 初回設定: 頭数の質問 (§9) ---- */}
      {dogState.maxDogs === null && !flow && (
        <FirstRunSheet
          onDone={(n) => updateDogs({ ...dogState, maxDogs: n })}
        />
      )}

      {/* ---- シート群 ---- */}
      {/* きょうの記録: まとめ入力・当日は編集として開く (§2,4,16) */}
      {sheet.kind === 'note' && dog && (
        <NoteSheet
          existing={todayNotes}
          onSave={saveDayNotes}
          onClose={() => setSheet({ kind: 'none' })}
        />
      )}
      {sheet.kind === 'measureConfirm' && (
        <MeasureConfirmSheet
          dog={sheet.dog}
          onStart={() => startMeasurement(sheet.dog)}
          onClose={() => setSheet({ kind: 'none' })}
        />
      )}
      {sheet.kind === 'deleteDog' && (
        <ConfirmSheet
          title={`${dogLabel(sheet.dog)}のプロフィールを削除しますか？`}
          body="入力済みのプロフィール情報が削除され、元に戻せません。"
          confirmLabel="削除する"
          danger
          dog={sheet.dog}
          onConfirm={() => deleteDog(sheet.dog)}
          onClose={() => setSheet({ kind: 'none' })}
        />
      )}
      {sheet.kind === 'endWatch' && (
        <ConfirmSheet
          title={`${dogLabel(sheet.dog)}の見守りを終了しますか？`}
          body={`見守りを終了すると、${dogLabel(sheet.dog)}はホーム画面の犬の切り替えや、新しい測定の対象に表示されなくなります。これまでの測定結果や健康日誌は削除されず、後から見守りを再開できます。`}
          confirmLabel="見守りを終了する"
          dog={sheet.dog}
          onConfirm={() => endWatch(sheet.dog)}
          onClose={() => setSheet({ kind: 'none' })}
        />
      )}
      {sheet.kind === 'limit' && (
        <LimitSheet
          title={sheet.title}
          body={sheet.body}
          onOpenSettings={() => {
            setSheet({ kind: 'none' })
            go('settings')
          }}
          onClose={() => setSheet({ kind: 'none' })}
        />
      )}
      {sheet.kind === 'reduce' && (
        <ReduceSheet
          watching={watching}
          onConfirm={(id) => {
            // ここでは確定しない — 最終確認へ (§10)
            const d = watching.find((x) => x.id === id)
            if (d) {
              setSheet({ kind: 'reduceConfirm', newMax: sheet.newMax, dog: d })
            }
          }}
          onClose={() => setSheet({ kind: 'none' })}
        />
      )}
      {sheet.kind === 'reduceConfirm' && (
        <ConfirmSheet
          title={`${dogLabel(sheet.dog)}の見守りを終了しますか？`}
          body={`見守りを終了すると、${dogLabel(sheet.dog)}はホーム画面の犬の切り替えや、新しい測定の対象に表示されなくなります。これまでの測定結果や健康日誌は削除されず、後から見守りを再開できます。`}
          confirmLabel="見守りを終了して変更"
          dog={sheet.dog}
          onConfirm={() => applyReduce(sheet.newMax, sheet.dog.id)}
          onClose={() => setSheet({ kind: 'none' })}
        />
      )}

      {/* ---- 測定フロー (フルスクリーンイベント) ---- */}
      {flow && (
        <MeasureFlow
          phase={flow}
          samples={samples}
          dogName={
            dogState.dogs.find((d) => d.id === sessionDogId.current)?.name ??
            ''
          }
          result={result}
          onFinish={finishMeasurement}
          onDone={closeFlow}
        />
      )}
    </div>
  )
}

/* ---------- ヘルパ ---------- */

function localSummary(
  samples: SensorSample[],
  started: Date | null,
): SessionSummary | null {
  if (samples.length === 0) return null
  const valid = samples.filter((s) => (s.flags & 0x03) === 0)
  const ppbs = valid.map((s) => s.hydrogen_ppb)
  const startedAt = started ?? new Date(samples[0].timestamp)
  return {
    startedAt: startedAt.toISOString(),
    durationS: Math.round((Date.now() - startedAt.getTime()) / 1000),
    sampleCount: valid.length,
    avgPpb: ppbs.length
      ? Math.round(ppbs.reduce((a, b) => a + b, 0) / ppbs.length)
      : 0,
    maxPpb: ppbs.length ? Math.max(...ppbs) : 0,
    minPpb: ppbs.length ? Math.min(...ppbs) : 0,
  }
}

function loadHistory(): SessionSummary[] {
  try {
    return JSON.parse(localStorage.getItem(HISTORY_KEY) ?? '[]')
  } catch {
    return []
  }
}

/** 画面タイトル (§3,4)。homeはヘッダー非表示のため実質未使用 */
function switchTitle(route: Route, dog: Dog | null): string {
  switch (route) {
    case 'dogs':
      return '愛犬'
    case 'settings':
      return '設定'
    case 'history':
      return dog?.name ?? '日誌'
    default:
      return dog?.name ?? 'HydroPaw'
  }
}
