/**
 * Dogsタブ — 犬カードを縦に並べて管理する (docs/21 v2.2 §4-7)。
 *
 * 画面タイトル(日付+「愛犬」)はApp側ヘッダーが表示する。
 * カード操作の文言には犬の名前を入れる(空なら「この愛犬」 §5)。
 * 写真はプロフィール編集の肉球アイコンから登録/撮影/削除できる (§6)。
 */
import { useRef, useState } from 'react'
import { PawIcon } from './components/icons'
import { ageLabel, dogLabel, type Dog } from './lib/dogs'
import { fileToDogPhoto } from './lib/photo'

export function DogsView(props: {
  watching: Dog[]
  archived: Dog[]
  drafts: Dog[] // 名前未設定の残骸(存在する場合のみ表示)
  maxDogs: number
  hasRecords: (dogId: string) => boolean
  onSave: (dog: Dog) => void
  onCreate: (dog: Omit<Dog, 'id'>) => void
  onDelete: (dog: Dog) => void // 確認はApp側
  onEndWatch: (dog: Dog) => void // 確認はApp側
  onResume: (dog: Dog) => void // 上限判定はApp側
  onAddRequest: () => boolean // 上限内ならtrue(フォームを開いてよい)
}) {
  const [editingId, setEditingId] = useState<string | null>(null)
  const [adding, setAdding] = useState(false)

  const card = (dog: Dog, kind: 'watching' | 'archived' | 'draft') => (
    <section key={dog.id} className="card dog-card vertical">
      <div className="avatar big">
        {dog.photo ? (
          <img src={dog.photo} alt="" className="dog-photo" />
        ) : (
          <PawIcon size={40} />
        )}
      </div>
      <div className="dog-name">
        {dog.name || '未設定のプロフィール'}
      </div>
      <div className="dog-sub">
        {[dog.breed, ageLabel(dog), dog.weightKg && `${dog.weightKg}kg`]
          .filter(Boolean)
          .join(' · ')}
      </div>

      <button
        className="btn ghost slim"
        onClick={() => {
          setAdding(false)
          setEditingId(editingId === dog.id ? null : dog.id)
        }}
      >
        プロフィールを編集
      </button>

      {editingId === dog.id && (
        <DogForm
          key={dog.id}
          initial={dog}
          onSave={(d) => {
            props.onSave({ ...d, id: dog.id, archived: dog.archived })
            setEditingId(null)
          }}
        />
      )}

      {/* 破壊的/低頻度の操作は間隔を空けた控えめなテキスト (§5,6) */}
      <div className="card-tail">
        {kind === 'watching' &&
          (props.hasRecords(dog.id) ? (
            <button
              className="linklike subtle"
              onClick={() => props.onEndWatch(dog)}
            >
              {dogLabel(dog)}の見守りを終了する
            </button>
          ) : (
            <button
              className="linklike subtle danger-text"
              onClick={() => props.onDelete(dog)}
            >
              {dogLabel(dog)}のプロフィールを削除する
            </button>
          ))}
        {kind === 'archived' && (
          <button className="linklike subtle accent-text"
            onClick={() => props.onResume(dog)}>
            見守りを再開する
          </button>
        )}
        {kind === 'draft' && (
          <button
            className="linklike subtle danger-text"
            onClick={() => props.onDelete(dog)}
          >
            {dogLabel(dog)}のプロフィールを削除する
          </button>
        )}
      </div>
    </section>
  )

  return (
    <div className="stack view">
      <div className="view-title-row">
        <span className="comment small">
          見守り中 {props.watching.length} / {props.maxDogs}頭
        </span>
      </div>

      {/* ---- 見守り中(縦並び §4) ---- */}
      {props.watching.map((d) => card(d, 'watching'))}

      {/* ---- 未設定の残骸(存在する場合のみ §5A) ---- */}
      {props.drafts.map((d) => card(d, 'draft'))}

      {/* ---- 追加 (上限チェックはApp側 §11) ---- */}
      {adding ? (
        <section className="card">
          <div className="card-head">
            <span className="label plain">新しい愛犬</span>
          </div>
          <DogForm
            initial={{ id: '', name: '', breed: '', weightKg: '', birthYear: '' }}
            requireName
            onSave={(d) => {
              props.onCreate(d)
              setAdding(false)
            }}
          />
        </section>
      ) : (
        <button
          className="btn ghost"
          onClick={() => {
            if (props.onAddRequest()) {
              setEditingId(null)
              setAdding(true)
            }
          }}
        >
          ＋ 新しい愛犬を追加
        </button>
      )}

      {/* ---- 見守りを終了した犬 (存在する場合のみ §7) ---- */}
      {props.archived.length > 0 && (
        <>
          <div className="day-label" style={{ marginTop: 8 }}>
            見守りを終了した犬
          </div>
          {props.archived.map((d) => card(d, 'archived'))}
        </>
      )}
    </div>
  )
}

