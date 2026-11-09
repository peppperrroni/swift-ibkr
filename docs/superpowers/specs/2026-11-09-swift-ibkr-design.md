# swift-ibkr — клиент IB Gateway на чистом Swift

Дата: 2026-11-09. Владелец одобрил направление в чате (сессия адаптера IB Gateway для TWS).

## Зачем

TWS (торговый терминал на Swift для Windows и macOS) должен торговать реальным paper-счётом IBKR через IB Gateway
за теми же портами, что сейчас закрывает `MockBroker`. Готового Swift-SDK у IBKR нет. Владелец хочет отдельный
пакет — просто способ говорить с IB Gateway из Swift: подключиться, отправить запрос, получить ответ. Данные пакет
никому не раздаёт. TWS — первый потребитель; адаптер `IBKRBroker` в TWS строится поверх пакета отдельно.

Успех: из Swift на Windows и на Mac можно подключиться к IB Gateway, поставить и отменить ордер, получить целые
ордера и исполнения с комиссией, позиции, счёт, котировки, историю, стакан, ленту и поиск контрактов; всё
типизировано, с `Decimal` для денег, и проверено тестами без живого Gateway.

## Цели

- Отдельный репозиторий `C:\Users\viohn\swift-ibkr`, SwiftPM-пакет, библиотека `IBKR`. Без зависимостей.
- Своя реализация сокетного протокола TWS API (не порт кода IB). Справочник по порядку полей — исходники
  `ib_async` (BSD 2-Clause) и документация IB.
- Swift-API: `async`/`await`, `AsyncStream` / `AsyncThrowingStream`, `actor`, `Sendable`; не 100 колбэков.
- Склейка внутри пакета: `openOrder` + `orderStatus` → один ордер; `execDetails` + `commissionReport` по execId →
  одно исполнение. Поздний подписчик не теряет событий: снимок и поток выдаются атомарно.
- Работает на Windows (Winsock) и macOS (BSD-сокеты).

## Не цели

- Не все ~100 сообщений TWS API: только нужные TWS (список ниже). Остальное добавляется по образцу, когда нужно.
- Не protobuf и не версии протокола 201+ (см. «Версия»).
- Не опционы, фьючерсы, FA-счета, сканеры, новости, WSH — пока не нужны.
- Не синхронные обёртки и не колбэк-API в стиле `EWrapper`.
- Не автоматическое переподключение в первой версии (только поток состояния подключения).

## Анти-цели (провал, даже если «работает»)

- Копия кода официального `ibapi` (лицензия «TWS API Non-Commercial» запрещает публиковать и распространять его код).
- Потерянные события: ордер или исполнение, пришедшие до подписки, не должны пропадать.
- Деньги во `Double`; «магические» UNSET-числа в публичных типах вместо `nil`.
- Молча проглоченная ошибка разбора: сообщение, которое не разобралось, видно потребителю.
- Утечка подписок: закончил `for await` — пакет сам отменил подписку у Gateway.

## Решения владельца

- Пакет отдельно, в своём репозитории; TWS подключает его как зависимость. Сначала локально, на GitHub — только
  с явного «да» владельца.
- Чистый Swift, без Python/C++ мостов.
- Всё реальное: и торговля, и маркет-данные из IB. У владельца нет подписок на маркет-данные: пакет должен уметь
  просить отложенные данные (`reqMarketDataType`) и отдавать отказ IB (нет прав на данные) как типизированную
  ошибку подписки, а не висеть.
- IB Gateway с paper-счётом запущен на этом ПК (Windows). Порт API на момент записи не слушался — включить
  API (порт 4002, Read-Only выключен, Trusted IP 127.0.0.1) владелец сделает перед живой проверкой.

## Устройство

```
 потребитель ── await client.placeOrder(…) / for await tick in client.marketData(…)
                  │
 IBClient (actor) ── роутер: reqId → поток или ответ запроса; ордера/исполнения → трекеры; прочее → messages
   │   ▲
   │   └── Decoder → enum IBMessage ← FrameReader ← Socket (Winsock / BSD)
   └────► Encoder ← enum IBRequest ── Throttle (≤ 45 сообщений/с) ─────────────► Socket
```

- **Socket** — тонкая обёртка над сокетом ОС: подключение с таймаутом, запись до конца (цикл на частичных
  записях), чтение кусками. `#if os(Windows)` WinSDK, иначе Darwin/Glibc.
