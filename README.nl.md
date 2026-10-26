# Proxmox IaC Testlab — Root-Cause Analyse

Incidenten uit de opbouw van een Proxmox-lab volledig als code: VM's uit templates met OpenTofu, inrichting met Ansible, CI in Gitea Actions, monitoring met Zabbix en Prometheus/Grafana. Elk incident volgt hetzelfde format: symptoom → root cause → fix → les.

---

## 1. Locale-fout (`nl_NL.UTF-8`/`en_US.UTF-8`) — terugkerend op elke nieuwe VM

**Symptoom:** `perl: warning: Setting locale failed` op vrijwel elke nieuwe machine (`pve`, `ans01-tl`, `db01`, `mon-lab02`, etc.).

**Root cause:** de SSH-client op het beheerwerkstation stuurt `LC_*`-omgevingsvariabelen (waaronder `nl_NL.UTF-8`) mee naar elke server waarop wordt ingelogd. Die locale is nooit gegenereerd in de VM's, omdat de fix nooit in de basis-templates (9000/9100) is verwerkt — elke fix was een losse, per-VM ingreep.

**Impact:** cosmetisch/ruis in de meeste gevallen, maar bij Zabbix zorgde dit voor een daadwerkelijk blokkerende fout in de webinterface-installatiewizard (`Locale for language "en_US" is not found`).

**Fix (tijdelijk):** per VM `en_US.UTF-8` en `nl_NL.UTF-8` gegenereerd (`dpkg-reconfigure locales`).

**Fix (structureel, gepland):** beide locales genereren in de templates 9000/9100, zodat elke clone ze meteen heeft.

**Les:** een fix die je op meer dan één VM met de hand doet, hoort in het template of in een Ansible-rol. Anders komt de fout bij elke nieuwe machine terug.

---

## 2. SSH-key-selectie-verwarring tussen meerdere `Host`-aliassen

**Symptoom:** herhaaldelijke `Permission denied (publickey)`-fouten bij het verbinden met `git01`, `mon-lab01` en `runner01`, ondanks een correct geladen ssh-agent.

**Root cause, twee varianten:**
1. Een `Host <ip-gitea>`-config-blok, oorspronkelijk bedoeld voor Gitea's eigen SSH-server (poort 2222, user `git`), matchte óók op normale systeem-SSH-pogingen naar hetzelfde IP (poort 22, de beheergebruiker) — SSH matcht op het letterlijke adres, niet op intentie. Hierdoor probeerde elke systeem-SSH-poging de verkeerde poort/user.
2. De ssh-agent op `ans01-tl` liep meerdere keren onverklaarbaar leeg, ondanks een geconfigureerde `.bashrc`-autostart.

**Fix:**
1. Het conflicterende `Host`-blok is omgezet naar een losse alias (`Host gitea-ssh`) die niet meer matcht op het kale IP-adres — de Git-remote-URL is dienovereenkomstig aangepast.
2. Voor de leeglopende agent is geen structurele oorzaak gevonden; het herhaalde patroon staat genoteerd als openstaand punt.

**Les:** geef elke SSH-dienst een eigen alias in plaats van een blok op IP-adres. `ssh -G <host>` laat zien welke instellingen echt gelden voor een verbinding.

---

## 3. Gitea `app.ini`-template overschreef runtime-gegenereerde secrets (config-drift)

**Symptoom:** na het toevoegen van een `[actions]`-sectie aan de Ansible-template en een hernieuwde playbook-run, verscheen onverwacht opnieuw de Gitea-installatiewizard — een teken dat Gitea dacht nooit geïnstalleerd te zijn geweest.

**Root cause:** de oorspronkelijke Ansible-template van `app.ini` bevatte alleen de instellingen die *expliciet* door de Ansible-role waren gezet. Secties die Gitea zelf tijdens de eerste-setup-wizard had gegenereerd (`INTERNAL_TOKEN`, `JWT_SECRET`, `INSTALL_LOCK`, `WORK_PATH`, `[mailer]`, `[service]`, `[openid]`, etc.) stonden niet in de template. Omdat `ansible.builtin.template` het doelbestand **volledig** overschrijft, verdween al die door Gitea zelf toegevoegde configuratie bij elke playbook-run.

**Waarom dit gevaarlijk was:** `INSTALL_LOCK` verdween mee, waardoor Gitea dacht dat het opnieuw geïnstalleerd moest worden — een verkeerde klik op "Install Gitea" had potentieel de bestaande database kunnen beschadigen.

**Fix (structureel):**
- De actuele, runtime-gegenereerde waarden van `INTERNAL_TOKEN` en `JWT_SECRET` zijn uit `/etc/gitea/app.ini` gehaald en in `ansible-vault` vastgelegd (niet opnieuw gegenereerd — de bestaande, werkende waarden zijn behouden).
- De template is uitgebreid met alle secties die Gitea zelf nodig heeft, met de secrets als expliciete, vault-gestuurde variabelen.
- `INSTALL_LOCK = true` is als vaste waarde in de template opgenomen.

