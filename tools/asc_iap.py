#!/usr/bin/env python3
"""Заводит покупки Hearthmend в App Store Connect через API.

Запускается из CI (workflow "App Store Connect: покупки"), ключ берется из секретов:
ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8. Повторный запуск безопасен: то, что уже есть, пропускается.
Товары те же, что в docs/monetization.md и Sources/HearthCore/Shop.swift.
"""
import json
import os
import sys
import time
import urllib.error
import urllib.request

import jwt

API = "https://api.appstoreconnect.apple.com"
BUNDLE = "com.personal.hearthmend"

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from asc_texts import TEXTS, check, text  # noqa: E402

# product id, тип, цена USD, ссылочное имя, поле текста (имя и field_desc), сколько кристаллов для имени
PRODUCTS = [
    ("gems.small", "CONSUMABLE", "0.99", "Gems 80", "gems", 80),
    ("gems.medium", "CONSUMABLE", "4.99", "Gems 450", "gems", 450),
    ("gems.large", "CONSUMABLE", "9.99", "Gems 1000", "gems", 1000),
    ("gems.chest", "CONSUMABLE", "19.99", "Gems 2200", "gems", 2200),
    ("gems.huge", "CONSUMABLE", "49.99", "Gems 6000", "gems", 6000),
    ("gems.mega", "CONSUMABLE", "99.99", "Gems 13000", "gems", 13000),
    ("starter", "NON_CONSUMABLE", "1.99", "Starter Pack", "starter", 0),
    ("piggy", "CONSUMABLE", "2.99", "Piggy Bank", "piggy", 0),
    ("event.pass", "CONSUMABLE", "3.99", "Event Pass", "pass", 0),
    ("bundle.weekend", "CONSUMABLE", "4.99", "Weekend Bundle", "weekend", 0),
    ("builder", "NON_CONSUMABLE", "6.99", "Builder Kit", "builder", 0),
]
VIP = ("vip.monthly", "4.99", "VIP Monthly")


def loc_texts(field, n=0):
    return [(loc, text(loc, field, n=n), text(loc, field + "_desc")) for loc in TEXTS]


REVIEW_NOTE = "Purchase from the shop (tap + next to gems). Rewards are granted instantly."

errors = []


