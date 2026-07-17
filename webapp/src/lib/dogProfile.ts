/** 愛犬プロフィール(localStorage)。 */
export interface DogProfile {
  name: string
  breed: string
  weightKg: string
  birthYear: string
}

const KEY = 'hydropaw.dog.v1'

export const defaultProfile: DogProfile = {
  name: 'ポチ',
  breed: '柴犬',
  weightKg: '8.2',
  birthYear: '2022',
}

export function loadProfile(): DogProfile {
  try {
    const raw = localStorage.getItem(KEY)
    if (!raw) return defaultProfile
    return { ...defaultProfile, ...JSON.parse(raw) }
  } catch {
    return defaultProfile
  }
}

export function saveProfile(p: DogProfile): void {
  localStorage.setItem(KEY, JSON.stringify(p))
}

export function ageLabel(p: DogProfile): string {
  const y = parseInt(p.birthYear, 10)
  if (!Number.isFinite(y)) return ''
  const age = new Date().getFullYear() - y
  return age >= 0 && age < 30 ? `${age}歳` : ''
}
