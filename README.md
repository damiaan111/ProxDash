# 🖥️ ProxDash — HomeLab Dashboard

Een moderne, zelfgehoste dashboard voor je HomeLab — draait als LXC container op Proxmox VE.

![ProxDash](https://img.shields.io/badge/ProxDash-v2.0-3b82f6?style=for-the-badge&logo=proxmox&logoColor=white)
![Platform](https://img.shields.io/badge/Platform-Proxmox%20VE-e57000?style=for-the-badge)
![License](https://img.shields.io/badge/License-MIT-06d6a0?style=for-the-badge)

---

## 🚀 Installatie

Kopieer en plak dit commando in de **Proxmox VE shell** (als root):

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/damiaan111/ProxDash/main/homelab-dashboard/main/ct/homelab-dashboard.sh)"
```

> **Vereisten:** Proxmox VE 7 of hoger · Root toegang · Internetverbinding · DHCP op je bridge

Het script doet automatisch het volgende:
- Maakt een Debian 12 LXC container aan (256MB RAM, 2GB disk, 1 core)
- Installeert Node.js 20.x
- Download de dashboard bestanden
- Start de `proxdash` systemd service
- Toont het IP-adres en de URL na installatie

---

## 🌐 Openen

Na installatie open je het dashboard op:

```
http://<container-ip>:7575
```

Het IP-adres wordt getoond aan het einde van het installatie-script.

---

## ✨ Features

- **Geanimeerde IT-achtergrond** — Matrix-stijl regen met binaire karakters
- **Bewerkingsmodus** — Klik op ✏️ Bewerken om namen van services en categorieën direct in de interface aan te passen
- **Handmatige status refresh** — 🔄 Refresh knop controleert alle services op online/offline
- **Rechtermuisklik menu** — Snel bewerken, openen of verwijderen via contextmenu
- **Zoekfunctie** — Zoek direct via `Ctrl+K` / `⌘K`
- **Categorieën met kleur** — Services gegroepeerd per categorie met eigen kleur
- **Responsive** — Werkt op desktop en mobiel
- **Geen externe dependencies** — Volledig zelfstandig, geen cloud services

---

## 🔧 Container beheren

**Service herstarten:**
```bash
pct exec <CT_ID> -- systemctl restart proxdash
```

**Logs bekijken:**
```bash
pct exec <CT_ID> -- journalctl -u proxdash -f
```

**Dashboard handmatig updaten:**
```bash
curl -fsSL "https://raw.githubusercontent.com/damiaan111/ProxDash/main/homelab-dashboard/main/app/index.html" \
  -o /tmp/index.html

pct push <CT_ID> /tmp/index.html /opt/homelab-dashboard/index.html

pct exec <CT_ID> -- systemctl restart proxdash
```

> Vervang `<CT_ID>` met het ID van jouw container (te vinden via `pct list`)

---

## 📁 Repo structuur

```
ProxDash/
└── homelab-dashboard/
    └── main/
        ├── app/
        │   ├── index.html          # Dashboard frontend (single-file app)
        │   └── server.js           # Node.js backend server
        ├── ct/
        │   └── homelab-dashboard.sh    # Proxmox LXC installer script
        └── install/
            └── homelab-dashboard-install.sh  # Install script (draait in container)
```

---

## 📝 Licentie

MIT — vrij te gebruiken, aanpassen en delen.