/**
 * プロフィール編集/新規フォーム。新規は名前必須(保存時に正式作成 §5A)。
 * 肉球アイコン(または登録済み写真)のタップで写真操作を開く (§6)。
 */
function DogForm({
  initial,
  requireName = false,
  onSave,
}: {
  initial: Omit<Dog, 'id'> & { id?: string }
  requireName?: boolean
  onSave: (d: Omit<Dog, 'id'>) => void
}) {
  const [draft, setDraft] = useState(initial)
  const [touched, setTouched] = useState(false)
  const [photoMenu, setPhotoMenu] = useState(false)
  const cameraInput = useRef<HTMLInputElement>(null)
  const galleryInput = useRef<HTMLInputElement>(null)
  const nameMissing = draft.name.trim() === ''

  const set =
    (k: 'name' | 'breed' | 'weightKg' | 'birthYear') =>
    (e: React.ChangeEvent<HTMLInputElement>) => {
      setTouched(true)
      setDraft({ ...draft, [k]: e.target.value })
    }

  const onFile = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0]
    e.target.value = '' // 同じファイルの再選択を可能にする
    setPhotoMenu(false)
    if (!file) return
    try {
      const photo = await fileToDogPhoto(file)
      setDraft((d) => ({ ...d, photo }))
    } catch {
      /* 読めない画像は無視(元の状態を維持) */
    }
  }

  return (
    <div className="form" style={{ width: '100%', marginTop: 10 }}>
      {/* ---- 写真 (§6): タップで 撮る/選ぶ/削除 ---- */}
      <div className="photo-field">
        <button
          type="button"
          className="avatar big photo-btn"
          aria-label="愛犬の写真を設定"
          onClick={() => setPhotoMenu((v) => !v)}
        >
          {draft.photo ? (
            <img src={draft.photo} alt="" className="dog-photo" />
          ) : (
            <PawIcon size={40} />
          )}
          <span className="photo-badge">＋</span>
        </button>
        {photoMenu && (
          <div className="photo-actions">
            <button type="button" className="btn ghost slim"
              onClick={() => cameraInput.current?.click()}>
              写真を撮る
            </button>
            <button type="button" className="btn ghost slim"
              onClick={() => galleryInput.current?.click()}>
              写真を選ぶ
            </button>
            {draft.photo && (
              <button type="button" className="btn ghost slim danger-text"
                onClick={() => {
                  setDraft((d) => ({ ...d, photo: undefined }))
                  setPhotoMenu(false)
                }}>
                現在の写真を削除
              </button>
            )}
            <button type="button" className="btn ghost slim"
              onClick={() => setPhotoMenu(false)}>
              キャンセル
            </button>
          </div>
        )}
        {/* カメラ起動(mobile) / ファイル選択。desktopはどちらも選択ダイアログ */}
        <input ref={cameraInput} type="file" accept="image/*"
          capture="environment" hidden onChange={onFile} />
        <input ref={galleryInput} type="file" accept="image/*"
          hidden onChange={onFile} />
      </div>

      <label>
        <span>名前</span>
        <input value={draft.name} onChange={set('name')} placeholder="必須" />
      </label>
      {requireName && touched && nameMissing && (
        <p className="comment small" style={{ color: 'var(--warn)' }}>
          名前を入力すると保存できます
        </p>
      )}
      <label>
        <span>犬種</span>
        <input value={draft.breed} onChange={set('breed')} />
      </label>
      <label>
        <span>体重 (kg)</span>
        <input value={draft.weightKg} onChange={set('weightKg')} inputMode="decimal" />
      </label>
      <label>
        <span>生まれた年</span>
        <input value={draft.birthYear} onChange={set('birthYear')} inputMode="numeric" />
      </label>
      <div className="controls" style={{ marginTop: 12 }}>
        <button
          className="btn primary"
          disabled={nameMissing}
          onClick={() => onSave(draft)}
        >
          保存
        </button>
      </div>
    </div>
  )
}
