# Moje docházka
Osobní evidence docházky a výplaty. Aplikace běží na https://blahamartin89-dochazka.github.io/moje-dochazka/
Aktualizováno: 2026-11-09

## Kopie pro kolegu
Stejný `index.html` je i ve složce `kolega/`. Liší se jen `kolega/config.js` (prázdné klíče, vlastní úložiště, žádné jeřáby). Adresa: https://blahamartin89-dochazka.github.io/moje-dochazka/kolega/

Po úpravě logiky zkopíruj soubor znovu, ať obě verze jedou ze stejného kódu:

```
cp index.html kolega/index.html
```

`config.js` v kořeni se nepřepisuje. Service worker v kořeni nesahá na `/kolega/` a worker v `kolega/` nesahá na kořen.


