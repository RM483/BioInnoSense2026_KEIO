/**
 * 多頭飼い対応の犬ストア (localStorage)。
 *
 * 犬は3状態で扱う (docs/21 v2.1):
 *  A. 未設定プロフィール … name が空。ホームに出さず、頭数にも数えない
 *  B. 設定済み・記録なし … 見守り中ならホームに表示。完全削除可(警告つき)
 *  C. 設定済み・記録あり … 完全削除不可。「見守りを終了」(archived) のみ
 *
 * maxDogs = 見守れる上限。初回起動時に質問し、Settingsで変更できる。
 * 上限に数えるのは「見守り中(=名前あり && !archived)」の犬だけ。
 */
export interface Dog {
  id: string
  name: string
  breed: string
  weightKg: string
  birthYear: string
  /** 見守りを終了した犬 (データは保持し、ホーム/測定対象から外す) */
  archived?: boolean
  /** 愛犬写真 (正方形JPEGのdataURL §6)。未登録は肉球アイコン */
  photo?: string
}

/** 操作文言などで名前を安全に表示する(空なら「この愛犬」 §5) */
export const dogLabel = (d: Dog): string =>
  d.name.trim() !== '' ? d.name : 'この愛犬'

export interface DogsState {
  dogs: Dog[]
  selectedId: string
  /** 見守る犬の上限。null = 初回設定が未回答 */
  maxDogs: number | null
}

const KEY = 'hydropaw.dogs.v1'
const LEGACY_KEY = 'hydropaw.dog.v1'

export const defaultDog: Dog = {
  id: 'dog-1',
  name: 'ポチ',
  breed: '柴犬',
  weightKg: '8.2',
  birthYear: '2022',
}

/** プロフィール設定完了 = 名前が保存されている */
export const isComplete = (d: Dog): boolean => d.name.trim() !== ''

/** 見守り中 = 設定完了かつ見守り終了していない */
export const isWatching = (d: Dog): boolean => isComplete(d) && !d.archived

export const watchingDogs = (s: DogsState): Dog[] => s.dogs.filter(isWatching)

export const archivedDogs = (s: DogsState): Dog[] =>
  s.dogs.filter((d) => isComplete(d) && d.archived === true)

/** 未設定プロフィール(名前が空のまま保存されてしまったもの) */
export const draftDogs = (s: DogsState): Dog[] =>
  s.dogs.filter((d) => !isComplete(d))

export function loadDogs(): DogsState {
  try {
    const raw = localStorage.getItem(KEY)
    if (raw) {
      const s = JSON.parse(raw) as Partial<DogsState>
      if (Array.isArray(s.dogs) && s.dogs.length > 0) {
        return normalize({
          dogs: s.dogs,
          selectedId: s.selectedId ?? s.dogs[0].id,
          maxDogs: typeof s.maxDogs === 'number' ? s.maxDogs : null,
        })
      }
    }
    // ---- 旧単頭ストアからの移行 ----
    const legacy = localStorage.getItem(LEGACY_KEY)
    if (legacy) {
      const p = JSON.parse(legacy)
      const dog: Dog = { ...defaultDog, ...p, id: 'dog-1' }
      const s: DogsState = { dogs: [dog], selectedId: dog.id, maxDogs: null }
      saveDogs(s)
      return s
    }
  } catch {
    /* 破損時は既定値 */
  }
  return { dogs: [defaultDog], selectedId: defaultDog.id, maxDogs: null }
}

/** 選択IDが見守り中でない場合、安全な犬へフォールバックする */
export function normalize(s: DogsState): DogsState {
  const watching = watchingDogs(s)
  if (watching.some((d) => d.id === s.selectedId)) return s
  return { ...s, selectedId: watching[0]?.id ?? '' }
}

export function saveDogs(s: DogsState): void {
  localStorage.setItem(KEY, JSON.stringify(s))
}

/** 選択中の犬(見守り中のみ)。0頭ならnull */
export function selectedDog(s: DogsState): Dog | null {
  return watchingDogs(s).find((d) => d.id === s.selectedId) ?? null
}

export function newDogId(s: DogsState): string {
  const n = s.dogs.reduce((max, d) => {
    const m = /^dog-(\d+)$/.exec(d.id)
    return m ? Math.max(max, parseInt(m[1], 10)) : max
  }, 0)
  return `dog-${n + 1}`
}

export function ageLabel(d: Dog): string {
  const y = parseInt(d.birthYear, 10)
  if (!Number.isFinite(y)) return ''
  const age = new Date().getFullYear() - y
  return age >= 0 && age < 30 ? `${age}歳` : ''
}
