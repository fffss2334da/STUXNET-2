# Stuxnet: журнал реализации

Этот файл дополняет `LOCAL_FEATURES_PLAN.md`. Отметка `Сделано` означает, что
код уже присутствует в рабочем дереве. Отметка `Проверяется` означает, что для
нее нужен macOS/iOS runtime или финальный CI build.

## Сделано в текущей ветке

- Сделано: собственный профиль читает серверный `wasOnline` из `TelegramUserPresence`
  и показывает абсолютное время последнего серверного входа. `Last Seen · Just now`
  и локальный fallback удалены; старое поле настроек только декодируется для
  совместимости.
- Сделано: fake messages имеют versioned snapshot и journal, стабильный local
  message id, защиту от дублей, редактирование, удаление и очистку ledger.
- Сделано: fake paid messages пишут Stars ledger идемпотентно, входящие
  начисляют Stars, исходящие списывают, а удаление/редактирование создаёт
  компенсирующую запись.
- Сделано: paid fake messages получают понятный локальный текст для истории и
  chat-list preview: `Paid message · N Stars` или `Received N Stars`.
- Сделано: fake gifts/NFT имеют локального owner, recipient, transfer intent,
  fee, chat action и профильную проекцию; transfer сохраняет получателя до
  удаления исходника.
- Сделано: fake channels, роли owner/admin/member, локальные посты, реакции,
  Stars, media picker и редактирование отделены от сетевого Telegram peer.
- Сделано: локальные username/tag/phone/name overrides проецируются в title и
  profile без изменения Telegram account.
- Сделано: настройки имеют отдельные разделы Ghost, Fake, Channels, Gifts,
  Stars, Voice и Appearance; значения проходят нормализацию.

## Проверяется на следующем проходе

- Проверяется: открыть и закрыть любой чат из списка, подарка, профиля и
  редактора, затем повторить после перезапуска.
- Проверяется: fake paid message появляется в чате сразу, не дублируется при
  повторном Save и удаляется вместе с Postbox/journal/ledger.
- Проверяется: fake gift action открывает чат нужного получателя, а не профиль
  или Saved Messages, и повторный transfer не меняет адресата.
- Проверяется: owner/admin channel preview показывает Telegram-похожие права и
  строку ввода, member не получает controls публикации.
- Проверяется: миграции старых массивов, read-only неизвестной schema и recovery
  после обрезанного journal.
- Проверяется: codec/store regressions на macOS и один полный unsigned IPA build.

## Ограничения

Fake channels и fake gifts остаются локальными проекциями. Они не создают
синтетический серверный `TelegramChannel`, не отправляют fake-данные в API и не
могут изменить права реального канала. Это сохраняет безопасное обновление
адаптеров при новых версиях Telegram.

