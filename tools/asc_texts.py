"""Тексты покупок для App Store Connect на всех языках игры.

Ограничения Apple: имя покупки до 30 символов, описание до 45. Проверяет tools/asc_iap.py.
Ключ - локаль App Store Connect, порядок полей у всех языков одинаковый.
"""

# gems: имя с {n}, описание пака; затем имя/описание: starter, piggy, pass, weekend, builder, vip; группа подписки
FIELDS = ["gems", "gems_desc", "starter", "starter_desc", "piggy", "piggy_desc", "pass", "pass_desc",
          "weekend", "weekend_desc", "builder", "builder_desc", "vip", "vip_desc", "group"]

TEXTS = {
    "en-US": ["{n} Gems", "Gems for energy, bubbles and the jar",
              "Starter Pack", "Gems, energy and coins to begin",
              "Piggy Bank", "All the gems saved from your orders",
              "Event Pass", "A second reward on every event step",
              "Weekend Bundle", "Gems, energy and a little pond",
              "Builder's Kit", "Stars for buildings and a street lamp",
              "VIP", "Free firefly jar, double daily gems", "Hearthmend VIP"],
    "ru": ["{n} кристаллов", "Кристаллы на энергию, пузыри и кувшин",
           "Стартовый набор", "Кристаллы, энергия и монеты для начала",
           "Копилка", "Все кристаллы, накопленные за заказы",
           "Пропуск события", "Вторая награда на каждой ступени",
           "Набор выходных", "Кристаллы, энергия и прудик",
           "Набор строителя", "Звезды на постройки и фонарь",
           "VIP", "Кувшин без ожидания, x2 кристаллы в подарке", "Hearthmend VIP"],
    "uk": ["{n} кристалів", "Кристали на енергію, бульбашки і глечик",
           "Стартовий набір", "Кристали, енергія і монети для старту",
           "Скарбничка", "Усі кристали, накопичені за замовлення",
           "Перепустка події", "Друга нагорода на кожному щаблі",
           "Набір вихідних", "Кристали, енергія і ставок",
           "Набір будівельника", "Зірки на будівлі та ліхтар",
           "VIP", "Глечик без очікування, x2 кристали в дарунку", "Hearthmend VIP"],
    "de-DE": ["{n} Edelsteine", "Edelsteine für Energie, Blasen und Glas",
              "Startpaket", "Edelsteine, Energie und Münzen zum Start",
              "Sparschwein", "Alle Edelsteine aus deinen Aufträgen",
              "Event-Pass", "Zweite Belohnung auf jeder Event-Stufe",
              "Wochenendpaket", "Edelsteine, Energie und ein Teich",
              "Baumeister-Set", "Sterne für Gebäude und eine Laterne",
              "VIP", "Glühwürmchenglas gratis, doppelte Steine", "Hearthmend VIP"],
    "fr-FR": ["{n} gemmes", "Des gemmes pour l'énergie et le bocal",
              "Pack de départ", "Gemmes, énergie et pièces pour débuter",
              "Tirelire", "Toutes les gemmes de tes commandes",
              "Pass d'événement", "Une 2e récompense à chaque palier",
              "Pack du week-end", "Gemmes, énergie et un petit bassin",
              "Kit du bâtisseur", "Des étoiles et un lampadaire",
              "VIP", "Bocal gratuit, gemmes du jour doublées", "Hearthmend VIP"],
    "es-ES": ["{n} gemas", "Gemas para energía, burbujas y el tarro",
              "Pack de inicio", "Gemas, energía y monedas para empezar",
              "Hucha", "Todas las gemas ahorradas en pedidos",
              "Pase del evento", "Una 2.ª recompensa en cada paso",
              "Pack de fin de semana", "Gemas, energía y un estanque",
              "Kit del constructor", "Estrellas para construir y una farola",
              "VIP", "Tarro gratis y gemas diarias dobles", "Hearthmend VIP"],
    "pt-BR": ["{n} gemas", "Gemas para energia, bolhas e o pote",
              "Pacote inicial", "Gemas, energia e moedas para começar",
              "Cofrinho", "Todas as gemas guardadas nos pedidos",
              "Passe do evento", "Uma 2ª recompensa em cada etapa",
              "Pacote de fim de semana", "Gemas, energia e um laguinho",
              "Kit do construtor", "Estrelas para construir e um poste",
              "VIP", "Pote grátis e gemas diárias em dobro", "Hearthmend VIP"],
    "it": ["{n} gemme", "Gemme per energia, bolle e barattolo",
           "Pacchetto iniziale", "Gemme, energia e monete per iniziare",
           "Salvadanaio", "Tutte le gemme risparmiate con gli ordini",
           "Pass evento", "Una 2ª ricompensa a ogni tappa",
           "Pacchetto weekend", "Gemme, energia e un laghetto",
           "Kit del costruttore", "Stelle per costruire e un lampione",
           "VIP", "Barattolo gratis, gemme del giorno x2", "Hearthmend VIP"],
    "ja": ["ジェム{n}個", "エネルギー、バブル、瓶に使えるジェム",
           "スターターパック", "はじめに役立つジェム・エネルギー・コイン",
           "貯金箱", "注文でたまったジェムをすべて",
           "イベントパス", "イベントの各段階でもう一つのごほうび",
           "週末セット", "ジェム、エネルギー、小さな池",
           "建築家セット", "建物用のスターと街灯",
           "VIP", "ホタルの瓶が無料、毎日のジェム2倍", "Hearthmend VIP"],
    "ko": ["보석 {n}개", "에너지, 거품, 병에 쓰는 보석",
           "스타터 팩", "시작에 필요한 보석, 에너지, 코인",
           "저금통", "주문으로 모은 보석 전부",
           "이벤트 패스", "이벤트 각 단계마다 추가 보상",
           "주말 패키지", "보석, 에너지, 작은 연못",
           "건축가 세트", "건물용 별과 가로등",
           "VIP", "반딧불 병 무료, 매일 보석 2배", "Hearthmend VIP"],
    "zh-Hans": ["{n} 颗宝石", "用于能量、泡泡和萤火虫罐的宝石",
                "新手礼包", "开局用的宝石、能量和金币",
                "存钱罐", "订单攒下的全部宝石",
                "活动通行证", "活动每一级多一份奖励",
                "周末礼包", "宝石、能量和小池塘",
                "建造者礼包", "建筑用星星和一盏路灯",
                "VIP", "萤火虫罐免费，每日宝石翻倍", "Hearthmend VIP"],
    "tr": ["{n} Mücevher", "Enerji, baloncuk ve kavanoz için",
           "Başlangıç Paketi", "Başlamak için mücevher, enerji, altın",
           "Kumbara", "Siparişlerden biriken tüm mücevherler",
           "Etkinlik Kartı", "Her etkinlik basamağında ikinci ödül",
           "Hafta Sonu Paketi", "Mücevher, enerji ve küçük bir gölet",
           "Usta Seti", "Binalar için yıldız ve sokak lambası",
           "VIP", "Bedava kavanoz, günlük mücevher x2", "Hearthmend VIP"],
    "pl": ["{n} klejnotów", "Klejnoty na energię, bańki i słoik",
           "Pakiet startowy", "Klejnoty, energia i monety na start",
           "Skarbonka", "Wszystkie klejnoty z zamówień",
           "Przepustka wydarzenia", "Druga nagroda na każdym etapie",
           "Pakiet weekendowy", "Klejnoty, energia i stawek",
           "Zestaw budowniczego", "Gwiazdy na budowy i latarnia",
           "VIP", "Darmowy słoik, podwójne klejnoty dnia", "Hearthmend VIP"],
}


def text(locale, field, **kw):
    return TEXTS[locale][FIELDS.index(field)].format(**kw)


def check():
    bad = []
    for loc, vals in TEXTS.items():
        assert len(vals) == len(FIELDS), loc
        for f, v in zip(FIELDS, vals):
            v = v.format(n=13000)
            limit = 45 if f.endswith("_desc") else (60 if f == "group" else 30)
            if len(v) > limit:
                bad.append(f"{loc} {f}: {len(v)} > {limit}: {v}")
    return bad


if __name__ == "__main__":
    print("\n".join(check()) or "ok")
