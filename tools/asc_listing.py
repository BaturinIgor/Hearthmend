#!/usr/bin/env python3
"""Страница приложения в App Store Connect на всех языках: подзаголовок, ссылка на политику,
описание, ключевые слова, рекламный текст, ссылка поддержки. Тексты в docs/listing/listing.json.

Запускается из того же workflow, что и tools/asc_iap.py. Существующие тексты обновляются,
недостающие языки добавляются. Меняется только версия, которая готовится к отправке.
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from asc_iap import app_id, call, errors, get_all, ok, rel  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
LISTING = json.load(open(os.path.join(HERE, "..", "docs", "listing", "listing.json")))
NAME = "Hearthmend: Merge Village"
PRIVACY = "https://baturinigor.github.io/hearthmend-legal/privacy.html"
SUPPORT = "https://baturinigor.github.io/hearthmend-legal/support.html"
EDITABLE = {"PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED", "INVALID_BINARY"}


def upsert(kind, existing, locale, attrs, parent_rel, parent_type, parent_id):
    have = existing.get(locale)
    if have:
        changed = {k: v for k, v in attrs.items() if have["attributes"].get(k) != v}
        if changed:
            s, d = call("PATCH", f"/v1/{kind}/{have['id']}", {"data": {"type": kind, "id": have["id"], "attributes": changed}})
            if ok(s, d, f"{kind} {locale}"):
                print(f"{kind} {locale}: обновлено {', '.join(changed)}")
        return
    s, d = call("POST", f"/v1/{kind}", {"data": {"type": kind, "attributes": dict(locale=locale, **attrs),
                                                "relationships": {parent_rel: rel(parent_type, parent_id)}}})
    if ok(s, d, f"{kind} {locale}"):
        print(f"{kind} {locale}: добавлено")


EULA = "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"


def main():
    # в приложении есть подписка: Apple требует ссылку на условия (EULA) в описании на каждом языке
    missing = [l for l, t in LISTING.items() if EULA not in t["description"]]
    if missing:
        sys.exit(f"Нет ссылки на EULA в описании: {', '.join(missing)}")
    app = app_id()

    infos = get_all(f"/v1/apps/{app}/appInfos")
    live = {"READY_FOR_DISTRIBUTION", "READY_FOR_SALE"}
    info = next((i for i in infos if (i["attributes"].get("state") or i["attributes"].get("appStoreState")) not in live),
                infos[0] if infos else None)
    if info:
        existing = {l["attributes"]["locale"]: l for l in get_all(f"/v1/appInfos/{info['id']}/appInfoLocalizations")}
        for locale, t in LISTING.items():
            upsert("appInfoLocalizations", existing, locale,
                   {"name": NAME, "subtitle": t["subtitle"], "privacyPolicyUrl": PRIVACY},
                   "appInfo", "appInfos", info["id"])

    versions = get_all(f"/v1/apps/{app}/appStoreVersions?filter[platform]=IOS")
    version = next((v for v in versions if v["attributes"].get("appStoreState") in EDITABLE), None)
    if not version:
        print("::warning::Нет версии в подготовке, описание не меняю")
    else:
        print("Версия", version["attributes"].get("versionString"))
        existing = {l["attributes"]["locale"]: l for l in
                    get_all(f"/v1/appStoreVersions/{version['id']}/appStoreVersionLocalizations")}
        first = version["attributes"].get("versionString") == "1.0"
        for locale, t in LISTING.items():
            attrs = {"description": t["description"], "keywords": t["keywords"], "promotionalText": t["promo"],
                     "supportUrl": SUPPORT}
            # "Что нового" Apple принимает только у обновлений, не у первой версии
            if not first and t.get("whatsNew"):
                attrs["whatsNew"] = t["whatsNew"]
            upsert("appStoreVersionLocalizations", existing, locale, attrs,
                   "appStoreVersion", "appStoreVersions", version["id"])

    if errors:
        print(f"Ошибок: {len(errors)}")
        sys.exit(1)
    print("Готово")


if __name__ == "__main__":
    main()
