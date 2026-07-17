/**
 * HydroPaw Cloud Functions
 *  - onMeasurementCreated: 日次統計の増分更新 + 高値アラート生成
 *  - cleanupOrphanPhotos : 孤児写真の定期削除
 */
import { initializeApp } from "firebase-admin/app";
import { FieldValue, getFirestore } from "firebase-admin/firestore";
import { getStorage } from "firebase-admin/storage";
import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { logger } from "firebase-functions/v2";

initializeApp();
const db = getFirestore();

/** H2高値アラート閾値 [ppb] (20ppm — app/lib/core/constants/h2.dart と同値) */
const ALERT_THRESHOLD_PPB = 20_000;

/**
 * 測定作成時: dailyStats を増分更新し、閾値超過でアラートを作成する。
 * パス: users/{uid}/dogs/{dogId}/measurements/{measurementId}
 *
 * 冪等性: Functions v2はat-least-once配信のため再実行があり得る。
 * 測定ドキュメント自身の statsApplied フラグをトランザクション内で
 * 検査・更新することで二重計上を防ぐ。
 */
export const onMeasurementCreated = onDocumentCreated(
  "users/{uid}/dogs/{dogId}/measurements/{measurementId}",
  async (event) => {
    const snap = event.data;
    if (!snap) return;
    const data = snap.data();

    const { uid, dogId, measurementId } = event.params;
    const startedAt: Date = data.startedAt.toDate();
    const dateKey = startedAt.toISOString().slice(0, 10); // yyyy-mm-dd

    const dogRef = db.doc(`users/${uid}/dogs/${dogId}`);
    const statsRef = dogRef.collection("dailyStats").doc(dateKey);
    const measurementRef = snap.ref;

    // 日次統計をトランザクションで増分更新(再集計不要な設計)
    const applied = await db.runTransaction(async (tx) => {
      const mSnap = await tx.get(measurementRef);
      if (!mSnap.exists || mSnap.data()?.statsApplied === true) {
        return false; // 再配信 or 既に削除済み → 何もしない
      }
      const sSnap = await tx.get(statsRef);
      const prev = sSnap.exists
        ? (sSnap.data() as {
            count: number;
            sumAvgPpb: number;
            maxPpb: number;
          })
        : { count: 0, sumAvgPpb: 0, maxPpb: 0 };

      tx.set(statsRef, {
        date: dateKey,
        count: prev.count + 1,
        sumAvgPpb: prev.sumAvgPpb + (data.avgPpb ?? 0),
        avgPpb: Math.round(
          (prev.sumAvgPpb + (data.avgPpb ?? 0)) / (prev.count + 1)
        ),
        maxPpb: Math.max(prev.maxPpb, data.maxPpb ?? 0),
        updatedAt: FieldValue.serverTimestamp(),
      });
      tx.update(measurementRef, { statsApplied: true });
      return true;
    });

    // 高値アラート (将来: FCM push通知の拡張点)。
    // measurementIdをドキュメントIDに使い、再実行でも重複作成しない。
    if (applied && (data.avgPpb ?? 0) >= ALERT_THRESHOLD_PPB) {
      await dogRef.collection("alerts").doc(measurementId).set({
        measurementId,
        avgPpb: data.avgPpb,
        thresholdPpb: ALERT_THRESHOLD_PPB,
        createdAt: FieldValue.serverTimestamp(),
        acknowledged: false,
      });
      logger.info("High H2 alert created", { uid, dogId, avgPpb: data.avgPpb });
    }
  }
);

/**
 * 毎日04:00 JST: Dogドキュメントが存在しない写真をStorageから削除する。
 */
export const cleanupOrphanPhotos = onSchedule(
  { schedule: "0 4 * * *", timeZone: "Asia/Tokyo" },
  async () => {
    const bucket = getStorage().bucket();
    const [files] = await bucket.getFiles({ prefix: "dogs/" });

    let deleted = 0;
    for (const file of files) {
      // パス形式: dogs/{uid}/{dogId}/photo.jpg
      const parts = file.name.split("/");
      if (parts.length < 4) continue;
      const [, uid, dogId] = parts;
      const dogSnap = await db.doc(`users/${uid}/dogs/${dogId}`).get();
      if (!dogSnap.exists) {
        await file.delete();
        deleted++;
      }
    }
    logger.info(`cleanupOrphanPhotos: deleted ${deleted} files`);
  }
);
