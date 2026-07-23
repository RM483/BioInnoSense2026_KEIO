/**
 * HydroPaw — 半導体式(FIS SB-19)+ Arduino Uno R4 WiFi 変種
 * ============================================================================
 * 中間発表「読み出し回路」の構成をそのまま実装:
 *   VC — SB19(Rs) — VS節点 — RL — GND の分圧を MCP6022(電圧フォロワ)+RC で安定化し、
 *   R4 WiFi の 14bit ADC で読み、Rs を算出 → BAP-lite で呼気を解析 →
 *   HPP フレームを BLE(NUS) で notify。既存 HydroPaw アプリがそのまま受信できる。
 *
 * ヒータ(VH=0.9V/120mW)は外部 LT3080 が常時供給する(本スケッチは制御しない)。
 *
 * 依存: ArduinoBLE ライブラリ (ライブラリマネージャで導入)。ボード: Arduino UNO R4 WiFi。
 * データフロー: ADC → sensor_sb19(Rs) → bap_lite → hpp_encode → BLE notify。
 * ============================================================================
 */
#include <ArduinoBLE.h>
#include "config.h"
#include "sensor_sb19.h"
#include "bap_lite.h"
#include "hpp.h"

/* ---- BLE (Nordic UART Service) ---- */
BLEService        nus(NUS_SERVICE_UUID);
BLECharacteristic txChar(NUS_TX_UUID, BLENotify, 20);                 /* FW→App */
BLECharacteristic rxChar(NUS_RX_UUID, BLEWrite | BLEWriteWithoutResponse, 64); /* App→FW */

/* ---- アプリ層 ---- */
static bapl_t       g_bap;
static hpp_decoder_t g_rx;
static uint8_t      g_seq = 0;
static uint32_t     g_session_start = 0;
static uint32_t     g_last_sample = 0;
static uint16_t     g_stream_div = 0;
static bool         g_armed = false;   /* 呼気セッション監視中か */

/* ================= BLE 送信 (HPPフレームを<=20Bチャンクでnotify) ================= */
static void ble_send(const uint8_t *frame, size_t len) {
  if (!txChar.subscribed()) return;
  size_t off = 0;
  while (off < len) {
    size_t n = (len - off > 20u) ? 20u : (len - off);
    txChar.writeValue(&frame[off], n);
    off += n;
    delay(3); /* 連続notifyの取りこぼし対策(BLEスタックに間を与える) */
  }
}
static void send_hpp(uint8_t type, const uint8_t *payload, uint8_t plen) {
  uint8_t f[HPP_MAX_FRAME_SIZE];
  size_t n = hpp_encode(type, g_seq++, payload, plen, f);
  ble_send(f, n);
}
static void send_phase(uint8_t phase, uint8_t detail) {
  uint8_t p[2] = { phase, detail };
  send_hpp(HPP_EVT_PHASE, p, 2);
}
/* EVT_DATA(13B): STM32版と同レイアウト。ppbフィールドは相対H2指標(較正前)。 */
static void send_data(int32_t h2_index, uint8_t flags) {
  uint8_t p[13];
  hpp_put_u32(&p[0], millis() - g_session_start);
  hpp_put_i32(&p[4], h2_index);
  hpp_put_i16(&p[8], 0);      /* temp: 温度センサ無し */
  hpp_put_u16(&p[10], 0);     /* rh: 湿度センサ無し */
  p[12] = flags;
  send_hpp(HPP_EVT_DATA, p, sizeof(p));
}
/* EVT_RESULT(30B): STM32版と同レイアウト。ppb系は相対指標にマップ。 */
static void send_result(const bapl_result_t *r) {
  uint8_t p[30];
  int32_t peak_idx = (int32_t)((r->peak_r - 1.0f) * 1000.0f);
  uint32_t auc_i   = (uint32_t)(r->auc * 1000.0f);
  p[0] = r->session_id; p[1] = r->quality; p[2] = r->confidence; p[3] = r->flags;
  hpp_put_i32(&p[4], 0);            /* baseline(相対) = 0 */
  hpp_put_i32(&p[8], peak_idx);     /* peak(相対H2指標) */
  hpp_put_i32(&p[12], peak_idx);    /* plateau ≒ peak */
  hpp_put_u32(&p[16], auc_i);
  hpp_put_u16(&p[20], r->rise_ds);
  hpp_put_u16(&p[22], r->duration_ds);
  hpp_put_i16(&p[24], 0);           /* temp mean */
  hpp_put_i16(&p[26], 0);           /* rh delta */
  hpp_put_u16(&p[28], 0);           /* pre_mad */
  send_hpp(HPP_EVT_RESULT, p, sizeof(p));
}