**Les:** een Ansible-template voor een applicatie die zelf ook configuratie genereert/aanpast, moet **alle** velden bevatten die de applicatie verwacht — niet alleen de velden die de beheerder bewust heeft ingesteld. Secrets die de applicatie zelf genereert, horen zo snel mogelijk te worden "geadopteerd" in de vault, in plaats van de applicatie ze bij elke run opnieuw te laten verzinnen.

---

## 4. PostgreSQL/Zabbix/act_runner: `become_user` faalt met chmod-fout op Debian 13

**Symptoom:** herhaaldelijk (drie keer, in drie verschillende rollen) dezelfde fout: `chmod: invalid mode: 'A+user:<gebruiker>:rx:allow'`, bij elke Ansible-taak die `become_user` gebruikte om als een niet-root-gebruiker (`postgres`, `zabbix`, `act_runner`) te draaien.

**Eerste analyse (onjuist):** "het filesystem ondersteunt geen ACL's".

**Root cause (gecorrigeerd, nog niet getest in het lab):** als Ansible een taak als een andere, onbevoorrechte gebruiker draait, moet die gebruiker de tijdelijke modulebestanden kunnen lezen. Ansible probeert daarvoor eerst `setfacl`. Dat zit in het pakket `acl`, dat niet in de Debian 13-cloudimage staat. Ansible valt dan terug op andere methodes, als laatste een `chmod A+…`-syntax die GNU `chmod` niet kent. De foutmelding gaat dus over het ontbrekende pakket, niet over het filesystem.

**Fix:**
- Tijdelijk (drie keer toegepast): `become: true` (root) met een expliciet `sudo -u <gebruiker>` in het shell-commando zelf.
- Structureel (volgende stap): het pakket `acl` installeren in de basisrol of het template, en testen of `become_user` dan zonder workaround werkt.

**Les:** een foutmelding eerst opzoeken in de documentatie voordat je een oorzaak aanneemt. De eerste analyse was een aanname, en de workaround verborg dat drie keer.

---

## 5. PostgreSQL: `listen_addresses`-wijziging niet actief vóór vervolgtaken

**Symptoom:** `tofu init` met de PostgreSQL-backend gaf `connection refused`, ondanks dat de Ansible-playbook had gemeld dat `listen_addresses = '*'` was ingesteld.

**Root cause:** de service-herstart (via de `notify`-handler) gebeurt standaard pas aan het **eind** van een Ansible-playbook, niet direct na de taak die de wijziging aanbracht. Latere taken in hetzelfde playbook (database/user aanmaken) verbonden dus nog met de oude, niet-herstarte PostgreSQL-instantie — en toen de state-migratie vanaf een andere host (`ans01-tl`) werd geprobeerd, luisterde de dienst nog steeds alleen op `localhost`.

**Fix:** een `ansible.builtin.meta: flush_handlers`-taak toegevoegd direct na de service-start-taak, die de pending handler-restart afdwingt vóórdat latere taken verdergaan.

**Les:** "changed" betekent dat het configbestand is aangepast, niet dat de dienst de nieuwe instelling gebruikt. Hangen latere taken af van een herstart, dan `flush_handlers`. Controleer daarna met `ss -tlnp` of de dienst echt op het juiste adres luistert.

---

## 6. Zabbix-specifieke installatieproblemen (meerdere, cumulatief)

Een reeks losse, elk kleine problemen tijdens de Zabbix-installatie:

1. **PHP-versie-aanname fout**: de role verwees naar `php8.2-fpm`, maar Debian 13 shipt standaard met **PHP 8.4**. → Hardcoded naar de juiste versie.
2. **Schema-import faalde stil**: `zcat ... | psql ...` in een `shell`-taak rapporteerde succes ondanks dat het bronbestand niet bestond (verkeerd pad: `/usr/share/zabbix/sql-scripts/` in plaats van het werkelijke `/usr/share/zabbix-sql-scripts/`). Oorzaak: bij een pipe checkt bash standaard alleen de exit-code van het láátste commando (`psql`), niet van `zcat`. → Pad gecorrigeerd, en `set -o pipefail` toegevoegd zodat een fout ergens in de pipe de hele taak laat falen.
3. **PostgreSQL-optie ontbrak in de setup-wizard**: de `php8.4-pgsql`-extensie was niet meegeïnstalleerd. → Toegevoegd aan de package-lijst.
4. **`public`-schema-permissiefout** (`permission denied for schema public`): sinds PostgreSQL 15 heeft het `public`-schema geen automatische CREATE-rechten meer voor gewone gebruikers. → Expliciete `GRANT ALL ON SCHEMA public`-taak toegevoegd.
5. **Wachtwoord-mismatch bij eerste vault-integratie**: de `CREATE ROLE ... IF NOT EXISTS`-taak wijzigt het wachtwoord niet als de rol al bestond met een ouder (placeholder-)wachtwoord. → Een aparte, altijd-uitgevoerde `ALTER ROLE ... PASSWORD`-taak toegevoegd, zodat het wachtwoord bij elke run gegarandeerd overeenkomt met de vault.