- **FrameReader** — собирает кадры из кусков: 4 байта длины big-endian + тело; неполный кадр ждёт следующего куска;
  длина больше 16 МиБ (`0xFFFFFF`) — ошибка протокола, разрыв.
- **Поля** — тело кадра: поля-строки ASCII/UTF-8, каждое с `\0` в конце. Первое поле — id сообщения текстом.
  Чтение: курсор по полям с типизированным разбором (`Int`, `Decimal`, `Bool` из `"0"/"1"`, `String`, опциональные).
  Отсутствие значения (`""`, `2147483647`, `9223372036854775807`, `1.7976931348623157E308`) → `nil`.
  Запись: `nil` → пустое поле, `Bool` → `"1"/"0"`, `Decimal` — его каноническая строка без экспоненты.
- **Рукопожатие** — `API\0`, затем кадр с текстом `v100..178`; ответ — кадр из двух полей: версия сервера и время
  подключения; затем `startApi` (71): версия 2, clientId, пустые optional capabilities. Готовность — когда пришли
  `nextValidId` (9) и `managedAccounts` (15).
- **Decoder** — по id сообщения разбирает поля в `enum IBMessage` с типизированными значениями. Неизвестный id →
  `.unknown(id, fields)` (не ошибка: Gateway шлёт и то, о чём мы не просили). Ошибка разбора известного сообщения →
  `.malformed(id, fields, reason)` в общий поток и в лог потребителю, соединение не рвётся.
- **Encoder** — `enum IBRequest` → поля в порядке протокола версии 178.
- **Throttle** — не больше 45 исходящих сообщений в скользящую секунду (лимит IB — 50), лишние ждут очереди. Отмены
  идут той же очередью.
- **IBClient (actor)** — владеет соединением, выдаёт reqId и orderId (из `nextValidId`, один счётчик, как у
  `ib_async`), роутит ответы:
  - ответ с reqId → продолжение / поток именно этого запроса; маркер конца (`…End`) завершает запрос со списком;
  - `error(reqId, code, text)` разбирается по явной таблице кодов (**моё решение** после рецензии; таблица и её
    пополнение — в `docs/DECISIONS.md`): *уведомления* — 2100–2199, 10167 (показаны отложенные данные), 399, 161 и
    подобные — идут в `messages`, запрос не рвут; *подтверждение отмены* — 202 по orderId делает ордер отменённым, а
    не отклонённым; *фатальные* — прочие коды с reqId активного запроса завершают его поток типизированной
    `IBError(code, text)`, с orderId известного ордера — делают ордер отклонённым с текстом; reqId −1 — ошибка уровня
    соединения (в `messages`). Неизвестный код с reqId считается фатальным для запроса;
  - таймауты: подключение и разовые запросы — с таймаутом (параметр, по умолчанию 10 с), потоки — без;
  - конец `for await` / отмена задачи → `onTermination` шлёт отмену подписки (`cancelMktData`, `cancelHistoricalData`,
    `cancelMktDepth`, `cancelTickByTickData`, `cancelPositions`, `cancelAccountSummary`, `cancelPnLSingle`).
- **Трекеры** (часть состояния actor):
  - Client ID выбирает потребитель; пакет не навязывает режим. Свои ордера приходят вживую при любом ID; чужие —
    снимком через `reqAllOpenOrders`, вживую — если потребитель подключён с ID 0 и `reqAutoOpenOrders(true)` (ордера,
    введённые руками в десктопном TWS) или его ID — «Master API client ID» в настройках Gateway. Все три пути идут
    в тот же трекер (решение владельца: фокус на фреймворке, режим — забота приложения).
  - **OrderTracker**: ключ — `(clientId, orderId)`, для ордеров, поставленных вручную в TWS (orderId 0), — `permId`.
    `openOrder` даёт контракт, сторону, количество, тип, цены, TIF, outsideRth, parentId, ocaGroup, orderRef, account и
    статус; `orderStatus` — статус, filled, remaining, avgFillPrice, permId, parentId, whyHeld. Каждое изменение
    публикует **целый** ордер. `orderStatus` до первого `openOrder` этого ордера хранится и применяется, когда
    `openOrder` придёт (неполный ордер не публикуется). Ошибка IB по orderId (отказ) делает ордер отклонённым с текстом.
  - **ExecutionTracker**: `execDetails` и `commissionReport` склеиваются по execId; исполнение публикуется, когда есть
    обе половины, в любом порядке прихода. Поправка исполнения (тот же execId до последней точки, новый суффикс)
    заменяет прежнее.
  - Снимок + поток: `client.orders()` и `client.executions()` возвращают текущий список и поток дальнейших
    изменений, зарегистрированный в том же шаге actor — событие не может проскочить между ними.
  - **Изменение ордера** (порт TWS `modify`) — по протоколу это повторный `placeOrder` с тем же orderId и целым
    ордером; поэтому трекер хранит ордер в том виде, в каком он был отправлен, и `modify` шлёт его с новыми ценами.
