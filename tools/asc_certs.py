#!/usr/bin/env python3
"""Сертификаты разработчика, которые оставили прошлые сборки в CI.

    python3 tools/asc_certs.py            # только показать
    python3 tools/asc_certs.py --revoke   # отозвать сертификаты разработки, созданные через API

Каждая сборка на чистой машине GitHub создает новый сертификат Apple Development: закрытый ключ
от него живет только на этой машине и пропадает вместе с ней. Когда таких сертификатов набирается
предел, Xcode не может подписать сборку. Сертификаты распространения (App Store) не трогаются.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from asc_iap import call, get_all, ok  # noqa: E402

DEV_TYPES = {"DEVELOPMENT", "IOS_DEVELOPMENT"}


def main():
    revoke = "--revoke" in sys.argv
    certs = get_all("/v1/certificates?limit=200")
    dev = []
    for c in certs:
        a = c["attributes"]
        kind, name = a.get("certificateType"), a.get("name") or a.get("displayName") or ""
        print(f"{c['id']}  {kind}  {name}  до {str(a.get('expirationDate', ''))[:10]}")
        if kind in DEV_TYPES and "Created via API" in name:
            dev.append(c["id"])
    print(f"::notice::Сертификатов всего {len(certs)}, разработки из CI {len(dev)}")
    if not revoke:
        return
    for cid in dev:
        s, d = call("DELETE", f"/v1/certificates/{cid}")
        if ok(s, d, f"отзыв {cid}"):
            print(f"отозван {cid}")


if __name__ == "__main__":
    main()
