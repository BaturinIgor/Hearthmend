#!/usr/bin/env python3
"""Загружает скриншоты в App Store Connect.

1. Скриншоты страницы: shots/<locale>/<NN>_<имя>.png -> набор APP_IPHONE_67 (6.9") версии,
   которая готовится к отправке. Старые скриншоты набора заменяются, порядок как в именах файлов.
2. Скриншот для проверки покупок: shots/review_shop.png -> каждой покупке и подписке VIP,
   у которой его еще нет.

Запускается из workflow Screenshots с секретами ASC_*. Повторный запуск безопасен.
"""
import hashlib
import os
import sys
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from asc_iap import app_id, call, errors, get_all, ok, rel  # noqa: E402
from asc_listing import EDITABLE  # noqa: E402

DISPLAY = "APP_IPHONE_67"


def upload(kind, relationships, path):
    """Создает ресурс-картинку, отправляет файл частями и отмечает загруженным."""
    blob = open(path, "rb").read()
    s, d = call("POST", f"/v1/{kind}", {"data": {"type": kind,
                                                "attributes": {"fileName": os.path.basename(path), "fileSize": len(blob)},
                                                "relationships": relationships}})
    if not ok(s, d, f"{kind} {path}"):
        return False
    rid = d["data"]["id"]
    for op in d["data"]["attributes"].get("uploadOperations") or []:
        part = blob[op["offset"]:op["offset"] + op["length"]]
        req = urllib.request.Request(op["url"], data=part, method=op["method"],
                                     headers={h["name"]: h["value"] for h in op.get("requestHeaders") or []})
        try:
            urllib.request.urlopen(req, timeout=120).read()
        except Exception as e:  # noqa: BLE001
            ok(500, {"errors": str(e)}, f"upload part {path}")
            return False
    s, d = call("PATCH", f"/v1/{kind}/{rid}", {"data": {"type": kind, "id": rid, "attributes": {
        "uploaded": True, "sourceFileChecksum": hashlib.md5(blob).hexdigest()}}})
    return ok(s, d, f"{kind} commit {path}")


def store_screenshots(app, root):
    versions = get_all(f"/v1/apps/{app}/appStoreVersions?filter[platform]=IOS")
    version = next((v for v in versions if v["attributes"].get("appStoreState") in EDITABLE), None)
    if not version:
        print("::warning::Нет версии в подготовке, скриншоты страницы не загружаю")
        return
    locs = {l["attributes"]["locale"]: l["id"] for l in
            get_all(f"/v1/appStoreVersions/{version['id']}/appStoreVersionLocalizations")}
    for locale in sorted(os.listdir(root)):
        folder = os.path.join(root, locale)
        if not os.path.isdir(folder):
            continue
        files = sorted(f for f in os.listdir(folder) if f.endswith(".png"))
        if locale not in locs:
            print(f"::warning::{locale}: нет локализации версии, пропускаю")
            continue
        sets = get_all(f"/v1/appStoreVersionLocalizations/{locs[locale]}/appScreenshotSets")
        target = next((x for x in sets if x["attributes"]["screenshotDisplayType"] == DISPLAY), None)
        if not target:
            s, d = call("POST", "/v1/appScreenshotSets", {"data": {"type": "appScreenshotSets",
                        "attributes": {"screenshotDisplayType": DISPLAY},
                        "relationships": {"appStoreVersionLocalization": rel("appStoreVersionLocalizations", locs[locale])}}})
            if not ok(s, d, f"appScreenshotSets {locale}"):
                continue
            target = d["data"]
        for old in get_all(f"/v1/appScreenshotSets/{target['id']}/appScreenshots"):
            s, d = call("DELETE", f"/v1/appScreenshots/{old['id']}")
            ok(s, d, f"delete screenshot {locale}")
        done = sum(upload("appScreenshots", {"appScreenshotSet": rel("appScreenshotSets", target["id"])},
                          os.path.join(folder, f)) for f in files)
        print(f"{locale}: {done}/{len(files)} скриншотов")


def review_screenshots(app, path):
    if not os.path.exists(path):
        print("::warning::Нет скриншота магазина для проверки покупок")
        return
    for iap in get_all(f"/v1/apps/{app}/inAppPurchasesV2?limit=200"):
        pid = iap["attributes"]["productId"]
        s, d = call("GET", f"/v2/inAppPurchases/{iap['id']}/appStoreReviewScreenshot")
        if s == 200 and d.get("data"):
            print(f"{pid}: скриншот для проверки уже есть")
            continue
        if upload("inAppPurchaseAppStoreReviewScreenshots", {"inAppPurchaseV2": rel("inAppPurchases", iap["id"])}, path):
            print(f"{pid}: скриншот для проверки загружен")
    for group in get_all(f"/v1/apps/{app}/subscriptionGroups"):
        for sub in get_all(f"/v1/subscriptionGroups/{group['id']}/subscriptions"):
            pid = sub["attributes"]["productId"]
            s, d = call("GET", f"/v1/subscriptions/{sub['id']}/appStoreReviewScreenshot")
            if s == 200 and d.get("data"):
                print(f"{pid}: скриншот для проверки уже есть")
                continue
            if upload("subscriptionAppStoreReviewScreenshots", {"subscription": rel("subscriptions", sub["id"])}, path):
                print(f"{pid}: скриншот для проверки загружен")


def main():
    root = sys.argv[1] if len(sys.argv) > 1 else "shots"
    app = app_id()
    store_screenshots(app, os.path.join(root, "store"))
    review_screenshots(app, os.path.join(root, "review_shop.png"))
    if errors:
        print(f"Ошибок: {len(errors)}")
        sys.exit(1)
    print("Готово")


if __name__ == "__main__":
    main()
