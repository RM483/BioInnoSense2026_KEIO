/**
 * @file test_fis.cpp
 * @brief bap_lite と hpp のホスト検証。Arduino不要(g++でビルド)。
 *   1) HPP CRC が CCITT-FALSE (STM32版とバイト互換) であることを既知ベクタで確認。
 *   2) 合成MOS呼気カーブ(Rs降下→回復)を流し、READY→ONSET→OFFSET と
 *      妥当な Q/C/peak が出ることを確認。
 *   make -C arduino_fis/test  で実行。
 */
#include <cstdio>
#include <cmath>
#include "../bap_lite.h"
#include "../hpp.h"
#include "../sensor_sb19.h"

static int fails = 0;
#define CHECK(c, msg) do{ if(!(c)){ printf("FAIL: %s\n", msg); fails++; } else { printf("ok: %s\n", msg);} }while(0)

static const char *EVN(bapl_evt_t e){
  switch(e){case BAPL_EVT_R0_LOCKED:return "R0_LOCK";case BAPL_EVT_READY:return "READY";
  case BAPL_EVT_ONSET:return "ONSET";case BAPL_EVT_OFFSET:return "OFFSET";default:return "";}
}

int main() {
  /* ---- 1) HPP CRC 互換性 ---- */
  const uint8_t v[] = {'1','2','3','4','5','6','7','8','9'};
  uint16_t crc = hpp_crc16(v, 9);
  printf("CRC16-CCITT-FALSE('123456789') = 0x%04X (期待 0x29B1)\n", crc);
  CHECK(crc == 0x29B1, "HPP CRC は CCITT-FALSE (STM32版と互換)");

  uint8_t frame[64];
  size_t fn = hpp_encode(HPP_EVT_PHASE, 7, (const uint8_t[]){1,0}, 2, frame);
  CHECK(fn == 9 && frame[0]==0xA5 && frame[1]==0x01 && frame[2]==0x87, "HPP encode ヘッダ整合");

  /* ---- 2) 合成呼気カーブ ---- */
  bapl_t b; uint32_t now = 1000;
  bapl_init(&b, 1, now, /*already_warm=*/true);

  const float R0 = 50000.0f;              /* 清浄大気 Rs 50kΩ */
  bool onset=false, offset=false;
  bapl_result_t res; res.quality=0;

  auto feed = [&](float rs){
    now += 100;                            /* 10Hz */
    bapl_evt_t e = bapl_on_sample(&b, rs, sb19_rs_valid(rs), now);
    if (e!=BAPL_EVT_NONE) printf("t=%.1fs  %s  r=%.3f\n", now/1000.0, EVN(e), bapl_response(&b));
    if (e==BAPL_EVT_ONSET) onset=true;
    if (e==BAPL_EVT_OFFSET){ offset=true; bapl_finalize(&b,&res); }
  };

  /* ベースライン(静穏) → R0ロック & READY */
  for (int i=0;i<14;i++) feed(R0 + ((i&1)?300:-300));
  CHECK(b.phase==BAPL_READY, "予熱+静穏で READY へ遷移");

  /* 呼気: Rs降下(H2上昇) → プラトー → 回復 */
  float rise[] = {43000,38000,33000,30000,29000,29000,29500,30000,33000,38000,44000,48000,49500,50000,50000};
  for (float rs : rise){ feed(rs); if(offset) break; }
  /* offsetがまだなら静穏を足して確定させる */
  for (int i=0;i<10 && !offset;i++) feed(R0 + ((i&1)?200:-200));

  printf("\n---- 結果 ----\n");
  CHECK(onset, "ONSET を検出");
  CHECK(offset, "OFFSET を検出");
  printf("Q=%u C=%u peak_r=%.3f rise=%.1fs dur=%.1fs flags=0x%02X R0=%.0fΩ\n",
         res.quality, res.confidence, res.peak_r, res.rise_ds/10.0, res.duration_ds/10.0,
         res.flags, res.r0_ohm);
  CHECK(res.peak_r > 1.15f, "peak_r が onset閾値を超える");
  CHECK(res.duration_ds > 0, "duration>0");
  CHECK(res.quality > 0, "quality>0");

  printf("\n%s\n", fails==0 ? "ALL PASSED" : "SOME FAILED");
  return fails==0 ? 0 : 1;
}