**Gemeenschappelijke les:** software die relatief nieuw geüpgraded is (Zabbix 7.0, PostgreSQL 15+) brengt vaak net-veranderde paden/gedrag mee t.o.v. oudere, veelgebruikte installatiehandleidingen — expliciet verifiëren in plaats van vertrouwen op bekende patronen uit eerdere versies.

---

## 7. `act_runner`-download: verouderde/verplaatste release-URL

**Symptoom:** `HTTP Error 404: Not Found` bij het downloaden van de `act_runner`-binary vanaf `gitea.com/gitea/act_runner/releases/...`.

**Root cause:** het project is deels hernoemd (van `act_runner` naar `runner`, vanaf versie 2.x), met een onbevestigde nieuwe URL-structuur. De oudere, stabiele 0.2.x-reeks bleek nog wel betrouwbaar bereikbaar via een ander domein: `dl.gitea.com/act_runner/`.

**Fix:** teruggeschakeld naar de bekende, bevestigd-werkende versie (0.2.13) via het juiste domein, in plaats van te gokken op de nieuwste, onzekere URL-structuur.

**Les:** bij third-party release-assets loont het om de daadwerkelijke releases-pagina/downloadstructuur te verifiëren in plaats van een downloadpatroon te extrapoleren uit een andere, verouderde bron.

---

## 8. CI-containers: PEP 668 blokkeert systeembrede `pip install`

**Symptoom:** `error: externally-managed-environment` bij `pip install ansible-lint` binnen een Gitea Actions-workflow.

**Root cause:** moderne Debian/Ubuntu-gebaseerde container-images passen PEP 668 toe, een Python-brede bescherming tegen het per ongeluk overschrijven van systeem-Python-packages.

**Fix:** `--break-system-packages` toegevoegd aan alle `pip install`-commando's binnen de CI-workflow — hetzelfde patroon dat al eerder op de VM's zelf werd toegepast.

**Les:** in een wegwerpcontainer is `--break-system-packages` een acceptabele snelle fix, maar wel een workaround. Netter is een venv of een eigen CI-image waarin de tools al staan. Dat is een volgende stap.

---

## 9. Trage `tofu destroy` bij tijdelijke test-VM's (7+ minuten)

**Symptoom:** de "destroy"-stap van de eerste ephemeral-test-CI-run bleef **ruim 7 minuten** hangen, tegenover een paar seconden bij een eerdere, handmatige test.

**Root cause:** OpenTofu's Proxmox-provider vraagt bij destroy standaard een **nette ACPI-shutdown** aan via de guest-agent en wacht geduldig tot de VM zelf afsluit (`stop_on_destroy = false`, de default). Wanneer de guest-agent traag reageert (bijvoorbeeld net na een Ansible-run die pakketten installeerde), duurt die nette afsluiting fors langer dan verwacht.

**Fix:** `stop_on_destroy = true` toegevoegd aan de resource-definitie van de tijdelijke test-VM's — dit forceert een snelle, harde stop. Voor wegwerp-VM's is een nette shutdown functioneel niet nodig; snelheid weegt zwaarder.

**Nevenincident:** tijdens het debuggen van deze trage destroy werd de workflow-run per ongeluk als "afgerond" geïnterpreteerd terwijl hij nog liep, wat leidde tot een verweesde VM (`ci-test-255`) die handmatig moest worden opgeruimd op de Proxmox-host. Les: bij een lang-lopende, onduidelijke CI-stap eerst de daadwerkelijke status verifiëren (bijv. via `sudo qm list` op de hypervisor) voordat een nieuwe run wordt gestart.

---

## Terugkerende patronen — samengevat

Een paar type-fouten kwamen structureel meerdere keren terug, wat ze de moeite waard maakt om als algemene lessen te onthouden:

1. **`become_user` zonder pakket `acl`** → `acl` in de basisrol installeren; foutmeldingen eerst opzoeken in plaats van een oorzaak aannemen.
2. **Templates die applicatie-gegenereerde configuratie overschrijven** → altijd eerst de volledige, actuele configuratie van een verse installatie inventariseren vóórdat een Ansible-template wordt geschreven, niet alleen de zelf-ingestelde velden.
3. **Verouderde download-URL's/versienummers** → bij elke nieuwe service eerst de actuele, officiële releases-pagina verifiëren in plaats van te vertrouwen op bekende patronen.
4. **SSH-key/`Host`-config-conflicten** → specifieke, niet-overlappende `Host`-aliassen gebruiken in plaats van generieke IP-gebaseerde blokken wanneer een host meerdere SSH-diensten/poorten aanbiedt.
5. **Stille fouten in shell-pipes** → `set -o pipefail` als standaardgewoonte bij elk `ansible.builtin.shell`-commando met een pipe.
6. **Handmatige fixes per VM** → wat vaker dan één keer met de hand gebeurt, hoort in het template of in een rol.
