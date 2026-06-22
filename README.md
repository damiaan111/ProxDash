# 🖥️ ProxDash — HomeLab Dashboard

![ProxDash](https://img.shields.io/badge/ProxDash-v2.1-3b82f6?style=for-the-badge&logo=proxmox&logoColor=white)
![Platform](https://img.shields.io/badge/Proxmox%20VE-7%2B-e57000?style=for-the-badge)
![License](https://img.shields.io/badge/License-MIT-06d6a0?style=for-the-badge)

Een zelfgebouwd dashboard voor je homelabservices. Geen account, geen cloud, geen gedoe — gewoon een LXC container op je Proxmox host draaien en je bent klaar.

---

## 🚀 Installeren

Open de shell op je **Proxmox host** (als root) en plak dit commando:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/damiaan111/ProxDash/main/homelab-dashboard/main/ct/homelab-dashboard.sh)"
```

Het script regelt alles: container aanmaken, Node.js installeren, bestanden neerzetten en de service opstarten. Na een minuut of twee zie je het IP-adres en ben je klaar.

> **Wat je nodig hebt:** Proxmox VE 7 of hoger · root toegang · DHCP actief op je bridge (standaard `vmbr0`)

---

## 🌐 Dashboard openen

```
http://<container-ip>:7575
```

Het IP-adres wordt aan het einde van het installatiescript getoond. Weet je het niet meer? Doe dan `pct list` en daarna `pct exec <ID> -- hostname -I`.

---

## ✨ Wat kan het?

- **Geanimeerde achtergrond** — matrix-stijl regen op de achtergrond, subtiel genoeg om niet af te leiden
- **Services beheren** — toevoegen, bewerken en verwijderen via een netjes modaal venster
- **Bewerkingsmodus** — klik op *Bewerken* (of druk `E`) om namen direct in het dashboard aan te passen
- **Status checken** — klik op *Refresh* om alle services snel te pingen en de status bij te werken
- **Laatste controle** — kaarten tonen wanneer ze voor het laatst gecheckt zijn (bijv. *✓ 3 min geleden*)
- **Rechtermuisklik menu** — snelmenu per service voor bewerken, openen of verwijderen
- **Zoeken** — zoek direct met `Ctrl+K` of `⌘K`
- **Lege categorieën** verbergen zichzelf automatisch
- **State opgeslagen in `state.json`** — je instellingen blijven bewaard, ook na een herstart van de container

---

## ⌨️ Sneltoetsen

| Toets | Actie |
|---|---|
| `E` | Bewerkingsmodus aan/uit |
| `Ctrl+K` / `⌘K` | Zoekbalk focussen |
| `Escape` | Modal sluiten / bewerkingsmodus verlaten |

---

## 🔧 Container beheren

**Service herstarten:**
```bash
pct exec <CT_ID> -- systemctl restart proxdash
```

**Logs bekijken (live):**
```bash
pct exec <CT_ID> -- journalctl -u proxdash -f
```

**Dashboard handmatig updaten naar de nieuwste versie:**
```bash
curl -fsSL "https://raw.githubusercontent.com/damiaan111/ProxDash/main/homelab-dashboard/main/app/index.html" \
  -o /tmp/index.html

pct push <CT_ID> /tmp/index.html /opt/homelab-dashboard/index.html

pct exec <CT_ID> -- systemctl restart proxdash
```

> Vervang `<CT_ID>` met het ID van jouw container. Weet je het niet? Kijk met `pct list`.

---

## 📁 Repo structuur

```
ProxDash/
└── homelab-dashboard/
    └── main/
        ├── app/
        │   ├── index.html                    # De volledige dashboard app (één bestand)
        │   └── server.js                     # Node.js server — serveert de app en beheert state.json
        ├── ct/
        │   └── homelab-dashboard.sh          # Draai dit op je Proxmox host om alles te installeren
        └── install/
            └── homelab-dashboard-install.sh  # Installatielogica die in de container draait
```

---

## 📝 Licentie

MIT — gebruik het, pas het aan, doe er mee wat je wilt.
