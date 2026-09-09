#!/bin/bash

# sanoid передаёт имя датасета в SANOID_TARGETS (одно значение)
ds="$SANOID_TARGETS"

written=$(zfs get -Hp -o value written "$ds" 2>/dev/null)

if [ -z "$written" ] || [ "$written" -eq 0 ]; then
    exit 1   # изменений нет, выходим со статусом 1 и снимка не будет
fi

exit 0       # были изменения, выходим со статусом 0 и делаем снимок
