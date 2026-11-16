# Покупки и магазин

Награды и правила в `Sources/HearthCore/Shop.swift`, проверка в `Tests/HearthCoreTests/ShopTests.swift`.
Покупки через StoreKit 2: `Hearthmend/App/StoreManager.swift`. Для запуска в Xcode без App Store Connect
схема берет товары из `Config/Products.storekit`.

## Что завести в App Store Connect

Сначала: Agreements, Tax, and Banking → принять Paid Apps и заполнить банк и налоги.
Потом в приложении com.personal.hearthmend → Monetization → In-App Purchases / Subscriptions:

| Product ID | Тип | Цена | Что дает |
|---|---|---|---|
| com.personal.hearthmend.gems.small | Consumable | 0.99 | 80 кристаллов |
| com.personal.hearthmend.gems.medium | Consumable | 4.99 | 450 кристаллов |
| com.personal.hearthmend.gems.large | Consumable | 9.99 | 1000 кристаллов |
| com.personal.hearthmend.gems.chest | Consumable | 19.99 | 2200 кристаллов |
| com.personal.hearthmend.starter | Non-Consumable | 1.99 | 250 кристаллов, 200 энергии, 1000 монет, один раз |
| com.personal.hearthmend.vip.monthly | Auto-Renewable, группа VIP, 1 месяц | 4.99 | кувшин в любой момент, двойные кристаллы в подарке дня |

## Защита от выгодных петель

- Один кристалл стоит `energyPerGem` энергии везде: пачка энергии, пузыри, кувшин.
- Энергия за монеты дороже, чем монеты, которые эта энергия принесет в заказах.
- Одна транзакция выдается один раз (`grantedTransactions`), стартовый набор один раз (`purchasedOneTime`).
- Бот баланса (`Simulator`) покупает энергию за монеты и открывает кувшин, тесты держат долю этой энергии.

## Автоматически через API

Секреты репозитория `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8` (ключ App Store Connect API, роль App Manager).
- Actions → «App Store Connect: покупки» → Run workflow: заводит все товары выше с описаниями (en, ru),
  ценами и странами. Повторный запуск ничего не дублирует. Скриншот для ревью покупок Apple просит
  добавить вручную перед первой отправкой.
- Actions → «TestFlight» → Run workflow: подписанная сборка (автоподпись через тот же ключ) и загрузка.