- **Синхронизация при подключении** (**моё решение**, как у `ib_async`): после готовности `connect` сам шлёт
  `reqAllOpenOrders`, `reqCompletedOrders` и `reqExecutions` и возвращается, когда пришли их маркеры конца
  (`openOrderEnd`, `completedOrdersEnd`, `execDetailsEnd`) — так `orders()` сразу содержит сегодняшние ордера,
  включая исполненные и отменённые до запуска, а `executions()` — сегодняшние исполнения. Завершённые ордера
  приходят без рабочего orderId и ключуются по permId.

## Публичный API (набросок, имена — на усмотрение строителя)

```swift
let client = IBClient()
try await client.connect(host: "127.0.0.1", port: 4002, clientID: 1)
client.state                       // AsyncStream<ConnectionState>: connecting / connected(serverVersion, accounts) / disconnected(Error?)
client.messages                    // AsyncStream<IBMessage>: всё, что не ушло в запрос, плюс уведомления и ошибки

let id = try await client.placeOrder(contract, order)        // orderId; bracket — родитель + дети с parentId, transmit
try await client.cancelOrder(id)
let (orders, orderUpdates) = await client.orders()           // снимок + поток целых ордеров
let (fills, fillUpdates) = await client.executions()         // снимок + поток исполнений с комиссией

client.positions()                 // AsyncThrowingStream<[Position]>: весь набор на каждое изменение
client.accountSummary(tags:)       // AsyncThrowingStream<[AccountValue]>
client.pnlSingle(account:conID:)   // AsyncThrowingStream<PnL>
client.setMarketDataType(.delayed)
client.marketData(contract)        // AsyncThrowingStream<Tick>
client.historicalBars(contract, end:, duration:, barSize:, rth:, keepUpToDate:)  // AsyncThrowingStream<BarEvent>
client.marketDepth(contract, rows:)                         // AsyncThrowingStream<DepthUpdate>
client.tickByTick(contract, .allLast)                       // AsyncThrowingStream<TickByTick>
try await client.matchingSymbols("AAP")                     // [ContractDescription]
try await client.contractDetails(contract)                  // [ContractDetails] (с tradingHours / liquidHours, minTick)
```

Модели: `Contract` (conId, symbol, secType, exchange, primaryExchange, currency, localSymbol), `Order` (action,
totalQuantity, orderType, lmtPrice, auxPrice, tif, outsideRth, parentId, transmit, ocaGroup, orderRef, account),
`OrderSnapshot` (order + contract + статус и прогресс), `Execution` + `CommissionReport` → `Fill`. Цены и количества —
`Decimal`; время — то, что прислал IB, разобранное в `Date`/секунды там, где формат известен.

## Сообщения (версия 178)

Исходящие (id): startApi 71, reqIds 8, reqCurrentTime 49, placeOrder 3, cancelOrder 4, reqOpenOrders 5,
reqAllOpenOrders 16, reqAutoOpenOrders 15, reqExecutions 7, reqPositions 61 / cancelPositions 64,
reqAccountSummary 62 / cancel 63, reqPnLSingle 94 / cancel 95, reqMarketDataType 59, reqMktData 1 / cancel 2,
reqHistoricalData 20 / cancel 25, reqMktDepth 10 / cancel 11, reqTickByTickData 97 / cancel 98,
reqMatchingSymbols 81, reqContractDetails 9.