/* ================= セッション制御 ================= */
static void arm_session(bool already_warm) {
  static uint8_t sid = 0;
  bapl_init(&g_bap, ++sid, millis(), already_warm);
  g_session_start = millis();
  g_armed = true;
  send_phase(HPP_PHASE_WARMUP, 0);
}

/* App→FW コマンド処理(最小: 呼気開始/停止/情報) */
static void on_frame(const hpp_frame_t *f) {
  switch (f->type) {
    case HPP_CMD_BREATH:                 /* 新規測定を再アーム */
      arm_session(true);                 /* 連続加熱中なので warm 扱い */
      break;
    case HPP_CMD_STOP:
      g_armed = false;
      break;
    case HPP_CMD_GET_INFO: {
      uint8_t p[2] = { FW_VERSION_MAJOR, FW_VERSION_MINOR };
      send_hpp(HPP_EVT_INFO, p, 2);
      break;
    }
    default: break;                      /* 他は無視(MOS変種は最小コマンド) */
  }
}

/* ================= setup / loop ================= */
void setup() {
  Serial.begin(115200);
  analogReadResolution(ADC_BITS);
  if (PIN_HEATER_EN >= 0) { pinMode(PIN_HEATER_EN, OUTPUT); digitalWrite(PIN_HEATER_EN, HIGH); }
  pinMode(PIN_STATUS_LED, OUTPUT);

  if (!BLE.begin()) { Serial.println("BLE init failed"); while (1) { } }
  BLE.setLocalName(BLE_LOCAL_NAME);
  BLE.setDeviceName(BLE_LOCAL_NAME);
  BLE.setAdvertisedService(nus);
  nus.addCharacteristic(txChar);
  nus.addCharacteristic(rxChar);
  BLE.addService(nus);
  BLE.advertise();

  hpp_decoder_init(&g_rx);
  arm_session(false);                    /* 起動直後は予熱待ち */
  Serial.println("Fuwan-R4 (FIS SB-19) boot / advertising");
}

void loop() {
  BLEDevice central = BLE.central();
  if (!central) { delay(20); return; }

  digitalWrite(PIN_STATUS_LED, HIGH);
  while (central.connected()) {
    /* App→FW 受信(HPP) */
    if (rxChar.written()) {
      int n = rxChar.valueLength();
      const uint8_t *v = rxChar.value();
      hpp_frame_t fr;
      for (int i = 0; i < n; i++)
        if (hpp_decoder_feed(&g_rx, v[i], &fr)) on_frame(&fr);
    }

    /* 定周期サンプリング */
    uint32_t now = millis();
    if (now - g_last_sample < SAMPLE_PERIOD_MS) continue;
    g_last_sample = now;
    if (!g_armed) continue;

    uint16_t adc = analogRead(PIN_VS_ADC);
    float rs = sb19_rs_ohm(adc);
    bool  valid = sb19_rs_valid(rs);

    bapl_evt_t ev = bapl_on_sample(&g_bap, rs, valid, now);
    float rr = bapl_response(&g_bap);
    int32_t h2_index = (int32_t)((rr - 1.0f) * 1000.0f);
    if (h2_index < 0) h2_index = 0;

    switch (ev) {
      case BAPL_EVT_READY:  send_phase(HPP_PHASE_READY, 0);  break;
      case BAPL_EVT_ONSET:  send_phase(HPP_PHASE_BREATH, 0); break;
      case BAPL_EVT_OFFSET: {
        send_phase(HPP_PHASE_ANALYZE, 0);
        bapl_result_t res;
        bapl_finalize(&g_bap, &res);
        /* 低品質なら1回だけ自動再測定 */
        if (res.quality < BAP_RETRY_QUALITY && g_bap.retries == 0u) {
          bapl_begin_retry(&g_bap, now);
          send_phase(HPP_PHASE_RETRY, res.quality);
        } else {
          send_result(&res);
          send_phase(HPP_PHASE_DONE, res.quality);
          Serial.print("RESULT Q="); Serial.print(res.quality);
          Serial.print(" C="); Serial.print(res.confidence);
          Serial.print(" peak_r="); Serial.print(res.peak_r, 3);
          Serial.print(" dur="); Serial.println(res.duration_ds);
          arm_session(true); /* 連続運用: 次の呼気を待つ */
        }
        break;
      }
      default: break;
    }

    /* ライブ値ストリーム(2Hz) */
    if (++g_stream_div >= BLE_STREAM_DIV) {
      g_stream_div = 0;
      uint8_t flags = (g_bap.phase == BAPL_WARMING) ? 0x04 : 0x00; /* warmup bit */
      send_data(h2_index, flags);
    }
  }
  digitalWrite(PIN_STATUS_LED, LOW);
  hpp_decoder_init(&g_rx); /* 切断でRXデコーダをリセット */
}
