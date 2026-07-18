/**
 * 愛犬写真の取り込み (docs/21 v2.2 §6)。
 * 端末写真/カメラ撮影のFileを、円形表示に合わせて中央寄せの正方形へ
 * トリミングし、小さなJPEG dataURLへ変換して localStorage に保存できる
 * サイズにする。元画像は変更しない(読み取りのみ)。
 */
const SIZE = 384 // 表示は最大176px程度。2倍強でRetinaにも十分

export async function fileToDogPhoto(file: File): Promise<string> {
  const url = URL.createObjectURL(file)
  try {
    const img = await loadImage(url)
    const side = Math.min(img.naturalWidth, img.naturalHeight)
    const sx = (img.naturalWidth - side) / 2
    const sy = (img.naturalHeight - side) / 2

    const canvas = document.createElement('canvas')
    canvas.width = SIZE
    canvas.height = SIZE
    const ctx = canvas.getContext('2d')
    if (!ctx) throw new Error('canvas 2d unavailable')
    ctx.drawImage(img, sx, sy, side, side, 0, 0, SIZE, SIZE)
    return canvas.toDataURL('image/jpeg', 0.85)
  } finally {
    URL.revokeObjectURL(url)
  }
}

function loadImage(url: string): Promise<HTMLImageElement> {
  return new Promise((resolve, reject) => {
    const img = new Image()
    img.onload = () => resolve(img)
    img.onerror = () => reject(new Error('image load failed'))
    img.src = url
  })
}