Входящие (id): tickPrice 1, tickSize 2, orderStatus 3, error 4, openOrder 5, nextValidId 9, contractData 10,
execDetails 11, updateMktDepth 12, updateMktDepthL2 13, managedAccounts 15, historicalData 17, currentTime 49,
tickGeneric 45, tickString 46, contractDataEnd 52, openOrderEnd 53, execDetailsEnd 55, marketDataType 58,
commissionReport 59, position 61, positionEnd 62, accountSummary 63, accountSummaryEnd 64, symbolSamples 79,
tickReqParams 81, historicalDataUpdate 90, pnlSingle 95, tickByTick 99, completedOrder 101 / completedOrdersEnd 102.
Исходящий reqCompletedOrders 99. Входящий orderBound 100 (ручной ордер TWS получил API-id при clientId 0) — в
трекер, связывает permId с orderId.

## Версия

Клиент объявляет `v100..178`. Сервер отвечает версией не выше объявленной; `ib_async` объявляет `v157..178` и так
работает с нынешними Gateway — значит, текстовый формат без protobuf (он начинается с 201) доступен. Пакет
принимает только ответ ровно 178: меньше — ошибка «Gateway слишком старый», больше — ошибка протокола (значит,
предположение неверно). Раскладка полей одна, без веток по версиям. Риск: IB может перестать принимать старые
версии клиента; тогда — переход на protobuf отдельным проектом.

## Тесты

- Swift Testing. Кодек и трекеры — на байтовых фикстурах без Gateway: кадр → `IBMessage` и `IBRequest` → байты, по
  фикстуре на каждое сообщение; трекеры — на последовательностях сообщений (orderStatus до openOrder; комиссия до
  исполнения; поправка исполнения; ручной ордер по permId; отказ ордера по error).
- Первые фикстуры собраны вручную по порядку полей `ib_async` — они проверяют, что мы прочли протокол так же.
  Замкнутость этой проверки снимает живая запись: на шаге с Gateway реальные кадры сохраняются в фикстуры.
- `IBClient` тестируется на фейковом транспорте (в памяти), без сокета.
- Живая проверка — на paper-счёте владельца, только после его подтверждения, что API Gateway включён.

## Этапы

1. **Кодек и склейка**: кадры, поля, рукопожатие, сообщения ордеров/исполнений/ошибок/id/счетов
   (placeOrder в том числе как изменение, cancelOrder, reqOpenOrders, reqAllOpenOrders, reqCompletedOrders,
   reqExecutions; openOrder, orderStatus, openOrderEnd, completedOrder, completedOrdersEnd, execDetails,
   execDetailsEnd, commissionReport, error с таблицей кодов, nextValidId, managedAccounts), `OrderTracker`,
   `ExecutionTracker`. Только тесты, без сокета. Подробный план пишется на этот этап; следующие этапы планируются
   после него, этап 3 и дальше — после живой проверки этапа 2 (её фикстуры заменяют самодельные).
2. **Подключение**: Socket, FrameReader, Throttle, `IBClient` с рукопожатием, роутингом, ордерами и исполнениями;
   живая проверка на paper-счёте (поставить и отменить лимитник, получить исполнение), запись реальных кадров.
3. **Счёт и позиции**: positions, accountSummary, pnlSingle.
4. **Маркет-данные**: marketDataType, mktData, history + keepUpToDate, depth, tick-by-tick, matchingSymbols,
   contractDetails; отказ «нет прав на данные» — типизированной ошибкой. Без подписок у владельца стакан и
   tick-by-tick проверяются вживую только как этот типизированный отказ — это и считается «готово» (**моё
   решение**); живые данные проверятся, когда появятся подписки.
5. **TWS**: модуль `Sources/IBGateway` с `IBKRBroker` за портами TWS, выбор брокера по `Settings.broker` в
   `DependencyContainer` (своя спека в репозитории TWS).

## Ограничения

- Windows: Swift 6.4.2 (x86_64-unknown-windows-msvc); macOS — Mac владельца (Swift 6.4.2). Пакет не тянет WinRT, так
  что собирается обычным `swift build`; если на Windows упадёт так же, как TWS, — `--build-system native`.
- Язык Swift 6 (строгая проверка параллелизма).
- Коммиты: одна повелительная фраза + причины; последняя строка `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
  Ничего не пушится на GitHub без «да» владельца.
- Документы репозитория: `README.md` (что это, как собрать и проверить), эта спека, `docs/DECISIONS.md` (решения и
  отвергнутое) — меняются вместе с поведением.

## На усмотрение строителя

Имена типов и методов; раскладка файлов; форма `IBMessage` (одна большая `enum` или группы); как именно устроен
фейковый транспорт; таймауты по умолчанию; формат лога.
