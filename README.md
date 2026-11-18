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

## Přístup kolegů e-mailem
Zámek je zapnutý. V `index.html` je `window.KOLEGA_ACCESS=true`. SQL `supabase/kolega_access.sql` běží, hook Before user created je `public.hook_kolega_before_user_created`.

Bez hooku si kdokoli může založit účet. Aplikace ho odhlásí, účet v Auth ale zůstane. Hook nový účet odmítne, pokud e-mail není aktivní v `allowed_emails`. Už existující účet Martina hook nemění.

Vestavěná pošta Supabase pošle jen 2 e-maily za hodinu a jen členům organizace. Na kolegy je potřeba vlastní SMTP. Šablona Magic Link musí obsahovat `{{ .Token }}`, aby přišel šestimístný kód.

Docházka kolegy se do tabulek Martina neukládá. Zůstává v telefonu.


