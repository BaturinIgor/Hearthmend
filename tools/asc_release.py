#!/usr/bin/env python3
"""Готовит версию Hearthmend к отправке на проверку через App Store Connect API.

- версия с номером из project.yml (MARKETING_VERSION), копирайт;
- категории: Игры -> Головоломки, Казуальные;
- возрастной рейтинг: ничего из списка (4+);
- цена: бесплатно, во всех странах;
- права на контент: сторонний контент с правами (купленный пак графики);
- данные для проверки: заметка для ревьюера;
- последняя готовая сборка этой версии привязывается к версии.

В конце печатает, что осталось сделать вручную (то, чего нет в API).
Повторный запуск безопасен.
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from asc_iap import EXCLUDED_TERRITORIES, app_id, call, errors, get_all, ok, rel, territories  # noqa: E402
from asc_listing import EDITABLE  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
VERSION = re.search(r'MARKETING_VERSION:\s*"([^"]+)"', open(os.path.join(HERE, "..", "project.yml")).read()).group(1)
COPYRIGHT = "2026 Igor Baturin"
REVIEW_NOTES = ("Hearthmend is an offline merge puzzle. No account or login is needed. "
                "Merge two equal items on the board, deliver orders for stars, spend stars in the village (map button). "
                "In-app purchases are in the shop (+ next to gems). Weekend festival runs Friday to Sunday.")

AGE_ENUMS = ["alcoholTobaccoOrDrugUseOrReferences", "contests", "gamblingSimulated", "gunsOrOtherWeapons",
             "horrorOrFearThemes", "matureOrSuggestiveThemes", "medicalOrTreatmentInformation",
             "profanityOrCrudeHumor", "sexualContentGraphicAndNudity", "sexualContentOrNudity",
             "violenceCartoonOrFantasy", "violenceRealistic", "violenceRealisticProlongedGraphicOrSadistic"]
AGE_BOOLS = ["gambling", "unrestrictedWebAccess", "lootBox", "advertising", "ageAssurance",
             "healthOrWellnessTopics", "messagingAndChat", "parentalControls", "userGeneratedContent", "socialMedia"]

todo = []


def patch_dropping_unknown(kind, rid, attrs, what):
    """PATCH; если API не знает какое-то поле, убирает его и пробует снова."""
    attrs = dict(attrs)
    for _ in range(len(attrs) + 8):
        s, d = call("PATCH", f"/v1/{kind}/{rid}", {"data": {"type": kind, "id": rid, "attributes": attrs}})
        if 200 <= s < 300:
            print(f"{what}: готово")
            return True
        errs = d.get("errors", [])
        field = lambda e: e.get("source", {}).get("pointer", "").rsplit("/", 1)[-1]  # noqa: E731
        # новые обязательные вопросы анкеты: в игре ничего такого нет, отвечаем «нет»
        missing = {field(e) for e in errs if e.get("code", "").endswith("ATTRIBUTE.REQUIRED")} - set(attrs) - {""}
        if missing:
            print(f"{what}: обязательные поля {', '.join(sorted(missing))} = нет")
            attrs.update({k: False for k in missing})
            continue
        bad = {field(e) for e in errs} & set(attrs)
        if not bad:
            return ok(s, d, what)
        print(f"{what}: API не знает {', '.join(sorted(bad))}, без них")
        for k in bad:
            attrs.pop(k)
    return False


def main():
    app = app_id()

    s, d = call("PATCH", f"/v1/apps/{app}", {"data": {"type": "apps", "id": app, "attributes": {
        "contentRightsDeclaration": "USES_THIRD_PARTY_CONTENT"}}})
    ok(s, d, "права на контент")

    # --- appInfo: категории и возраст
    infos = get_all(f"/v1/apps/{app}/appInfos")
    live = {"READY_FOR_DISTRIBUTION", "READY_FOR_SALE"}
    info = next((i for i in infos if (i["attributes"].get("state") or i["attributes"].get("appStoreState")) not in live), None)
    if info:
        s, d = call("PATCH", f"/v1/appInfos/{info['id']}", {"data": {"type": "appInfos", "id": info["id"], "relationships": {
            "primaryCategory": rel("appCategories", "GAMES"),
            "primarySubcategoryOne": rel("appCategories", "GAMES_PUZZLE"),
            "primarySubcategoryTwo": rel("appCategories", "GAMES_CASUAL")}}})
        if ok(s, d, "категории"):
            print("категории: Games / Puzzle, Casual")
        s, d = call("GET", f"/v1/appInfos/{info['id']}/ageRatingDeclaration")
        if ok(s, d, "возрастной рейтинг") and d.get("data"):
            attrs = {k: "NONE" for k in AGE_ENUMS}
            attrs.update({k: False for k in AGE_BOOLS})
            patch_dropping_unknown("ageRatingDeclarations", d["data"]["id"], attrs, "возрастной рейтинг 4+")
    else:
        print("::warning::нет appInfo в подготовке")

    # --- цена: бесплатно
    s, d = call("GET", f"/v1/apps/{app}/appPriceSchedule")
    has_price = False
    if s == 200 and d.get("data"):
        s2, d2 = call("GET", f"/v1/appPriceSchedules/{d['data']['id']}/manualPrices?limit=1")
        has_price = s2 == 200 and bool(d2.get("data"))
    if has_price:
        print("цена: уже задана")
    else:
        free = next((p["id"] for p in get_all(f"/v1/apps/{app}/appPricePoints?filter[territory]=USA&limit=200")
                     if float(p["attributes"].get("customerPrice") or 0) == 0), None)
        if free:
            s, d = call("POST", "/v1/appPriceSchedules", {
                "data": {"type": "appPriceSchedules", "relationships": {
                    "app": rel("apps", app), "baseTerritory": rel("territories", "USA"),
                    "manualPrices": {"data": [{"type": "appPrices", "id": "${p0}"}]}}},
                "included": [{"type": "appPrices", "id": "${p0}", "attributes": {"startDate": None},
                              "relationships": {"appPricePoint": rel("appPricePoints", free)}}]})
            if ok(s, d, "цена"):
                print("цена: бесплатно")
        else:
            ok(0, {"errors": "нет бесплатной цены"}, "цена")

    # --- страны
    s, d = call("GET", f"/v1/apps/{app}/appAvailabilityV2")
    if s == 200 and d.get("data"):
        print("страны: уже заданы")
        avail = d["data"]["id"]
        for ta in get_all(f"/v2/appAvailabilities/{avail}/territoryAvailabilities?include=territory&limit=200"):
            terr = ta.get("relationships", {}).get("territory", {}).get("data", {}).get("id")
            if terr in EXCLUDED_TERRITORIES and ta["attributes"].get("available"):
                s2, d2 = call("PATCH", f"/v1/territoryAvailabilities/{ta['id']}", {"data": {
                    "type": "territoryAvailabilities", "id": ta["id"], "attributes": {"available": False}}})
                if ok(s2, d2, f"страна {terr} выключена"):
                    print(f"страны: {terr} убрана")
    else:
        terrs = territories()
        s, d = call("POST", "/v2/appAvailabilities", {
            "data": {"type": "appAvailabilities", "attributes": {"availableInNewTerritories": True},
                     "relationships": {"app": rel("apps", app), "territoryAvailabilities": {
                         "data": [{"type": "territoryAvailabilities", "id": f"${{t{t}}}"} for t in terrs]}}},
            "included": [{"type": "territoryAvailabilities", "id": f"${{t{t}}}", "attributes": {"available": True},
                          "relationships": {"territory": rel("territories", t)}} for t in terrs]})
        if ok(s, d, "страны"):
            print(f"страны: {len(terrs)}")

    # --- версия
    versions = get_all(f"/v1/apps/{app}/appStoreVersions?filter[platform]=IOS")
    version = next((v for v in versions if v["attributes"].get("appStoreState") in EDITABLE), None)
    if not version:
        s, d = call("POST", "/v1/appStoreVersions", {"data": {"type": "appStoreVersions",
                    "attributes": {"platform": "IOS", "versionString": VERSION},
                    "relationships": {"app": rel("apps", app)}}})
        if not ok(s, d, "новая версия"):
            return finish()
        version = d["data"]
    vid = version["id"]
    attrs = {"copyright": COPYRIGHT}
    if version["attributes"].get("versionString") != VERSION:
        attrs["versionString"] = VERSION
    s, d = call("PATCH", f"/v1/appStoreVersions/{vid}", {"data": {"type": "appStoreVersions", "id": vid, "attributes": attrs}})
    if ok(s, d, "версия"):
        print(f"версия {VERSION}, копирайт {COPYRIGHT}")

    # --- данные для проверки
    s, d = call("GET", f"/v1/appStoreVersions/{vid}/appStoreReviewDetail")
    detail = d.get("data") if s == 200 else None
    if detail:
        a = detail["attributes"]
        s, d = call("PATCH", f"/v1/appStoreReviewDetails/{detail['id']}", {"data": {
            "type": "appStoreReviewDetails", "id": detail["id"],
            "attributes": {"notes": REVIEW_NOTES, "demoAccountRequired": False}}})
        if 200 <= s < 300:
            print("заметка для проверки: обновлена")
        elif any(e.get("code", "").endswith("ATTRIBUTE.REQUIRED") for e in d.get("errors", [])):
            todo.append("App Review Information: Notes: " + REVIEW_NOTES)
        else:
            ok(s, d, "заметка для проверки")
    else:
        a = {}
        s, d = call("POST", "/v1/appStoreReviewDetails", {"data": {"type": "appStoreReviewDetails",
                    "attributes": {"notes": REVIEW_NOTES, "demoAccountRequired": False},
                    "relationships": {"appStoreVersion": rel("appStoreVersions", vid)}}})
        # без контактов Apple не создает раздел: тогда заметку вписывает человек вместе с контактами
        if 200 <= s < 300:
            print("заметка для проверки: добавлена")
        elif any(e.get("code", "").endswith("ATTRIBUTE.REQUIRED") for e in d.get("errors", [])):
            todo.append("App Review Information: Notes: " + REVIEW_NOTES)
        else:
            ok(s, d, "заметка для проверки")
    if not (a.get("contactEmail") and a.get("contactPhone") and a.get("contactFirstName")):
        todo.append("App Review Information: имя, телефон и почта для связи с проверяющим")

    # --- сборка
    builds = get_all(f"/v1/builds?filter[app]={app}&filter[preReleaseVersion.version]={VERSION}"
                     f"&filter[processingState]=VALID&sort=-uploadedDate&limit=5")
    if builds:
        b = builds[0]
        s, d = call("PATCH", f"/v1/appStoreVersions/{vid}/relationships/build", {"data": {"type": "builds", "id": b["id"]}})
        if ok(s, d, "сборка"):
            print(f"сборка {b['attributes'].get('version')} привязана к версии {VERSION}")
    else:
        todo.append(f"нет готовой сборки {VERSION}: запусти workflow TestFlight и подожди обработку")

    todo.append("App Privacy: Data Not Collected (в API этого нет)")
    finish()


def finish():
    for t in todo:
        print("::notice::Осталось: " + t)
    if errors:
        print(f"Ошибок: {len(errors)}")
        sys.exit(1)
    print("Готово")


if __name__ == "__main__":
    main()
