# Статистика Hearthmend (Google Analytics for Firebase)

С версии 1.2, схема как в ZenHab. Обертка: `Hearthmend/App/Analytics.swift`. Продукт `FirebaseAnalyticsCore`
(без IDFA/AdSupport), IDFV и рекламные сигналы выключены в `project.yml`. Личного не уходит: только счетчики
и id игровых данных (задачи, районы, цепочки, товары).

## Что уходит

| Событие | Когда |
|---|---|
| `app_installed` (`is_update`) | первый запуск версии со статистикой; `is_update = 1` у обновившихся с 1.1 |
| `tutorial_step` (`step`, `step_name`) | игрок дошел до шага обучения: 1 merge (генератор нажат), 2 deliver, 3 build, 4 done |
| `tutorial_complete` | обучение пройдено до конца |
| `tutorial_skipped` (`step`) | обучение пропущено кнопкой (тогда `tutorial_step` за пропущенные шаги не уходят) |
| `level_up` (`level`) | новый уровень |
| `task_built` (`task`, `district`, `tasks_done`, `level`) | построена задача деревни |
| `district_done` (`district`, `district_index`, `level`) | отстроен весь район |
| `chain_unlocked` (`chain`, `level`) | открыта новая цепочка |
| `shortage_shown` (`kind`: energy / gems / coins, `need`) | всплыло окно «не хватает» |
| `purchase_started` / `purchase_cancelled` / `purchase_failed` (`purchase_product_id`) | покупка за деньги |
| `purchase` (`value`, `currency`, `item_id`) | покупка прошла: стандартное событие GA4, доход в отчетах |
| `screen_view` (`screen_name`: Board, Village, Shop, ShopFromShortage, Settings, Feedback) | показ экрана |
| `review_prompt_shown` (`level`, `days_played`) | показан системный запрос оценки (`Hearthmend/App/ReviewPrompt.swift`) |
| `feedback_sent` (`kind`: bug / idea / other, `via`: telegram / mail) | отправлено сообщение разработчику |
| `item_mended` (`chain`, `tier`) | починена сломанная вещь (механики поля 1.2, `Sources/HearthCore/BoardLife.swift`) |
| `hearth_fueled` (`tier`) | в очаг брошен предмет леса |
| `mechanic_seen` (`mechanic`: life / hearth / broken) | игрок впервые встретил механику поля |
| `daily_state` | раз в день: уровень, звезды, монеты, кристаллы, энергия, район, всего заказов и слияний, стрик, покупки |
| user properties `build_type`, `first_seen_week`, `level`, `is_vip`, `is_payer` | для разрезов и когорт |

У всех событий есть параметр `screen` (экран, на котором случилось).

## Включение (владелец)

1. Firebase console → проект с остальными приложениями → «Добавить приложение» → iOS,
   bundle ID `com.personal.hearthmend`, имя Hearthmend. Скачать `GoogleService-Info.plist`.
2. Секрет GitHub: `gh secret set GOOGLE_SERVICE_INFO_PLIST < ~/Downloads/GoogleService-Info.plist`.
   Для локальной проверки положить файл в `tools/analytics/` (он в .gitignore).
3. Сборка TestFlight кладет plist сама (`tools/analytics/add_firebase_config.sh com.personal.hearthmend`).
   Без секрета или с plist на другой bundle ID сборка не падает: warning в логе, статистика выключена.
4. GA4 → Администратор → «Специальные определения»: user property `build_type` (и `level`, `is_payer`),
   параметры событий `step`, `step_name`, `task`, `district`, `kind`, `purchase_product_id`. Без этого их не видно в отчетах.
   В отчетах смотреть сравнение `build_type = appstore`.
5. App Store Connect → App Privacy: см. `docs/appstore.md` (раздел «Основное»). Политика: `docs/privacy.html`,
   скопировать в репозиторий hearthmend-legal вместе с выходом 1.2.

Локально: plist в `Hearthmend/Resources/`, `xcodegen generate`, запуск с `-AnalyticsDebug -FIRDebugEnabled`,
события видны в Firebase → DebugView. В Debug, на симуляторе и в демо (`-demo`, `-shot`) без этих аргументов ничего не уходит.

## Отзывы

Кнопка «Написать разработчику» в настройках (`Hearthmend/UI/FeedbackView.swift`). Сообщение уходит в Telegram-бот,
если заданы секреты `FEEDBACK_BOT_TOKEN` и `FEEDBACK_CHAT_ID` (подходит тот же бот, что у ZenHab), иначе
открывается письмо на `dawnwell.app+hearthmend@gmail.com`. К тексту добавляются версия игры и iOS, модель устройства и уровень.

## Воронка первой сессии

GA4 → «Исследования» → «Анализ последовательностей»: `first_open` → `tutorial_step` (step 1) → step 2 → step 3
→ `tutorial_complete` → `task_built` → `level_up` (level 3), фильтр `build_type = appstore`.
Удержание: «Когорты» по `first_seen_week`. Где игрок упирается: `shortage_shown` по `kind` и `level`.