def token():
    now = int(time.time())
    return jwt.encode(
        {"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 1000, "aud": "appstoreconnect-v1"},
        os.environ["ASC_KEY_P8"], algorithm="ES256",
        headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"})


def call(method, path, body=None):
    url = path if path.startswith("http") else API + path
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method, headers={
        "Authorization": "Bearer " + token(), "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            raw = r.read()
            return r.status, (json.loads(raw) if raw else {})
    except urllib.error.HTTPError as e:
        raw = e.read()
        try:
            return e.code, json.loads(raw)
        except ValueError:
            return e.code, {"raw": raw.decode(errors="replace")}


def ok(status, data, what):
    if 200 <= status < 300:
        return True
    msg = f"{what}: HTTP {status} {json.dumps(data.get('errors', data), ensure_ascii=False)[:800]}"
    print("::error::" + msg)
    errors.append(msg)
    return False


def get_all(path):
    out = []
    while path:
        s, d = call("GET", path)
        if not ok(s, d, "GET " + path):
            break
        out += d.get("data", [])
        path = d.get("links", {}).get("next")
    return out


def rel(type_, id_):
    return {"data": {"type": type_, "id": id_}}


def app_id():
    apps = get_all(f"/v1/apps?filter[bundleId]={BUNDLE}")
    if not apps:
        print(f"::error::Нет приложения с Bundle ID {BUNDLE}. Создай его в App Store Connect (New App) и запусти снова.")
        sys.exit(1)
    print("Приложение:", apps[0]["id"], apps[0]["attributes"].get("name"))
    return apps[0]["id"]


def territories():
    return [t["id"] for t in get_all("/v1/territories?limit=200")]


def price_point(path, price):
    for p in get_all(path):
        if p["attributes"].get("customerPrice") == price:
            return p["id"]
    return None


def ensure_iap(app, terrs):
    existing = {i["attributes"]["productId"]: i for i in get_all(f"/v1/apps/{app}/inAppPurchasesV2?limit=200")}
    for suffix, kind, price, ref, field, n in PRODUCTS:
        pid = f"{BUNDLE}.{suffix}"
        if pid in existing:
            iap = existing[pid]["id"]
            print(f"{pid}: уже есть ({existing[pid]['attributes'].get('state')})")
        else:
            s, d = call("POST", "/v2/inAppPurchases", {"data": {
                "type": "inAppPurchases",
                "attributes": {"name": ref, "productId": pid, "inAppPurchaseType": kind,
                               "reviewNote": REVIEW_NOTE, "familySharable": False},
                "relationships": {"app": rel("apps", app)}}})
            if not ok(s, d, f"создать {pid}"):
                continue
            iap = d["data"]["id"]
            print(f"{pid}: создан")

        locs = {l["attributes"]["locale"]: l for l in get_all(f"/v2/inAppPurchases/{iap}/inAppPurchaseLocalizations")}
        for locale, name, desc in loc_texts(field, n):
            have = locs.get(locale)
            if have:
                a = have["attributes"]
                if a.get("name") != name or a.get("description") != desc:
                    s, d = call("PATCH", f"/v1/inAppPurchaseLocalizations/{have['id']}", {"data": {
                        "type": "inAppPurchaseLocalizations", "id": have["id"],
                        "attributes": {"name": name, "description": desc}}})
                    ok(s, d, f"{pid} описание {locale}")
                continue
            s, d = call("POST", "/v1/inAppPurchaseLocalizations", {"data": {
                "type": "inAppPurchaseLocalizations",
                "attributes": {"locale": locale, "name": name, "description": desc},
                "relationships": {"inAppPurchaseV2": rel("inAppPurchases", iap)}}})
            ok(s, d, f"{pid} описание {locale}")

        s, d = call("GET", f"/v2/inAppPurchases/{iap}/iapPriceSchedule")
        has_price = s == 200 and d.get("data")
        if has_price:
            s2, d2 = call("GET", f"/v1/inAppPurchasePriceSchedules/{d['data']['id']}/manualPrices?limit=1")
            has_price = s2 == 200 and d2.get("data")
        if not has_price:
            pp = price_point(f"/v2/inAppPurchases/{iap}/pricePoints?filter[territory]=USA&limit=200", price)
            if not pp:
                ok(0, {"errors": "нет цены " + price}, f"{pid} цена")
            else:
                s, d = call("POST", "/v1/inAppPurchasePriceSchedules", {
                    "data": {"type": "inAppPurchasePriceSchedules", "relationships": {
                        "inAppPurchase": rel("inAppPurchases", iap),
                        "baseTerritory": rel("territories", "USA"),
                        "manualPrices": {"data": [{"type": "inAppPurchasePrices", "id": "${p1}"}]}}},
                    "included": [{"type": "inAppPurchasePrices", "id": "${p1}",
                                  "attributes": {"startDate": None},
                                  "relationships": {"inAppPurchasePricePoint": rel("inAppPurchasePricePoints", pp)}}]})
                if ok(s, d, f"{pid} цена"):
                    print(f"{pid}: цена {price} USD")

        s, d = call("GET", f"/v2/inAppPurchases/{iap}/inAppPurchaseAvailability")
        if not (s == 200 and d.get("data")):
            s, d = call("POST", "/v1/inAppPurchaseAvailabilities", {"data": {
                "type": "inAppPurchaseAvailabilities",
                "attributes": {"availableInNewTerritories": True},
                "relationships": {"inAppPurchase": rel("inAppPurchases", iap),
                                  "availableTerritories": {"data": [{"type": "territories", "id": t} for t in terrs]}}}})
            ok(s, d, f"{pid} страны")


def ensure_vip(app, terrs):
    suffix, price, ref = VIP
    pid = f"{BUNDLE}.{suffix}"
    groups = get_all(f"/v1/apps/{app}/subscriptionGroups")
    group = next((g["id"] for g in groups if g["attributes"].get("referenceName") == "VIP"), None)
    if not group:
        s, d = call("POST", "/v1/subscriptionGroups", {"data": {
            "type": "subscriptionGroups", "attributes": {"referenceName": "VIP"},
            "relationships": {"app": rel("apps", app)}}})
        if not ok(s, d, "группа VIP"):
            return
        group = d["data"]["id"]
    glocs = {l["attributes"]["locale"] for l in get_all(f"/v1/subscriptionGroups/{group}/subscriptionGroupLocalizations")}
    for locale in TEXTS:
        if locale in glocs:
            continue
        s, d = call("POST", "/v1/subscriptionGroupLocalizations", {"data": {
            "type": "subscriptionGroupLocalizations", "attributes": {"locale": locale, "name": text(locale, "group")},
            "relationships": {"subscriptionGroup": rel("subscriptionGroups", group)}}})
        ok(s, d, f"группа VIP описание {locale}")

    subs = {x["attributes"]["productId"]: x["id"] for x in get_all(f"/v1/subscriptionGroups/{group}/subscriptions")}
    sub = subs.get(pid)
    if sub:
        print(f"{pid}: уже есть")
    else:
        s, d = call("POST", "/v1/subscriptions", {"data": {
            "type": "subscriptions",
            "attributes": {"name": ref, "productId": pid, "subscriptionPeriod": "ONE_MONTH",
                           "familySharable": False, "groupLevel": 1, "reviewNote": REVIEW_NOTE},
            "relationships": {"group": rel("subscriptionGroups", group)}}})
        if not ok(s, d, f"создать {pid}"):
            return
        sub = d["data"]["id"]
        print(f"{pid}: создан")

    locs = {l["attributes"]["locale"] for l in get_all(f"/v1/subscriptions/{sub}/subscriptionLocalizations")}
    for locale, name, desc in loc_texts("vip"):
        if locale not in locs:
            s, d = call("POST", "/v1/subscriptionLocalizations", {"data": {
                "type": "subscriptionLocalizations",
                "attributes": {"locale": locale, "name": name, "description": desc},
                "relationships": {"subscription": rel("subscriptions", sub)}}})
            ok(s, d, f"{pid} описание {locale}")

    s, d = call("GET", f"/v1/subscriptions/{sub}/subscriptionAvailability")
    if not (s == 200 and d.get("data")):
        s, d = call("POST", "/v1/subscriptionAvailabilities", {"data": {
            "type": "subscriptionAvailabilities", "attributes": {"availableInNewTerritories": True},
            "relationships": {"subscription": rel("subscriptions", sub),
                              "availableTerritories": {"data": [{"type": "territories", "id": t} for t in terrs]}}}})
        ok(s, d, f"{pid} страны")

    priced = {p.get("relationships", {}).get("territory", {}).get("data", {}).get("id")
              for p in get_all(f"/v1/subscriptions/{sub}/prices?include=territory&limit=200")}
    base = price_point(f"/v1/subscriptions/{sub}/pricePoints?filter[territory]=USA&limit=200", price)
    if not base:
        ok(0, {"errors": "нет цены " + price}, f"{pid} цена")
        return
    # цена в США и равные ей цены в остальных странах
    points = [("USA", base)] + [
        (p["relationships"]["territory"]["data"]["id"], p["id"])
        for p in get_all(f"/v1/subscriptionPricePoints/{base}/equalizations?include=territory&limit=200")]
    added = 0
    for terr, pp in points:
        if terr in priced:
            continue
        s, d = call("POST", "/v1/subscriptionPrices", {"data": {
            "type": "subscriptionPrices", "attributes": {"startDate": None, "preserveCurrentPrice": False},
            "relationships": {"subscription": rel("subscriptions", sub),
                              "subscriptionPricePoint": rel("subscriptionPricePoints", pp),
                              "territory": rel("territories", terr)}}})
        if ok(s, d, f"{pid} цена {terr}"):
            added += 1
    print(f"{pid}: цен добавлено {added}, уже было {len(priced)}")


def main():
    bad = check()
    if bad:
        sys.exit("тексты длиннее лимитов Apple:\n" + "\n".join(bad))
    app = app_id()
    terrs = territories()
    print("Стран:", len(terrs))
    ensure_iap(app, terrs)
    ensure_vip(app, terrs)
    if errors:
        print(f"Ошибок: {len(errors)}")
        sys.exit(1)
    print("Готово")


if __name__ == "__main__":
    main()
